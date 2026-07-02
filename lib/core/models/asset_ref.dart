/// 미분류 큐의 자산 1건 — 순수 DTO(플랫폼 타입 노출 금지, architecture §2.1 규칙3).
///
/// 원본 바이트는 절대 담지 않는다. 참조([id])만 보관한다(datamodel §1).
/// 썸네일은 [PhotoService.thumbnail]로 필요 시점에 지연 로드한다.
class AssetRef {
  const AssetRef({
    required this.id,
    required this.mediaType,
    this.createdAt,
  });

  /// 플랫폼 자산 ID (iOS `PHAsset.localIdentifier` / Android MediaStore `_ID`).
  final String id;

  /// 0 = 사진, 1 = 영상 (datamodel §2.1).
  final int mediaType;

  /// 원본 생성 시각(있으면). 성능 프리필터/정렬 표시용. 없으면 null.
  final DateTime? createdAt;

  @override
  bool operator ==(Object other) =>
      other is AssetRef && other.id == id;

  @override
  int get hashCode => id.hashCode;
}
