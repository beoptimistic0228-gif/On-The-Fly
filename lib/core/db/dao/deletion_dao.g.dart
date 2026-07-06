// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'deletion_dao.dart';

// ignore_for_file: type=lint
mixin _$DeletionDaoMixin on DatabaseAccessor<AppDatabase> {
  $DeletionLogsTable get deletionLogs => attachedDatabase.deletionLogs;
  DeletionDaoManager get managers => DeletionDaoManager(this);
}

class DeletionDaoManager {
  final _$DeletionDaoMixin _db;
  DeletionDaoManager(this._db);
  $$DeletionLogsTableTableManager get deletionLogs =>
      $$DeletionLogsTableTableManager(_db.attachedDatabase, _db.deletionLogs);
}
