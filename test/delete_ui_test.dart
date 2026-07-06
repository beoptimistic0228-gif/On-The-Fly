// F-14b'/F-14c' 단위·위젯 테스트: 정리 루프 내 단건 삭제 UI.
//
// 범위: (1) SortController.deleteCurrent 성공/실패 전이, (2) 최초 1회 교육 시트,
// (3) supportsDeletion=false 시 삭제 버튼 미노출, (4) 완료 화면 총계·분해 표기.
//
// 플랫폼 채널 없이: PhotoService.deleteAsset 결과를 fake 로 주입해 컨트롤러/화면
// 로직만 검증한다(실제 삭제 동작은 실기기 항목, §G.5).

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:on_the_fly/app/settings_store.dart';
import 'package:on_the_fly/app/theme.dart';
import 'package:on_the_fly/core/analytics/analytics_service.dart';
import 'package:on_the_fly/core/db/deletion_repository.dart';
import 'package:on_the_fly/core/db/processed_repository.dart';
import 'package:on_the_fly/core/models/album_ref.dart';
import 'package:on_the_fly/core/models/asset_ref.dart';
import 'package:on_the_fly/core/models/assignment.dart';
import 'package:on_the_fly/core/models/photo_permission.dart';
import 'package:on_the_fly/core/photo/photo_service.dart';
import 'package:on_the_fly/core/providers.dart';
import 'package:on_the_fly/features/done/done_screen.dart';
import 'package:on_the_fly/features/sort/sort_controller.dart';
import 'package:on_the_fly/features/sort/sort_screen.dart';

/// deleteAsset 결과·supportsDeletion 을 제어할 수 있는 인메모리 PhotoService.
class _FakePhotoService implements PhotoService {
  _FakePhotoService({
    required this.queue,
    required this.albums,
    this.deleteResult = true,
    this.supports = true,
  });

  final List<AssetRef> queue;
  final List<AlbumRef> albums;
  bool deleteResult;
  final bool supports;

  final List<String> deleteCalls = [];
  final Map<String, AlbumRef> _pending = {};

  @override
  bool get supportsDeletion => supports;

  @override
  Future<bool> deleteAsset(AssetRef asset) async {
    deleteCalls.add(asset.id);
    if (deleteResult) _pending.remove(asset.id);
    return deleteResult;
  }

  @override
  Future<PhotoPermission> ensurePermission() async => PhotoPermission.granted;

  @override
  Future<void> openSystemSettings() async {}

  @override
  Future<void> presentLimited() async {}

  @override
  Future<List<AssetRef>> loadUnclassifiedQueue() async => queue;

  @override
  Future<List<AlbumRef>> listAlbums() async => albums;

  @override
  void stageAssignment(AssetRef asset, AlbumRef album) =>
      _pending[asset.id] = album;

  @override
  void unstageAssignment(String assetId) => _pending.remove(assetId);

  @override
  List<PendingAssignment> pendingAssignments() => _pending.entries
      .map((e) => PendingAssignment(assetId: e.key, album: e.value, mediaType: 0))
      .toList();

  @override
  Future<BatchAssignResult> commitAssignments() async {
    final succeeded = _pending.entries
        .map((e) =>
            AssignedAsset(finalAssetId: e.key, albumId: e.value.id, mediaType: 0))
        .toList();
    _pending.clear();
    return BatchAssignResult(succeeded: succeeded, failed: const []);
  }

  @override
  Future<AlbumRef> createAlbum(String name) async =>
      AlbumRef(id: 'new', name: name, updatedAt: DateTime(2026));

  @override
  Future<Uint8List?> thumbnail(String assetId, {int size = 256}) async => null;
}

/// logDeletion 호출 횟수만 세는 fake.
class _RecordingDeletionRepo implements DeletionRepository {
  int logged = 0;

  @override
  Future<void> logDeletion() async => logged++;

  @override
  Future<List<DateTime>> deletionDates() async => const [];
}

class _RecordingAnalytics implements AnalyticsService {
  final List<String> events = [];
  int count(String name) => events.where((e) => e == name).length;

