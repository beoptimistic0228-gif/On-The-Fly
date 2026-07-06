// F-14a' 단위 테스트: 단건 삭제 core.
//
// 범위: (1) deleteAsset 결과 매핑 + 서비스 내부 정리(pending·캐시), (2) DeletionLogs
// 스키마 v2 마이그레이션 + logDeletion, (3) streak 합집합(처리일 ∪ 삭제일).
//
// 플랫폼 채널·실기기 없이 검증한다: deleteAsset 의 플랫폼 호출부는 제외하고, 순수
// 매핑 로직(applyDeletionResult)·in-memory Drift DB·순수 streak 함수를 대상으로 한다.

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:on_the_fly/core/db/album_repository.dart';
import 'package:on_the_fly/core/db/app_database.dart';
import 'package:on_the_fly/core/db/deletion_repository.dart';
import 'package:on_the_fly/core/db/processed_repository.dart';
import 'package:on_the_fly/core/models/album_ref.dart';
import 'package:on_the_fly/core/models/asset_ref.dart';
import 'package:on_the_fly/core/photo/photo_manager_photo_service.dart';

/// PhotoService 의존성(ProcessedRepository)만 채우는 no-op fake.
/// deleteAsset 내부 정리(applyDeletionResult)는 이 의존성을 쓰지 않는다.
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
  Future<int> streakDays() async => 0;
}

class _StubAlbumRepo implements AlbumRepository {
  @override
  Future<List<AlbumRef>> allAlbums() async => const [];
  @override
  Future<AlbumRef?> albumById(String id) async => null;
  @override
  Future<void> saveAlbum(AlbumRef album) async {}
  @override
  Future<void> setSystemRef(String albumId, String systemRef) async {}
}

// AlbumRepository import 를 위 stub 이 참조.
AssetRef _asset(String id) => AssetRef(id: id, mediaType: 0);

