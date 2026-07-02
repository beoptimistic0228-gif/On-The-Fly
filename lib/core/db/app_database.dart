import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'dao/album_dao.dart';
import 'dao/processed_dao.dart';

part 'app_database.g.dart';

/// 처리한 자산 기록 — 중복 방지의 핵심(datamodel §2.1).
///
/// **미분류 판별의 단일 진실**: 미분류 = 라이브러리의 모든 자산 중
/// id 가 이 테이블에 없는 것(`assetId NOT IN (SELECT id FROM processed_assets)`).
/// OS 앨범 소속으로 판단하지 않는다(datamodel §3).
@DataClassName('ProcessedAsset')
class ProcessedAssets extends Table {
  /// 플랫폼 자산 ID (PK).
  /// **Android는 이동 후 최종(재발급된) id 를 기록**(datamodel §3.1.1).
  TextColumn get id => text()();

  /// 처리(배정) 완료 시각. "마지막 처리 이후" 계산·streak 산출에 사용.
  DateTimeColumn get processedAt => dateTime()();

  /// 배정된 앨범(FK → Albums.id).
  TextColumn get albumId =>
      text().references(Albums, #id, onDelete: KeyAction.cascade)();

  /// 0 = 사진, 1 = 영상 (통계·표시용).
  IntColumn get mediaType => integer().withDefault(const Constant(0))();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// 로컬 앨범 참조/캐시(datamodel §2.2).
@DataClassName('Album')
class Albums extends Table {
  /// 앱 내부 앨범 ID(UUID) (PK).
  TextColumn get id => text()();

  /// 사용자가 지은 앨범명.
  TextColumn get name => text()();

  /// 시스템 반영 목적지(iOS PHAssetCollection.localIdentifier / Android RELATIVE_PATH).
  /// 생성 직후 잠깐 null 가능.
  TextColumn get systemAlbumRef => text().nullable()();

  /// 커버 썸네일용 자산 ID(참조만).
  TextColumn get coverAssetId => text().nullable()();

  /// 정렬(최근 사용 순)·동기화용.
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// 앱 로컬 DB(Drift/SQLite, D3 확정).
@DriftDatabase(
  tables: [ProcessedAssets, Albums],
  daos: [ProcessedDao, AlbumDao],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  /// 테스트 주입용(인메모리 등).
  AppDatabase.forTesting(super.executor);

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) => m.createAll(),
        beforeOpen: (details) async {
          // FK(ProcessedAsset → Album) 강제.
          await customStatement('PRAGMA foreign_keys = ON');
        },
      );

  static QueryExecutor _openConnection() {
    return LazyDatabase(() async {
      final dir = await getApplicationDocumentsDirectory();
      final file = File(p.join(dir.path, 'on_the_fly.sqlite'));
      return NativeDatabase.createInBackground(file);
    });
  }
}
