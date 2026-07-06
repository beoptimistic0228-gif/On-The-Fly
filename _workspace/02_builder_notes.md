# 02 · 빌더 노트 (feature-builder — 핵심 사전 UI 구현 결과)

> 대상: **qa-verifier**(상태 전이·경계 검증), **platform-integrator**(계약 불일치), **spec-architect**(스펙 편차).
> 범위: `lib/features/` 핵심 사전 UI(온보딩→홈→정리→완료) + `lib/app/`(라우터·테마·설정) + `lib/main.dart` 연결.
> 상태: `flutter analyze` **No issues found**. `flutter test` 통과(온보딩 스모크 1건). 실기기 실행 미수행.
> core 레이어는 재구현하지 않음 — 전부 `providers.dart` 로 주입.

---

## A. 생성/수정 파일

### 신규 (lib/app)
- `app/settings_store.dart` — `sharedPrefsProvider`(main 에서 override) + `AppSettings`(온보딩 완료·알림 시각·알림 on/off) + `appSettingsProvider`
- `app/router.dart` — go_router 구성. 온보딩 완료 여부로 시작 위치 결정
- `app/theme.dart` — M3 테마

### 신규 (lib/features)
- `features/shared/asset_thumbnail.dart` — `thumbnailProvider`(FutureProvider.autoDispose.family, 캐싱) + `AssetThumbnail` 위젯(영상 배지)
- `features/onboarding/onboarding_screen.dart` — 4스텝 온보딩(가치·프라이버시 → 사진권한 → 알림권한·시각 → 첫 정리)
- `features/onboarding/permission_help.dart` — `LimitedAccessCard`(D2 전체 접근 유도)
- `features/home/home_providers.dart` — `homeDataProvider`(권한·미분류개수·streak), `PhotoAccessException`
- `features/home/home_screen.dart` — 홈(로딩/빈/정상/에러) + streak 카드
- `features/sort/sort_controller.dart` — `SortController`(Notifier) + `SortState` + `CommitOutcome`. stage→commit→markProcessed 흐름
- `features/sort/sort_screen.dart` — 정리 화면(카드/진행/스테이징 배너/Undo/퀵앨범/commit)
- `features/sort/swipeable_card.dart` — 스와이프 제스처 카드(우=배정/좌=건너뛰기/상=최근앨범, 방향 힌트)
- `features/sort/album_picker_sheet.dart` — 앨범 선택 모달(기존 목록 + 인라인 생성)
- `features/sort/video_preview_sheet.dart` — 영상 간이 미리보기(F-08, 썸네일 기반)
- `features/done/done_screen.dart` — 완료(성공N/실패M + streak 애니메이션 + 광고자리 TODO)
- `features/settings/settings_screen.dart` — 알림 시각·토글·프라이버시(IAP 는 P1, 미구현)

### 수정
- `lib/main.dart` — `ProviderScope`(UncontrolledProviderScope+container) + `NotificationService.init()` + go_router 연결
- `test/widget_test.dart` — 기존 카운터 테스트 → 온보딩 스모크 테스트로 교체
- `pubspec.yaml` — `shared_preferences` 추가(아래 C-1 참조)

---

## B. 화면별 사용 인터페이스 (계약 준수)

| 화면 | 사용한 계약(providers 경유) |
|------|------|
| main | `notificationServiceProvider.init()`, `appSettingsProvider.onboardingCompleted` |
| 온보딩 | `photoServiceProvider.ensurePermission()`·`loadUnclassifiedQueue()`, `notificationServiceProvider.requestPermission()`·`scheduleDaily()`, `appSettings.setOnboardingCompleted/setNotifyTime/setNotifyEnabled` |
| 홈 | `photoServiceProvider.ensurePermission()`·`loadUnclassifiedQueue()`(개수), `processedRepositoryProvider.streakDays()` |
| 정리 | `photoServiceProvider.ensurePermission/loadUnclassifiedQueue/listAlbums/stageAssignment/unstageAssignment/pendingAssignments/commitAssignments`, `processedRepositoryProvider.markProcessed`(성공분만), `thumbnail()` |
| 앨범 모달 | `photoServiceProvider.listAlbums()`·`createAlbum()`·`thumbnail()`(커버) |
| 완료 | `processedRepositoryProvider.streakDays()` |
| 설정 | `notificationServiceProvider.requestPermission/scheduleDaily/cancelAll`, `appSettings` |

