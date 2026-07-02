import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:photo_manager/photo_manager.dart';

import '../db/album_repository.dart';
import '../db/processed_repository.dart';
import '../models/album_ref.dart';
import '../models/asset_ref.dart';
import '../models/assignment.dart';
import '../models/photo_permission.dart';
import 'photo_service.dart';

/// photo_manager 기반 [PhotoService] 구현.
///
/// 플랫폼 차이(iOS 태깅 / Android 배치 이동·동의창 / id 재발급)를 이 안에 가둔다.
/// features 는 [PhotoService] 추상 타입만 본다.
class PhotoManagerPhotoService implements PhotoService {
  PhotoManagerPhotoService(this._processedRepo, this._albumRepo);

  final ProcessedRepository _processedRepo;
  final AlbumRepository _albumRepo;

  /// stage 예약 큐(메모리). key = assetId → 단일 앨범 배정(다중 배정 없음).
  /// insertion order 유지(Dart Map) → "대기 중" 순서 표시에 사용.
  final Map<String, PendingAssignment> _pending = <String, PendingAssignment>{};

  final Random _random = Random();

  // ── 권한 ─────────────────────────────────────────────────────────────
  @override
  Future<PhotoPermission> ensurePermission() async {
    final PermissionState state = await PhotoManager.requestPermissionExtend();
    switch (state) {
      case PermissionState.authorized:
        return PhotoPermission.granted;
      case PermissionState.limited:
        // D2: 부분 접근 정리 미지원 → 호출측이 "전체 접근 유도" 안내를 띄운다.
        return PhotoPermission.limited;
      case PermissionState.notDetermined:
      case PermissionState.restricted:
      case PermissionState.denied:
        return PhotoPermission.denied;
    }
  }

  // ── 미분류 큐 ────────────────────────────────────────────────────────
  @override
  Future<List<AssetRef>> loadUnclassifiedQueue() async {
    // onlyAll: 루트("Recent"/All Photos) 하나만 받아 전체 라이브러리를 훑는다.
    final paths = await PhotoManager.getAssetPathList(
      onlyAll: true,
      type: RequestType.common, // 사진 + 영상
    );
    if (paths.isEmpty) return const <AssetRef>[];
    final all = paths.first;

    // ★ 최종 판별 기준 = 처리 ID 집합(datamodel §3). OS 앨범 소속 아님.
    final processedIds = await _processedRepo.processedIdSet();

    // NOTE: datamodel §3.2 의 createDateTime 시간 프리필터는 §3.4 엣지케이스
    // (과거 사진 나중 추가 → 생성일 프리필터에 안 걸려 누락)를 유발하므로 MVP는
    // 전체 스캔 + ID 대조로 "미분류 누락 0"을 우선한다. 대용량 성능 이슈 시
    // 프리필터를 옵션으로 재도입 가능(한계 D, 02_integrator_notes).
    final result = <AssetRef>[];
    const pageSize = 200;
    var page = 0;
    while (true) {
      final assets = await all.getAssetListPaged(page: page, size: pageSize);
      if (assets.isEmpty) break;
      for (final a in assets) {
        if (!processedIds.contains(a.id)) {
          result.add(
            AssetRef(
              id: a.id,
              mediaType: a.type == AssetType.video ? 1 : 0,
              createdAt: a.createDateTime,
            ),
          );
        }
      }
      if (assets.length < pageSize) break;
      page++;
    }
    return result;
  }

  // ── stage / unstage / pending ───────────────────────────────────────
  @override
  void stageAssignment(AssetRef asset, AlbumRef album) {
    _pending[asset.id] = PendingAssignment(
      assetId: asset.id,
      album: album,
      mediaType: asset.mediaType,
    );
  }

  @override
  void unstageAssignment(String assetId) {
    _pending.remove(assetId);
  }

  @override
  List<PendingAssignment> pendingAssignments() =>
      List<PendingAssignment>.unmodifiable(_pending.values);

