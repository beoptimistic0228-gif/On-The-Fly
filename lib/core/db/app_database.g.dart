// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_database.dart';

// ignore_for_file: type=lint
class $AlbumsTable extends Albums with TableInfo<$AlbumsTable, Album> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $AlbumsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _systemAlbumRefMeta = const VerificationMeta(
    'systemAlbumRef',
  );
  @override
  late final GeneratedColumn<String> systemAlbumRef = GeneratedColumn<String>(
    'system_album_ref',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _coverAssetIdMeta = const VerificationMeta(
    'coverAssetId',
  );
  @override
  late final GeneratedColumn<String> coverAssetId = GeneratedColumn<String>(
    'cover_asset_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    name,
    systemAlbumRef,
    coverAssetId,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'albums';
  @override
  VerificationContext validateIntegrity(
    Insertable<Album> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('system_album_ref')) {
      context.handle(
        _systemAlbumRefMeta,
        systemAlbumRef.isAcceptableOrUnknown(
          data['system_album_ref']!,
          _systemAlbumRefMeta,
        ),
      );
    }
    if (data.containsKey('cover_asset_id')) {
      context.handle(
        _coverAssetIdMeta,
        coverAssetId.isAcceptableOrUnknown(
          data['cover_asset_id']!,
          _coverAssetIdMeta,
        ),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Album map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Album(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      systemAlbumRef: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}system_album_ref'],
      ),
      coverAssetId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}cover_asset_id'],
      ),
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $AlbumsTable createAlias(String alias) {
    return $AlbumsTable(attachedDatabase, alias);
  }
}

class Album extends DataClass implements Insertable<Album> {
  /// 앱 내부 앨범 ID(UUID) (PK).
  final String id;

  /// 사용자가 지은 앨범명.
  final String name;

  /// 시스템 반영 목적지(iOS PHAssetCollection.localIdentifier / Android RELATIVE_PATH).
  /// 생성 직후 잠깐 null 가능.
  final String? systemAlbumRef;

  /// 커버 썸네일용 자산 ID(참조만).
  final String? coverAssetId;