**핵심 불변식 준수**: 스와이프=`stageAssignment`(기록 없음) → 세션 끝 `commitAssignments()` → `result.succeeded` 순회하며 `finalAssetId` 로만 `markProcessed`. 실패/취소분은 예약 큐에 유지(재 commit 대상). 광고는 정리 흐름에 넣지 않음(완료 화면에 TODO 주석만).

---

## C. 계약 ↔ UI 기대 불일치 / 편차 (integrator·architect 확인 요망)

1. **[설정 저장소 계약 없음 → shared_preferences 추가]** core(02_integrator_notes)에 온보딩 완료 여부·알림 시각을 저장할 계약이 없음. UI 로컬 설정 최소 보관을 위해 `shared_preferences` 의존성을 추가하고 `AppSettings`(features 레이어)로 캡슐화함. core 침범 아님. 필요 시 core 로 승격 검토.

2. **[설정 앱 딥링크/제한 선택 재표시 메서드 없음]** 스펙(온보딩·홈 에러·D2)은 "설정 앱에서 켜기" 딥링크와 limited→전체 유도를 요구하지만 `PhotoService` 계약에 `openSystemSettings()`/`presentLimitedPicker()` 가 없음(한계 E 에서 "UI 책임"이라 했으나 수단 미제공). 플랫폼 직접 호출 금지 규칙에 따라 **`ensurePermission()` 재호출**로 대체 구현함(권한 거부/limited 시 "권한 다시 요청"/"전체 접근 허용" 버튼 = 재요청). **권장**: `PhotoService.openSystemSettings()` / `presentLimitedPicker()` 추가. iOS 영구 거부·limited 상태에서 재요청만으로는 전체 접근 전환이 제한적일 수 있음(실기기 확인 필요).

3. **[영상 인라인 재생 플러그인 없음]** F-08 "가벼운 인라인 미리보기"를 위해 `video_player` 등이 deps·계약에 없음. 현재는 큰 썸네일 + 재생 아이콘의 **간이 프리뷰(다이얼로그)** 로 처리. 실제 재생이 필요하면 `video_player` 의존성 추가 선행 필요.

4. **[commit 취소 vs 실패 구분]** 한계 B(Android 취소/실패 구분 불가) 그대로 수용. UI 는 `BatchAssignResult.cancelled==true` → 정리 화면 유지 + "동의 필요" 안내, `failed>0`(취소 아님) → 완료 화면에서 "M장 실패, 다시 시도" 안내로 처리. Android 에서 실제 취소가 `failed` 로 들어오면(cancelled=false) 완료 화면으로 넘어가며 실패로 표기됨 — 실기기 관찰 후 보완 여지.

---

## D. 구현 판단 / UX 세부 (QA 참고)

- **스와이프 방향**(00_decisions 미결, 잠정안 적용): 오른쪽=앨범 배정 모달, 왼쪽=나중에(건너뛰기), 위=최근 앨범 즉시 예약(앨범 없으면 모달). 손맛 테스트 후 조정 가능. 방향 감지 후 카드는 가운데로 스냅백하고 콜백만 호출 → **모달 취소 시 카드 유실 없음**(실제 전진은 상태 변경으로만 발생).
- **자동 commit**: 큐 소진 시 `ref.listen` 으로 `isExhausted` 감지 → 자동 `commit`. 예약 0인데 소진되면 홈으로(스낵바 안내). `_finishing` 플래그로 중복 트리거 방지.
- **홈 갱신**: 정리/완료 후 `ref.invalidate(homeDataProvider)`(정리 버튼 push 복귀, 완료 "홈으로", noop 소진 경로)로 미분류 개수·streak 재계산.
- **성능**: 썸네일은 `FutureProvider.autoDispose.family` + `keepAlive()` 로 캐싱(스크롤·재빌드 재로드 감소, PRD 성능 NFR).
- **상태**: 홈=`homeDataProvider`(AsyncValue 4상태), 정리=`SortState.status`(loading/denied/committing/error/ready), 모달=FutureBuilder(로딩/에러/빈/정상).

---

