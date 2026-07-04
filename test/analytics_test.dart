// F-12 분석 계측 검증.
//
// 핵심 이벤트가 "올바른 시점 · 올바른 속성" 으로 찍히는지 Fake AnalyticsService
// 를 주입해 확인한다. 플랫폼 채널을 타지 않도록 PhotoService/ProcessedRepository
// /NotificationService 도 fake 로 override 한다.

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:on_the_fly/app/settings_store.dart';
import 'package:on_the_fly/app/theme.dart';
import 'package:on_the_fly/core/analytics/analytics_service.dart';
import 'package:on_the_fly/core/db/processed_repository.dart';
import 'package:on_the_fly/core/photo/photo_service.dart';
import 'package:on_the_fly/core/models/album_ref.dart';
import 'package:on_the_fly/core/models/asset_ref.dart';
import 'package:on_the_fly/core/models/assignment.dart';
import 'package:on_the_fly/core/models/photo_permission.dart';
import 'package:on_the_fly/core/notifications/notification_service.dart';
import 'package:on_the_fly/core/providers.dart';
import 'package:on_the_fly/features/onboarding/onboarding_screen.dart';
import 'package:on_the_fly/features/sort/sort_controller.dart';

/// 호출된 이벤트를 순서대로 기록하는 Fake.
class RecordingAnalyticsService implements AnalyticsService {
  final List<AnalyticsEvent> events = [];

  Iterable<AnalyticsEvent> byName(String name) =>
      events.where((e) => e.name == name);

  AnalyticsEvent? firstOrNull(String name) =>
      byName(name).isEmpty ? null : byName(name).first;

  @override
  void logAppOpen() => events.add(const AnalyticsEvent(AnalyticsEvents.appOpen));

  @override
  void logOnboardingComplete({
    required int notifyHour,
    required int notifyMinute,
    required bool notifyEnabled,
  }) =>
      events.add(AnalyticsEvent(AnalyticsEvents.onboardingComplete, {
        AnalyticsParams.notifyHour: notifyHour,
        AnalyticsParams.notifyMinute: notifyMinute,
        AnalyticsParams.notifyEnabled: notifyEnabled,
      }));

  @override
  void logSortSessionStart({required int unclassifiedCount}) =>
      events.add(AnalyticsEvent(AnalyticsEvents.sortSessionStart, {
        AnalyticsParams.unclassifiedCount: unclassifiedCount,
      }));

  @override
  void logAssetAssigned({required String albumId}) =>
      events.add(AnalyticsEvent(AnalyticsEvents.assetAssigned, {
        AnalyticsParams.albumId: albumId,
      }));

  @override
  void logAssetSkipped() =>
      events.add(const AnalyticsEvent(AnalyticsEvents.assetSkipped));

  @override
  void logSortSessionComplete({
    required int processedCount,
    required int remainingUnclassified,
  }) =>
      events.add(AnalyticsEvent(AnalyticsEvents.sortSessionComplete, {
        AnalyticsParams.processedCount: processedCount,
        AnalyticsParams.remainingUnclassified: remainingUnclassified,
      }));

  @override
  void logNotificationOpened() =>
      events.add(const AnalyticsEvent(AnalyticsEvents.notificationOpened));
}

/// 인메모리 PhotoService — commit 은 모든 예약을 성공 처리.
class FakePhotoService implements PhotoService {
  FakePhotoService({
    required this.queue,
    required this.albums,
    this.permission = PhotoPermission.granted,
  });

  final List<AssetRef> queue;
  final List<AlbumRef> albums;
  final PhotoPermission permission;

  final Map<String, AlbumRef> _pending = {};
  final Map<String, int> _mediaTypes = {};

  @override
  Future<PhotoPermission> ensurePermission() async => permission;

  @override
  Future<void> openSystemSettings() async {}

  @override
  Future<void> presentLimited() async {}

  @override
  Future<List<AssetRef>> loadUnclassifiedQueue() async => queue;

  @override
  void stageAssignment(AssetRef asset, AlbumRef album) {
    _pending[asset.id] = album;
    _mediaTypes[asset.id] = asset.mediaType;
  }

  @override
  void unstageAssignment(String assetId) => _pending.remove(assetId);

  @override
  List<PendingAssignment> pendingAssignments() => _pending.entries
      .map((e) => PendingAssignment(
            assetId: e.key,
            album: e.value,
            mediaType: _mediaTypes[e.key] ?? 0,
          ))
      .toList();

  @override
  Future<BatchAssignResult> commitAssignments() async {
    final succeeded = _pending.entries
        .map((e) => AssignedAsset(
              finalAssetId: e.key,
              albumId: e.value.id,
              mediaType: _mediaTypes[e.key] ?? 0,
            ))
        .toList();
    _pending.clear();
    return BatchAssignResult(succeeded: succeeded, failed: const []);
  }

  @override
  Future<AlbumRef> createAlbum(String name) async =>
      AlbumRef(id: 'new', name: name, updatedAt: DateTime(2026));

  @override
  Future<List<AlbumRef>> listAlbums() async => albums;

  @override
  Future<Uint8List?> thumbnail(String assetId, {int size = 256}) async => null;
}

/// 처리 기록을 무시하는 fake(계측 검증엔 부작용 불필요).
class FakeProcessedRepository implements ProcessedRepository {
  int marked = 0;

  @override
  Future<int> countProcessedInRange(DateTime from, DateTime to) async => 0;

  @override
  Future<DateTime?> lastProcessedAt() async => null;

  @override
  Future<void> markProcessed({
    required String assetId,
    required String albumId,
    required int mediaType,
  }) async {
    marked++;
  }

