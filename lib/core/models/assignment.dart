import 'album_ref.dart';

/// 배정 "예약" 1건 (stage) — 아직 시스템 반영·ProcessedAsset 기록 없음.
/// 스와이프 순간 메모리 큐에 쌓인다(datamodel §7.1).
class PendingAssignment {
  const PendingAssignment({
    required this.assetId,
    required this.album,
    required this.mediaType,
  });

  final String assetId;
  final AlbumRef album;

  /// 0 = 사진, 1 = 영상.
  final int mediaType;
}

/// commit 성공으로 실제 반영된 자산 1건.
class AssignedAsset {
  const AssignedAsset({
    required this.finalAssetId,
    required this.albumId,
    required this.mediaType,
  });

  /// **이동/태깅 후 최종 자산 ID.**
  /// - Android: 이동 후 재발급될 수 있는 현재 id (datamodel §3.1.1).
  /// - iOS    : 태깅 후에도 불변인 id.
  ///
  /// 호출측(feature/sort)은 이 값으로만 `markProcessed` 한다.
  final String finalAssetId;

  final String albumId;
  final int mediaType;
}

/// 배치 commit 결과(부분 성공 모델, architecture §2.1 / datamodel §7).
///
/// 불변식: **성공분([succeeded])만** 호출측이 `markProcessed` 한다.
/// [failed] / 취소분은 stage 큐에 유지되어 재시도 대상이 된다.
class BatchAssignResult {
  const BatchAssignResult({
    required this.succeeded,
    required this.failed,
    this.cancelled = false,
  });

  /// 시스템 반영 성공분. Android는 이동 후 최종 id(finalAssetId) 포함.
  final List<AssignedAsset> succeeded;

  /// 실패한 assetId 목록 → stage 큐 유지.
  final List<String> failed;

  /// 사용자가 시스템 동의창을 취소(전량 미반영)한 경우 true.
  /// iOS(동의창 없음)에서는 항상 false.
  final bool cancelled;

  bool get isEmpty => succeeded.isEmpty && failed.isEmpty;
}
