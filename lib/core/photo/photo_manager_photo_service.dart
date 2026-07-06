import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show immutable, visibleForTesting;
import 'package:flutter/services.dart' show MethodChannel;
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
  PhotoManagerPhotoService(this._processedRepo, this._albumRepo) {
    // supportsDeletion 은 UI 가 **동기** 조회하는데 Android 지원 판정엔 SDK_INT
    // (플랫폼 채널·비동기)가 필요하다. onboarding→home→정리 화면에 도달하기 훨씬
    // 전에 미리(백그라운드) 캐시해 둔다. 실패해도 무해(기본값 = 미지원 → 버튼 숨김).
    // ensurePermission 에서도 await 로 한 번 더 보장한다(온보딩 게이트).
    if (Platform.isAndroid) {
      unawaited(_ensureAndroidSdkInt());
    }
  }

  final ProcessedRepository _processedRepo;
  final AlbumRepository _albumRepo;

  /// 네이티브 배치 이동 채널(Android C-5/C-4). 전체 pending 을 단일 쓰기 동의로 이동.
  /// android/app .../MediaMoveHandler.kt 와 짝. iOS/데스크톱에선 사용하지 않는다.
  /// D5: 여기에 `sdkInt`(삭제 지원 판정용) 초경량 메서드를 추가로 얹었다.
  static const MethodChannel _mediaChannel =
      MethodChannel('on_the_fly/media_store');

  /// Android SDK_INT 캐시(삭제 지원 판정용, D5-5). null = 미조회. 플랫폼 채널로
  /// 1회 조회 후 보관한다. iOS/데스크톱에선 사용하지 않는다.
  int? _androidSdkInt;

  /// stage 예약 큐(메모리). key = assetId → 단일 앨범 배정(다중 배정 없음).
  /// insertion order 유지(Dart Map) → "대기 중" 순서 표시에 사용.
  final Map<String, PendingAssignment> _pending = <String, PendingAssignment>{};

  /// 미분류 큐 스캔 캐시(성능). 관측 신호(총 자산수·처리 집합)가 그대로면 재스캔을
  /// 건너뛴다. 신호가 바뀌면(신규 자산·commit·삭제) 무효화되어 정확한 재로드가 돈다
  /// → "카운트 근사, 큐는 정확" 불변식 유지. 앱 수명(싱글턴) 동안만 유효(콜드스타트 1회 스캔).
  _QueueScanCache? _queueCache;

  final Random _random = Random();

  // ── 권한 ─────────────────────────────────────────────────────────────
  @override
  Future<PhotoPermission> ensurePermission() async {
    // 온보딩 게이트에서 SDK_INT 를 확정 캐시(정리 화면 도달 전 supportsDeletion 정확).
    if (Platform.isAndroid) {
      await _ensureAndroidSdkInt();
    }
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

  @override
  Future<void> openSystemSettings() => PhotoManager.openSetting();

  @override
  // RequestType.common(사진+영상) = 이 앱이 다루는 미디어 범위와 일치.
  // photo_manager 내부에서 iOS/Android 채널만 호출하므로 그 외 플랫폼은 no-op(안전).
  Future<void> presentLimited() =>
      PhotoManager.presentLimited(type: RequestType.common);

  // ── 미분류 큐 ────────────────────────────────────────────────────────
  @override
  Future<List<AssetRef>> loadUnclassifiedQueue() async {
    // onlyAll: 루트("Recent"/All Photos) 하나만 받아 전체 라이브러리를 훑는다.
    final paths = await PhotoManager.getAssetPathList(
      onlyAll: true,
      type: RequestType.common, // 사진 + 영상
    );
    if (paths.isEmpty) {
      _queueCache = const _QueueScanCache(
        _ScanSignature(total: 0, processedCount: 0, lastProcessedMicros: null),
        <AssetRef>[],
      );
      return const <AssetRef>[];
    }
    final all = paths.first;

    // ── 성능(재스캔 회피): 전체 자산수 + 처리 집합의 "지문"이 지난 로드와 같으면
    // 스캔 결과도 같으므로 캐시를 그대로 돌려준다. 이 값들은 모두 싼 카운트 쿼리다
    // (assetCountAsync = 네이티브 COUNT, processedCount = SQL COUNT). 16k 페이징
    // (수십 초)을 홈 재진입/정리 재진입마다 반복하지 않게 하는 게 목적이다.
    //
    // 왜 안전한가(불변식): 신규 자산이 들어오면 total 이, commit/삭제가 있으면
    // processedCount·lastProcessedAt 가 바뀌어 캐시 미스 → 정확한 재스캔이 돈다.
    // 즉 관측 가능한 변화가 있으면 항상 실제 로드다("큐는 정확"). 총 개수가 동일한
    // 외부 삭제+추가(동시 발생·commit 없음)라는 병적 케이스만 근사이며, 다음 카운트
    // 변화에서 자가 치유된다("카운트는 근사 허용"). 설계 근거: 02_integrator_notes 한계 D.
    final total = await all.assetCountAsync;
    final processedCount = await _processedRepo.processedCount();
    final lastProcessedAt = await _processedRepo.lastProcessedAt();
    final signature = _ScanSignature(
      total: total,
      processedCount: processedCount,
      lastProcessedMicros: lastProcessedAt?.microsecondsSinceEpoch,
    );
    final cache = _queueCache;
    if (cache != null && cache.signature == signature) {
      return cache.queue;
    }

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
    final frozen = List<AssetRef>.unmodifiable(result);
    _queueCache = _QueueScanCache(signature, frozen);
    return frozen;
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
    final BatchAssignResult result;
    if (Platform.isIOS || Platform.isMacOS) {
      result = await _commitDarwin(pending);
    } else if (Platform.isAndroid) {
      result = await _commitAndroid(pending);
    } else {
      // 미지원 플랫폼: 아무 것도 반영하지 않고 실패로 표시(큐 유지).
      result = BatchAssignResult(
        succeeded: const [],
        failed: pending.map((e) => e.assetId).toList(),
      );
    }
    // 처리분이 생겼으면 미분류 큐 캐시를 버린다(다음 로드는 정확한 재스캔).
    if (result.succeeded.isNotEmpty) {
      _queueCache = null;
    }
    return result;
  }

  // ── 단건 삭제(D5, 즉시·영구) ─────────────────────────────────────────
  @override
  bool get supportsDeletion {
    // iOS/macOS: PhotoKit deleteAssets 는 항상 지원(시스템 확인창+최근삭제됨).
    if (Platform.isIOS || Platform.isMacOS) return true;
    // Android: API 30+ 만. SDK_INT 미조회(null) 상태는 보수적으로 미지원.
    if (Platform.isAndroid) {
      final sdk = _androidSdkInt;
      return sdk != null && sdk >= 30;
    }
    return false;
  }

  @override
  Future<bool> deleteAsset(AssetRef asset) async {
    // 2차 방어(UI 버튼 미노출이 1차): 지원 안 되는 플랫폼/구버전은 즉시 false.
    if (Platform.isAndroid) {
      final sdk = await _ensureAndroidSdkInt();
      if (sdk == null || sdk < 30) return false;
    } else if (!(Platform.isIOS || Platform.isMacOS)) {
      return false;
    }

    final List<String> deleted;
    try {
      // deleteWithIds → Android(API30+) createDeleteRequest(영구)+동의창 1회 /
      // iOS deleteAssets(시스템 확인창)+최근삭제됨. 반환 = 실제 삭제된 id 리스트,
      // 취소·실패면 빈 리스트(§9 Q1·Q4 구분 불가).
      deleted = await PhotoManager.editor.deleteWithIds(<String>[asset.id]);
    } catch (_) {
      return false;
    }
    return applyDeletionResult(asset.id, deleted);
  }

  /// `deleteWithIds` 반환 → 성공 여부 매핑 + 서비스 내부 정리(§0.3).
  ///
  /// 플랫폼/채널 없이 단위 테스트 가능하도록 순수 로직으로 분리(deleteAsset 은
  /// 플랫폼 호출만 담당). 성공(삭제 id 포함) 시:
  ///  - 혹시 배정 예약(`_pending`)에 있으면 제거 → commit 이 사라진 자산을 이동
  ///    시도하는 혼선을 원천 차단(정상 흐름상 현재 카드는 pending 에 없지만 방어).
  ///  - 스캔 캐시 무효화 → 다음 loadUnclassifiedQueue 는 정확 재스캔(§9 Q6, 카운트
  ///    지문 자가무효화에 더해 명시 무효화로 세션 도중 삭제도 안전).
  @visibleForTesting
  bool applyDeletionResult(String assetId, List<String> deletedIds) {
    final ok = deletedIds.contains(assetId);
    if (ok) {
      _pending.remove(assetId);
      _queueCache = null;
    }
    return ok;
  }

  /// Android SDK_INT 를 플랫폼 채널로 1회 조회·캐시(삭제 지원 판정). 채널 미배선·
  /// 예외 시 미상(null 유지) → 보수적으로 미지원 취급(삭제 버튼 숨김·삭제 차단).
  Future<int?> _ensureAndroidSdkInt() async {
    if (!Platform.isAndroid) return null;
    final cached = _androidSdkInt;
    if (cached != null) return cached;
    try {
      _androidSdkInt = await _mediaChannel.invokeMethod<int>('sdkInt');
    } catch (_) {
      // 미조회 유지(기본 미지원).
    }
    return _androidSdkInt;
  }

  /// 테스트 전용: SDK_INT 캐시 강제 주입(플랫폼 채널 없이 supportsDeletion 검증).
  @visibleForTesting
  void debugSetAndroidSdkInt(int? sdk) => _androidSdkInt = sdk;

  /// 테스트 전용: 스캔 캐시 프라임(삭제 시 무효화 검증용).
  @visibleForTesting
  void debugPrimeQueueCache(List<AssetRef> queue) {
    _queueCache = _QueueScanCache(
      const _ScanSignature(
          total: 0, processedCount: 0, lastProcessedMicros: null),
      List<AssetRef>.unmodifiable(queue),
    );
  }

  /// 테스트 전용: 스캔 캐시가 살아있는지.
  @visibleForTesting
  bool get debugQueueCached => _queueCache != null;

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

  /// Android: **전체 pending 을 단일 쓰기 동의로** 이동(QA C-5). 앨범별 이동을
  /// 앨범 수만큼 동의창을 띄우던 것을, 네이티브 채널이 `createWriteRequest` 한 번으로
  /// 전량 승인받은 뒤 앨범별 RELATIVE_PATH 갱신을 추가 동의 없이 수행한다.
  ///
  /// 취소(QA C-4): 채널이 RESULT_CANCELED 를 명시 반환 → `cancelled=true`(예약 유지,
  /// failed 0). 이동 후 id 재발급은 기존 [_resolveAndroidFinalIds] 로 대응.
  ///
  /// API<30(createWriteRequest 미지원)·채널 미배선 시 [_commitAndroidLegacy] 로 폴백.
  Future<BatchAssignResult> _commitAndroid(
    List<PendingAssignment> pending,
  ) async {
    // 앨범별 그룹(이동 후 최종 id 해석에 필요) + 전체 이동 계획(flat) 작성.
    final byAlbum = <String, List<PendingAssignment>>{};
    for (final pa in pending) {
      byAlbum.putIfAbsent(pa.album.id, () => <PendingAssignment>[]).add(pa);
    }

    final entityById = <String, AssetEntity>{};
    final failedResolve = <String>[];
    final moves = <Map<String, Object>>[];
    for (final pa in pending) {
      final entity = await AssetEntity.fromId(pa.assetId);
      if (entity == null) {
        failedResolve.add(pa.assetId); // 이미 라이브러리에 없음 → 실패(큐 유지).
        continue;
      }
      entityById[pa.assetId] = entity;
      moves.add(<String, Object>{
        'id': pa.assetId,
        'mediaType': pa.mediaType, // 0=사진/1=영상 → 네이티브 URI 구성.
        'relativePath': _androidTargetPath(pa.album),
      });
    }
    if (moves.isEmpty) {
      // 해석 가능한 자산 0 → 전량 실패(큐 유지). 취소 아님.
      return BatchAssignResult(succeeded: const [], failed: failedResolve);
    }

    // ★ 단일 createWriteRequest → 앨범별 이동(추가 동의 없음).
    final MoveChannelResult res;
    try {
      final raw =
          await _mediaChannel.invokeMethod<Object?>('moveToAlbums', {
        'moves': moves,
      });
      res = parseMoveChannelResult(raw);
    } catch (_) {
      // 채널 예외(미배선·액티비티 없음 등) → 레거시 per-album 경로로 폴백(동작 보장).
      return _commitAndroidLegacy(pending);
    }

    if (res.unsupported) {
      // API<30: createWriteRequest 미지원 → 레거시(단일 targetPath 당 동의 1회).
      return _commitAndroidLegacy(pending);
    }
    if (res.cancelled) {
      // C-4: 사용자가 동의창 취소 → 전량 예약 유지, cancelled=true(failed 0).
      return const BatchAssignResult(
          succeeded: [], failed: [], cancelled: true);
    }

    // 부분 성공: moved(갱신 성공) 만 최종 id 해석 후 확정.
    final movedSet = res.moved.toSet();
    final succeeded = <AssignedAsset>[];
    final failed = <String>[...failedResolve, ...res.failed];

    for (final group in byAlbum.values) {
      final album = group.first.album;
      final movedGroup =
          group.where((pa) => movedSet.contains(pa.assetId)).toList();
      if (movedGroup.isEmpty) continue;
      final movedEntities =
          movedGroup.map((pa) => entityById[pa.assetId]!).toList();
      // 이동 후 최종 id 해석(datamodel §3.1.1). RELATIVE_PATH 갱신은 대개 id 를
      // 유지하나, 삼성 등 일부 OEM 은 재발급하므로 지문 매칭으로 대응(FIX-2b).
      final finalIds = await _resolveAndroidFinalIds(album, movedEntities);
      for (var i = 0; i < movedGroup.length; i++) {
        final pa = movedGroup[i];
        final finalId = finalIds[i];
        if (finalId != null) {
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
    }
    return BatchAssignResult(succeeded: succeeded, failed: failed);
  }

  /// (레거시/폴백) Android 앨범별 배치 이동 — 앨범 수만큼 동의창이 뜬다.
  /// API<30(단일 batch write request 미지원) 또는 네이티브 채널 미배선 시에만 쓴다.
  /// C-5 를 해소하지 못하므로 정상 경로는 [_commitAndroid] 이며 이건 안전망이다.
  Future<BatchAssignResult> _commitAndroidLegacy(
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

/// 미분류 큐 스캔 캐시의 "지문". 전체 자산수와 처리 집합 상태가 모두 같으면
/// 미분류 스캔 결과도 동일하므로 재스캔을 건너뛴다(성능). 값 동등성으로 비교.
@immutable
class _ScanSignature {
  const _ScanSignature({
    required this.total,
    required this.processedCount,
    required this.lastProcessedMicros,
  });

  /// 라이브러리 전체 자산수(신규/삭제 감지).
  final int total;

  /// 처리(배정 완료)된 자산수(commit 감지).
  final int processedCount;

  /// 마지막 처리 시각(µs). 같은 id 재기록 등 count 불변 변화까지 감지.
  final int? lastProcessedMicros;

  @override
  bool operator ==(Object other) =>
      other is _ScanSignature &&
      other.total == total &&
      other.processedCount == processedCount &&
      other.lastProcessedMicros == lastProcessedMicros;

  @override
  int get hashCode => Object.hash(total, processedCount, lastProcessedMicros);
}

/// 미분류 큐 스캔 결과 + 그 시점의 [_ScanSignature].
@immutable
class _QueueScanCache {
  const _QueueScanCache(this.signature, this.queue);
  final _ScanSignature signature;
  final List<AssetRef> queue;
}

/// 네이티브 배치 이동 채널(`moveToAlbums`) 응답의 파싱 결과(C-5/C-4).
///
/// - [unsupported]: API<30 → 호출측이 레거시 경로로 폴백.
/// - [cancelled]  : 사용자가 단일 쓰기 동의창을 취소 → 예약 유지, failed 0.
/// - [moved]      : RELATIVE_PATH 갱신에 성공한 assetId(이동 후 최종 id 해석 대상).
/// - [failed]     : 갱신 실패 assetId(큐 유지).
@immutable
@visibleForTesting
class MoveChannelResult {
  const MoveChannelResult({
    required this.unsupported,
    required this.cancelled,
    required this.moved,
    required this.failed,
  });

  final bool unsupported;
  final bool cancelled;
  final List<String> moved;
  final List<String> failed;
}

/// 채널 응답(Map) → [MoveChannelResult]. 알 수 없는 응답은 "아무것도 이동 안 됨"으로
/// 안전 해석(succeeded 0, cancelled/unsupported false → 호출측이 전량 failed 처리).
/// 플랫폼 채널 없이 단위 테스트 가능하도록 순수 함수로 둔다.
@visibleForTesting
MoveChannelResult parseMoveChannelResult(Object? raw) {
  if (raw is! Map) {
    return const MoveChannelResult(
      unsupported: false,
      cancelled: false,
      moved: <String>[],
      failed: <String>[],
    );
  }
  List<String> ids(Object? v) =>
      v is List ? v.map((e) => e.toString()).toList() : const <String>[];
  return MoveChannelResult(
    unsupported: raw['unsupported'] == true,
    cancelled: raw['cancelled'] == true,
    moved: ids(raw['moved']),
    failed: ids(raw['failed']),
  );
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
