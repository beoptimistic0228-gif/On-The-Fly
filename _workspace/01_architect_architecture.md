# 01 · 아키텍처 (Architecture)

> SSOT: `그때그때_PRD_v1.0.md` + CLAUDE.md(스택 Flutter 확정) + `flutter-app-design` 스킬.
> 대상 독자: Flutter 초심자(나관, Unity/C#·.NET 배경). 전문용어는 짧게 풀고, 익숙한 .NET 개념에 빗댄다.

---

## 결론 먼저 — 기술 선택 한 장 요약

| 영역 | 선택(권장) | 한 줄 이유(초심자용) | 대안 | .NET 비유 |
|------|-----------|----------------------|------|-----------|
| 상태관리 | **Riverpod** | 화면과 데이터를 깔끔히 분리, 테스트 쉬움, 코드 적음 | Provider(더 단순·기능 적음), Bloc(엄격하나 과함) | DI 컨테이너 + 옵저버블 |
| 로컬 DB | **Drift**(SQLite) — **확정 D3** | 처리 ID 조회가 잦음 → 타입 안전+쿼리 컴파일 검증 | — (확정) | EF Core |
| 사진 접근 | **photo_manager** | iOS PhotoKit·Android MediaStore를 **한 API**로. 앨범 생성·**배치 자산 이동(write request)** 지원 | 직접 platform channel(비권장, 품 많음) | 네이티브 SDK 래퍼 |
| 알림 | **flutter_local_notifications** + **timezone** | 서버 없이 매일 정시 로컬 알림 | (대안 없음, 사실상 표준) | 로컬 스케줄러 |
| 라우팅 | **go_router** | 선언형, 온보딩 분기(첫 실행 여부)를 쉽게 | Navigator 2.0 수동(복잡) | 라우트 테이블 |
| 광고 | **google_mobile_ads**(AdMob) — **확정 D3** | 스토어 표준, 서버 불필요 | — (확정) | SDK |
| 인앱결제 | **in_app_purchase**(공식) — **확정 D3** | StoreKit/Play Billing 공식 래퍼, "서버 없음" 원칙 부합 | — (확정) | 스토어 SDK |
| 분석 | **Firebase Analytics** — **확정 D3** | 무료 티어, North Star/D7 이벤트 산출 | — (확정) | 텔레메트리 |

> **스택 전부 확정(00_decisions D3).** DB=Drift, 광고=AdMob, IAP=in_app_purchase, 분석=Firebase Analytics.

---

## 1. 폴더 구조 (feature-first)

> **feature-first** = "기능(화면) 단위"로 폴더를 나눈다. 로그인·홈처럼 기능별로 뭉쳐두면 초심자가 "이 화면 고치려면 어디?"를 바로 안다. (반대는 layer-first: widgets/, models/ 로 나누는 방식 — 규모 커지면 헤맴.)

```
lib/
  main.dart                  # 앱 진입점, ProviderScope, 라우터 연결
  app.dart                   # MaterialApp.router, 테마

  core/                      # ★ 플랫폼·공통 서비스 (features가 의존, 반대는 금지)
    db/
      app_database.dart        # Drift DB 정의(ProcessedAsset, Album 테이블)
      dao/                     # 데이터 접근 객체(쿼리 모음) = Repository 유사
    photo/
      photo_service.dart       # photo_manager 래핑 (미분류 큐·앨범생성·시스템반영)
    notifications/
      notification_service.dart# 매일 알림 스케줄
    ads/
      ad_service.dart          # 광고 로드·노출 정책(7일·세션1회)
    iap/
      purchase_service.dart    # 광고제거 구매/복원
    analytics/
      analytics_service.dart   # F-12 이벤트 (인터페이스 우선, 구현 뒤)
    routing/
      app_router.dart          # go_router 정의(온보딩 분기)
    models/                    # 순수 데이터 타입(AssetRef, AlbumRef 등, DTO)
    widgets/                   # 공통 위젯(버튼, 썸네일, 상태뷰)

  features/                  # ★ UI + 화면별 상태
    onboarding/  { presentation/ , application/ (Riverpod providers) }
    home/        { presentation/ , application/ }
    sort/        { presentation/ , application/ }   # 스와이프 핵심
    album/       { presentation/ , application/ }   # 앨범 선택 모달
    done/        { presentation/ , application/ }
    settings/    { presentation/ , application/ }
```

- **의존 방향(중요)**: `features → core` 한 방향만. core는 features를 몰라야 한다(=재사용·테스트 가능). C#의 "도메인/인프라 레이어를 UI가 참조, 반대 금지"와 동일.
- 각 feature 폴더 = `presentation`(위젯) + `application`(Riverpod provider/notifier = 화면 상태·로직). 필요 시 `application`이 core 서비스를 호출.

---

## 2. core ↔ features 경계 인터페이스 (협업 계약 = QA 검증 지점) ★

> 이 절이 **platform-integrator(core 구현) ↔ feature-builder(features 구현)** 의 계약서다. 인터페이스만 먼저 합의하면 양쪽이 병렬로 작업 가능하고, QA는 이 시그니처와 동작을 검증한다.
> 초심자 팁: 아래 `abstract class`(추상 클래스) = C#의 interface. "무엇을 제공하는지"만 정의하고 구현은 core가 채운다.

### 2.1 PhotoService (가장 중요)
```dart
abstract class PhotoService {
  /// 권한 요청/상태
  Future<PhotoPermission> ensurePermission();      // granted / limited / denied

  /// 미분류 큐 로드 — 판별 규칙은 datamodel 문서 §3
  Future<List<AssetRef>> loadUnclassifiedQueue();

  /// 배정 "예약"(stage) — 즉시 반영 없음. 메모리/임시 큐에만 쌓음 (D1, datamodel §7)
  /// 스와이프 순간 호출. 시스템 반영·ProcessedAsset 기록 없음.
  void stageAssignment(AssetRef asset, AlbumRef album);

  /// 예약분 되돌리기(commit 전이라 안전)
  void unstageAssignment(String assetId);

  /// 현재 예약 목록(UI "옮길 N장 대기 중" 표시용)
  List<PendingAssignment> pendingAssignments();

  /// 배치 확정(commit) — 세션 끝에 1회 (F-05, D1)
  /// Android: 시스템 동의창 1회 후 배치 이동(moveAssetsToPath)
  /// iOS: 앨범 태깅 즉시 (동의창 없음, UX 일관성 위해 동일 인터페이스)
  /// 플랫폼 차이는 이 구현체 내부에 캡슐화 → features는 이 하나만 호출
  /// 성공분(BatchAssignResult.succeeded)만 호출측이 markProcessed 한다
  Future<BatchAssignResult> commitAssignments();

  /// 앨범 생성(F-04). 시스템 앨범/폴더까지 만들고 systemAlbumRef 채움
  Future<AlbumRef> createAlbum(String name);

  /// 앨범 목록(시스템+로컬 병합)
  Future<List<AlbumRef>> listAlbums();

  /// 썸네일/영상 미리보기용 데이터 핸들(원본 저장 아님)
  Future<Uint8List?> thumbnail(String assetId, {int size});
}

/// 예약 1건
class PendingAssignment {
  final String assetId;
  final AlbumRef album;
  final int mediaType;
}

/// 배치 commit 결과 (부분 성공 모델)
class BatchAssignResult {
  final List<AssignedAsset> succeeded; // 성공분. Android는 이동 후 최종 id(finalAssetId) 포함
  final List<String> failed;           // 실패 assetId → stage 큐 유지
  final bool cancelled;                // 사용자가 동의창 취소(전량 미반영)
}

class AssignedAsset {
  final String finalAssetId;           // Android=이동 후 재발급 id / iOS=불변 id (datamodel §3.1.1)
  final String albumId;
  final int mediaType;
}
```

### 2.2 ProcessedRepository (Drift DAO 래핑)
```dart
abstract class ProcessedRepository {
  Future<Set<String>> processedIdSet();
  Future<DateTime?> lastProcessedAt();
  Future<void> markProcessed({required String assetId, required String albumId, required int mediaType});
  Future<int> streakDays();                 // 연속 정리일수
  Future<int> countProcessedInRange(DateTime from, DateTime to);
}
```

### 2.3 NotificationService
```dart
abstract class NotificationService {
  Future<bool> requestPermission();
  Future<void> scheduleDaily(TimeOfDay time);  // 매일 반복
  Future<void> cancelAll();
}
```

### 2.4 AdService / PurchaseService / AnalyticsService
```dart
abstract class AdService {
  bool shouldShowAd();                       // 7일 경과 & 미구매 & 세션1회 정책 판단(한 곳에 캡슐화)
  Future<void> showInterstitialOnce();       // 완료 화면 뒤 1회
}
abstract class PurchaseService {
  Future<bool> isAdRemoved();
  Future<void> buyRemoveAds();
  Future<void> restore();
}
abstract class AnalyticsService {            // F-12
  void logSessionCompleted({required int assignedCount});
  void logAppOpen();
  void logAssign({required int mediaType});
}
```

> **경계 계약의 규칙**
> 1. features는 위 **추상 타입만** import한다(구현체 아님). Riverpod로 주입 → 테스트 시 가짜(fake)로 교체 가능.
> 2. **stage → commit → (성공분만) markProcessed** 순서를 features(sort)가 지킨다(datamodel §7). 스와이프는 `stageAssignment`(즉시 반영 없음), 세션 끝 `commitAssignments`, 반환 `BatchAssignResult.succeeded`의 `finalAssetId`로만 `markProcessed`. QA 필수 검증 포인트.
> 3. `AssetRef` / `AlbumRef`는 core/models의 **순수 DTO**(플랫폼 타입 노출 금지) → UI가 photo_manager에 직접 안 묶임.

---

## 3. 상태관리 패턴 (Riverpod) — 초심자 가이드

- **Provider** = "값이나 서비스를 앱 어디서든 꺼내 쓰게 해주는 콘센트"(C# DI 등록과 유사).
- 화면 상태는 **AsyncValue<T>** 로 다룬다 → `loading / data / error` 3상태를 UI에서 `.when()`으로 분기. (screens 문서의 로딩·정상·에러 상태와 1:1 대응)
- 예: `unclassifiedQueueProvider` (FutureProvider) → 홈/정리 화면이 구독. 처리 후 `ref.invalidate`로 큐 재계산.
- 서비스는 `Provider<PhotoService>` 등으로 주입, 테스트에서 override.

권장 규칙: **위젯 안에 비즈니스 로직 금지**. 위젯은 provider를 읽고 그리기만, 로직은 `Notifier`/서비스에.

---

## 4. 라우팅 (go_router)

```
/onboarding   (첫 실행: onboardingCompleted==false 시 redirect)
/home
/sort
/done
/settings
```
- 앨범 선택은 **모달(bottom sheet)** → 라우트 아니어도 됨(정리 화면 위 오버레이).
- redirect 로직: 온보딩 완료 플래그(간단히 `shared_preferences` 또는 Drift 설정 테이블)로 첫 화면 분기.

---

## 5. 플랫폼 특이사항 (platform-integrator 필독)
| 플랫폼 | commit 반영 방식 | 마찰 |
|--------|----------|------|
| iOS | PhotoKit 앨범에 자산 **태깅**(원본 타임라인 유지). commit 시 즉시(동의창 없음) | 전체 접근 권한 필요(limited면 전체 접근 유도, D2), "정리된 느낌" 약함 → 완료화면 streak로 보완 |
| Android | MediaStore/Scoped Storage로 **배치 폴더 이동**(`moveAssetsToPath`). commit 시 시스템 동의창 1회 → 배치 이동. 이동 후 id 재발급 → 최종 id로 기록(datamodel §3.1.1) | per-asset 즉시 이동 불가(`copyAssetToPath` 조용한 실패, 02_feasibility R1) → **stage→commit 배치 승인**으로 해결 |

> 두 플랫폼의 차이는 **PhotoService 구현체 안에 가둔다.** features는 `stageAssignment` + `commitAssignments` 만 호출하고 내부 차이(동의창/태깅/id 재발급)를 모른다.

---

## 6. 테스트 경계(QA용)
- core 서비스: 추상 인터페이스 → **fake 구현으로 단위 테스트**.
- features: provider override로 fake 주입 → 위젯 테스트(상태 4종 렌더).
- **핵심 시나리오 통합 테스트**: 큐 로드 → stage 예약 → commit(성공 N/실패 M/취소) → 성공분만 처리 기록·실패분 큐 유지 → 재큐 시 제외 검증(datamodel §7). Android는 이동 후 최종 id로 기록되는지 검증.

---

## 확정 사항 (00_decisions D3 — 모두 확정, 착수 차단 없음)
1. **로컬 DB = Drift**(SQLite, EF Core 유사).
2. **분석 SDK = Firebase Analytics**(무료 티어, North Star/D7).
3. **광고 SDK = AdMob**(`google_mobile_ads`), 노출 트리거 = 첫 정리일 +7일.
4. **인앱결제 = 공식 `in_app_purchase`**(구매 복원 지원, "서버 없음" 원칙 부합).
5. **정리 반영 = stage→commit 배치 모델(D1)**, 제한 접근 = 전체 접근 유도(D2).
