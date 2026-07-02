import 'package:drift/drift.dart';

import '../app_database.dart';

part 'album_dao.g.dart';

/// Album 접근 객체(앱이 관리하는 정리 대상 앨범 CRUD).
@DriftAccessor(tables: [Albums])
class AlbumDao extends DatabaseAccessor<AppDatabase> with _$AlbumDaoMixin {
  AlbumDao(super.db);

  /// 최근 사용 순 전체 앨범.
  Future<List<Album>> allAlbums() {
    return (select(albums)
          ..orderBy([(t) => OrderingTerm.desc(t.updatedAt)]))
        .get();
  }

  Future<Album?> byId(String id) {
    return (select(albums)..where((t) => t.id.equals(id))).getSingleOrNull();
  }

  /// 삽입 또는 갱신(생성/이름변경/시스템참조 채움 공통).
  Future<void> upsert(AlbumsCompanion album) {
    return into(albums).insertOnConflictUpdate(album);
  }

  /// 시스템 참조만 갱신(생성 직후 systemAlbumRef 채우기).
  Future<void> setSystemRef(String id, String systemRef) {
    return (update(albums)..where((t) => t.id.equals(id))).write(
      AlbumsCompanion(
        systemAlbumRef: Value(systemRef),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }
}