## E. QA 넘길 검증 포인트(스펙 §정리 + integrator §E 대응)
1. stage 후에도 해당 자산이 `loadUnclassifiedQueue` 에 남는가(정리 화면 재진입/Undo).
2. commit 성공분만 `markProcessed` → 이후 미분류에서 제외. 실패/취소분은 pending 유지.
3. Undo 가 마지막 스와이프(배정/건너뛰기)를 정확히 되돌리고 인덱스 복귀하는가.
4. 큐 소진 → 자동 commit → 완료 화면 전이, 예약 0이면 홈 이동.
5. 홈 N == 실제 미분류 개수, 정리 후 갱신.
6. denied/limited 에서 크래시 없이 안내(홈 에러 카드 / LimitedAccessCard).
7. 광고가 정리 흐름 중간에 뜨지 않음(현재 광고 미구현, 완료 화면 TODO 주석만).

## F. P1 미구현(의도)
- 광고(AdMob)/IAP(in_app_purchase) 미구현. 완료 화면에 광고 트리거 위치만 TODO 주석(첫 정리일+7일·세션 1회·축하 뒤, D3). 설정 화면 광고 제거 IAP 미구현.
- 분석(F-12)은 **계측 계층 + 이벤트만 먼저 구현**함(아래 G). Firebase 백엔드는 나중(사용자 확정) — 의존성/설정 파일 미추가.

## G. 분석 계측(F-12) — "계측 계층 + 이벤트 먼저, Firebase는 나중"

### 신규 파일
- `core/analytics/analytics_service.dart` — 추상 계약 + 이벤트/속성 상수(`AnalyticsEvents`/`AnalyticsParams`) + `AnalyticsEvent` 값 객체.
- `core/analytics/local_analytics_service.dart` — 로컬/Noop 구현(debugPrint + 인메모리 기록). Firebase 교체 지점 TODO 명시.
- `test/analytics_test.dart` — Fake 주입 단위/위젯 테스트 2건.

### 수정 파일
- `core/providers.dart` — `analyticsServiceProvider`(LocalAnalyticsService 주입).
- `core/notifications/notification_service.dart` / `local_notification_service.dart` — `didAppLaunchFromNotification()` **추가(additive)**. `notification_opened` 계측용(콜드 스타트 launch-detail, 읽기 전용 `getNotificationAppLaunchDetails`). 기존 시그니처 무변경.
- `main.dart`(app_open + notification_opened), `onboarding_screen.dart`(onboarding_complete), `sort_controller.dart`(sort_session_start/asset_assigned/asset_skipped/sort_session_complete).

### 설계 판단
- **타입 안전 메서드 방식 채택**(제네릭 `logEvent` 아님): SKILL 최대 리스크가 "이름·속성 오타". 콜사이트에서 문자열을 직접 타이핑하지 않도록 이벤트별 메서드 노출, 이름·키는 상수 단일 출처. 다른 경계 계약(NotificationService)과 동일 패턴.
- **반환 `void`**(fire-and-forget): 동기 콜사이트(스와이프 핸들러)에서 await 없이 호출. Firebase 교체 시 구현체 내부에서 `unawaited(logEvent(...))` 래핑.

### 이벤트 7종 실제 계측 지점 + 시점 판단 근거
| 이벤트 | 위치 | 속성 | 시점 근거 |
|--------|------|------|----------|
| `app_open` | `main()` 부팅 | — | 콜드 스타트 1회 |
| `notification_opened` | `main()` — `didAppLaunchFromNotification()` true 시 | — | 알림 탭 콜드 스타트만(포그라운드 탭은 후속: `onDidReceiveNotificationResponse` 배선 필요) |
| `onboarding_complete` | `onboarding_screen._finishToSort` (setOnboardingCompleted 직후) | notify_hour/minute/enabled | 온보딩 확정 = 완료 스텝에서 정리 진입하는 순간 |
| `sort_session_start` | `sort_controller.load()` 큐 로드 성공(ready) | unclassified_count | 큐 로드 성공 = 세션 실질 시작(denied/error 는 미발화). autoDispose 라 화면 진입당 1회 |
| `asset_assigned` | `sort_controller.commit()` `result.succeeded` 순회 | album_id(로컬 UUID) | **stage 아님 = commit 성공분.** SKILL "배정 성공" = 시스템 실반영 성공. stage 는 Undo/취소/실패로 되돌 수 있어 과대계상 → 성공 자산마다 1회 |
| `asset_skipped` | `sort_controller.skipCurrent()` | — | 사용자 스킵 액션 시점 |
| `sort_session_complete` | `sort_controller.commit()` (취소·noop 제외) | processed_count, remaining_unclassified | 완료 화면으로 전이하는 실반영 커밋에서만. 남은수 = 세션 시작 큐 − 성공수(음수 방지) |

