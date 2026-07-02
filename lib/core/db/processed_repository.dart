import 'dao/processed_dao.dart';

/// 처리 기록 리포지토리 — architecture §2.2 경계 계약.
///
/// features 는 이 추상 타입만 의존한다(Riverpod 주입, 테스트 시 fake 교체).
abstract class ProcessedRepository {
  /// 처리된 자산 ID 집합(미분류 판별 기준, datamodel §3).
  Future<Set<String>> processedIdSet();

  /// 마지막 처리 시각(없으면 null).
  Future<DateTime?> lastProcessedAt();

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

/// Drift 기반 구현(ProcessedDao 래핑).
class DriftProcessedRepository implements ProcessedRepository {
  DriftProcessedRepository(this._dao);

  final ProcessedDao _dao;

  @override
  Future<Set<String>> processedIdSet() => _dao.processedIdSet();

  @override
  Future<DateTime?> lastProcessedAt() => _dao.lastProcessedAt();

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
    final dates = await _dao.allProcessedDates();
    if (dates.isEmpty) return 0;

    // 날짜(자정 기준) 집합으로 정규화.
    final days = dates
        .map((d) => DateTime(d.year, d.month, d.day))
        .toSet();

    final now = DateTime.now();
    var cursor = DateTime(now.year, now.month, now.day);

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
}
