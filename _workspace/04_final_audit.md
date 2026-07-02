# 04 · 최종 감사 (final-auditor — 릴리스 전 독립 게이트)

> 기준: `그때그때_PRD_v1.0.md`(SSOT) + `_workspace/00_decisions.md`(D1~D3) + 01_architect_* 설계.
> 방법: 팀 자기보고(02/03)를 믿지 않고 `lib/`·`android/`·`ios/`·`pubspec.yaml` 전량 코드 재확인 + grep 유출 경로 스캔 + `flutter analyze`/`flutter test`/`pub outdated` 직접 실행.
> 날짜: 2026-07-03. 실기기 없음 → 기기 의존 항목은 "PLAUSIBLE(실기기 검증 필수)"로 명시.

---

## 0. 품질 게이트 (직접 실행)

| 게이트 | 결과 |
|--------|------|
| `flutter analyze` | **No issues found** (exit 0) |
| `flutter test` | **All tests passed** (2/2 — 온보딩 스모크 + QA I-1 재진입 회귀) |
| `flutter pub outdated` | 직접 의존성 전부 최신(resolvable 기준). 위험 의존성 없음 |

QA 리포트의 HIGH I-1(정리 화면 재진입 파손)은 **수정 확인**: `sort_controller.dart:226-227` `NotifierProvider.autoDispose` 전환 + 회귀 테스트(`test/sort_controller_reentry_test.dart`) 존재. 반면 QA C-2(설정 딥링크/presentLimited)와 C-4(취소/실패 구분)는 **미수정 상태로 남아 있음**(아래 A-4/A-5).

---

## A. PRD·설계 정합성 (심각도순)

### A-0. F-01~F-13 정합성 총괄

| ID | 기능 | 우선순위 | 판정 | 근거(파일:라인) |
|----|------|---------|------|------|
| F-01 | 미분류 큐 생성 | P0 | **구현** | `photo_manager_photo_service.dart:50-87` — 전체 스캔 + `processedIdSet()` 대조(73). 판별=처리 ID 집합(설계 §3 준수). 시간 프리필터는 의도적 미적용(integrator 한계 D, 문서화된 편차 — 정확성 우선, 성능 리스크만 잔존) |
| F-02 | 매일 알림 | P0 | **부분** | `local_notification_service.dart:74-87` 스케줄 자체는 구현. 그러나 **타임존 미설정으로 발송 시각이 로컬과 어긋남**(→ A-2, HIGH) |
| F-03 | 스와이프 배정 UI | P0 | **구현** | `swipeable_card.dart:58-71`(우=배정/좌=나중에/상=최근앨범), `sort_controller.dart:134-149` stage, 자동 전진 |
| F-04 | 앨범 선택/생성 | P0 | **구현** | `album_picker_sheet.dart:45-63,164-192` + `photo_manager_photo_service.dart:266-289`. 평면 구조 준수(parentId 없음). 앨범명 입력 검증 없음(→ B-3, LOW) |
| F-05 | 시스템 앨범 반영 | P0 | **부분** | iOS 태깅 `_commitDarwin`(129-168) / Android 배치 이동 `_commitAndroid`(171-230) 구현. 단 iOS 빈 앨범 재해석 실패 위험(→ A-3), Android 동의창 다회·취소 오안내(→ A-5). 실기기 전면 미검증 |
| F-06 | 처리 완료 기록(중복 방지) | P0 | **구현** | `sort_controller.dart:194-199` 성공분 `finalAssetId`만 `markProcessed` → `processed_dao.dart:16-21` ID 집합 → 큐 제외. 재진입 회귀 테스트 통과 |
| F-07 | 온보딩 | P0 | **구현** | `onboarding_screen.dart` 4스텝(가치·프라이버시→사진권한→알림권한·시각→첫 정리). 설정 딥링크만 부재(→ A-4) |
| F-08 | 영상 지원 | P0 | **부분** | 썸네일+재생배지 `asset_thumbnail.dart:81-88` 구현. 그러나 "탭 시 간이 재생"이 **정적 큰 썸네일 다이얼로그**(`video_preview_sheet.dart:10-36`, 재생 아님)이고 화면 스펙의 영상 길이 표시도 없음 |
| F-09 | 광고(7일·완료 뒤·세션 1회) | P1 | **미구현** | `pubspec.yaml`에 google_mobile_ads 없음. `done_screen.dart:117-119` TODO 주석만 |
| F-10 | 광고 제거 IAP | P1 | **미구현** | in_app_purchase 의존성·코드 0건. `settings_screen.dart`에 구매/복원 UI 없음 |
| F-11 | 건너뛰기 | P1 | **구현** | `sort_controller.dart:152-161` skip은 stage·기록 없음 → 다음 큐 재등장(§3.4 준수) |
| F-12 | 분석 SDK 이벤트 | **P0** | **미구현** | firebase/analytics grep 0건. AnalyticsService 인터페이스(architecture §2.4)조차 없음 |
| F-13 | 프라이버시 안내 | P1 | **구현** | 온보딩 스텝1(`onboarding_screen.dart:137-157`) + 설정(`settings_screen.dart:76-87`) + `Info.plist:9` 권한 문구까지 일관 |