void main() {
  group('deleteAsset 결과 매핑 + 내부 정리 (applyDeletionResult)', () {
    late PhotoManagerPhotoService svc;

    setUp(() {
      svc = PhotoManagerPhotoService(_StubProcessedRepo(), _StubAlbumRepo());
    });

    test('삭제 id 포함 → true', () {
      expect(svc.applyDeletionResult('a1', <String>['a1']), isTrue);
    });

    test('빈 반환(취소/실패) → false', () {
      expect(svc.applyDeletionResult('a1', const <String>[]), isFalse);
    });

    test('다른 id 만 반환 → false', () {
      expect(svc.applyDeletionResult('a1', <String>['other']), isFalse);
    });

    test('성공 시 배정 예약(_pending)에서 해당 자산 제거(방어)', () {
      final album = AlbumRef(id: 'alb', name: '여행', updatedAt: DateTime(2026));
      svc.stageAssignment(_asset('a1'), album);
      svc.stageAssignment(_asset('a2'), album);
      expect(svc.pendingAssignments().map((p) => p.assetId), containsAll(['a1', 'a2']));

      svc.applyDeletionResult('a1', <String>['a1']);

      final remaining = svc.pendingAssignments().map((p) => p.assetId).toList();
      expect(remaining, isNot(contains('a1')));
      expect(remaining, contains('a2'), reason: '다른 예약은 보존');
    });

    test('실패 시 _pending 그대로 유지', () {
      final album = AlbumRef(id: 'alb', name: '여행', updatedAt: DateTime(2026));
      svc.stageAssignment(_asset('a1'), album);
      svc.applyDeletionResult('a1', const <String>[]); // 실패
      expect(svc.pendingAssignments().map((p) => p.assetId), contains('a1'));
    });

    test('성공 시 스캔 캐시 무효화', () {
      svc.debugPrimeQueueCache(<AssetRef>[_asset('x')]);
      expect(svc.debugQueueCached, isTrue);
      svc.applyDeletionResult('a1', <String>['a1']);
      expect(svc.debugQueueCached, isFalse);
    });

    test('실패 시 스캔 캐시 유지(불필요한 재스캔 방지)', () {
      svc.debugPrimeQueueCache(<AssetRef>[_asset('x')]);
      svc.applyDeletionResult('a1', const <String>[]);
      expect(svc.debugQueueCached, isTrue);
    });
  });

  group('supportsDeletion (Android SDK 게이트, 테스트 주입)', () {
    // 호스트(비-모바일)에서는 Platform.isAndroid/isIOS 가 모두 false 라
    // 기본 supportsDeletion=false. Android 분기 자체는 debugSetAndroidSdkInt 로
    // SDK 값만 바꿔선 검증 불가(Platform 게이트가 우선)하므로, 여기서는 SDK 미조회
    // 기본값이 안전(미지원)임만 확인한다. 실제 API 레벨별 동작은 실기기 항목.
    test('SDK 미조회 기본값은 미지원(호스트)', () {
      final svc = PhotoManagerPhotoService(_StubProcessedRepo(), _StubAlbumRepo());
      expect(svc.supportsDeletion, isFalse);
    });
  });

  group('DeletionLogs 스키마 v2 + logDeletion', () {
    test('v1 → v2 onUpgrade 가 deletion_logs 를 생성한다', () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);

      // v2 스키마로 생성된 상태 → 테이블 제거해 v1 상황을 흉내낸다.
      await db.customStatement('DROP TABLE IF EXISTS deletion_logs');

      // onUpgrade(1→2) 를 직접 실행 → 테이블 재생성 검증.
      final strategy = db.migration;
      await strategy.onUpgrade(Migrator(db), 1, 2);

      // 재생성됐으면 기록·조회가 정상 동작.
      await db.deletionDao.logDeletion(DateTime(2026, 7, 7, 9));
      final dates = await db.deletionDao.allDeletionDates();
      expect(dates, hasLength(1));
    });

    test('logDeletion append + deletionDates 반환(리포지토리)', () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final repo = DriftDeletionRepository(db.deletionDao);

      await repo.logDeletion();
      await repo.logDeletion();
      expect(await repo.deletionDates(), hasLength(2));
    });
  });

  group('streak 합집합 (computeStreak 순수 함수)', () {
    final now = DateTime(2026, 7, 7, 12);
    DateTime day(int d) => DateTime(2026, 7, d);

    test('빈 집합 → 0', () {
      expect(computeStreak(const <DateTime>[], now: now), 0);
    });

    test('처리일만: 오늘·어제 연속 → 2', () {
      expect(computeStreak([day(7), day(6)], now: now), 2);
    });

    test('삭제일만: 오늘 → 1 (삭제만 한 날도 인정)', () {
      expect(computeStreak([day(7)], now: now), 1);
    });

    test('혼합: 처리(오늘)+삭제(어제) 합집합 → 2', () {
      expect(computeStreak([day(7), day(6)], now: now), 2);
    });

    test('같은 날 처리+삭제 중복은 1일로 집계', () {
      expect(computeStreak([day(7), day(7), day(6)], now: now), 2);
    });

    test('공백일(오늘 없음, 어제 있음) → 어제부터 인정', () {
      expect(computeStreak([day(6), day(5)], now: now), 2);
    });

    test('공백일(오늘·어제 모두 없음) → 0', () {
      expect(computeStreak([day(4), day(3)], now: now), 0);
    });
  });

  group('streak 합집합 (DriftProcessedRepository 통합 — 두 테이블 union)', () {
    test('삭제만 있어도 오늘 streak=1', () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final repo = DriftProcessedRepository(db.processedDao, db.deletionDao);

      // 처리 기록 0, 삭제 기록만 오늘.
      await db.deletionDao.logDeletion(DateTime.now());
      expect(await repo.streakDays(), 1);
    });

    test('처리·삭제가 서로 다른 날이면 합쳐서 streak', () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final repo = DriftProcessedRepository(db.processedDao, db.deletionDao);

      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day, 10);
      final yesterday = today.subtract(const Duration(days: 1));

      // 처리(오늘) — FK 때문에 앨범 선행 삽입 후 raw insert 로 날짜 통제.
      await db.into(db.albums).insert(AlbumsCompanion.insert(
            id: 'alb',
            name: '여행',
            updatedAt: now,
          ));
      await db.into(db.processedAssets).insert(ProcessedAssetsCompanion.insert(
            id: 'p1',
            processedAt: today,
            albumId: 'alb',
          ));
      // 삭제(어제).
      await db.deletionDao.logDeletion(yesterday);

      expect(await repo.streakDays(), 2,
          reason: '처리(오늘) ∪ 삭제(어제) = 연속 2일');
    });
  });
}
