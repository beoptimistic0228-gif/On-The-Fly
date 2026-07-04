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