  @override
  Future<Set<String>> processedIdSet() async => {};

  @override
  Future<int> streakDays() async => 0;
}

/// 아무것도 안 하는 알림 fake.
class FakeNotificationService implements NotificationService {
  bool launchedFromNotification;
  FakeNotificationService({this.launchedFromNotification = false});

  @override
  Future<void> cancelAll() async {}

  @override
  Future<void> init() async {}

  @override
  Future<bool> requestPermission() async => true;

  @override
  Future<void> scheduleDaily(TimeOfDay time) async {}

  @override
  Future<bool> didAppLaunchFromNotification() async => launchedFromNotification;
}

// core/providers.dart 에서 노출되지 않는 리포지토리 provider 는 여기서 import.
// (providers.dart 가 processedRepositoryProvider/photoServiceProvider 를 노출)

void main() {
  AlbumRef album(String id) =>
      AlbumRef(id: id, name: 'A$id', updatedAt: DateTime(2026));
  AssetRef asset(String id) => AssetRef(id: id, mediaType: 0);

  test(
      'commit 성공 시 asset_assigned×N + sort_session_complete 가 정확한 속성으로 찍힌다',
      () async {
    final analytics = RecordingAnalyticsService();
    final photo = FakePhotoService(
      queue: [asset('a1'), asset('a2'), asset('a3')],
      albums: [album('alb1')],
    );

    final container = ProviderContainer(overrides: [
      analyticsServiceProvider.overrideWithValue(analytics),
      photoServiceProvider.overrideWithValue(photo),
      processedRepositoryProvider.overrideWithValue(FakeProcessedRepository()),
    ]);
    addTearDown(container.dispose);

    // 컨트롤러 유지(autoDispose) + 초기 build 의 microtask load 소진.
    final sub = container.listen(sortControllerProvider, (_, _) {});
    addTearDown(sub.close);
    final notifier = container.read(sortControllerProvider.notifier);
    await notifier.load();

    // 세션 시작 이벤트 = 미분류수 3.
    final start = analytics.firstOrNull(AnalyticsEvents.sortSessionStart);
    expect(start, isNotNull);
    expect(start!.params[AnalyticsParams.unclassifiedCount], 3);

    // a1 배정 → a2 건너뛰기 → a3 배정.
    notifier.assignCurrent(album('alb1')); // index0(a1)
    notifier.skipCurrent(); // index1(a2)
    notifier.assignCurrent(album('alb1')); // index2(a3)

    // ★ 시점 검증: 아직 commit 전이므로 asset_assigned 는 0건(stage 아님).
    expect(analytics.byName(AnalyticsEvents.assetAssigned), isEmpty);
    expect(analytics.byName(AnalyticsEvents.assetSkipped).length, 1);

    final outcome = await notifier.commit();
    expect(outcome.successCount, 2);

    // asset_assigned 는 성공분(2)만큼, albumId 는 로컬 앨범 UUID.
    final assigned = analytics.byName(AnalyticsEvents.assetAssigned).toList();
    expect(assigned.length, 2);
    expect(assigned.every((e) => e.params[AnalyticsParams.albumId] == 'alb1'),
        isTrue);

    // sort_session_complete: 처리수 2, 남은 미분류수 = 3 - 2 = 1.
    final complete = analytics.firstOrNull(AnalyticsEvents.sortSessionComplete);
    expect(complete, isNotNull);
    expect(complete!.params[AnalyticsParams.processedCount], 2);
    expect(complete.params[AnalyticsParams.remainingUnclassified], 1);
  });

  testWidgets('온보딩 마지막 스텝 완료 시 onboarding_complete 가 찍힌다',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final analytics = RecordingAnalyticsService();

    final router = GoRouter(
      initialLocation: '/onboarding',
      routes: [
        GoRoute(
          path: '/onboarding',
          builder: (_, _) => const OnboardingScreen(),
        ),
        GoRoute(
          path: '/sort',
          builder: (_, _) => const Scaffold(body: Text('sort-stub')),
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPrefsProvider.overrideWithValue(prefs),
          analyticsServiceProvider.overrideWithValue(analytics),
          photoServiceProvider.overrideWithValue(
            FakePhotoService(queue: [asset('a1')], albums: [album('alb1')]),
          ),
          notificationServiceProvider
              .overrideWithValue(FakeNotificationService()),
        ],
        child: MaterialApp.router(
          theme: buildAppTheme(),
          routerConfig: router,
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 스텝1: 시작하기 → 사진 스텝.
    await tester.tap(find.text('시작하기'));
    await tester.pumpAndSettle();

    // 스텝2: 사진 접근 허용(fake=granted) → 알림 스텝 자동 이동.
    await tester.tap(find.text('사진 접근 허용'));
    await tester.pumpAndSettle();

    // 스텝3: 나중에 설정 → 첫 정리 스텝.
    await tester.tap(find.text('나중에 설정'));
    await tester.pumpAndSettle();

    // 스텝4: 첫 정리 시작 → onboarding_complete + /sort.
    await tester.tap(find.text('지금 첫 정리 시작'));
    await tester.pumpAndSettle();

    final e = analytics.firstOrNull(AnalyticsEvents.onboardingComplete);
    expect(e, isNotNull, reason: 'onboarding_complete 가 찍혀야 한다');
    // 기본 알림 시각 21:00.
    expect(e!.params[AnalyticsParams.notifyHour], 21);
    expect(e.params[AnalyticsParams.notifyMinute], 0);
    expect(find.text('sort-stub'), findsOneWidget);
  });
}
