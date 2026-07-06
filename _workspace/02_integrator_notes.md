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
Future<void>            openSystemSettings();         // 설정 앱 권한 페이지 열기(C-2·D2 실효 경로)
Future<void>            presentLimited();             // iOS14+ limited 재선택 시트(현 UI 미노출, 계약만)
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
- **[한계 E · iOS limited — C-2로 해소(2026-07-04)]** `ensurePermission()` 이 `limited`/영구 `denied` 면 재호출은 시스템 다이얼로그를 다시 띄우지 않아 "전체 접근 유도" 버튼이 무반응이었다(QA C-2). 계약에 `openSystemSettings()`(설정 앱 열기)·`presentLimited()`(iOS14+ 재선택 시트) 를 추가해 해소. UI 는 limited 카드·denied 재시도에서 `openSystemSettings()` 경로 사용, 설정 복귀(resume) 시 HomeScreen 관찰자가 권한 재확인. `presentLimited()` 는 부분 접근 정리 미지원(D2) 정책상 현재 UI 미노출(계약 완결성·향후 확장용). 실기기에서 설정 딥링크 동작 확인 필요.
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

---

## F. QA 오픈이슈 3건 구현 (2026-07-06, platform-integrator)

> 대상: C-5(동의창 연발), C-4(취소/실패 구분), 성능(16k 재스캔). 커밋은 오케스트레이터가.
> 품질 게이트: `flutter analyze` **No issues found** · `flutter test` **44 passed**(신규 6) · `flutter build apk --debug` **성공**.

### F.0 photo_manager raw API 조사 결과 (C-5 배경)
- photo_manager 3.9.0 은 `PhotoManager.editor.android.moveAssetsToPath(entities, **targetPath**)` 만 노출한다. 내부적으로 `MediaStore.createWriteRequest()` 로 **동의창 1회**를 띄우지만, **targetPath 는 호출당 1개**다(plugin.dart `androidMoveAssetsToPath(assetIds, targetPath)`).
- 따라서 앨범 N개 = targetPath N개 = `moveAssetsToPath` N회 = **동의창 N회**(C-5 의 근본원인).
- raw `createWriteRequest`(임의 URI 묶음에 대한 배치 쓰기요청)는 **Dart 레벨에 미노출**. photo_manager 네이티브의 `PhotoManagerWriteManager` 안에 갇혀 있고 공개 채널 메서드가 없다.
- **결론: 신규 pub 의존성 없이 소규모 플랫폼 채널(Kotlin)을 직접 작성**해 전체 pending 을 단일 `createWriteRequest` 로 처리. photo_manager 의 `PhotoManagerWriteManager`/`MediaStoreUtils.getUri` 를 레퍼런스로 URI 구성(사진=`Images.Media`, 영상=`Video.Media` + `_id`)을 정확히 맞췄다.

### F.1 C-5 — 단일 batch 동의로 통합 (구현 완료)
- **신규 네이티브**: `android/app/src/main/kotlin/com/geuttaeguttae/on_the_fly/MediaMoveHandler.kt`
  - 채널 `on_the_fly/media_store`, 메서드 `moveToAlbums(moves: [{id, mediaType, relativePath}])`.
  - 전체 URI 를 모아 `MediaStore.createWriteRequest(cr, uris)` **1회** → `startIntentSenderForResult`.
  - 승인(RESULT_OK) 시 앨범별 `RELATIVE_PATH` 갱신(`cr.update`)을 **추가 동의 없이** 수행(백그라운드 스레드, 결과는 메인 스레드 회신).
  - `requestCode=45317`(photo_manager 40071 과 비충돌). API<30 은 `unsupported=true` 반환.
- **MainActivity.kt**: `configureFlutterEngine` 에서 채널 배선 + `onActivityResult` 위임(우리 코드 소비 후 `super` 호출로 photo_manager 레거시 경로 공존).
- **Dart**: `photo_manager_photo_service.dart._commitAndroid` 재작성 — 앨범별 `moveAssetsToPath` 반복 대신 flat `moves` 를 채널에 한 번 전달. 승인 여부는 **채널 반환**으로 판단.

