import 'dart:typed_data';

import '../models/album_ref.dart';
import '../models/asset_ref.dart';
import '../models/assignment.dart';
import '../models/photo_permission.dart';

/// 사진 라이브러리 연동 경계 계약(architecture §2.1).
///
/// features 는 이 추상 타입만 import 한다(구현체 아님). 플랫폼 차이
/// (iOS 태깅 / Android 배치 이동·동의창 / id 재발급)는 구현체 내부에 캡슐화된다.
///
/// 정리 흐름: **stage → commit → (성공분만) markProcessed** (datamodel §7).
abstract class PhotoService {
  /// 권한 요청 후 상태 반환.
  /// - limited 면 호출측이 "전체 접근 유도" 안내를 띄운다(D2). 부분 접근 정리는 미지원.
  Future<PhotoPermission> ensurePermission();

  /// 미분류 큐 로드. 판별 규칙 = datamodel §3(처리 ID 집합 기준, OS 앨범 소속 아님).
  ///
  /// 반환: 미분류 [AssetRef] 목록(원본 바이트 없음). 권한 없으면 빈 목록.
  Future<List<AssetRef>> loadUnclassifiedQueue();

  /// 배정 "예약"(stage). 즉시 반영·기록 없음(datamodel §7.1). 같은 자산 재예약은 덮어쓴다.
  void stageAssignment(AssetRef asset, AlbumRef album);

  /// 예약분 되돌리기(commit 전이라 안전).
  void unstageAssignment(String assetId);

  /// 현재 예약 목록("옮길 N장 대기 중" 표시용).
  List<PendingAssignment> pendingAssignments();

  /// 배치 확정(commit) — 세션 끝에 1회.
  /// - Android: 시스템 동의창 1회 → 배치 이동(moveAssetsToPath). 이동 후 최종 id 반환.
  /// - iOS    : 앨범 태깅 즉시(동의창 없음).
  ///
  /// **성공분([BatchAssignResult.succeeded])만** 호출측이 `markProcessed` 한다.
  /// 실패·취소분은 예약 큐에 유지된다.
  Future<BatchAssignResult> commitAssignments();

  /// 앨범 생성(F-04). 로컬 Album 행 생성 후 시스템 앨범/폴더 참조를 채운다.
  Future<AlbumRef> createAlbum(String name);

  /// 앱이 관리하는 앨범 목록.
  Future<List<AlbumRef>> listAlbums();

  /// 썸네일 데이터(원본 저장 아님, 지연 로드). 없으면 null.
  Future<Uint8List?> thumbnail(String assetId, {int size});
}