  @override
  void logAssetDeleted() => events.add(AnalyticsEvents.assetDeleted);
  @override
  void logSortSessionComplete({
    required int processedCount,
    required int remainingUnclassified,
    required int deletedCount,
  }) =>
      events.add(AnalyticsEvents.sortSessionComplete);
  // 나머지는 이 테스트에서 미사용.
  @override
  void logAppOpen() {}
  @override
  void logOnboardingComplete({
    required int notifyHour,
    required int notifyMinute,
    required bool notifyEnabled,
  }) {}
  @override
  void logSortSessionStart({required int unclassifiedCount}) {}
  @override
  void logAssetAssigned({required String albumId}) {}
  @override
  void logAssetSkipped() {}
  @override
  void logNotificationOpened() {}
  @override
  void logAdShown() {}
  @override
  void logRemoveAdsPurchased() {}
  @override
  void logRemoveAdsRestored() {}
}

class _StubProcessedRepo implements ProcessedRepository {
  @override
  Future<int> countProcessedInRange(DateTime from, DateTime to) async => 0;
  @override
  Future<DateTime?> lastProcessedAt() async => null;
  @override
  Future<int> processedCount() async => 0;
  @override
  Future<Set<String>> processedIdSet() async => <String>{};
  @override
  Future<void> markProcessed({
    required String assetId,
    required String albumId,
    required int mediaType,
  }) async {}
  @override
  Future<int> streakDays() async => 3;
}

AssetRef _asset(String id) => AssetRef(id: id, mediaType: 0);
AlbumRef _album(String id) =>
    AlbumRef(id: id, name: 'A$id', updatedAt: DateTime(2026));

