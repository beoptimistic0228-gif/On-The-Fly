# 02 · 통합 노트 (platform-integrator — core 레이어 구현 결과)

> 대상: **feature-builder**(공개 인터페이스), **qa-verifier**(검증 경계), **spec-architect**(설계 편차·승인 필요 항목).
> 범위: `lib/core/` (데이터 모델 + Drift DB, PhotoService, NotificationService, Riverpod 프로바이더, 플랫폼 설정). UI(features)는 미포함.
> 상태: `flutter analyze` **No issues found**. build_runner 코드 생성 완료. 실기기 실행은 미수행(기기 없음).

---

## A. 생성/수정 파일

### 신규 (lib/core)
- `models/photo_permission.dart` — `PhotoPermission { granted, limited, denied }`
- `models/asset_ref.dart` — `AssetRef`(순수 DTO)
- `models/album_ref.dart` — `AlbumRef`(순수 DTO, `copyWith`)
- `models/assignment.dart` — `PendingAssignment`, `AssignedAsset`, `BatchAssignResult`
- `db/app_database.dart` — Drift 테이블 `ProcessedAssets`/`Albums` + `AppDatabase`(FK on)
- `db/dao/processed_dao.dart` — `ProcessedDao`(처리 ID 집합·기록·streak 원천·범위 집계)
- `db/dao/album_dao.dart` — `AlbumDao`(앨범 CRUD)
- `db/processed_repository.dart` — `ProcessedRepository`(abstract) + `DriftProcessedRepository`
- `db/album_repository.dart` — `AlbumRepository`(abstract) + `DriftAlbumRepository`
- `photo/photo_service.dart` — `PhotoService`(abstract, 경계 계약)
- `photo/photo_manager_photo_service.dart` — `PhotoManagerPhotoService`(구현)
- `notifications/notification_service.dart` — `NotificationService`(abstract)
- `notifications/local_notification_service.dart` — `LocalNotificationService`(구현)
- `providers.dart` — Riverpod 프로바이더 5종

### 생성물(build_runner, 커밋 대상)
- `db/app_database.g.dart`, `db/dao/processed_dao.g.dart`, `db/dao/album_dao.g.dart`

### 수정 (플랫폼 설정)
- `android/app/src/main/AndroidManifest.xml` — 사진/영상·알림·부팅 권한 + 알림 리시버 2종
- `ios/Runner/Info.plist` — `NSPhotoLibraryUsageDescription`, `NSPhotoLibraryAddUsageDescription`

> `lib/main.dart` 는 손대지 않음(UI 에이전트 담당). 앱 부팅 시 `ProviderScope` 감싸기 + `NotificationService.init()` 호출은 feature/onboarding 또는 main 에서 수행해야 함(아래 D 참조).

---

## B. 공개 인터페이스 시그니처 (feature-builder 는 이것만 보고 UI를 짠다)

> 규칙: features 는 **추상 타입만** import. Riverpod 프로바이더로 주입받는다. photo_manager 타입은 절대 노출 안 됨(전부 순수 DTO).

### B.1 Riverpod 프로바이더 (`lib/core/providers.dart`)
```dart
final appDatabaseProvider          = Provider<AppDatabase>(...);
final processedRepositoryProvider  = Provider<ProcessedRepository>(...);
final albumRepositoryProvider      = Provider<AlbumRepository>(...);
final photoServiceProvider         = Provider<PhotoService>(...);
final notificationServiceProvider  = Provider<NotificationService>(...);
```
사용 예: `final photo = ref.read(photoServiceProvider);`

### B.2 PhotoService (`lib/core/photo/photo_service.dart`)
```dart
Future<PhotoPermission> ensurePermission();           // granted / limited / denied
Future<List<AssetRef>>  loadUnclassifiedQueue();      // 미분류 큐 전체(판별=처리ID집합)
void stageAssignment(AssetRef asset, AlbumRef album); // 예약(즉시 반영 없음)
void unstageAssignment(String assetId);               // 예약 취소
List<PendingAssignment> pendingAssignments();         // 현재 예약 목록(대기 N장)
Future<BatchAssignResult> commitAssignments();        // 배치 확정(Android 동의창1회 / iOS 즉시)
Future<AlbumRef>        createAlbum(String name);     // 앨범 생성(F-04)
Future<List<AlbumRef>>  listAlbums();                 // 앱 관리 앨범 목록
Future<Uint8List?>      thumbnail(String assetId, {int size}); // 썸네일(기본 size=200)
```
- **네이밍 확정**: 태스크의 `loadUnsorted({int page})` 대신 **architecture §2.1 확정 계약인 `loadUnclassifiedQueue()`** 로 구현(반환 타입도 `AssetRef` = 순수 DTO). 페이지네이션은 내부에서 처리하고 전체 미분류 목록을 한 번에 반환한다(AssetRef는 id+타입+생성일만이라 대용량도 가볍다; 썸네일은 `thumbnail()`로 지연 로드).
- **stage → commit → markProcessed 순서(datamodel §7, QA 필수)**:
  ```dart
  // 스와이프 시
  photo.stageAssignment(asset, album);        // 반영·기록 없음
  // 세션 끝(큐 소진 또는 사용자 commit)
  final r = await photo.commitAssignments();  // Android=동의창1회 / iOS=즉시
  for (final s in r.succeeded) {              // ★ 성공분만
    await processed.markProcessed(
      assetId: s.finalAssetId,                // Android=이동 후 최종 id / iOS=불변 id
      albumId: s.albumId, mediaType: s.mediaType,
    );
  }
  // r.failed / r.cancelled 는 예약 큐에 그대로 유지됨(자동). UI는 성공N/실패M 표시.
  ```
  > **중요**: `commitAssignments()` 는 DB에 기록하지 **않는다**. 반드시 호출측이 `succeeded` 를 순회하며 `markProcessed` 해야 처리 확정된다(architecture §2.1 규칙2 그대로).

