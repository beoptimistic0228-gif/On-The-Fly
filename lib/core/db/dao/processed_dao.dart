import 'package:drift/drift.dart';

import '../app_database.dart';

part 'processed_dao.g.dart';

/// ProcessedAsset 접근 객체(중복 방지 쿼리 모음).
///
/// 핵심 책임: (1) 처리 ID 집합 조회 → 미분류 판별, (2) commit 성공분 기록.
@DriftAccessor(tables: [ProcessedAssets])
class ProcessedDao extends DatabaseAccessor<AppDatabase>
    with _$ProcessedDaoMixin {
  ProcessedDao(super.db);

  /// 처리된 자산 ID 전체 집합(미분류 판별의 기준, datamodel §3).
  Future<Set<String>> processedIdSet() async {
    final query = selectOnly(processedAssets)
      ..addColumns([processedAssets.id]);
    final rows = await query.get();
    return rows.map((r) => r.read(processedAssets.id)!).toSet();
  }

  /// 처리된 자산 총 개수(COUNT). 미분류 큐 캐시의 무효화 신호로 사용(전체 집합을
  /// 매번 로드하지 않고 값이 바뀌었는지만 싸게 확인).
  Future<int> processedCount() async {
    final countExpr = processedAssets.id.count();
    final query = selectOnly(processedAssets)..addColumns([countExpr]);
    final row = await query.getSingle();
    return row.read(countExpr) ?? 0;
  }

  /// 마지막 처리 시각(없으면 null). 성능 프리필터·streak 계산에 사용.
  Future<DateTime?> lastProcessedAt() async {
    final maxExpr = processedAssets.processedAt.max();
    final query = selectOnly(processedAssets)..addColumns([maxExpr]);
    final row = await query.getSingleOrNull();
    return row?.read(maxExpr);
  }

  /// commit 성공분 기록. **이동 후 최종 [assetId]로 호출**해야 한다(datamodel §3.1.1).
  /// 같은 id 재기록은 덮어쓴다(idempotent).
  Future<void> markProcessed({
    required String assetId,
    required String albumId,
    required int mediaType,
  }) {
    return into(processedAssets).insertOnConflictUpdate(
      ProcessedAssetsCompanion.insert(
        id: assetId,
        processedAt: DateTime.now(),
        albumId: albumId,
        mediaType: Value(mediaType),
      ),
    );
  }

  /// [from, to) 범위의 처리 건수(세션당 정리 매수·통계용).
  Future<int> countInRange(DateTime from, DateTime to) async {
    final countExpr = processedAssets.id.count();
    final query = selectOnly(processedAssets)
      ..addColumns([countExpr])
      ..where(processedAssets.processedAt.isBiggerOrEqualValue(from) &
          processedAssets.processedAt.isSmallerThanValue(to));
    final row = await query.getSingle();
    return row.read(countExpr) ?? 0;
  }

  /// 모든 처리 시각(streak 연속일 계산용).
  Future<List<DateTime>> allProcessedDates() async {
    final query = selectOnly(processedAssets)
      ..addColumns([processedAssets.processedAt]);
    final rows = await query.get();
    return rows.map((r) => r.read(processedAssets.processedAt)!).toList();
  }
}