void main() {
  group('SortController.deleteCurrent (F-14b\')', () {
    Future<
        ({
          ProviderContainer container,
          _FakePhotoService photo,
          _RecordingDeletionRepo del,
          _RecordingAnalytics analytics,
        })> setup({bool deleteResult = true}) async {
      final photo = _FakePhotoService(
        queue: [_asset('a1'), _asset('a2'), _asset('a3')],
        albums: [_album('alb1')],
        deleteResult: deleteResult,
      );
      final del = _RecordingDeletionRepo();
      final analytics = _RecordingAnalytics();
      final container = ProviderContainer(overrides: [
        photoServiceProvider.overrideWithValue(photo),
        deletionRepositoryProvider.overrideWithValue(del),
        analyticsServiceProvider.overrideWithValue(analytics),
        processedRepositoryProvider.overrideWithValue(_StubProcessedRepo()),
      ]);
      container.listen(sortControllerProvider, (_, _) {});
      await container.read(sortControllerProvider.notifier).load();
      return (
        container: container,
        photo: photo,
        del: del,
        analytics: analytics
      );
    }

    test('삭제 성공 → true·index++·deletedCount++·logDeletion·asset_deleted', () async {
      final s = await setup(deleteResult: true);
      addTearDown(s.container.dispose);
      final notifier = s.container.read(sortControllerProvider.notifier);

      final before = s.container.read(sortControllerProvider);
      expect(before.index, 0);
      expect(before.deletedCount, 0);

      final ok = await notifier.deleteCurrent();
      expect(ok, isTrue);

      final after = s.container.read(sortControllerProvider);
      expect(after.index, 1, reason: '다음 카드로 진행');
      expect(after.deletedCount, 1);
      expect(s.del.logged, 1, reason: 'streak 원천에 1회 기록');
      expect(s.analytics.count(AnalyticsEvents.assetDeleted), 1);
      expect(s.photo.deleteCalls, ['a1']);
    });

    test('삭제 실패/취소 → false·상태 무변경·기록 없음', () async {
      final s = await setup(deleteResult: false);
      addTearDown(s.container.dispose);
      final notifier = s.container.read(sortControllerProvider.notifier);

      final ok = await notifier.deleteCurrent();
      expect(ok, isFalse);

      final after = s.container.read(sortControllerProvider);
      expect(after.index, 0, reason: '카드 유지');
      expect(after.deletedCount, 0);
      expect(s.del.logged, 0, reason: '실패 시 streak 미기록');
      expect(s.analytics.count(AnalyticsEvents.assetDeleted), 0);
    });

    test('삭제는 undo 스택에 안 쌓인다(canUndo 무변경)', () async {
      final s = await setup(deleteResult: true);
      addTearDown(s.container.dispose);
      final notifier = s.container.read(sortControllerProvider.notifier);

      await notifier.deleteCurrent();
      expect(s.container.read(sortControllerProvider).canUndo, isFalse,
          reason: '삭제만 했으면 되돌릴 게 없다');
    });

    test('삭제만 한 세션 commit → deletedCount 실린 outcome + 완료 이벤트', () async {
      final s = await setup(deleteResult: true);
      addTearDown(s.container.dispose);
      final notifier = s.container.read(sortControllerProvider.notifier);

      await notifier.deleteCurrent(); // a1
      await notifier.deleteCurrent(); // a2
      final outcome = await notifier.commit();

      expect(outcome.successCount, 0);
      expect(outcome.deletedCount, 2);
      expect(outcome.isNoop, isFalse, reason: '삭제분이 있으면 완료 화면으로 간다');
      expect(s.analytics.count(AnalyticsEvents.sortSessionComplete), 1);
    });
  });

  group('삭제 버튼·교육 시트 (F-14c\')', () {
    Future<void> pumpSort(
      WidgetTester tester, {
      required _FakePhotoService photo,
      required SharedPreferences prefs,
      _RecordingDeletionRepo? del,
    }) async {
      final router = GoRouter(
        initialLocation: '/sort',
        routes: [
          GoRoute(path: '/sort', builder: (_, _) => const SortScreen()),
          GoRoute(
              path: '/done',
              builder: (_, _) => const Scaffold(body: Text('done-stub'))),
          GoRoute(
              path: '/home',
              builder: (_, _) => const Scaffold(body: Text('home-stub'))),
        ],
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPrefsProvider.overrideWithValue(prefs),
            photoServiceProvider.overrideWithValue(photo),
            deletionRepositoryProvider
                .overrideWithValue(del ?? _RecordingDeletionRepo()),
            analyticsServiceProvider.overrideWithValue(_RecordingAnalytics()),
            processedRepositoryProvider
                .overrideWithValue(_StubProcessedRepo()),
          ],
          child: MaterialApp.router(
            theme: buildAppTheme(),
            routerConfig: router,
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('supportsDeletion=false 면 삭제 버튼을 렌더하지 않는다', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final photo = _FakePhotoService(
        queue: [_asset('a1')],
        albums: [_album('alb1')],
        supports: false,
      );
      await pumpSort(tester, photo: photo, prefs: prefs);

      expect(find.byIcon(Icons.delete_outline), findsNothing);
    });

    testWidgets('supportsDeletion=true 면 삭제 버튼이 보인다', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final photo = _FakePhotoService(
        queue: [_asset('a1')],
        albums: [_album('alb1')],
        supports: true,
      );
      await pumpSort(tester, photo: photo, prefs: prefs);

      expect(find.byIcon(Icons.delete_outline), findsOneWidget);
    });

    testWidgets('삭제 첫 탭 → 교육 시트, [삭제] 진행 시 삭제·플래그 저장', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final del = _RecordingDeletionRepo();
      final photo = _FakePhotoService(
        queue: [_asset('a1'), _asset('a2'), _asset('a3')],
        albums: [_album('alb1')],
      );
      await pumpSort(tester, photo: photo, prefs: prefs, del: del);

      // 첫 탭 → 교육 시트 등장.
      await tester.tap(find.byIcon(Icons.delete_outline));
      await tester.pumpAndSettle();
      expect(find.text('사진을 삭제할까요?'), findsOneWidget);

      // 시트의 [삭제] 로 진행 → 실제 삭제.
      await tester.tap(find.widgetWithText(FilledButton, '삭제'));
      await tester.pumpAndSettle();

      expect(photo.deleteCalls, ['a1'], reason: '진행 시에만 삭제');
      expect(del.logged, 1);
      expect(prefs.getBool('seen_delete_intro'), isTrue,
          reason: '진행 후 최초 1회 플래그 저장');
    });

    testWidgets('교육 시트 [취소] 면 삭제하지 않고 플래그도 안 세운다', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final photo = _FakePhotoService(
        queue: [_asset('a1'), _asset('a2')],
        albums: [_album('alb1')],
      );
      await pumpSort(tester, photo: photo, prefs: prefs);

      await tester.tap(find.byIcon(Icons.delete_outline));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, '취소'));
      await tester.pumpAndSettle();

      expect(photo.deleteCalls, isEmpty);
      expect(prefs.getBool('seen_delete_intro'), isNot(true));
    });

    testWidgets('이미 교육을 본 뒤엔 시트 없이 바로 삭제', (tester) async {
      SharedPreferences.setMockInitialValues({'seen_delete_intro': true});
      final prefs = await SharedPreferences.getInstance();
      final photo = _FakePhotoService(
        queue: [_asset('a1'), _asset('a2')],
        albums: [_album('alb1')],
      );
      await pumpSort(tester, photo: photo, prefs: prefs);

      await tester.tap(find.byIcon(Icons.delete_outline));
      await tester.pumpAndSettle();

      expect(find.text('사진을 삭제할까요?'), findsNothing,
          reason: '재사용 시 무마찰');
      expect(photo.deleteCalls, ['a1']);
    });

    testWidgets('삭제 실패 시 "삭제하지 못했어요" 스낵', (tester) async {
      SharedPreferences.setMockInitialValues({'seen_delete_intro': true});
      final prefs = await SharedPreferences.getInstance();
      final photo = _FakePhotoService(
        queue: [_asset('a1'), _asset('a2')],
        albums: [_album('alb1')],
        deleteResult: false,
      );
      await pumpSort(tester, photo: photo, prefs: prefs);

      await tester.tap(find.byIcon(Icons.delete_outline));
      await tester.pumpAndSettle();

      expect(find.text('삭제하지 못했어요'), findsOneWidget);
    });
  });

  group('완료 화면 총계·분해 (F-14c\')', () {
    Future<void> pumpDone(WidgetTester tester, CommitOutcome outcome) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final router = GoRouter(
        initialLocation: '/done',
        routes: [
          GoRoute(path: '/done', builder: (_, _) => DoneScreen(outcome: outcome)),
          GoRoute(
              path: '/home',
              builder: (_, _) => const Scaffold(body: Text('home-stub'))),
        ],
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPrefsProvider.overrideWithValue(prefs),
            processedRepositoryProvider
                .overrideWithValue(_StubProcessedRepo()),
          ],
          child: MaterialApp.router(
            theme: buildAppTheme(),
            routerConfig: router,
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('배정+삭제 혼합 → 총계 + 분해 라인', (tester) async {
      await pumpDone(
          tester,
          const CommitOutcome(
              successCount: 10,
              failedCount: 0,
              cancelled: false,
              deletedCount: 2));
      expect(find.text('12장을 정리했어요'), findsOneWidget);
      expect(find.text('앨범 10장 · 삭제 2장'), findsOneWidget);
    });

    testWidgets('삭제만 한 세션 → 삭제 문구, 분해·앨범안내 생략', (tester) async {
      await pumpDone(
          tester,
          const CommitOutcome(
              successCount: 0,
              failedCount: 0,
              cancelled: false,
              deletedCount: 3));
      expect(find.text('3장을 삭제했어요'), findsOneWidget);
      expect(find.textContaining('앨범 0장'), findsNothing);
      expect(find.textContaining('모든 앨범'), findsNothing);
    });

    testWidgets('삭제 0 → 기존 문구 유지, 분해 없음', (tester) async {
      await pumpDone(
          tester,
          const CommitOutcome(
              successCount: 5, failedCount: 0, cancelled: false));
      expect(find.text('5장을 앨범으로 옮겼어요'), findsOneWidget);
      expect(find.textContaining('삭제'), findsNothing);
    });
  });
}