### 프라이버시(PRD 최소수집 준수)
- 사진 내용·개인정보·원본 자산 ID 미포함. 카운트·로컬 앨범 UUID·화면/액션 이벤트만. `album_id` 는 앱 내부 UUID(원본/시스템 식별자 아님).

### 나중에 Firebase 로 교체 시 손댈 지점
1. `pubspec.yaml` 에 `firebase_core`/`firebase_analytics` 추가 + `flutterfire configure`(설정 파일).
2. `core/analytics/` 에 `FirebaseAnalyticsService`(동일 `AnalyticsService` 구현) 작성 — 각 메서드에서 `unawaited(_fa.logEvent(name: <상수>, parameters: <상수 키>))`. 이름·키는 기존 `AnalyticsEvents`/`AnalyticsParams` 재사용.
3. `providers.dart` `analyticsServiceProvider` 반환만 교체. **features 콜사이트 무변경**(추상 타입만 의존).
4. (선택) `notification_opened` 포그라운드 탭까지 계측하려면 `local_notification_service.init()` 에 `onDidReceiveNotificationResponse` 콜백 배선 후 analytics 연결.

### QA 검증 포인트(분석)
- 온보딩 완료 시 `onboarding_complete`(알림시각), 정리 진입 시 `sort_session_start`(미분류수), commit 성공 시 `asset_assigned`×성공수 + `sort_session_complete`(처리수·남은수)가 스펠링·속성 정확히 찍히는가. (test/analytics_test.dart 로 자동 검증)
- **stage 단계에서 asset_assigned 가 찍히지 않는지**(commit 전 0건) — 테스트로 고정.

## H. Firebase Analytics 실연동 (F-12, D3 확정) — 2026-07-04

로컬 계측 계층(G) 위에 **Firebase Analytics 백엔드를 실제로 배선**했다. 단, Firebase
콘솔 프로젝트가 아직 없어 **설정 파일이 부재**하므로, 지금은 안전하게 로컬로
폴백하고 설정이 붙는 순간 자동으로 Firebase 전송으로 전환된다(코드 변경 0).

### 신규/수정 파일
- **신규** `core/analytics/firebase_analytics_service.dart` — `AnalyticsService` 의
  Firebase 구현. 각 메서드는 `AnalyticsEvents`/`AnalyticsParams` 상수만 사용(문자열
  직접 타이핑 없음), 단일 지점 `_log` 에서 `unawaited(_fa.logEvent(...))` fire-and-forget.
  **Firebase 는 속성 값으로 String/num 만 허용**하므로(bool 거부, SDK 런타임 assert)
  `_coerceForFirebase` 가 bool → int(1/0) 강제(예: `notify_enabled`). 테스트용
  `withSink` 생성자로 SDK 없이 매핑 검증 가능.
- **신규** `test/firebase_analytics_service_test.dart` — 7종 이벤트 매핑 + bool→int
  강제 + "모든 값이 String/num" 불변식 검증(8 테스트, 전부 통과).
- **수정** `pubspec.yaml` — `firebase_core ^4.11.0`, `firebase_analytics ^12.4.3` 추가.
- **수정** `main.dart` — 부팅 시 `_initAnalyticsService()`: `Firebase.initializeApp()` 을
  **try-catch** 로 감싸 성공 시 `FirebaseAnalyticsService`, 실패(설정 부재) 시
  `LocalAnalyticsService` 폴백. 결과를 `analyticsServiceProvider` override 로 주입
  (기존 `sharedPrefsProvider` override 패턴과 동일). **features 콜사이트 무변경.**
- **수정** `core/providers.dart` — `analyticsServiceProvider` 기본값은 그대로
  `LocalAnalyticsService`(override 안 되는 테스트 환경용), 실제 선택은 main 이 주입.

### 왜 지금 google-services 플러그인을 안 넣었나 (중요)
Android 의 `google-services` gradle 플러그인은 `google-services.json` 이 있어야
빌드된다. 파일이 없는데 플러그인을 넣으면 **빌드가 깨진다.** 그래서 플러그인은
설정 파일이 생긴 뒤에 추가한다. 지금은 `firebase_core`/`firebase_analytics`
**의존성만** 추가돼 있고, 이것만으로는 Android 빌드가 깨지지 않는다(플러그인이
없어 `initializeApp()` 이 런타임에 예외 → 로컬 폴백). `flutter build apk --debug`
로 검증했다.