### F.2 C-4 — 취소 vs 실패 구분 (구현 완료)
- 네이티브가 `RESULT_CANCELED` 를 명시 수신 → `{cancelled:true, moved:[], failed:[]}`.
- Dart `_commitAndroid` 는 이를 받아 `BatchAssignResult(succeeded:[], failed:[], **cancelled:true**)` 반환 → `_pending` 전량 유지(제거 안 함), failed 0.
- **core 계약만 정확히 맞췄고 `lib/features/` 는 손대지 않음.** `sort_screen.dart:34` 의 기존 `outcome.cancelled` 분기가 이제 Android 에서 실제로 true 가 되어 "동의 필요, 예약 유지" 안내로 동작(기존 죽은 코드 활성화).
- 폴백/한계: API<30(`unsupported`)·채널 예외 시 `_commitAndroidLegacy`(기존 per-album `moveAssetsToPath`) 로 폴백 — 이 경로는 여전히 bool 반환이라 취소=실패로 처리(C-4 미해소)지만, minSdk 대상 실기기(Android 11+)는 정상 경로를 탄다.

### F.3 성능 — 미분류 큐 스캔 캐시 (구현 완료)
- `loadUnclassifiedQueue()` 에 **지문(signature) 가드 캐시** 추가. 지문 = `(전체 자산수 assetCountAsync, 처리수 processedCount, 마지막 처리시각)`. 모두 싼 COUNT 쿼리.
- 지문이 지난 로드와 동일하면 재스캔(16k 페이징, 수십 초) 없이 캐시 큐 반환. 홈 재진입/정리 재진입마다 반복되던 전체 스캔을 제거.
- **불변식 유지 근거**: 신규 자산 → total 변화, commit/삭제 → processedCount·lastProcessedAt 변화 → 캐시 미스 → 정확한 재스캔. **관측 가능한 변화가 있으면 항상 실제 로드**("큐는 정확"). 총개수 동일 외부 삭제+추가(commit 없음)라는 병적 케이스만 근사이며 다음 카운트 변화에서 자가치유("카운트는 근사 허용"). commit 성공 시 `_queueCache=null` 로 명시 무효화도 병행.
- 신규 계약: `ProcessedRepository.processedCount()`(+DAO·Drift 구현·테스트 fake 반영). PhotoService 공개 시그니처는 **불변**(캐시는 구현 내부).

### F.4 변경 파일
- 신규: `android/.../MediaMoveHandler.kt`, `test/move_channel_result_test.dart`.
- 수정: `android/.../MainActivity.kt`(채널 배선), `lib/core/photo/photo_manager_photo_service.dart`(_commitAndroid 재작성 + 레거시 폴백 + 스캔 캐시 + `MoveChannelResult`/`parseMoveChannelResult`), `lib/core/db/dao/processed_dao.dart`·`lib/core/db/processed_repository.dart`(`processedCount()`), `test/analytics_test.dart`(fake 에 `processedCount`).
- **`lib/features/` 무수정**(제약 준수).

### F.5 UI 팀 전달사항 (features 는 코드로 안 고침)
1. **홈 카운트 추가 최적화(선택)**: 현재 `home_providers.dart` 는 `loadUnclassifiedQueue().length` 로 개수를 얻는다. 스캔 캐시 덕에 재진입은 이미 싸졌지만, 개수만 필요한 홈은 큐 리스트 구성조차 불필요하다. 필요 시 core 에 순수 카운트 메서드(`total - processedCount`)를 추가 노출해 전환하면 콜드스타트 첫 홈까지도 O(1) 가 된다 — 지금은 계약 최소화를 위해 미노출. **당장은 불필요**(캐시로 충분).
2. **C-4 문구**: `sort_screen.dart:36` 의 취소 안내 문구는 그대로 유효(이제 Android 실기기에서 실제로 트리거됨). 변경 불필요.

### F.6 실기기 스모크 결과 (2026-07-06 수행 · 삼성 S22 Ultra SM-S908N · Android 16 · 16k장)

> 소유자 입회 하에 adb 로 직접 구동·검증. 디버그 APK 설치 후 실측. **3건 모두 PASS.**

