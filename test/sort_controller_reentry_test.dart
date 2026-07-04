// 회귀 테스트 (QA I-1): 정리 화면 재진입 시 미분류 큐가 새로 로드되는가.
//
// 버그: sortControllerProvider 가 일반 NotifierProvider 라 앱 수명 내내 캐시되어,
// 정리 화면을 나갔다 다시 들어와도 load() 가 재실행되지 않아 스테일 큐/소진 상태가
// 남았다. autoDispose 전환으로 리스너가 0이 되면 폐기되고 재진입 시 재로드된다.
//
// 실기기/플랫폼 채널 없이, PhotoService 를 fake 로 주입해 load 호출 횟수로 검증한다.

import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:on_the_fly/core/models/album_ref.dart';
import 'package:on_the_fly/core/models/asset_ref.dart';
import 'package:on_the_fly/core/models/assignment.dart';
import 'package:on_the_fly/core/models/photo_permission.dart';
import 'package:on_the_fly/core/photo/photo_service.dart';
import 'package:on_the_fly/core/providers.dart';
import 'package:on_the_fly/features/sort/sort_controller.dart';

/// load() 경로만 실제로 동작하는 최소 fake. loadUnclassifiedQueue 호출 횟수를 센다.
class _FakePhotoService implements PhotoService {
  int loadCount = 0;

  @override
  Future<PhotoPermission> ensurePermission() async => PhotoPermission.granted;

  @override
  Future<void> openSystemSettings() async {}

  @override
  Future<void> presentLimited() async {}

  @override
  Future<List<AssetRef>> loadUnclassifiedQueue() async {
    loadCount++;
    return const [
      AssetRef(id: 'a1', mediaType: 0),
      AssetRef(id: 'a2', mediaType: 0),
    ];
  }

  @override
  Future<List<AlbumRef>> listAlbums() async => [
        AlbumRef(id: 'alb1', name: '여행', updatedAt: DateTime(2026, 1, 1)),
      ];

  @override
  List<PendingAssignment> pendingAssignments() => const [];

  // load() 가 쓰지 않는 나머지는 미사용.
  @override
  void stageAssignment(AssetRef asset, AlbumRef album) =>
      throw UnimplementedError();
  @override
  void unstageAssignment(String assetId) => throw UnimplementedError();
  @override
  Future<BatchAssignResult> commitAssignments() => throw UnimplementedError();
  @override
  Future<AlbumRef> createAlbum(String name) => throw UnimplementedError();
  @override
  Future<Uint8List?> thumbnail(String assetId, {int size = 0}) =>
      throw UnimplementedError();
}

/// autoDispose 폐기·마이크로태스크가 정리되도록 이벤트 루프를 넘긴다.
Future<void> _settle() => Future<void>.delayed(Duration.zero);

void main() {
  test('정리 화면 재진입 시 미분류 큐를 새로 로드한다 (QA I-1 회귀)', () async {
    final fake = _FakePhotoService();
    final container = ProviderContainer(
      overrides: [photoServiceProvider.overrideWithValue(fake)],
    );
    addTearDown(container.dispose);

    // 1회차 진입: 화면이 컨트롤러를 구독.
    final sub1 = container.listen(sortControllerProvider, (_, _) {});
    await _settle();
    expect(fake.loadCount, 1, reason: '최초 진입 시 1회 로드');
    expect(container.read(sortControllerProvider).queue.length, 2);

    // 화면 이탈: 리스너 제거 → autoDispose 로 컨트롤러 폐기.
    sub1.close();
    await _settle();

    // 2회차 진입: 새 인스턴스로 build()→load() 가 다시 돌아야 한다.
    container.listen(sortControllerProvider, (_, _) {});
    await _settle();
    expect(fake.loadCount, 2, reason: '재진입 시 재로드되어야 함(스테일 큐 방지)');
    expect(container.read(sortControllerProvider).status, SortStatus.ready);
  });
}