### Firebase 활성화 절차 (사용자가 나중에 할 일)
아래를 마치면 **코드 수정 없이** 앱이 자동으로 Firebase 로 전송한다.

1. **Firebase 콘솔에서 프로젝트 생성** — https://console.firebase.google.com → 새
   프로젝트. Google Analytics(GA4) 연동을 **켠다**(Firebase Analytics 데이터가 GA4
   속성으로 흐름).
2. **FlutterFire CLI 로 앱 등록 + 설정 파일 생성**(권장, 가장 쉬움):
   ```
   dart pub global activate flutterfire_cli
   flutterfire configure
   ```
   프로젝트를 고르면 자동으로:
   - `lib/firebase_options.dart` 생성 → main.dart 를 아래처럼 한 줄만 바꾼다:
     `await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);`
     (지금은 인자 없는 `initializeApp()` — 설정 파일 기반. options 를 넘기면 더 명시적)
   - Android `android/app/google-services.json`, iOS `ios/Runner/GoogleService-Info.plist` 배치.
3. **Android: google-services gradle 플러그인 추가**(설정 파일이 생긴 뒤에만):
   - `android/settings.gradle`(플러그인 DSL) 의 `plugins { }` 블록에
     `id "com.google.gms.google-services" version "4.4.2" apply false` 추가.
   - `android/app/build.gradle` 의 `plugins { }` 블록에
     `id "com.google.gms.google-services"` 추가.
   (FlutterFire 최신 버전은 이 gradle 수정도 일부 자동화하지만, 안 되면 수동으로.)
4. **iOS**: `GoogleService-Info.plist` 를 Xcode 로 Runner 타겟에 추가(폴더 복사만으로는
   번들에 안 들어갈 수 있음). CocoaPods 는 `flutter build ios` 시 자동 설치.
5. **검증**: 디버그 실행 후 로그에 `[analytics] Firebase 초기화 성공` 이 뜨는지 확인.
   Firebase 콘솔 → Analytics → DebugView 에서 `app_open` 등 이벤트 실시간 확인
   (디버그 이벤트는 `adb shell setprop debug.firebase.analytics.app <패키지명>` 후 보임).

### 현재 폴백 동작 요약
| 상태 | `Firebase.initializeApp()` | 주입되는 구현 | 이벤트 목적지 |
|------|------|------|------|
| 설정 파일 없음(현재) | 예외 발생 → catch | `LocalAnalyticsService` | debugPrint + 인메모리 |
| 설정 파일 있음(활성화 후) | 성공 | `FirebaseAnalyticsService` | Firebase/GA4 |

크래시는 어느 경우에도 없다(try-catch 보장). 이벤트 이름·속성·발화 시점은 두
구현이 동일하므로, 백엔드가 바뀌어도 지표 정의는 변하지 않는다.

---

## I. 수익화 (F-09 광고 · F-10 광고 제거 IAP) — feature-builder P1

> 대상: qa-verifier(광고 위치·게이트 불변식), spec-architect(범위), final-auditor(프라이버시).
> 상태: `flutter analyze` No issues · `flutter test` 38개 통과(신규 12) · `flutter build apk --debug` 성공.
> 원칙 준수: 서버 없음(SDK/스토어만) · 광고는 완료 화면 통계 "아래" 세션당 1회 · 사진/개인정보 SDK 유출 없음.

### I-1. 형태 선택 근거 (과설계 금지)
- **광고 = 배너 1개**. 완료 화면 와이어프레임의 광고 자리가 "streak 통계 아래 박스형"이라 인라인 배너 계열이 정확히 대응. 전면(interstitial)은 완료의 성취감을 가로채고, 네이티브는 MVP 에 과함 → 배너 하나만.
- **IAP = 설정의 구매/복원 2버튼**. 비소모성 1개.