### A-1. [HIGH] MVP 범위 미완 — F-12(P0)·F-09·F-10 미구현
- **판정**: PRD 8절 In Scope = F-01~F-13 전체인데 3건 미구현. 특히 **F-12는 P0**(North Star "주간 정리 완료 사용자 수"·D7 리텐션 산출 불가 → 성공 지표를 아예 측정할 수 없음).
- **근거**: `pubspec.yaml:30-46`(광고/IAP/분석 의존성 전무), `done_screen.dart:117-119`(TODO만), builder notes §F("P1 미구현 의도" — 그러나 F-12는 PRD상 P1이 아니라 P0).
- **영향**: 이대로 출시하면 "무료 배포 + 지표 깜깜이". 과금 모델(NFR 7절)·핵심 KPI 전부 부재. PRD v1.0 기준 릴리스 정의 미충족.
- **권고**: (a) F-12 최소 구현(Firebase Analytics + logAppOpen/logSessionCompleted/logAssign, architecture §2.4 계약 그대로) 후 F-09/F-10 후속, 또는 (b) 사용자(낙관)가 "수익화·분석 없는 v0.9 소프트런치"로 **PRD 개정을 명시 승인**. 어느 쪽이든 현재 상태는 PRD v1.0 확정본과 불일치.

### A-2. [HIGH] 알림 타임존 미설정 → F-02 인수 조건 실질 미충족
- **판정**: `tz.local`이 기본 **UTC**인 채 `zonedSchedule` 호출. 한국(UTC+9) 기기에서 21:00 설정 시 21:00 UTC = **다음날 06:00 KST**에 발송된다.
- **근거**: `local_notification_service.dart:32-34`(주석으로 자인: "tz.local 은 기본 UTC"), `:105-119`(`_nextInstanceOf`가 `tz.local` 기준 계산), `:82`(inexact은 ±분 단위 오차 허용이지 9시간 오프셋을 정당화하지 못함). integrator 한계 C·QA I-3이 "inexact라 영향 제한"으로 과소평가했으나, 이는 **정시성 오차가 아니라 시각 자체가 틀리는 결함**.
- **영향**: "매일 정한 시간에 알림"은 습관 루프의 트리거(제품 목표의 심장). 사실상 F-02 파손 — D7 리텐션 가설 검증 불가.
- **권고**: `flutter_timezone`(또는 동등)으로 기기 타임존명 획득 → `tz.setLocalLocation()` 후 스케줄. 수정 대상: platform-integrator. 반나절 이하 작업.

### A-3. [HIGH·PLAUSIBLE, 실기기 검증 필수] iOS 새(빈) 앨범 commit 실패 가능 — 첫 사용 핵심 여정 파손 위험
- **판정**: iOS commit은 앨범을 `getAssetPathList()` 재조회로 해석하는데(`photo_manager_photo_service.dart:310-319` `_resolveDarwinPath`), photo_manager의 경로 목록은 **기본적으로 빈 앨범을 제외**한다(`FilterOptionGroup.containsEmptyAlbum` 기본 false). 방금 만든 앨범은 항상 비어 있으므로 조회에 안 잡혀 `path == null` → 그 앨범에 예약된 **전량 failed** 가능.
- **근거**: `createAlbum`(277-278)이 반환한 `AssetPathEntity`를 버리고 id 문자열만 저장 → commit 때 `_resolveDarwinPath`가 `getAssetPathList(hasAll: false, type: RequestType.common)`(311-314)로 재조회 — `containsEmptyAlbum` 옵션 미지정.
- **영향**: MVP의 단 하나의 여정(온보딩→새 앨범 생성→스와이프→commit→Aha)이 iOS에서 첫 회부터 실패할 수 있음. 유실은 없으나(실패분 큐 유지) "오 편하다"가 "안 되네"가 된다.
- **권고**: `_resolveDarwinPath`에서 `filterOption: FilterOptionGroup(containsEmptyAlbum: true)` 지정, 또는 `PHAssetCollection` id로 직접 fetch(`AssetPathEntity.fromId`). 수정 대상: platform-integrator. **실기기(iOS)에서 "새 앨범 → 배정 → commit" 스모크를 릴리스 전 필수 수행.**

