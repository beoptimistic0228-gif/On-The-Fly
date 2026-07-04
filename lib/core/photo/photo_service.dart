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

  /// 시스템 설정 앱의 "이 앱" 권한 페이지를 연다(D2 전체 접근 유도의 실효 경로).
  ///
  /// **왜 필요한가(QA C-2)**: iOS 에서 권한이 이미 `limited`(부분) 또는 영구
  /// `denied` 면 [ensurePermission](= requestPermissionExtend) 재호출은 시스템
  /// 다이얼로그를 **다시 띄우지 않고** 같은 상태를 그대로 반환한다. 따라서
  /// "전체 접근으로 전환"은 사용자를 설정 앱으로 보내 "모든 사진"을 직접 켜게
  /// 하는 것이 유일하게 동작하는 경로다.
  ///
  /// 이 호출은 **설정 앱을 여는 것까지만** 보장하며 즉시 완료된다(사용자가 값을
  /// 바꾸고 돌아오는 것은 감지하지 않는다). 호출측은 앱이 다시 활성화될 때
  /// (resume) 권한을 재확인해야 한다 — home 은 homeDataProvider 무효화,
  /// onboarding 은 "다시 시도" 버튼이 그 역할을 한다.
  Future<void> openSystemSettings();

  /// iOS 14+ 제한(limited) 사진 재선택 시트를 띄운다(부분 접근에서 선택 사진 변경).
  ///
  /// **UI 노출 정책**: D2 는 **전체 접근 유도**가 목적이고 부분 접근 정리는 MVP
  /// 미지원이라, 현재 UI 에는 노출하지 않는다(전체 접근 경로는 [openSystemSettings]).
  /// 계약 완결성과 향후 "선택 사진 변경" 확장을 위해 경계에 포함해 둔다.
  ///
  /// 지원하지 않는 플랫폼(iOS 14 미만·데스크톱 등)에서 호출돼도 **안전한 no-op**
  /// 이어야 한다.
  Future<void> presentLimited();

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