### I-2. 생성/수정 파일
신규 (lib/core/monetization):
- `monetization_config.dart` — 광고 유닛 ID·상품 ID·유예일수 단일 출처 + **실 ID 교체 절차 문서**. 지금은 전부 Google 공식 테스트 값.
- `ad_gate.dart` — **순수 정책** `AdGate.shouldShowCompletionAd()`(첫 정리+7일·미제거·세션당 1회) + `AdSession`(세션 1회 상태).
- `ad_service.dart` — 추상 `AdService`/`CompletionBanner`(SDK 타입 격리).
- `admob_ad_service.dart` — `google_mobile_ads` 구현(SDK import 유일 지점). 배너 로드/폐기.
- `noop_ad_service.dart` — 무동작 폴백(테스트·미지원·초기화 실패).
- `purchase_service.dart` — 추상 `PurchaseService` + `RemoveAdsProduct`/`StoreStatus`.
- `in_app_purchase_service.dart` — `in_app_purchase` 구현(SDK import 유일 지점). 권한=로컬 캐시 bool, 구매/복원 스트림 처리.
- `noop_purchase_service.dart` — 무동작 폴백(로컬 캐시 권한은 유지).

신규 (lib/features):
- `features/done/completion_ad_slot.dart` — 완료 화면 광고 슬롯 위젯(게이트 판정→로드→표시, 실패 시 빈 위젯).
- `features/settings/remove_ads_section.dart` — 구매/복원 UI(스토어 미설정 시 우아하게 비활성).

수정:
- `lib/core/analytics/analytics_service.dart`(+Local/Firebase 구현) — `ad_shown`·`remove_ads_purchased`·`remove_ads_restored` 3개 이벤트 추가(속성 없음, 개인정보 없음).
- `lib/core/providers.dart` — `adServiceProvider`·`purchaseServiceProvider`(기본 Noop)·`adSessionProvider`·`adsRemovedProvider`(반응형 스트림).
- `lib/main.dart` — `_initAdService()`/`_initPurchaseService()` 부팅 + override 주입(analytics 와 동일 폴백 패턴).
- `lib/app/settings_store.dart` — `firstSortDate` get + `recordFirstSortDateIfAbsent()`(광고 게이트 기준).
- `lib/features/done/done_screen.dart` — 첫 정리일 기록(successCount>0) + `CompletionAdSlot` 배치(streak 아래).
- `lib/features/settings/settings_screen.dart` — `RemoveAdsSection` 추가.
- `android/.../AndroidManifest.xml` · `ios/Runner/Info.plist` — AdMob App ID meta-data(테스트 값, 없으면 SDK 크래시).
- `pubspec.yaml` — `google_mobile_ads: ^9.0.0`(6.0.0 은 Gradle 9 에서 `configurations.all` 로 빌드 실패 → 9.0.0 으로 상향), `in_app_purchase: ^3.2.0`.

신규 테스트: `test/ad_gate_test.dart`(게이트 6케이스), `test/purchase_service_test.dart`(폴백 3케이스), `firebase_analytics_service_test.dart`(신규 이벤트 3매핑 추가).

### I-3. 광고 게이트 로직 (불변식)
`AdGate.shouldShowCompletionAd(firstSortDate, now, adsRemoved, shownThisSession)` — 전부 AND:
1. `!adsRemoved` (F-10 구매 시 영구 억제)
2. `firstSortDate != null` (첫 정리 전 억제)
3. `now >= firstSortDate + 7일` (D3: 설치일 아님, **첫 정리일** 기준)
4. `!shownThisSession` (세션당 1회)
- **위치 불변식은 구조로 보장**: 이 함수는 `completion_ad_slot.dart` = 완료 화면에서만 호출. 정리 화면(sort_*)은 이 위젯/함수를 전혀 참조하지 않음 → "정리 흐름 중 삽입" 원천 불가.
- **첫 정리일 기록**: `done_screen` 진입(commit 성공분>0) 시 `recordFirstSortDateIfAbsent`. SharedPreferences 캐시가 동기 반영되므로 첫 정리 당일엔 항상 게이트 false(광고 없음).
- **로드 실패/미지원/미초기화**: 빈 위젯 → 완료 화면은 광고 없이 정상. 광고가 UX 인질 안 됨.

### I-4. 실 계정/스토어 등록 시 사용자가 할 일 (체크리스트)
1. **AdMob 앱 등록** → 발급 App ID 로 교체:
   - `android/app/src/main/AndroidManifest.xml` 의 `com.google.android.gms.ads.APPLICATION_ID`
   - `ios/Runner/Info.plist` 의 `GADApplicationIdentifier`
   - (⚠️ 이 값이 없거나 틀리면 SDK 초기화 시 크래시)