  /// 정렬(최근 사용 순)·동기화용.
  final DateTime updatedAt;
  const Album({
    required this.id,
    required this.name,
    this.systemAlbumRef,
    this.coverAssetId,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['name'] = Variable<String>(name);
    if (!nullToAbsent || systemAlbumRef != null) {
      map['system_album_ref'] = Variable<String>(systemAlbumRef);
    }
    if (!nullToAbsent || coverAssetId != null) {
      map['cover_asset_id'] = Variable<String>(coverAssetId);
    }
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  AlbumsCompanion toCompanion(bool nullToAbsent) {
    return AlbumsCompanion(
      id: Value(id),
      name: Value(name),
      systemAlbumRef: systemAlbumRef == null && nullToAbsent
          ? const Value.absent()
          : Value(systemAlbumRef),
      coverAssetId: coverAssetId == null && nullToAbsent
          ? const Value.absent()
          : Value(coverAssetId),
      updatedAt: Value(updatedAt),
    );
  }

  factory Album.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Album(
      id: serializer.fromJson<String>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      systemAlbumRef: serializer.fromJson<String?>(json['systemAlbumRef']),
      coverAssetId: serializer.fromJson<String?>(json['coverAssetId']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'name': serializer.toJson<String>(name),
      'systemAlbumRef': serializer.toJson<String?>(systemAlbumRef),
      'coverAssetId': serializer.toJson<String?>(coverAssetId),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  Album copyWith({
    String? id,
    String? name,
    Value<String?> systemAlbumRef = const Value.absent(),
    Value<String?> coverAssetId = const Value.absent(),
    DateTime? updatedAt,
  }) => Album(
    id: id ?? this.id,
    name: name ?? this.name,
    systemAlbumRef: systemAlbumRef.present
        ? systemAlbumRef.value
        : this.systemAlbumRef,
    coverAssetId: coverAssetId.present ? coverAssetId.value : this.coverAssetId,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  Album copyWithCompanion(AlbumsCompanion data) {
    return Album(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      systemAlbumRef: data.systemAlbumRef.present
          ? data.systemAlbumRef.value
          : this.systemAlbumRef,
      coverAssetId: data.coverAssetId.present
          ? data.coverAssetId.value
          : this.coverAssetId,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Album(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('systemAlbumRef: $systemAlbumRef, ')
          ..write('coverAssetId: $coverAssetId, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, name, systemAlbumRef, coverAssetId, updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Album &&
          other.id == this.id &&
          other.name == this.name &&
          other.systemAlbumRef == this.systemAlbumRef &&
          other.coverAssetId == this.coverAssetId &&
          other.updatedAt == this.updatedAt);
}

class AlbumsCompanion extends UpdateCompanion<Album> {
  final Value<String> id;
  final Value<String> name;
  final Value<String?> systemAlbumRef;
  final Value<String?> coverAssetId;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const AlbumsCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.systemAlbumRef = const Value.absent(),
    this.coverAssetId = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  AlbumsCompanion.insert({
    required String id,
    required String name,
    this.systemAlbumRef = const Value.absent(),
    this.coverAssetId = const Value.absent(),
    required DateTime updatedAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       name = Value(name),
       updatedAt = Value(updatedAt);
  static Insertable<Album> custom({
    Expression<String>? id,
    Expression<String>? name,
    Expression<String>? systemAlbumRef,
    Expression<String>? coverAssetId,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (systemAlbumRef != null) 'system_album_ref': systemAlbumRef,
      if (coverAssetId != null) 'cover_asset_id': coverAssetId,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  AlbumsCompanion copyWith({
    Value<String>? id,
    Value<String>? name,
    Value<String?>? systemAlbumRef,
    Value<String?>? coverAssetId,
    Value<DateTime>? updatedAt,
    Value<int>? rowid,
  }) {
    return AlbumsCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      systemAlbumRef: systemAlbumRef ?? this.systemAlbumRef,
      coverAssetId: coverAssetId ?? this.coverAssetId,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (systemAlbumRef.present) {
      map['system_album_ref'] = Variable<String>(systemAlbumRef.value);
    }
    if (coverAssetId.present) {
      map['cover_asset_id'] = Variable<String>(coverAssetId.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('AlbumsCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('systemAlbumRef: $systemAlbumRef, ')
          ..write('coverAssetId: $coverAssetId, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ProcessedAssetsTable extends ProcessedAssets
    with TableInfo<$ProcessedAssetsTable, ProcessedAsset> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ProcessedAssetsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _processedAtMeta = const VerificationMeta(
    'processedAt',
  );
  @override
  late final GeneratedColumn<DateTime> processedAt = GeneratedColumn<DateTime>(
    'processed_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _albumIdMeta = const VerificationMeta(
    'albumId',
  );
  @override
  late final GeneratedColumn<String> albumId = GeneratedColumn<String>(
    'album_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES albums (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _mediaTypeMeta = const VerificationMeta(
    'mediaType',
  );
  @override
  late final GeneratedColumn<int> mediaType = GeneratedColumn<int>(
    'media_type',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  @override
  List<GeneratedColumn> get $columns => [id, processedAt, albumId, mediaType];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'processed_assets';
  @override
  VerificationContext validateIntegrity(
    Insertable<ProcessedAsset> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('processed_at')) {
      context.handle(
        _processedAtMeta,
        processedAt.isAcceptableOrUnknown(
          data['processed_at']!,
          _processedAtMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_processedAtMeta);
    }
    if (data.containsKey('album_id')) {
      context.handle(
        _albumIdMeta,
        albumId.isAcceptableOrUnknown(data['album_id']!, _albumIdMeta),
      );
    } else if (isInserting) {
      context.missing(_albumIdMeta);
    }
    if (data.containsKey('media_type')) {
      context.handle(
        _mediaTypeMeta,
        mediaType.isAcceptableOrUnknown(data['media_type']!, _mediaTypeMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ProcessedAsset map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ProcessedAsset(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      processedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}processed_at'],
      )!,
      albumId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}album_id'],
      )!,
      mediaType: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}media_type'],
      )!,
    );
  }

  @override
  $ProcessedAssetsTable createAlias(String alias) {
    return $ProcessedAssetsTable(attachedDatabase, alias);
  }
}

class ProcessedAsset extends DataClass implements Insertable<ProcessedAsset> {
  /// 플랫폼 자산 ID (PK).
  /// **Android는 이동 후 최종(재발급된) id 를 기록**(datamodel §3.1.1).
  final String id;

  /// 처리(배정) 완료 시각. "마지막 처리 이후" 계산·streak 산출에 사용.
  final DateTime processedAt;

  /// 배정된 앨범(FK → Albums.id).
  final String albumId;

  /// 0 = 사진, 1 = 영상 (통계·표시용).
  final int mediaType;
  const ProcessedAsset({
    required this.id,
    required this.processedAt,
    required this.albumId,
    required this.mediaType,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['processed_at'] = Variable<DateTime>(processedAt);
    map['album_id'] = Variable<String>(albumId);
    map['media_type'] = Variable<int>(mediaType);
    return map;
  }

  ProcessedAssetsCompanion toCompanion(bool nullToAbsent) {
    return ProcessedAssetsCompanion(
      id: Value(id),
      processedAt: Value(processedAt),
      albumId: Value(albumId),
      mediaType: Value(mediaType),
    );
  }

  factory ProcessedAsset.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ProcessedAsset(
      id: serializer.fromJson<String>(json['id']),
      processedAt: serializer.fromJson<DateTime>(json['processedAt']),
      albumId: serializer.fromJson<String>(json['albumId']),
      mediaType: serializer.fromJson<int>(json['mediaType']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'processedAt': serializer.toJson<DateTime>(processedAt),
      'albumId': serializer.toJson<String>(albumId),
      'mediaType': serializer.toJson<int>(mediaType),
    };
  }

  ProcessedAsset copyWith({
    String? id,
    DateTime? processedAt,
    String? albumId,
    int? mediaType,
  }) => ProcessedAsset(
    id: id ?? this.id,
    processedAt: processedAt ?? this.processedAt,
    albumId: albumId ?? this.albumId,
    mediaType: mediaType ?? this.mediaType,
  );
  ProcessedAsset copyWithCompanion(ProcessedAssetsCompanion data) {
    return ProcessedAsset(
      id: data.id.present ? data.id.value : this.id,
      processedAt: data.processedAt.present
          ? data.processedAt.value
          : this.processedAt,
      albumId: data.albumId.present ? data.albumId.value : this.albumId,
      mediaType: data.mediaType.present ? data.mediaType.value : this.mediaType,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ProcessedAsset(')
          ..write('id: $id, ')
          ..write('processedAt: $processedAt, ')
          ..write('albumId: $albumId, ')
          ..write('mediaType: $mediaType')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, processedAt, albumId, mediaType);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ProcessedAsset &&
          other.id == this.id &&
          other.processedAt == this.processedAt &&
          other.albumId == this.albumId &&
          other.mediaType == this.mediaType);
}

class ProcessedAssetsCompanion extends UpdateCompanion<ProcessedAsset> {
  final Value<String> id;
  final Value<DateTime> processedAt;
  final Value<String> albumId;
  final Value<int> mediaType;
  final Value<int> rowid;
  const ProcessedAssetsCompanion({
    this.id = const Value.absent(),
    this.processedAt = const Value.absent(),
    this.albumId = const Value.absent(),
    this.mediaType = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ProcessedAssetsCompanion.insert({
    required String id,
    required DateTime processedAt,
    required String albumId,
    this.mediaType = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       processedAt = Value(processedAt),
       albumId = Value(albumId);
  static Insertable<ProcessedAsset> custom({
    Expression<String>? id,
    Expression<DateTime>? processedAt,
    Expression<String>? albumId,
    Expression<int>? mediaType,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (processedAt != null) 'processed_at': processedAt,
      if (albumId != null) 'album_id': albumId,
      if (mediaType != null) 'media_type': mediaType,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ProcessedAssetsCompanion copyWith({
    Value<String>? id,
    Value<DateTime>? processedAt,
    Value<String>? albumId,
    Value<int>? mediaType,
    Value<int>? rowid,
  }) {
    return ProcessedAssetsCompanion(
      id: id ?? this.id,
      processedAt: processedAt ?? this.processedAt,
      albumId: albumId ?? this.albumId,
      mediaType: mediaType ?? this.mediaType,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (processedAt.present) {
      map['processed_at'] = Variable<DateTime>(processedAt.value);
    }
    if (albumId.present) {
      map['album_id'] = Variable<String>(albumId.value);
    }
    if (mediaType.present) {
      map['media_type'] = Variable<int>(mediaType.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ProcessedAssetsCompanion(')
          ..write('id: $id, ')
          ..write('processedAt: $processedAt, ')
          ..write('albumId: $albumId, ')
          ..write('mediaType: $mediaType, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $AlbumsTable albums = $AlbumsTable(this);
  late final $ProcessedAssetsTable processedAssets = $ProcessedAssetsTable(
    this,
  );
  late final ProcessedDao processedDao = ProcessedDao(this as AppDatabase);
  late final AlbumDao albumDao = AlbumDao(this as AppDatabase);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [albums, processedAssets];
  @override
  StreamQueryUpdateRules get streamUpdateRules => const StreamQueryUpdateRules([
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'albums',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('processed_assets', kind: UpdateKind.delete)],
    ),
  ]);
}

typedef $$AlbumsTableCreateCompanionBuilder =
    AlbumsCompanion Function({
      required String id,
      required String name,
      Value<String?> systemAlbumRef,
      Value<String?> coverAssetId,
      required DateTime updatedAt,
      Value<int> rowid,
    });
typedef $$AlbumsTableUpdateCompanionBuilder =
    AlbumsCompanion Function({
      Value<String> id,
      Value<String> name,
      Value<String?> systemAlbumRef,
      Value<String?> coverAssetId,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });

final class $$AlbumsTableReferences
    extends BaseReferences<_$AppDatabase, $AlbumsTable, Album> {
  $$AlbumsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static MultiTypedResultKey<$ProcessedAssetsTable, List<ProcessedAsset>>
  _processedAssetsRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.processedAssets,
    aliasName: 'albums__id__processed_assets__album_id',
  );

  $$ProcessedAssetsTableProcessedTableManager get processedAssetsRefs {
    final manager = $$ProcessedAssetsTableTableManager(
      $_db,
      $_db.processedAssets,
    ).filter((f) => f.albumId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _processedAssetsRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$AlbumsTableFilterComposer
    extends Composer<_$AppDatabase, $AlbumsTable> {
  $$AlbumsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get systemAlbumRef => $composableBuilder(
    column: $table.systemAlbumRef,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get coverAssetId => $composableBuilder(
    column: $table.coverAssetId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  Expression<bool> processedAssetsRefs(
    Expression<bool> Function($$ProcessedAssetsTableFilterComposer f) f,
  ) {
    final $$ProcessedAssetsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.processedAssets,
      getReferencedColumn: (t) => t.albumId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ProcessedAssetsTableFilterComposer(
            $db: $db,
            $table: $db.processedAssets,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$AlbumsTableOrderingComposer
    extends Composer<_$AppDatabase, $AlbumsTable> {
  $$AlbumsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get systemAlbumRef => $composableBuilder(
    column: $table.systemAlbumRef,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get coverAssetId => $composableBuilder(
    column: $table.coverAssetId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$AlbumsTableAnnotationComposer
    extends Composer<_$AppDatabase, $AlbumsTable> {
  $$AlbumsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get systemAlbumRef => $composableBuilder(
    column: $table.systemAlbumRef,
    builder: (column) => column,
  );

  GeneratedColumn<String> get coverAssetId => $composableBuilder(
    column: $table.coverAssetId,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  Expression<T> processedAssetsRefs<T extends Object>(
    Expression<T> Function($$ProcessedAssetsTableAnnotationComposer a) f,
  ) {
    final $$ProcessedAssetsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.processedAssets,
      getReferencedColumn: (t) => t.albumId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ProcessedAssetsTableAnnotationComposer(
            $db: $db,
            $table: $db.processedAssets,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$AlbumsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $AlbumsTable,
          Album,
          $$AlbumsTableFilterComposer,
          $$AlbumsTableOrderingComposer,
          $$AlbumsTableAnnotationComposer,
          $$AlbumsTableCreateCompanionBuilder,
          $$AlbumsTableUpdateCompanionBuilder,
          (Album, $$AlbumsTableReferences),
          Album,
          PrefetchHooks Function({bool processedAssetsRefs})
        > {
  $$AlbumsTableTableManager(_$AppDatabase db, $AlbumsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$AlbumsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$AlbumsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$AlbumsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String?> systemAlbumRef = const Value.absent(),
                Value<String?> coverAssetId = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => AlbumsCompanion(
                id: id,
                name: name,
                systemAlbumRef: systemAlbumRef,
                coverAssetId: coverAssetId,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String name,
                Value<String?> systemAlbumRef = const Value.absent(),
                Value<String?> coverAssetId = const Value.absent(),
                required DateTime updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => AlbumsCompanion.insert(
                id: id,
                name: name,
                systemAlbumRef: systemAlbumRef,
                coverAssetId: coverAssetId,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) =>
                    (e.readTable(table), $$AlbumsTableReferences(db, table, e)),
              )
              .toList(),
          prefetchHooksCallback: ({processedAssetsRefs = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [
                if (processedAssetsRefs) db.processedAssets,
              ],
              addJoins: null,
              getPrefetchedDataCallback: (items) async {
                return [
                  if (processedAssetsRefs)
                    await $_getPrefetchedData<
                      Album,
                      $AlbumsTable,
                      ProcessedAsset
                    >(
                      currentTable: table,
                      referencedTable: $$AlbumsTableReferences
                          ._processedAssetsRefsTable(db),
                      managerFromTypedResult: (p0) => $$AlbumsTableReferences(
                        db,
                        table,
                        p0,
                      ).processedAssetsRefs,
                      referencedItemsForCurrentItem: (item, referencedItems) =>
                          referencedItems.where((e) => e.albumId == item.id),
                      typedResults: items,
                    ),
                ];
              },
            );
          },
        ),
      );
}

typedef $$AlbumsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $AlbumsTable,
      Album,
      $$AlbumsTableFilterComposer,
      $$AlbumsTableOrderingComposer,
      $$AlbumsTableAnnotationComposer,
      $$AlbumsTableCreateCompanionBuilder,
      $$AlbumsTableUpdateCompanionBuilder,
      (Album, $$AlbumsTableReferences),
      Album,
      PrefetchHooks Function({bool processedAssetsRefs})
    >;
typedef $$ProcessedAssetsTableCreateCompanionBuilder =
    ProcessedAssetsCompanion Function({
      required String id,
      required DateTime processedAt,
      required String albumId,
      Value<int> mediaType,
      Value<int> rowid,
    });
typedef $$ProcessedAssetsTableUpdateCompanionBuilder =
    ProcessedAssetsCompanion Function({
      Value<String> id,
      Value<DateTime> processedAt,
      Value<String> albumId,
      Value<int> mediaType,
      Value<int> rowid,
    });

final class $$ProcessedAssetsTableReferences
    extends
        BaseReferences<_$AppDatabase, $ProcessedAssetsTable, ProcessedAsset> {
  $$ProcessedAssetsTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $AlbumsTable _albumIdTable(_$AppDatabase db) =>
      db.albums.createAlias('processed_assets__album_id__albums__id');

  $$AlbumsTableProcessedTableManager get albumId {
    final $_column = $_itemColumn<String>('album_id')!;

    final manager = $$AlbumsTableTableManager(
      $_db,
      $_db.albums,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_albumIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$ProcessedAssetsTableFilterComposer
    extends Composer<_$AppDatabase, $ProcessedAssetsTable> {
  $$ProcessedAssetsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get processedAt => $composableBuilder(
    column: $table.processedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get mediaType => $composableBuilder(
    column: $table.mediaType,
    builder: (column) => ColumnFilters(column),
  );

  $$AlbumsTableFilterComposer get albumId {
    final $$AlbumsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.albumId,
      referencedTable: $db.albums,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$AlbumsTableFilterComposer(
            $db: $db,
            $table: $db.albums,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ProcessedAssetsTableOrderingComposer
    extends Composer<_$AppDatabase, $ProcessedAssetsTable> {
  $$ProcessedAssetsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get processedAt => $composableBuilder(
    column: $table.processedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get mediaType => $composableBuilder(
    column: $table.mediaType,
    builder: (column) => ColumnOrderings(column),
  );

  $$AlbumsTableOrderingComposer get albumId {
    final $$AlbumsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.albumId,
      referencedTable: $db.albums,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$AlbumsTableOrderingComposer(
            $db: $db,
            $table: $db.albums,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ProcessedAssetsTableAnnotationComposer
    extends Composer<_$AppDatabase, $ProcessedAssetsTable> {
  $$ProcessedAssetsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<DateTime> get processedAt => $composableBuilder(
    column: $table.processedAt,
    builder: (column) => column,
  );

  GeneratedColumn<int> get mediaType =>
      $composableBuilder(column: $table.mediaType, builder: (column) => column);

  $$AlbumsTableAnnotationComposer get albumId {
    final $$AlbumsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.albumId,
      referencedTable: $db.albums,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$AlbumsTableAnnotationComposer(
            $db: $db,
            $table: $db.albums,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ProcessedAssetsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ProcessedAssetsTable,
          ProcessedAsset,
          $$ProcessedAssetsTableFilterComposer,
          $$ProcessedAssetsTableOrderingComposer,
          $$ProcessedAssetsTableAnnotationComposer,
          $$ProcessedAssetsTableCreateCompanionBuilder,
          $$ProcessedAssetsTableUpdateCompanionBuilder,
          (ProcessedAsset, $$ProcessedAssetsTableReferences),
          ProcessedAsset,
          PrefetchHooks Function({bool albumId})
        > {
  $$ProcessedAssetsTableTableManager(
    _$AppDatabase db,
    $ProcessedAssetsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ProcessedAssetsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ProcessedAssetsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ProcessedAssetsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<DateTime> processedAt = const Value.absent(),
                Value<String> albumId = const Value.absent(),
                Value<int> mediaType = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ProcessedAssetsCompanion(
                id: id,
                processedAt: processedAt,
                albumId: albumId,
                mediaType: mediaType,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required DateTime processedAt,
                required String albumId,
                Value<int> mediaType = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ProcessedAssetsCompanion.insert(
                id: id,
                processedAt: processedAt,
                albumId: albumId,
                mediaType: mediaType,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$ProcessedAssetsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({albumId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (albumId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.albumId,
                                referencedTable:
                                    $$ProcessedAssetsTableReferences
                                        ._albumIdTable(db),
                                referencedColumn:
                                    $$ProcessedAssetsTableReferences
                                        ._albumIdTable(db)
                                        .id,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$ProcessedAssetsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ProcessedAssetsTable,
      ProcessedAsset,
      $$ProcessedAssetsTableFilterComposer,
      $$ProcessedAssetsTableOrderingComposer,
      $$ProcessedAssetsTableAnnotationComposer,
      $$ProcessedAssetsTableCreateCompanionBuilder,
      $$ProcessedAssetsTableUpdateCompanionBuilder,
      (ProcessedAsset, $$ProcessedAssetsTableReferences),
      ProcessedAsset,
      PrefetchHooks Function({bool albumId})
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$AlbumsTableTableManager get albums =>
      $$AlbumsTableTableManager(_db, _db.albums);
  $$ProcessedAssetsTableTableManager get processedAssets =>
      $$ProcessedAssetsTableTableManager(_db, _db.processedAssets);
}
