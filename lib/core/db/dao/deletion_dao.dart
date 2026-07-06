import 'package:drift/drift.dart';

import '../app_database.dart';

part 'deletion_dao.g.dart';

/// DeletionLog 접근 객체(삭제 활동 기록, D5 streak 전용).
///
/// 자산 id·내용은 다루지 않는다(프라이버시). 삭제 성공 시각만 append 하고,
/// streak 산정 시 삭제일 집합을 돌려준다.
@DriftAccessor(tables: [DeletionLogs])
class DeletionDao extends DatabaseAccessor<AppDatabase> with _$DeletionDaoMixin {
  DeletionDao(super.db);

  /// 삭제 성공 1건 기록([at] = 삭제 시각). 배치 아님(즉시 모델, 성공마다 1행).
  Future<void> logDeletion(DateTime at) {
    return into(deletionLogs).insert(
      DeletionLogsCompanion.insert(deletedAt: at),
    );
  }

  /// 모든 삭제 시각(streak 연속일 계산용).
  Future<List<DateTime>> allDeletionDates() async {
    final query = selectOnly(deletionLogs)..addColumns([deletionLogs.deletedAt]);
    final rows = await query.get();
    return rows.map((r) => r.read(deletionLogs.deletedAt)!).toList();
  }
}
