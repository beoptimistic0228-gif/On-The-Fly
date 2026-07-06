import 'dao/deletion_dao.dart';

/// 삭제 활동 기록 리포지토리 — architecture §2.2 경계 계약(D5).
///
/// features(정리 컨트롤러)는 삭제 성공 시 [logDeletion]을 1회 호출한다.
/// 자산 id·내용은 넘기지 않는다(프라이버시): 시각만 기록해 streak 에 반영한다.
abstract class DeletionRepository {
  /// 삭제 성공 1건 기록(현재 시각). streak "삭제일" 원천에 append.
  Future<void> logDeletion();

  /// 모든 삭제 시각(streak 합집합 계산용).
  Future<List<DateTime>> deletionDates();
}

/// Drift 기반 구현(DeletionDao 래핑).
class DriftDeletionRepository implements DeletionRepository {
  DriftDeletionRepository(this._dao);

  final DeletionDao _dao;

  @override
  Future<void> logDeletion() => _dao.logDeletion(DateTime.now());

  @override
  Future<List<DateTime>> deletionDates() => _dao.allDeletionDates();
}
