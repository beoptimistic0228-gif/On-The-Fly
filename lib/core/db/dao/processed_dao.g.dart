// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'processed_dao.dart';

// ignore_for_file: type=lint
mixin _$ProcessedDaoMixin on DatabaseAccessor<AppDatabase> {
  $AlbumsTable get albums => attachedDatabase.albums;
  $ProcessedAssetsTable get processedAssets => attachedDatabase.processedAssets;
  ProcessedDaoManager get managers => ProcessedDaoManager(this);
}

class ProcessedDaoManager {
  final _$ProcessedDaoMixin _db;
  ProcessedDaoManager(this._db);
  $$AlbumsTableTableManager get albums =>
      $$AlbumsTableTableManager(_db.attachedDatabase, _db.albums);
  $$ProcessedAssetsTableTableManager get processedAssets =>
      $$ProcessedAssetsTableTableManager(
        _db.attachedDatabase,
        _db.processedAssets,
      );
}