### A-4. [MEDIUM] D2(제한 접근 → 전체 접근 유도) 부분 위배 — 유도 수단 무력 + 정리 미차단
- **판정 1(QA C-2 미수정)**: limited/denied에서 "전체 접근 허용"·"권한 다시 요청" 버튼이 `ensurePermission()` 재호출뿐(`permission_help.dart:56`, `home_screen.dart:92`). iOS에서 이미 limited/영구 denied면 시스템 다이얼로그가 다시 뜨지 않아 **버튼 무반응**. `PhotoService`에 `openSystemSettings()`/`presentLimited()`가 여전히 없음(`photo_service.dart:14-49` 9메서드 확인).
- **판정 2(신규)**: D2는 "부분 접근 정리는 MVP 미지원"인데, `sort_controller.dart:112-115`는 **denied만 차단**하고 limited는 통과 → 부분 접근 상태로 정리가 그대로 진행된다. 홈도 카드만 띄우고 [정리 시작] 활성(`home_screen.dart:117-119,153-163`).
- **영향**: limited 사용자는 (a) 전체 접근으로 전환할 실효 수단이 없고 (b) 미지원이라던 부분 정리를 하게 됨 — 확정 결정과 이중 불일치. "일부만 정리했는데 미분류가 남는" 완결감 훼손.
- **권고**: photo_manager 내장 `PhotoManager.openSetting()`/`presentLimited()`를 PhotoService에 추가(신규 deps 불필요, QA 권고와 동일). limited 시 정리 진입을 안내 화면으로 막을지 여부는 사용자 확인 후 결정(현행 유지 시 00_decisions에 편차 기록).

### A-5. [MEDIUM] D1 편차 — Android 동의창 "1회" 아님(앨범 수만큼) + 취소가 "실패"로 오안내
- **판정 1(신규)**: `_commitAndroid`는 앨범별 그룹으로 `moveAssetsToPath`를 **그룹당 1회씩 호출**(`photo_manager_photo_service.dart:182,203-206`) → 한 세션에서 3개 앨범에 배정하면 시스템 동의창 3회. D1 확정문("마지막에 시스템 동의창 1회")과 다름. 마찰 리스크(PRD 10절)가 그대로 재현될 수 있음.
- **판정 2(QA C-4 미수정)**: `moveAssetsToPath` 반환 bool로 취소/실패 구분 불가 → `cancelled` 항상 false(`:207-210`, `assignment.dart:46` 기본값). 사용자가 동의창을 취소해도 `/done`으로 넘어가 "N장 반영 못했어요"로 표기(`sort_screen.dart:34-38` cancelled 분기는 Android에서 사실상 사문). 예약 큐가 유지되어 **데이터 유실은 없음** — 안내 품질 문제.
- **권고**: (1) 이동은 MediaStore write-request 특성상 앨범별 분리가 불가피하면, commit 전에 "앨범 M개 → 동의창 M회" 사전 고지 또는 세션당 단일 앨범 UX 검토. (2) 취소 구분은 실기기에서 반환/예외 관찰 후 보완(QA 권고 유지). 00_decisions D1 문구와 실제 동작의 편차를 사용자에게 보고할 것.

### A-6. [LOW] F-08 다운그레이드 — "간이 재생"이 정적 프리뷰
- `video_preview_sheet.dart:10-36`: 탭 시 큰 썸네일 + 닫기 버튼(재생 없음). 화면 스펙의 "재생 아이콘 + 길이" 중 길이 표시도 없음(`AssetRef`에 duration 필드 자체가 없음). QA C-3과 동일 판단 — MVP 수용 가능하나 PRD 인수 조건("탭 시 간이 재생")과는 불일치. 릴리스 노트/백로그에 명시 권고(`video_player` 도입 시 계약에 duration 추가).

