import 'package:flutter/foundation.dart' show visibleForTesting;

import 'dao/deletion_dao.dart';
import 'dao/processed_dao.dart';

/// 처리 기록 리포지토리 — architecture §2.2 경계 계약.
///
/// features 는 이 추상 타입만 의존한다(Riverpod 주입, 테스트 시 fake 교체).
abstract class ProcessedRepository {
  /// 처리된 자산 ID 집합(미분류 판별 기준, datamodel §3).
  Future<Set<String>> processedIdSet();

  /// 마지막 처리 시각(없으면 null).
  Future<DateTime?> lastProcessedAt();

  /// 처리된 자산 총 개수(미분류 큐 캐시 무효화 신호).
  Future<int> processedCount();

  /// commit 성공분 1건 기록. **이동 후 최종 [assetId]**로 호출(datamodel §3.1.1).
  Future<void> markProcessed({
    required String assetId,
    required String albumId,
    required int mediaType,
  });

  /// 연속 정리일수(오늘 또는 어제까지 이어진 streak).
  Future<int> streakDays();

  /// [from, to) 범위 처리 건수.
  Future<int> countProcessedInRange(DateTime from, DateTime to);
}

/// 날짜 집합에서 오늘(또는 어제)까지 이어진 연속일 streak 을 계산한다.
///
/// 순수 함수(테스트 용이). [dates] 는 임의 시각 목록으로, 여기서 자정 기준
/// 날짜로 정규화해 집합화한다. 오늘 기록이 없으면 어제부터 이어지는 streak 를
/// 인정한다(오늘 아직 정리 안 함). 원천은 처리일 ∪ 삭제일 어느 쪽이든 무방.
@visibleForTesting
int computeStreak(Iterable<DateTime> dates, {DateTime? now}) {
  final days = dates
      .map((d) => DateTime(d.year, d.month, d.day))
      .toSet();
  if (days.isEmpty) return 0;

  final ref = now ?? DateTime.now();
  var cursor = DateTime(ref.year, ref.month, ref.day);

  // 오늘 기록이 없으면 어제부터 이어지는 streak 로 인정(오늘 아직 안 함).
  if (!days.contains(cursor)) {
    cursor = cursor.subtract(const Duration(days: 1));
    if (!days.contains(cursor)) return 0;
  }

  var streak = 0;
  while (days.contains(cursor)) {
    streak++;
    cursor = cursor.subtract(const Duration(days: 1));
  }
  return streak;
}

/// Drift 기반 구현(ProcessedDao 래핑).
class DriftProcessedRepository implements ProcessedRepository {
  DriftProcessedRepository(this._dao, this._deletionDao);

  final ProcessedDao _dao;

  /// streak 합집합(D5-4)의 "삭제일" 원천. 처리일과 함께 연속일을 계산한다.
  final DeletionDao _deletionDao;

  @override
  Future<Set<String>> processedIdSet() => _dao.processedIdSet();

  @override
  Future<DateTime?> lastProcessedAt() => _dao.lastProcessedAt();

  @override
  Future<int> processedCount() => _dao.processedCount();

  @override
  Future<void> markProcessed({
    required String assetId,
    required String albumId,
    required int mediaType,
  }) {
    return _dao.markProcessed(
      assetId: assetId,
      albumId: albumId,
      mediaType: mediaType,
    );
  }

  @override
  Future<int> countProcessedInRange(DateTime from, DateTime to) =>
      _dao.countInRange(from, to);

  @override
  Future<int> streakDays() async {
    // D5-4: streak = 처리일 ∪ 삭제일. 삭제만 한 날도 정리 활동으로 인정한다.
    final processed = await _dao.allProcessedDates();
    final deleted = await _deletionDao.allDeletionDates();
    return computeStreak(<DateTime>[...processed, ...deleted]);
  }
}
