import 'package:drift/drift.dart' show Value;

import '../models/album_ref.dart';
import 'app_database.dart';
import 'dao/album_dao.dart';

/// 앱이 관리하는 정리 대상 앨범 리포지토리.
///
/// [PhotoService] 가 앨범 생성/목록 병합에 사용한다(core 내부 의존, 허용).
abstract class AlbumRepository {
  /// 앱이 만든 앨범 전체(최근 사용 순).
  Future<List<AlbumRef>> allAlbums();

  Future<AlbumRef?> albumById(String id);

  /// 삽입/갱신.
  Future<void> saveAlbum(AlbumRef album);

  /// 시스템 참조(systemAlbumRef)만 갱신.
  Future<void> setSystemRef(String albumId, String systemRef);
}

/// Drift 기반 구현(AlbumDao 래핑).
class DriftAlbumRepository implements AlbumRepository {
  DriftAlbumRepository(this._dao);

  final AlbumDao _dao;

  @override
  Future<List<AlbumRef>> allAlbums() async {
    final rows = await _dao.allAlbums();
    return rows.map(_toRef).toList();
  }

  @override
  Future<AlbumRef?> albumById(String id) async {
    final row = await _dao.byId(id);
    return row == null ? null : _toRef(row);
  }

  @override
  Future<void> saveAlbum(AlbumRef album) {
    return _dao.upsert(
      AlbumsCompanion(
        id: Value(album.id),
        name: Value(album.name),
        systemAlbumRef: Value(album.systemAlbumRef),
        coverAssetId: Value(album.coverAssetId),
        updatedAt: Value(album.updatedAt),
      ),
    );
  }

  @override
  Future<void> setSystemRef(String albumId, String systemRef) =>
      _dao.setSystemRef(albumId, systemRef);

  AlbumRef _toRef(Album row) => AlbumRef(
        id: row.id,
        name: row.name,
        systemAlbumRef: row.systemAlbumRef,
        coverAssetId: row.coverAssetId,
        updatedAt: row.updatedAt,
      );
}