### A-7. [LOW] 부속 미완 2건 (QA I-2 미수정 포함)
- **커버 썸네일 영구 플레이스홀더**: `coverAssetId`를 채우는 경로가 여전히 없음 → `album_picker_sheet.dart:175` 분기 항상 false.
- **"최근 앨범" 퀵버튼이 사실상 "최근 생성" 순**: `Albums.updatedAt`이 생성/setSystemRef 때만 갱신되고(`album_dao.dart:29-36`) 배정에 사용해도 안 바뀜 → `sort_screen.dart:184` `albums.take(3)`·상 스와이프 대상이 최근 사용 앨범이 아님. 설계(screens §4 "최근 사용 순")와 미세 불일치.

### A-8. [INFO] Out of Scope 침범: 없음
삭제/중복 정리·태그·AI 그룹핑·중첩 폴더·다중 배정·통계·클라우드 — grep·코드 확인 결과 전부 부재(정상). 다중 배정은 `_pending` Map[assetId] 구조로 원천 차단(`photo_manager_photo_service.dart:27`). 광고 규칙(7일·완료 뒤·세션 1회) 위반 흔적 없음 — 광고 코드 자체가 0.

### A-9. [INFO] 표기·고지 잔무
- 앱 표시명이 `android:label="on_the_fly"`(`AndroidManifest.xml:21`)·`CFBundleDisplayName=On The Fly`(`Info.plist:15`) — 제품명 "그때그때" 미반영. 스토어 제출 전 정리 필요.
- datamodel 확정 3의 "재설치/백업복원 시 처리 기록 소실 → 짧게 고지" 문구가 온보딩/설정 어디에도 없음(감수 결정이나 고지 약속 미이행).

---

## B. 보안·프라이버시·취약점 (심각도순)

### B-1. [PASS — 최우선 항목] 원본 사진·영상 바이트의 외부 유출 경로: **없음**
- **네트워크**: `pubspec.yaml`에 http/dio 등 네트워크 라이브러리 0. `lib/` 전체 grep — http/dio/socket/upload/share/WebView **0건**. 릴리스 `AndroidManifest.xml`에 **INTERNET 권한 자체가 없음**(debug/profile 매니페스트에만 존재 — Flutter 개발용 표준, 릴리스 빌드에 미포함) → 유출 코드가 생겨도 릴리스에선 네트워크 불가. cleartext/ATS 설정도 부재(해당 없음).
- **파일/로그**: `File(` 사용은 DB 오픈 1곳(`app_database.dart:87`)뿐. print/debugPrint/Logger/writeAsBytes **0건** — 자산 데이터 로깅 없음.
- **저장**: DB는 `ProcessedAssets(id, processedAt, albumId, mediaType)` + `Albums(참조 메타)`만(`app_database.dart:18-59`) — 원본·EXIF·위치 저장 없음, 설계 §1 그대로. SharedPreferences는 온보딩 플래그·알림 시각 4키뿐(`settings_store.dart:20-23`). 썸네일은 `Image.memory`(`asset_thumbnail.dart:80`) 메모리 전용, 영구 사본 없음.
- **결론**: "사진은 폰 밖으로 안 나간다" 핵심 약속 **코드로 성립**. F-13 문구와 실제 동작 일치.

### B-2. [PASS] 시크릿·플랫폼 설정·권한 최소화
- 하드코딩 키/토큰 grep(전 확장자) 0건.
- Android 권한: READ_MEDIA_IMAGES/VIDEO + VISUAL_USER_SELECTED + READ_EXTERNAL_STORAGE(maxSdk 32 한정) + POST_NOTIFICATIONS + RECEIVE_BOOT_COMPLETED — 전부 기능 대응. `SCHEDULE_EXACT_ALARM` 의도적 미사용(권한 최소화). 리시버 2종 `exported="false"`(`AndroidManifest.xml:47-59`) — 양호.
- iOS: 사진 관련 2키만, 문구에 프라이버시 약속 포함(`Info.plist:8-11`).
- DB 위치: `getApplicationDocumentsDirectory()` 앱 샌드박스 — 적절. 내용이 자산 ID뿐이라 암호화 불요(민감도 낮음).
- SQL: Drift 타입 안전 쿼리만 — 인젝션 표면 없음. `pub outdated`: 직접 의존성 전부 최신.

### B-3. [LOW] 앨범명 사용자 입력 → Android RELATIVE_PATH 무검증
- **근거**: `album_picker_sheet.dart:46`(trim만) → `photo_manager_photo_service.dart:281,303-307` `'Pictures/$name'` 그대로 MediaStore RELATIVE_PATH로 사용.
- **영향**: 이름에 `/` 포함 시 중첩 폴더 생성(평면 구조 결정과 충돌), `..`·예약문자는 MediaStore가 거부해 이동 실패 → failed 처리(큐 유지)라 **유실·탈출은 없음**. 샌드박스 밖 traversal은 MediaStore가 차단하므로 보안 영향은 낮고 UX/일관성 문제.
- **권고**: 생성 시 `[/\\:*?"<>|]` 필터 + 길이 제한. feature-builder 소관, 소규모.