  // ── commit(배치 확정) ────────────────────────────────────────────────
  @override
  Future<BatchAssignResult> commitAssignments() async {
    final pending = _pending.values.toList(growable: false);
    if (pending.isEmpty) {
      return const BatchAssignResult(succeeded: [], failed: []);
    }
    if (Platform.isIOS || Platform.isMacOS) {
      return _commitDarwin(pending);
    }
    if (Platform.isAndroid) {
      return _commitAndroid(pending);
    }
    // 미지원 플랫폼: 아무 것도 반영하지 않고 실패로 표시(큐 유지).
    return BatchAssignResult(
      succeeded: const [],
      failed: pending.map((e) => e.assetId).toList(),
    );
  }

  /// iOS/macOS: 앨범 태깅(원본 타임라인 유지). 동의창 없음, id 불변.
  Future<BatchAssignResult> _commitDarwin(
    List<PendingAssignment> pending,
  ) async {
    final succeeded = <AssignedAsset>[];
    final failed = <String>[];
    final pathCache = <String, AssetPathEntity?>{};
    // albumId → 세션 내 확보된 systemRef. stage 스냅샷(pa.album.systemAlbumRef)이
    // 낡아 null 일 때, 앨범당 딱 1회만 생성/재확보하도록 최신값을 여기서 우선한다.
    final resolvedRefByAlbum = <String, String>{};

    for (final pa in pending) {
      try {
        final asset = await AssetEntity.fromId(pa.assetId);
        if (asset == null) {
          failed.add(pa.assetId);
          continue;
        }
        // ref 우선순위: 세션 내 확보값 > stage 시점 스냅샷.
        String? ref = resolvedRefByAlbum[pa.album.id] ?? pa.album.systemAlbumRef;

        // FIX-2a: systemAlbumRef == null 경합(생성 직후 DB 반영 지연·앱 재시작)에
        // 그 앨범 전량이 실패하지 않도록, 그 자리에서 darwin 앨범을 생성/재확보한다.
        if (ref == null) {
          final created =
              await PhotoManager.editor.darwin.createAlbum(pa.album.name);
          if (created == null) {
            failed.add(pa.assetId);
            continue;
          }
          ref = created.id;
          resolvedRefByAlbum[pa.album.id] = ref; // 앨범당 1회 생성 보장(중복 방지).
          pathCache[ref] = created; // 방금 만든 path 재사용.
          await _albumRepo.setSystemRef(pa.album.id, ref); // 이후 commit 재사용.
        }

        AssetPathEntity? path = pathCache[ref];
        if (path == null && !pathCache.containsKey(ref)) {
          path = await _resolveDarwinPath(ref);
          pathCache[ref] = path;
        }
        if (path == null) {
          failed.add(pa.assetId);
          continue;
        }
        // iOS 에서 copyAssetToPath = 대상 앨범에 소프트링크(소속 추가). 원본 유지.
        await PhotoManager.editor.copyAssetToPath(asset: asset, pathEntity: path);
        succeeded.add(
          AssignedAsset(
            finalAssetId: pa.assetId, // iOS id 불변
            albumId: pa.album.id,
            mediaType: pa.mediaType,
          ),
        );
        _pending.remove(pa.assetId);
      } catch (_) {
        failed.add(pa.assetId);
      }
    }
    return BatchAssignResult(succeeded: succeeded, failed: failed);
  }