### B.3 반환 shape / null 규칙 (QA 대조용)
- `PhotoPermission`: `granted`(전체) / `limited`(부분→전체접근 유도) / `denied`(거부·미결정·restricted).
- `AssetRef{ String id; int mediaType(0=사진,1=영상); DateTime? createdAt }`.
- `AlbumRef{ String id; String name; String? systemAlbumRef; String? coverAssetId; DateTime updatedAt }`.
  - `createAlbum` 반환은 iOS면 `systemAlbumRef`(=PHAssetCollection.localIdentifier) 채워짐, Android면 `Pictures/<name>` 형태 경로.
- `PendingAssignment{ String assetId; AlbumRef album; int mediaType }`.
- `BatchAssignResult{ List<AssignedAsset> succeeded; List<String> failed; bool cancelled }`.
  - `AssignedAsset{ String finalAssetId; String albumId; int mediaType }`.
  - 예약 없을 때 commit → `succeeded=[] failed=[]`(no-op).
- `thumbnail()` → 자산이 라이브러리에 없으면 `null`.
- 권한 없음/미분류 없음 → `loadUnclassifiedQueue()` 는 빈 리스트(예외 아님).

### B.4 ProcessedRepository (`lib/core/db/processed_repository.dart`)
```dart
Future<Set<String>> processedIdSet();
Future<DateTime?>    lastProcessedAt();
Future<void>         markProcessed({required String assetId, required String albumId, required int mediaType});
Future<int>          streakDays();                                  // 오늘/어제까지 이어진 연속일
Future<int>          countProcessedInRange(DateTime from, DateTime to);
```

### B.5 AlbumRepository (`lib/core/db/album_repository.dart`)
```dart
Future<List<AlbumRef>> allAlbums();          // 최근 사용 순
Future<AlbumRef?>      albumById(String id);
Future<void>          saveAlbum(AlbumRef album);
Future<void>          setSystemRef(String albumId, String systemRef);
```
> 참고: `createAlbum` 은 PhotoService 안에서 AlbumRepository 저장까지 처리하므로, UI는 보통 `photo.createAlbum()` / `photo.listAlbums()` 만 쓰면 된다. 리포지토리 직접 접근은 선택.

### B.6 NotificationService (`lib/core/notifications/notification_service.dart`)
```dart
Future<void> init();                    // 앱 시작 시 1회(타임존+플러그인 초기화)
Future<bool> requestPermission();       // 허용 시 true
Future<void> scheduleDaily(TimeOfDay time);
Future<void> cancelAll();
```

---

## C. 플랫폼 설정 반영 내역

### Android (`AndroidManifest.xml`)
- 권한: `READ_MEDIA_IMAGES`, `READ_MEDIA_VIDEO`, `READ_MEDIA_VISUAL_USER_SELECTED`(API34 부분접근), `READ_EXTERNAL_STORAGE`(maxSdk 32), `POST_NOTIFICATIONS`, `RECEIVE_BOOT_COMPLETED`.
- 리시버: `ScheduledNotificationReceiver`, `ScheduledNotificationBootReceiver`(BOOT_COMPLETED·MY_PACKAGE_REPLACED·QUICKBOOT) → **재부팅 후 알림 유지**(R7).
- `SCHEDULE_EXACT_ALARM` 미추가(의도) — 매일 리마인더는 `inexactAllowWhileIdle` 사용(권한 최소화, R7).

### iOS (`Info.plist`)
- `NSPhotoLibraryUsageDescription`(읽기/정리), `NSPhotoLibraryAddUsageDescription`(앨범 추가).
- 알림 권한은 런타임에서 `requestPermission()` 호출로 요청(plist 항목 불필요).

---

## D. 실기기 없이 검증 못 한 항목 · 한계 (QA/아키텍트 확인 필요)