### B-4. [MEDIUM·PLAUSIBLE, 실기기 검증 필수] Android id 재발급 best-effort 매칭 오기록 → 간접 유실 경로
- **근거**: `_resolveAndroidFinalIds`(`photo_manager_photo_service.dart:233-261`) — 이동 후 원래 id가 죽으면 대상 앨범 최신분에서 **순서 기반 추정 매칭**(258-260). 매칭이 어긋나면 (a) 엉뚱한 자산 id가 처리 기록됨 → 그 자산이 정리된 적 없이 큐에서 영구 제외(**사용자 인지 없는 간접 유실**), (b) 실제 이동된 자산은 새 id로 재등장. 보조 매칭 `_resolveAndroidPathByName`(322-331)은 **폴더 표시명만으로** 매칭 → 동명 폴더(예: DCIM/여행 vs Pictures/여행) 오선택 가능.
- **판정**: integrator 한계 A "최고위험" 자체 보고와 일치 — 코드 재확인 결과 사실. 정적으로는 더 못 좁힘.
- **권고**: 릴리스 전 실기기(최소 삼성 One UI + Pixel)에서 (1) 이동 후 id 유지 여부, (2) 재발급 시 매칭 정확도 검증. 오매칭 관찰 시 파일 경로/생성일 보조키 매칭으로 강화.

### B-5. [INFO] commit 실패·부분성공 데이터 유실 경로 — 설계대로 방어됨
- stage ≠ 기록(`sort_controller.dart` commit 전 DB 접근 없음), 성공분만 `markProcessed`(194-199), 실패·예외 시 예약 큐 유지(`photo_manager_photo_service.dart:162,207-210,223-227` — 성공분만 `_pending.remove`), commit 중 앱 강제종료 시에도 "반영됐는데 미기록"이면 다음 큐에서 재등장할 뿐(iOS 태깅 중복 무해, Android는 이미 이동된 자산이 재등장 — 재배정하면 동일 폴더 재이동으로 수렴). datamodel §7.2 불변식 3종 모두 코드로 성립. `markProcessed`는 idempotent(`processed_dao.dart:38` insertOnConflictUpdate).

---

## 릴리스 판정: **보류**

| 사유 | 축 |
|------|----|
| ① MVP In Scope 3건 미구현 — 특히 **F-12(P0) 분석**: North Star/D7 측정 불능. F-09/F-10 부재로 과금 모델 자체가 없음 | A-1 |
| ② **F-02 알림 시각 오프셋 결함**(UTC 스케줄) — 습관 루프 트리거 파손 | A-2 |
| ③ 핵심 여정(iOS 새 앨범 commit)·Android id 재발급이 **실기기 0회 검증** 상태 — 사진을 실제로 옮기는 앱을 정적 분석만으로 출시 불가 | A-3, B-4 |

보안·프라이버시 축은 **통과**(핵심 약속 "폰 밖 미전송" 코드로 성립, 유출 경로·시크릿·과다 권한 없음). 코어 루프(stage→commit→성공분 기록, ID 집합 판별, 건너뛰기, streak)는 설계 불변식을 정확히 지켜 견고함. 위 ①~③ 해소(또는 ①은 사용자 승인 하 PRD 개정) + 실기기 스모크 후 **조건부 통과**로 상향 가능.

### 출시 전 필수 수정 Top 3
1. **[platform-integrator] 알림 타임존 수정**(A-2): `flutter_timezone` 도입 → `tz.setLocalLocation()`. 즉효·저비용·습관 루프 직결.
2. **[platform-integrator] iOS 빈 앨범 commit 경로 수정**(A-3): `containsEmptyAlbum: true`(또는 AssetPathEntity.fromId) + **iOS/Android 실기기 스모크**(새 앨범→배정→commit→재큐 제외, id 재발급 매칭 B-4 동시 검증).
3. **[오케스트레이터→사용자 결정] F-12(P0) 분석 최소 구현 or PRD 스코프 개정 승인**(A-1): 현재 상태는 "PRD v1.0 확정본 대비 미완"이므로 코드 수정이든 문서 개정이든 어느 한쪽의 명시적 확정 필요. (동반: A-4 presentLimited/openSetting 추가로 D2 실효화.)