  /// Android: 앨범별로 묶어 배치 이동(동의창 1회). 이동 후 id 재발급 대응.
  Future<BatchAssignResult> _commitAndroid(
    List<PendingAssignment> pending,
  ) async {
    final succeeded = <AssignedAsset>[];
    final failed = <String>[];

    final byAlbum = <String, List<PendingAssignment>>{};
    for (final pa in pending) {
      byAlbum.putIfAbsent(pa.album.id, () => <PendingAssignment>[]).add(pa);
    }

    for (final group in byAlbum.values) {
      final album = group.first.album;
      final targetPath = _androidTargetPath(album);

      // stage 예약 → 실제 AssetEntity 해석.
      final pairs = <(PendingAssignment, AssetEntity)>[];
      for (final pa in group) {
        final entity = await AssetEntity.fromId(pa.assetId);
        if (entity == null) {
          failed.add(pa.assetId);
        } else {
          pairs.add((pa, entity));
        }
      }
      if (pairs.isEmpty) continue;

      try {
        final entities = pairs.map((p) => p.$2).toList();
        // 시스템 동의창(write request) 1회 → 배치 이동. bool = 배치 전체 성공 여부.
        // NOTE: copyAssetToPath 는 Android 11+에서 조용히 실패하므로 사용 금지
        // (02_feasibility R5). moveAssetsToPath(배치 write-request)만 사용.
        final ok = await PhotoManager.editor.android.moveAssetsToPath(
          entities: entities,
          targetPath: targetPath,
        );
        if (!ok) {
          // 실패/사용자취소 — bool 로는 구분 불가(한계 B). 전량 실패로 큐 유지.
          failed.addAll(pairs.map((p) => p.$1.assetId));
          continue;
        }
        // 이동 성공 → 이동 후 최종 id 해석(datamodel §3.1.1).
        // FIX-2b: 확정 id 만 성공(markProcessed 대상). 불확실분은 성공에서 제외해
        // failed 로 돌리고 _pending 에 유지 → 간접 유실 차단(유실 > 재등장 우선순위).
        final finalIds = await _resolveAndroidFinalIds(album, entities);
        for (var i = 0; i < pairs.length; i++) {
          final pa = pairs[i].$1;
          final finalId = finalIds[i];
          if (finalId != null) {
            // id 유지 or 안정 속성 유일 매칭 → 확정.
            succeeded.add(
              AssignedAsset(
                finalAssetId: finalId,
                albumId: album.id,
                mediaType: pa.mediaType,
              ),
            );
            _pending.remove(pa.assetId);
          } else {
            // 재발급 매칭 불확실 → 성공 아님. _pending 유지(재시도), 다음 큐 재등장 감수.
            failed.add(pa.assetId);
          }
        }
      } catch (_) {
        failed.addAll(pairs.map((p) => p.$1.assetId));
      }
    }
    return BatchAssignResult(succeeded: succeeded, failed: failed);
  }

  /// 이동 후 최종 id 해석. 반환값 `null` = **확정 불가(실패 처리 대상)**.
  ///
  /// FIX-2b: id 가 유지되면 그대로 확정. 재발급분은 대상 앨범에서 안정 속성
  /// (width·height·createDateSecond·duration, 있으면 title)으로 **유일 정확 매칭**
  /// 되는 것만 확정하고, 후보 0/다중이면 `null`(=실패)로 둔다. 순서 기반 추정
  /// 매칭(오배정→간접 유실)은 제거한다.
  ///
  /// TODO(device): OEM/스캐너별 id 재발급 동작·매칭 정확도는 실기기 검증 필요(한계 A).
  Future<List<String?>> _resolveAndroidFinalIds(
    AlbumRef album,
    List<AssetEntity> moved,
  ) async {
    final result = List<String?>.filled(moved.length, null);
    final reissued = <int>[];
    for (var i = 0; i < moved.length; i++) {
      final still = await AssetEntity.fromId(moved[i].id);
      if (still != null) {
        result[i] = moved[i].id; // id 유지 케이스 → 확정.
      } else {
        reissued.add(i); // 행 삭제+재삽입 → id 재발급 케이스.
      }
    }
    if (reissued.isEmpty) return result;

    // 앨범은 경로(RELATIVE_PATH) 기준·유일 후보만 사용(동명 폴더 오선택 방지).
    // 못 찾거나 모호하면 reissued 전부 null(=실패) → 큐 유지(간접 유실 금지).
    final path = await _resolveAndroidTargetPath(album);
    if (path == null) return result;

    final usedIds = result.whereType<String>().toSet();
    final candidates = await _loadAlbumFingerprints(path, exclude: usedIds);
    final captured = <AssetFingerprint>[
      for (final i in reissued) _fingerprintOf(moved[i]),
    ];
    final matched = matchByStableProps(captured, candidates);
    for (var k = 0; k < reissued.length; k++) {
      result[reissued[k]] = matched[k]; // 유일 정확 매칭 id 또는 null(불확실→실패).
    }
    return result;
  }

  AssetFingerprint _fingerprintOf(AssetEntity e) => AssetFingerprint(
        id: e.id,
        title: e.title,
        width: e.width,
        height: e.height,
        createSecond: e.createDateSecond,
        duration: e.duration,
      );