- **[PASS] C-5 단일 batch 동의(핵심)** — 서로 다른 2개 앨범(smoke1 + 가족여행_전주)에 각 1장 배정 후 commit → 시스템 쓰기 동의창이 **정확히 1회**. logcat 실측: `ActivityTaskManager: START ... act=create_write_request cmp=com.google.android.providers.media.module/.PermissionActivity` **1건**(승인 후 2번째 다이얼로그 없음). 동의창 문구 "on_the_fly에서 **사진 2개**를 수정하도록 허용하시겠습니까?"로 두 앨범 대상 자산이 한 동의에 묶임을 확인. 승인 후 MediaStore 실측: `_id 65 → Pictures/smoke1/`, `_id 66 → Pictures/가족여행_전주/`(**서로 다른 폴더로 정확 이동**). 기존 per-album 코드였다면 앨범당 1회씩 2회 떴어야 함.
- **[PASS] C-4 취소 vs 실패 구분** — 같은 2앨범 pending 에서 commit → 동의창 "거부" → 앱이 `/done` 으로 넘어가지 않고 **정리 화면 유지** + 스낵바 "정리를 완료하려면 동의가 필요해요. 예약은 그대로 남아 있어요."(= `outcome.cancelled` 분기, sort_screen.dart:36) 노출. "N장 반영 못했어요" 오안내 **없음**. 파일시스템 실측: `/sdcard/Pictures/smoke1`·`smoke2` **미생성**(취소로 이동 0). 이후 재 commit 시 동일 2장 그대로 남아 재시도 가능 확인(pending 유지).
- **[PASS] 성능(캐시/감산)** — 콜드 실행(프로세스 시작+16k 전체 스캔) 홈 카운트 표시까지 **~14.4s**. 반면 세션 내 정리 화면 재진입(캐시 적중)은 **~3s**(대부분 썸네일 디코드; 16k 재스캔 "미분류 세는 중" 스피너 **미노출**). commit 후 홈 카운트 **감산 갱신 정확**: 16062 → 16060 → 16058(2장씩 2회 커밋). 콜드 재스캔도 `total - processed` 와 일치(16058).
- **[검증] Android id 재발급 대응(한계 A)** — 이동 후 `_id` **재발급 실관찰**(원본 → 65/66 신규 id). FIX-2b 지문 매칭이 실기기에서 성공: `processed_assets` 에 **최종(재발급) id** 로 정확 기록(65→smoke1, 66→가족여행_전주) → 중복방지도 성립(재진입 시 미노출).
- **[한계 잔존] API<30 폴백 경로**는 이 기기(API36)에선 미탐(정상 경로만 실행). Android 10 이하 레거시 폴백은 여전히 미검증.

> **테스트로 이동된 실자산(소유자 복원 판단용)**: smoke1(신규 테스트 앨범) ← `_id 48,64,65`(3장) / 가족여행_전주(기존 앨범) ← `_id 66`(1장, 20210513_205047.jpg). 총 4장 이동. 앱에 되돌리기(un-move) 기능은 없으므로 필요 시 갤러리에서 수동 이동.

### F.7 실기기 검증 절차 (재현용, adb 포함)
> 대상: Android 11+(정상 경로). 특히 삼성 One UI(S22, id 재발급 관찰됨).

1. **빌드·설치**: `flutter install` 또는 `adb install -r build/app/outputs/flutter-apk/app-debug.apk`.
2. **C-5 단일 동의**: 서로 다른 **2개 이상 앨범**에 사진을 배정(스와이프) 후 "정리" → **시스템 쓰기 동의창이 딱 1회** 뜨는지 확인(기존엔 앨범 수만큼). logcat: `adb logcat | grep -i "createWriteRequest\|WriteHandler\|MediaMove"`.
3. **C-4 취소**: 위 동의창에서 **취소/거부** → 앱이 `/done` 으로 넘어가지 않고 "동의가 필요해요… 예약은 그대로" 스낵 표시, 대기 카운트 유지 확인. 다시 "정리" → 재차 동의창 1회.
4. **이동·id 실반영**: 승인 경로로 commit 후
   - 파일: `adb shell ls -R /sdcard/Pictures/<앨범명>/` 에 실제 파일.
   - MediaStore: `adb shell content query --uri content://media/external/images/media --projection _id:relative_path:_display_name | grep <앨범명>` 로 `relative_path` 갱신 확인.
   - 재진입 시 해당 자산이 미분류 큐에 **다시 안 뜨는지**(중복방지) 확인.
5. **id 재발급 대응**: 이동 전후 `_id` 비교(삼성은 재발급 관찰됨). 재발급돼도 지문 매칭(FIX-2b)으로 `succeeded` 에 최종 id 로 들어가는지, 매칭 실패분만 재등장하는지 확인.
6. **성능(캐시)**: 홈↔정리 왕복·홈 새로고침 반복 시 첫 1회만 수십 초, 이후 즉시 갱신되는지 체감 확인. 변화(신규 사진 추가/commit) 후엔 재스캔이 도는지 확인.
7. **폴백**: (가능하면) Android 10 기기에서 `unsupported` 경로가 레거시 이동으로 동작하는지 확인(없으면 미검증으로 기록).

**미해결/한계**: (a) `cr.update(RELATIVE_PATH)` 후 OEM별 id 재발급 실동작은 실기기 필수(한계 A 승계). (b) 채널이 액티비티 없는 상태(백그라운드)에서 호출되면 `no_activity` → 폴백. 실사용상 commit 은 포그라운드라 문제없음. (c) API<30 폴백 경로는 C-4 미해소(bool 반환).