2. **AdMob 배너 광고 유닛** 생성 → `monetization_config.dart` 의 `_realBannerAndroid`/`_realBannerIos` 교체.
3. `monetization_config.dart` 의 `_useTestAds = false` 로 전환(또는 `kReleaseMode` 분기)해 실 광고 노출.
4. **스토어 비소모성 상품** 등록: 상품 ID = `remove_ads`(=`MonetizationConfig.removeAdsProductId`). Play Console + App Store Connect 양쪽. 등록 전까지 설정의 광고 제거 버튼은 "준비 중"으로 우아하게 비활성.
5. iOS: 실 광고 전 `Info.plist` 에 `SKAdNetworkItems`(AdMob 문서 목록) 추가 권장(성과 측정). MVP 빌드엔 불필요.
6. (선택) 광고 노출/구매 지표는 Firebase 활성화 후 `ad_shown`·`remove_ads_purchased`·`remove_ads_restored` 로 확인.

---

## J. UI/UX 대폭 개선 (프로토타입 톤 탈피) — 2026-07-06

> 대상: qa-verifier(상태 전이 회귀 확인), spec-architect(화면 스펙 편차 없음), final-auditor.
> 상태: `flutter analyze` **No issues** · `flutter test` **44/44 통과** · `flutter build apk --debug` 성공 · 실기기(S22 Ultra) 라이트/다크 시각 확인.
> 범위: `lib/app/`(theme·router) + `lib/features/` 전 화면 + `main.dart`(다크 테마 배선 2줄). **lib/core·android 무수정**(공개 인터페이스 그대로 소비).