  /// 대상 앨범의 현재 자산 지문 목록(이동 후 재발급 매칭용). [exclude] id 는 제외.
  Future<List<AssetFingerprint>> _loadAlbumFingerprints(
    AssetPathEntity path, {
    required Set<String> exclude,
  }) async {
    final out = <AssetFingerprint>[];
    const pageSize = 200;
    const maxPages = 5; // 최근분 위주 상한(과도 스캔 방지).
    for (var page = 0; page < maxPages; page++) {
      final assets = await path.getAssetListPaged(page: page, size: pageSize);
      if (assets.isEmpty) break;
      for (final a in assets) {
        if (!exclude.contains(a.id)) out.add(_fingerprintOf(a));
      }
      if (assets.length < pageSize) break;
    }
    return out;
  }

  /// Android: 이동 목적지 RELATIVE_PATH 로 대상 앨범을 매칭. 유일 후보만 반환.
  ///
  /// FIX-2b(c): 표시명(`path.name`)만 비교하면 `DCIM/여행` vs `Pictures/여행`
  /// 같은 동명 폴더를 오선택할 수 있다. `relativePathAsync`(RELATIVE_PATH)로
  /// 경로를 비교하고, 경로를 못 얻는 기기에선 **표시명 유일 후보일 때만** 폴백한다.
  /// 후보가 0개거나 복수면 `null`(→ 재발급분 전부 실패, 간접 유실 금지).
  Future<AssetPathEntity?> _resolveAndroidTargetPath(AlbumRef album) async {
    final targetRel = _normalizeRelPath(_androidTargetPath(album));
    final paths = await PhotoManager.getAssetPathList(
      hasAll: false,
      type: RequestType.common,
    );

    // 1) RELATIVE_PATH 정확 매칭(경로 기준).
    final byPath = <AssetPathEntity>[];
    for (final p in paths) {
      final rel = await p.relativePathAsync;
      if (rel != null && _normalizeRelPath(rel) == targetRel) {
        byPath.add(p);
      }
    }
    if (byPath.length == 1) return byPath.first;
    if (byPath.length > 1) return null; // 모호 → 실패.

    // 2) 경로를 못 얻는 기기 폴백: 표시명 유일 후보만.
    final byName = paths.where((p) => p.name == album.name).toList();
    if (byName.length == 1) return byName.first;
    return null;
  }

  /// RELATIVE_PATH 비교 정규화: 앞뒤 슬래시 제거 + 소문자화(볼륨/케이스 차이 흡수).
  String _normalizeRelPath(String p) =>
      p.replaceAll(RegExp(r'^/+|/+$'), '').toLowerCase();

  // ── 앨범 ─────────────────────────────────────────────────────────────
  @override
  Future<AlbumRef> createAlbum(String name) async {
    final id = _newAlbumId();
    final now = DateTime.now();
    var ref = AlbumRef(id: id, name: name, updatedAt: now);

    // 1) 먼저 로컬 Album 행 생성(systemAlbumRef 는 잠깐 null).
    await _albumRepo.saveAlbum(ref);

    // 2) 시스템 앨범/폴더 참조 채우기.
    String? systemRef;
    if (Platform.isIOS || Platform.isMacOS) {
      final path = await PhotoManager.editor.darwin.createAlbum(name);
      systemRef = path?.id; // PHAssetCollection.localIdentifier
    } else if (Platform.isAndroid) {
      // Android 는 실제 이동(commit) 시점에 폴더가 생성된다. 목적지 경로만 확정.
      systemRef = 'Pictures/$name';
    }

    if (systemRef != null) {
      await _albumRepo.setSystemRef(id, systemRef);
      ref = ref.copyWith(systemAlbumRef: systemRef);
    }
    return ref;
  }

  @override
  Future<List<AlbumRef>> listAlbums() => _albumRepo.allAlbums();

  // ── 썸네일 ───────────────────────────────────────────────────────────
  @override
  Future<Uint8List?> thumbnail(String assetId, {int size = 200}) async {
    final asset = await AssetEntity.fromId(assetId);
    if (asset == null) return null;
    return asset.thumbnailDataWithSize(ThumbnailSize(size, size));
  }