> **머지 게이트: 실기기 스모크 (05_fix_directives 반영 후 추가)**
> FIX-2a(iOS 빈 앨범 commit)·FIX-2b(Android id 재발급 매칭)는 플랫폼 채널 의존이라
> 단위 테스트로 커버 불가한 경로가 있다. **머지 전 실기기 스모크 필수**:
> - iOS 1종: 신규 빈 앨범 생성→배정→commit 이 `succeeded` 포함 & 다음 큐에서 제외.
> - Android 2종(삼성 One UI + Pixel/AOSP): 이동 후 (a) id 유지/재발급 여부,
>   (b) 재발급분이 오기록 없이 `failed` 로 빠져 큐에 유지되는지, (c) 동의창 승인/취소.
> 코드 내 해당 지점은 `TODO(device):` 주석으로 표시(local id 재발급·매칭 정확도).
> FIX-1(알림 타임존)은 단위 테스트로 대부분 커버(폴백·nextInstanceOf); 실제 발화 정시성만 실기기 확인.


- **[한계 A · Android id 재발급 재조회 — 최고위험]** `_resolveAndroidFinalIds` 는 이동 후 각 자산을 `AssetEntity.fromId(원래id)` 로 재조회해 살아있으면 id 유지로 보고, null(재발급)이면 대상 앨범 최신 자산에서 **best-effort 매칭**한다. OEM/스캐너별 재발급 동작(§3.1.1·R2)은 **실기기 검증 필수**. best-effort 매칭이 오배정되면 미분류 재등장 또는 오기록 가능 → 실기기에서 (a) 이동 후 id 유지/변경 여부, (b) 재조회 매칭 정확도를 반드시 확인.
- **[한계 B · Android commit 취소 vs 실패 구분 불가]** `moveAssetsToPath` 반환이 `bool` 이라 사용자 동의창 취소와 이동 실패를 구분할 수 없다. 현재 둘 다 `failed` 로 처리(큐 유지, `cancelled=false`). "전량 취소" 를 UI에서 별도 문구로 안내하려면 실기기에서 취소 시 반환값·예외를 관찰해 보완 필요. (iOS는 동의창이 없어 `cancelled` 항상 false — 정상.)
- **[한계 C · 알림 로컬 타임존]** `timezone` 의 `tz.local` 은 기본 UTC 라, 실제 기기 로컬 시각과 오프셋만큼 어긋날 수 있다. 정확한 로컬 시각 예약을 위해 `flutter_timezone` 로 기기 타임존명을 얻어 `tz.setLocalLocation()` 설정이 필요(백로그, deps 추가 필요). 현재는 `inexact` 리마인더라 영향이 제한적이나 정시성 요구 시 반드시 보완.
- **[한계 D · 미분류 큐 성능 프리필터 미적용(설계 편차 — 아키텍트 확인)]** datamodel §3.2/§3.3 의 `createDateTime` 시간 프리필터는 §3.4 엣지케이스(과거 사진 나중 추가 시 프리필터에서 누락)를 유발하므로, MVP는 **전체 스캔 + 처리 ID 대조**로 "미분류 누락 0" 을 우선했다. 결과적으로 §3.3 의사코드의 `createdAfter: since` 를 **의도적으로 적용하지 않음**. 대용량 라이브러리 성능이 문제되면 프리필터를 옵션으로 재도입 가능. → **spec-architect 확인 요망**(계약 자체는 `loadUnclassifiedQueue()` 시그니처·판별기준=ID집합으로 동일하게 유지).
- **[한계 E · iOS limited]** `ensurePermission()` 이 `limited` 를 반환하면 UI가 전체 접근 유도(D2). 정리 화면 진입 차단·`presentLimited`/설정 딥링크 안내는 **UI(features) 책임**으로 남겨둠(core는 상태만 판별).
- **[한계 F · 백업복원 후 id 불안정(R3, 기존 감수)]** iOS 백업복원/기기이전, Android 재색인 후 저장된 id 불일치로 일부 재등장 가능. MVP 로컬 전용이라 **감수 + 온보딩 고지**(00_decisions 미결 B). core에서 추가 처리 없음.
- **[미검증 공통]** photo_manager 실제 호출(권한 팝업, `copyAssetToPath` iOS 태깅, `moveAssetsToPath` Android 동의창), Drift 파일 DB 오픈, 알림 실제 발화는 **정적 분석만 통과**한 상태. 실기기 스모크 테스트 필요.

---

## E. QA 검증 경계 (qa-verifier 용)
1. **stage ≠ 처리**: `stageAssignment` 후 `loadUnclassifiedQueue` 재호출 시 해당 자산이 **여전히 등장**해야 함(commit 전).
2. **성공→기록 원자성**: `commitAssignments().succeeded` 의 `finalAssetId` 로만 `markProcessed` → 이후 `loadUnclassifiedQueue` 에서 **제외**.
3. **부분 실패**: `failed`/취소분은 `pendingAssignments()` 에 유지 → 재 commit 대상.
4. **iOS 원본 유지**: 태깅 후 원본이 타임라인에 남아도 미분류 재등장 없어야 함(판별=ID집합).
5. **권한 거부/제한**: `denied`/`limited` 에서 크래시 없이 상태만 반환.
> 단위 테스트는 `AppDatabase.forTesting(NativeDatabase.memory())` + fake PhotoService(추상 override)로 구성 가능.