### J-1. 디자인 방향 (톤·타이포·컬러 근거)
- **톤 = "따뜻하고 정돈된 데일리 습관".** 기존 시드가 차가운 인디고(#3D5AFE)라 테마 주석의 "따뜻한 톤"과 어긋났다. **허니 앰버(#CB5E24 시드)** 로 교체 — streak 의 🔥 와 색 계열이 하나로 묶여 "성취/습관" 정서를 강화(원칙 3, iOS 성취감 보완).
- **컬러**: 웜 페이퍼 서피스(순백 대신 옅은 살구빛 #FCF7F2)로 사진이 배경에서 뜨게 함. primary/primaryContainer/surface 계열을 손으로 다듬어(ColorScheme.fromSeed + copyWith) M3 기본의 흐릿함을 걷어내고 브랜드 채도를 확보. 대비: 라이트 primary(#B85A22) on white ≈ 5.5:1, 버튼 라벨 가독 확보.
- **다크 테마 신규**: 알림이 밤(기본 21:00)에 오는 앱이라 실사용 맥락에 맞고 사진이 어두운 배경에서 돋보인다(원칙 1). 웜 near-black(#16110D) + 라이트 피치 primary. `main.dart` 에 `darkTheme`+`themeMode.system` 배선.
- **타이포**: 새 폰트 파일/네트워크 폰트 **미추가**(오프라인·의존성 최소). 기본(Roboto/시스템 CJK) 위에 display/headline 트래킹을 조이고 굵기를 w700~w800 로 올려 "의도된" 느낌만 부여. 홈 카운트는 displayLarge(w800) 히어로.
- **컴포넌트 테마 정비**: Card(플랫·surfaceTint off·radius 20), Chip(pill·surfaceContainerHigh), BottomSheet(top radius 28·drag handle), InputDecoration(filled·radius 14), SnackBar(floating), AppBar(bold 22 title), Divider·ProgressIndicator 색. 라운드 지오메트리 통일(카드/시트 20~28, 버튼/입력 14~16, 칩 full).
- **전환 애니메이션**: go_router `CustomTransitionPage` 로 페이드+살짝 떠오름(320ms). 급격한 좌우 슬라이드 대신 정리 루프가 차분히 이어지게. 뒤로가기 자동 역재생.

### J-2. 화면별 변경 요지
| 화면 | 변경 |
|------|------|
| **홈** | 미분류 카운트를 **그라데이션 히어로 카드**(displayLarge 숫자)로 격상. streak 카드에 **이번 주 7칸 습관 스트립**(원칙 3 강화) + 아이콘 원형 배지. 빈 상태는 🎉 축하 그라데이션 카드. CTA 풀너비·서브카피("30초면 충분해요"). 로딩/에러도 히어로 스켈레톤·원형 아이콘으로. |
| **정리(스와이프)** | **다크 라이트박스 캔버스**(kSortCanvas)로 전환 → 사진이 화면 주인공(원칙 1). 사진 카드 대형·라운드 24·그림자. 진행도를 AppBar 하단 **LinearProgressIndicator** 로. 크롬(퀵 앨범 칩·액션 3버튼·스테이징/커밋)을 **하단 서피스 패널**에 응집. 배정 버튼은 채운 앰버 원으로 **강조**(원칙 2 "탭 1회"). 권한/에러 상태도 다크 대응. |
| **완료** | 축하 마크를 **그라데이션 원+후광**으로, streak 카드에 7칸 스트립 추가. **삼성 갤러리 힌트**("옮긴 사진은 갤러리 앨범에 담겨요. 삼성 갤러리라면 '앨범 › 모든 앨범'에서") 자연 삽입(QA S-2 후속). **CompletionAdSlot 위치 불변**(streak 아래·홈 버튼 위, 원칙 4). |
| **온보딩** | 히어로 아이콘을 **그라데이션 원 안에** 배치(`_HeroIcon`). 프라이버시 카드에 아이콘 배지. 스텝 인디케이터를 현재 스텝 강조(flex 3:2)+애니메이션. **테스트 고정 문자열 유지**('폰 밖으로 나가지 않'·'시작하기'). |
| **설정** | 알림/프라이버시/광고를 **그룹 섹션 카드**(앰버 헤더+라운드 보더)로 재구성. 프라이버시에 shield 배지. RemoveAdsSection 의 자체 헤더/Divider 제거(섹션 래퍼가 대체). |
| **앨범 모달** | 헤더에 "탭 한 번으로 배정돼요" 서브카피. 입력 필드 테마 스타일 상속(filled·라운드). 시트 top radius 28·drag handle. |
| **스와이프 카드** | 방향 힌트 배지를 pill+그림자로. |

### J-3. 4원칙 체크 결과
1. **사진이 주인공** ✅ — 정리 화면 다크 라이트박스 위 대형 카드로 사진이 뷰포트 60%+ 차지, 크롬은 하단 패널로 응집.
2. **배정은 탭 1회** ✅ — 하단 퀵 앨범 칩(즉시 배정) + 채운 앰버 "앨범 배정" 원버튼으로 판단→행동 최단.
3. **streak 습관 자극** ✅ — 홈·완료 양쪽에 연속일 + **7칸 주간 스트립** 시각화로 강화.
4. **보상 먼저 광고 나중** ✅ — 완료 화면 축하·통계·streak **먼저**, `CompletionAdSlot` 은 그 아래 원위치 그대로(코드 구조상 정리 화면엔 없음).

### J-4. 회귀 방지 · 주의 준수
- **테마 함정 준수**: FilledButton `minimumSize: Size(64,56)` 유지, 풀너비는 콜사이트 `SizedBox(width: double.infinity)` 옵트인. `Size.fromHeight` 미사용(305984a 백지화 재발 방지).
- **정리 화면 AppBar title** 은 다크 캔버스 대비 위해 흰색 `titleTextStyle` 로 덮음(테마 title 색=onSurface 어두움이 foregroundColor 를 이겨 제목이 안 보이던 것 수정).
- core 공개 인터페이스·상태 전이 로직 무변경(SortController/CommitOutcome/providers 그대로). 순수 프레젠테이션만 손봄 → `sort_controller_reentry_test` 등 44 테스트 전원 통과.
- 신규 pub 의존성 **0개**.
- `main.dart` 는 core/android 아님 — 다크 테마 활성화에 필요한 `darkTheme`+`themeMode` 2줄만 추가.

### J-5. 실기기 시각 확인 (S22 Ultra, 라이트+다크)
온보딩→홈→정리→설정→앨범모달 순회. 스크린샷(스크래치패드 `uishots/`): 홈 로딩/로드(16058장 히어로+streak), 정리 다크 라이트박스(사진 히어로+하단 패널), 설정 그룹 카드, 앨범 모달, 홈 다크. **실제 commit/스와이프/칩 탭 미실행**(소유자 실사진 보호) — 정리 화면은 렌더 확인까지만, 앨범 모달은 열기만 하고 미선택 dismiss. 완료 화면은 직접 진입(실 commit) 불가라 코드 리뷰+위젯 테스트로 대체.