  // ── 내부 헬퍼 ────────────────────────────────────────────────────────
  String _androidTargetPath(AlbumRef album) {
    final ref = album.systemAlbumRef;
    if (ref != null && ref.isNotEmpty) return ref;
    return 'Pictures/${album.name}';
  }

  /// iOS: localIdentifier(=systemAlbumRef)로 컬렉션을 직접 해석.
  ///
  /// FIX-2a: 기존 `getAssetPathList` 선형 스캔은 **자산 0개인 신규 앨범**을
  /// 목록에서 누락시켜 첫 commit 전량 실패를 유발했다. `AssetPathEntity.fromId`
  /// 는 id 로 컬렉션을 직접 fetch 하므로 빈 앨범도 잡힌다. 못 찾으면 StateError
  /// 를 던지므로 try/catch 로 null 폴백(호출부의 `path==null → failed` 유지).
  Future<AssetPathEntity?> _resolveDarwinPath(String ref) async {
    try {
      return await AssetPathEntity.fromId(
        ref,
        type: RequestType.common, // 사진 + 영상
        albumType: 1, // 1 = 일반 앨범(user album). createAlbum 이 만든 타입.
      );
    } catch (_) {
      return null; // 못 찾으면 null → 호출부가 failed 처리(기존 흐름 유지).
    }
  }

  String _newAlbumId() {
    final ts = DateTime.now().microsecondsSinceEpoch;
    final rnd = _random.nextInt(0x7fffffff);
    return 'alb_${ts}_$rnd';
  }
}

/// 이동 전/후 자산을 대조하기 위한 안정 속성 지문(id 재발급 매칭용, FIX-2b).
///
/// 플랫폼 채널 없이 [matchByStableProps] 로 테스트 가능하도록 순수 값 객체로 둔다.
@visibleForTesting
class AssetFingerprint {
  const AssetFingerprint({
    required this.id,
    required this.title,
    required this.width,
    required this.height,
    required this.createSecond,
    required this.duration,
  });

  final String id;
  final String? title;
  final int width;
  final int height;
  final int? createSecond;
  final int duration;

  /// id 를 제외한 안정 속성의 동일 여부.
  ///
  /// title 은 플랫폼/조회 시점에 따라 null 일 수 있어, 양쪽 모두 존재할 때만
  /// 비교 조건에 넣는다(null 로 인한 오탈락 방지). 나머지는 항상 정확 비교.
  bool sameProps(AssetFingerprint other) {
    final titleOk =
        title == null || other.title == null || title == other.title;
    return width == other.width &&
        height == other.height &&
        createSecond == other.createSecond &&
        duration == other.duration &&
        titleOk;
  }
}

/// 이동 후 재발급 자산을 대상 앨범 후보와 **유일 정확 매칭**한다(FIX-2b 핵심 로직).
///
/// 반환 리스트는 [captured] 와 같은 길이. 각 원소는:
///  - 안정 속성이 정확히 일치하는 후보가 **딱 1개**면 그 후보의 id,
///  - 후보가 **0개거나 2개 이상(모호)**이면 `null`(= 확정 불가 → 호출부가 실패 처리).
///
/// 한 후보는 최대 하나의 captured 에만 배정한다(중복 배정 금지). 순수 함수라
/// 플랫폼 채널 없이 단위 테스트 가능.
@visibleForTesting
List<String?> matchByStableProps(
  List<AssetFingerprint> captured,
  List<AssetFingerprint> candidates,
) {
  final result = List<String?>.filled(captured.length, null);
  final usedCandidateIds = <String>{};
  for (var i = 0; i < captured.length; i++) {
    final matches = candidates
        .where((c) =>
            !usedCandidateIds.contains(c.id) && c.sameProps(captured[i]))
        .toList();
    if (matches.length == 1) {
      result[i] = matches.first.id;
      usedCandidateIds.add(matches.first.id);
    }
    // 0개 또는 다중 후보 → null 유지(불확실 → 실패, 간접 유실 금지).
  }
  return result;
}
