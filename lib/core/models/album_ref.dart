/// 로컬 앨범 참조 — 순수 DTO(datamodel §2.2 Album 테이블의 표현형).
///
/// 앱이 관리하는 정리 대상 앨범. iOS는 PhotoKit 앨범(태깅 목적지),
/// Android는 대상 폴더(RELATIVE_PATH)를 [systemAlbumRef]로 가리킨다.
class AlbumRef {
  const AlbumRef({
    required this.id,
    required this.name,
    this.systemAlbumRef,
    this.coverAssetId,
    required this.updatedAt,
  });

  /// 앱 내부 앨범 ID(UUID).
  final String id;

  /// 사용자가 지은 앨범명.
  final String name;

  /// 시스템 반영 목적지 식별자.
  /// - iOS  : `PHAssetCollection.localIdentifier` (= AssetPathEntity.id)
  /// - Android: 대상 RELATIVE_PATH (예: `Pictures/여행2026`)
  ///
  /// 새 앨범 생성 직후 잠깐 null 일 수 있다(datamodel §2.2).
  final String? systemAlbumRef;

  /// 커버 썸네일용 자산 ID(원본 아님, 참조만). 없으면 null.
  final String? coverAssetId;

  /// 정렬(최근 사용 순)·동기화용.
  final DateTime updatedAt;

  AlbumRef copyWith({
    String? name,
    String? systemAlbumRef,
    String? coverAssetId,
    DateTime? updatedAt,
  }) {
    return AlbumRef(
      id: id,
      name: name ?? this.name,
      systemAlbumRef: systemAlbumRef ?? this.systemAlbumRef,
      coverAssetId: coverAssetId ?? this.coverAssetId,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  bool operator ==(Object other) => other is AlbumRef && other.id == id;

  @override
  int get hashCode => id.hashCode;
}
