# 03 · QA 리포트 (qa-verifier — 경계면 교차검증)

> 대상: **feature-builder**, **platform-integrator**, **spec-architect**.
> 방법: `lib/core/`(제공자) ↔ `lib/features/`(소비자) 동시 대조 + 핵심 불변식 코드 확인 + `flutter analyze`/`flutter test` 실행.
> 날짜: 2026-07-03. 실기기 없음 → 기기 의존 항목은 정적 대조로 폴백(명시).

---

## 0. 품질 게이트 결과 (직접 실행)

| 게이트 | 결과 |
|--------|------|
| `flutter analyze` | **No issues found!** (exit 0, 7.2s) |
| `flutter test` | **All tests passed!** (1/1, 온보딩 스모크) — exit 0 |

> 한계: 자동 테스트는 온보딩 위젯 스모크 1건뿐. stage→commit→markProcessed·중복방지 불변식은 **단위 테스트 미작성** → 아래는 정적 코드 대조 기반. `AppDatabase.forTesting(NativeDatabase.memory())` + fake PhotoService 로 계약 테스트 추가 권장(integrator §E 명시).

---

## 1. 경계면 shape 대조 (core 시그니처 ↔ features 호출)

**결과: 공개 인터페이스 shape 불일치 0건.** providers.dart 5종·PhotoService 9메서드·ProcessedRepository 5메서드·NotificationService 4메서드 모두 features 호출부와 인자/비동기/반환 필드가 일치. 세부 대조:

| 계약(core) | 소비(features) | 판정 |
|---|---|---|
| `ensurePermission()→PhotoPermission{granted,limited,denied}` | onboarding/home/sort 에서 3값 switch | 일치 |
| `loadUnclassifiedQueue()→List<AssetRef>` | home 개수·sort 큐·onboarding 개수 | 일치 |
| `stage/unstage/pendingAssignments()` | sort_controller assign/skip/undo | 일치 |
| `commitAssignments()→BatchAssignResult{succeeded[AssignedAsset.finalAssetId,albumId,mediaType], failed, cancelled}` | sort_controller.commit `result.succeeded`/`.failed.length`/`.cancelled` | 일치 |
| `markProcessed({assetId,albumId,mediaType})` | commit 성공 루프 named args | 일치 |
| `createAlbum(name)→AlbumRef` / `listAlbums()` / `thumbnail(id,{size})` | album_picker / asset_thumbnail | 일치 |
| `streakDays()→int` | home/done | 일치 |

플랫폼 타입(photo_manager) features 노출 없음 확인(전부 순수 DTO). 계약 준수 양호.

---

## 2. 핵심 불변식 검증 (코드 확인)

| 불변식 | 판정 | 근거(파일:라인) |
|--------|------|------|
| 미분류 판별 = **처리 ID 집합** (OS 앨범 소속 아님) | **PASS** | `photo_manager_photo_service.dart:60,73` — `processedIdSet()` 로드 후 `!processedIds.contains(a.id)`. `onlyAll` 전체 스캔(§3.2 시간 프리필터 의도적 미적용, 한계 D). |
| stage → commit → **성공분(finalAssetId)만** markProcessed | **PASS** | `sort_controller.dart:185-193` — `result.succeeded` 순회하며 `s.finalAssetId` 로만 기록. commit 은 DB 미기록(`commitAssignments` 은 `_pending` 성공분만 제거). |
| 실패/취소분 큐 유지 | **PASS** | `photo_manager_photo_service.dart:162,223` 성공분만 `_pending.remove`; 실패는 `failed` 로만. |
| stage ≠ 처리(예약분 재로드 시 잔존) | **PASS** | `loadUnclassifiedQueue` 는 processedIds 만 제외, pending 미제외 → 스와이프만 하고 commit 안 하면 다음 큐 재등장(§3.4). |
| 배정 자산 다음 로드에서 제외 | **PASS (Android 기기위험)** | markProcessed→processedIdSet 제외. 단 Android id 재발급 시 `_resolveAndroidFinalIds` best-effort 매칭 오류 시 재등장 가능(한계 A, 기기 검증 필요). |
| iOS 원본 타임라인 잔존해도 재등장 없음 | **PASS** | `_commitDarwin` finalAssetId=불변 id → processedIds 에 포함. |
| 광고가 정리 흐름·사진 사이에 없음 | **PASS** | grep 결과 광고 코드 0. `done_screen.dart:117` TODO 주석만(축하 뒤 슬롯). |
| 원본 바이트 앱 외부 유출 경로 없음 | **PASS** | grep(http/dio/upload/socket/share/writeAsBytes/firebase/ads) 무결. thumbnail 은 `Image.memory` 로 메모리만. DB 는 id·참조만 저장. |

---

## 3. feature-builder 보고 불일치 4건 검증

### C-1. 설정 저장소 계약 없음 → shared_preferences 추가 — **정상(Info)**
- core 에 온보딩/알림 설정 계약 없음 확인(integrator §B). features 레이어 `AppSettings`(settings_store.dart)로 캡슐화, core 침범 없음. main.dart 에서 override 주입 정상.
- **판정: 실제 문제 아님.** 수용. 향후 필요 시 core 승격 검토(선택).

### C-2. 설정 딥링크/limited 재선택 수단 미제공 → ensurePermission 재호출 대체 — **실제 문제 (MEDIUM)**
- 경계면: `permission_help.dart:56`·`home_screen.dart:92` 가 `ensurePermission()` 재호출로 "전체 접근" 유도.
- **근거**: PhotoService 계약에 `openSystemSettings()`/`presentLimited()` 없음. iOS 에서 상태가 이미 `limited` 또는 영구 `denied` 면 `requestPermissionExtend()` 는 시스템 다이얼로그를 다시 띄우지 않고 같은 상태를 반환 → **버튼이 무반응**. D2(제한→전체 유도)는 사용자 승인 확정 결정인데 iOS 에서 실효성 없음.
- **수정 대상: platform-integrator.** photo_manager 가 이미 `PhotoManager.presentLimited()`(iOS14+ 재선택)·`PhotoManager.openSetting()`(설정 앱) 제공 → **신규 deps 없이** PhotoService 에 `presentLimited()`/`openSystemSettings()` 2메서드 추가 권장. UI 는 재호출 대신 이 경로 사용.

### C-3. 영상 인라인 재생 플러그인 없음 → 간이 썸네일 프리뷰 — **경미 (LOW)**
- `video_preview_sheet.dart` 는 큰 썸네일+재생아이콘 다이얼로그. F-08 "가벼운 인라인 미리보기" 를 정적 프리뷰로 대체.
- **판정: MVP 수용 가능한 다운그레이드.** 실제 재생 필요 시 `video_player` 의존성 선행. 차단 아님.

### C-4. Android commit 취소 vs 실패 구분 불가 — **실제 문제 (MEDIUM)**
- 경계면: `photo_manager_photo_service.dart:203-211` — `moveAssetsToPath`→`bool`, `!ok` 이면 전량 `failed`, **`cancelled` 는 항상 false**(생성자 기본값, Android 경로에서 set 안 함).
- 소비: `sort_screen.dart:34` `outcome.cancelled` 분기는 **Android 에서 사실상 죽은 코드**. 사용자가 동의창 취소 시 `failed`>0 로 처리되어 정리 화면 유지가 아니라 **/done 으로 넘어가 "N장 반영 못했어요"** 로 오안내(예약 큐는 유지되므로 데이터 유실은 아님).
- **수정 대상: platform-integrator(1차)·feature-builder(2차).** 취소를 `cancelled=true` 로 구분하려면 실기기에서 `moveAssetsToPath` 취소 시 반환값/예외 관찰 필요(한계 B). 정적으로는 구분 불가 → **기기 검증 필수**.

---

## 4. 추가 발견 이슈 (심각도순)

### [HIGH] I-1. `sortControllerProvider` 미(autoDispose)·미리로드 → **두 번째 정리 진입 시 스테일 큐/무한 스피너**
- 경계면: `sort_controller.dart:218` `NotifierProvider`(autoDispose 아님) + 어디서도 `invalidate(sortControllerProvider)`/재 `load()` 호출 없음(grep 확인: home·done·sort 모두 `homeDataProvider` 만 invalidate).
- **재현(정적 추론)**:
  1. 최초 `/sort` 진입 → `build()`→`load()` 1회 실행(정상).
  2. 스와이프·commit 완료 → `context.go('/done')` → `/home`.
  3. 홈에서 "정리 시작"(`home_screen.dart:157` `push('/sort')`) **재진입**.
  4. 그러나 Riverpod 앱스코프 프로바이더라 `SortController` 인스턴스·`state` 가 **유지됨** → `build()`/`load()` **재실행 안 됨**. state 는 직전 세션 그대로(index=이전 큐 끝, current==null).
  5. `sort_screen.dart:120` `status==ready && current==null` → **`CircularProgressIndicator` 무한 표시**. `ref.listen`(81) 은 상태 변화가 없어 `_finish` 자동트리거 안 됨 → **정리 화면 진입 불가**.
  - 큐 소진 전 수동 commit 후 재진입 시엔 **이미 처리한(옮긴) 사진이 스테일 큐에 다시 표시**됨(큐가 load 시점 캡처 후 갱신 안 됨).
- **영향**: 매일 재사용 핵심 루프(어제 정리→오늘 다시 정리) 파손. 앱의 심장 화면.
- **수정 대상: feature-builder.** 택1 — (a) `NotifierProvider.autoDispose` 로 전환(재진입 시 build→load 재실행; pending 은 PhotoService 싱글턴에 있어 유실 없음), 또는 (b) `/done`→홈 이탈 시 `ref.invalidate(sortControllerProvider)`, 또는 (c) `SortScreen` 진입마다 `load()` 호출. **(a) 권장.** 전환 후 재진입 스모크 테스트 추가 권장.
- 한계: 실기기/위젯테스트 미실행. **정적 대조 기반(Riverpod 3 수동 프로바이더는 kept-alive 기본)** — CONFIRMED 로 판단하나 위젯 테스트로 재확인 권장.

### [LOW] I-2. `AlbumRef.coverAssetId` 영구 미설정 → 앨범 커버 항상 플레이스홀더
- `createAlbum`(photo_manager_photo_service.dart:266)·`setSystemRef` 어디서도 coverAssetId 채우지 않음. album_dao 에 커버 갱신 경로 없음.
- 소비: `album_picker_sheet.dart:175` `album.coverAssetId != null` 분기가 항상 false → 폴더 아이콘만. 기능 미완(버그 아님).
- **수정 대상: platform-integrator/feature-builder(선택).** commit 성공 시 대상 앨범 대표 자산으로 coverAssetId 갱신 로직 추가 시 UX 향상.

### [INFO] I-3. 기기 의존 미검증 항목(integrator 한계 A/B/C/F 승계)
- Android id 재발급 매칭 정확도(A)·동의창 취소 반환(B)·알림 로컬 타임존(C, 현재 inexact 라 영향 제한)·백업복원 후 id(F). **정적 분석만 통과** — 실기기 스모크 필수. core 코드상 처리 로직은 존재(정적 PASS).

---

## 5. 다음 수정 우선순위 (1~3)

1. **[feature-builder · HIGH]** I-1: `sortControllerProvider` autoDispose 전환(또는 재진입 시 reload). 정리 화면 2회차 진입 파손 — 최우선.
2. **[platform-integrator · MEDIUM]** C-2: PhotoService 에 `presentLimited()`/`openSystemSettings()` 추가(photo_manager 내장, 신규 deps 불필요). iOS limited→전체(D2) 실효성 확보.
3. **[platform-integrator · MEDIUM]** C-4: Android 동의창 취소를 `cancelled=true` 로 구분(실기기에서 `moveAssetsToPath` 취소 반환 관찰 후). UI 오안내 제거.

> 상충/출처 병기: I-1 는 정적 추론(실행 미검증)이며 Riverpod 프로바이더 수명 기준. C-2/C-4 는 builder(§C-2/§C-4)·integrator(한계 B/E) 양측 보고와 일치 — 코드로 재확인 완료.

---

## 6. 실기기 스모크 발견 (2026-07-06, 삼성 S22 Ultra SM-S908N · Android 15 · 16k장)

첫 실기기 commit 흐름(배정→동의→이동) 관찰 결과. 파일시스템·MediaStore 직접 대조로 검증.

### 해소/검증된 것
- **[해소] S-1. 정리 화면 백지화** — 테마 FilledButton `Size.fromHeight(56)`(무한 최소너비)이 Row 컨텍스트에서 레이아웃 예외 유발. 테마 `Size(64,56)` + 풀너비 옵트인 9곳으로 수정(`305984a`). Impeller/16k장은 무관.
- **[검증] 핵심 실반영** — 배정 커밋 후 `/sdcard/Pictures/<앨범>/` 파일 실이동 + MediaStore `relative_path` 정상 갱신 확인(adb 대조). **id 재발급 실관찰**(신규 _id 47~59) → FIX-2b 매칭이 실기기에서 성공 동작, 중복방지(재진입 시 미노출)도 확인.
- **[해소] S-3. 홈 카운트 무갱신처럼 보임** — 재스캔(수십 초) 동안 이전 값 무표시 노출(Riverpod skipLoadingOnRefresh). 홈 상단 LinearProgressIndicator 로 갱신 중 표시.
- **[해소] S-4. 온보딩 알림 확인 후 무반응** — 16k 스캔을 기다린 후 스텝 전환하던 것을 즉시 전환 + "세는 중" 스피너로 수정(`305984a`).

### 신규 오픈 이슈
- **[MEDIUM] C-5. 동의창이 앨범(폴더 그룹)당 1회씩 연발** — 현 구현은 `moveAssetsToPath` 를 앨범 그룹별 호출 → 앨범 N개 배정 시 시스템 동의창 N회. 소유자 실사용 소감: "대량 정리 시 UX 치명적". 개선 방향: **전체 pending 자산의 쓰기 권한을 단일 batch write request 로 선획득** 후 앨범별 이동을 무동의 진행. photo_manager 가 raw `createWriteRequest` 를 노출하는지 조사 필요(미노출 시 플랫폼 채널 검토) — platform-integrator 배정.
- ~~**[INFO] S-2. 삼성 갤러리 앱에서 새 앨범 미표시(관찰)**~~ — **해소(2026-07-06)**. 파일·MediaStore 정상이었고, 원인은 삼성 갤러리의 앨범 탭 기본 보기가 일부만 노출하는 것 — **"모든 앨범" 보기로 전환하면 정상 표시**(소유자 확인). 앱 결함 아님. 참고: 온보딩/완료 화면 문구에 "갤러리의 '모든 앨범'에서 확인" 힌트를 넣을지는 UI/UX 개선 세션에서 판단.

---

## §7. 2026-07-06 QA + UI 개편 재검증 (qa-verifier)

> 검증 대상: (1) 커밋 `0984709`(C-5 단일 batch 동의 채널 + C-4 취소/실패 구분 + 16k 스캔 캐시, 실기기 3건 PASS), (2) 미커밋 working tree(feature-builder UI/UX 개편, 12파일 +1012/-284, 노트 §J).
> 방법: 품질 게이트 실제 실행 + 경계면 교차 대조(features ↔ core 공개 계약) + 핵심 불변식 재확인 + 회귀 함정 grep + 다크 테마 코드 검토.

### 7.1 품질 게이트 (실제 실행)
| 게이트 | 결과 | 근거 |
|--------|------|------|
| `flutter analyze` | **PASS** — No issues found! (ran in 3.4s) | exit 0 |
| `flutter test` | **PASS — 44/44** (All tests passed!) | `sort_controller_reentry_test`(I-1 회귀) 포함 전원 통과 |

두 게이트 모두 노트 기대치(클린 + 44/44)와 일치.

### 7.2 경계면 shape 교차 대조 (features ↔ core 공개 계약) — 모두 일치
- **BatchAssignResult.cancelled → CommitOutcome.cancelled → UI**: `sort_controller.commit()`(L204~227)이 `result.cancelled` 를 `CommitOutcome.cancelled` 로 정확히 전파. `sort_screen._finish()`(L38~42)의 cancelled 분기가 UI 개편 후에도 **보존**됨 → "동의가 필요해요, 예약은 그대로" 스낵 + 정리 화면 유지, `/done` 미전이. C-4 실기기 PASS와 코드 정합.
- **succeeded → markProcessed(성공분 한정)**: commit L206~215 이 `result.succeeded` 만 순회하며 `s.finalAssetId` 로 markProcessed. 실패/취소분은 pending 큐 유지. **stage≠처리 불변식 유지**.
- **ProcessedRepository.processedCount() 신규**: core 에 추가된 계약을 스캔 캐시 지문(`photo_manager_photo_service.dart` L97·594~618)이 정확히 소비. features 는 이 메서드를 직접 호출하지 않음(홈은 여전히 `loadUnclassifiedQueue().length`) — 계약 최소화 유지, 편차 없음.
- **PhotoService 9+메서드**: UI 개편은 `lib/core` 무수정(diff stat 확인 — core 파일 0건). features 는 abstract 타입만 소비, photo_manager 타입 노출 0. `sort_controller`/`CommitOutcome`/`providers` 도 미변경(J-4 주장과 diff 일치).

### 7.3 핵심 불변식 재확인 — 모두 유지
- **(a) 광고 위치**: `CompletionAdSlot` 은 `done_screen.dart:173` — streak 카드(L120~169) **아래**, "홈으로" 버튼(L177) **위**. UI 개편에서 밀리지 않음(원칙 4). **정리 흐름 내 광고 참조 0**: `lib/features/sort/` grep 결과 실제 광고 위젯/`AdGate`/`CompletionAdSlot`/banner 참조 **없음**(매칭은 전부 `read`·`Padding`·`loading` 등 부분문자열). 구조적으로 "정리 흐름 중 삽입" 불가.
- **(b) 미분류 판별 = 처리 ID 기준**: 이번 세션 core 판별 로직 무변경. 스캔 캐시 지문은 `processedCount`(SQL COUNT) 파생이며 OS 앨범 소속이 아님. iOS 원본 타임라인 잔존과 무관하게 처리 ID 집합으로 판별 유지.
- **(c) 프라이버시**: 신규 `MediaMoveHandler.kt` 는 MediaStore `_id`→`Uri`→`RELATIVE_PATH` 갱신만 수행. **원본 바이트 read/InputStream/File copy/http/upload 경로 0건**(grep 확인). 명시 주석 L29 "자산 참조(_id)만 다루며 원본 바이트를 읽거나 앱 밖으로 내보내지 않는다"와 코드 일치. 신규 유출 경로 없음.
- **(d) 스캔 캐시 무효화 — "큐는 정확" 유지**: 지문 = `(total 네이티브 COUNT, processedCount, lastProcessedMicros)`. 신규 자산→total 변화, commit→processedCount·lastProcessedAt 변화 → 캐시 미스→정확 재스캔. commit 성공 시 `_queueCache=null` 명시 무효화(L181) 병행. 관측 가능한 변화가 있으면 항상 실제 로드. 총개수 동일 외부 삭제+추가(commit 없음) 병적 케이스만 근사이며 다음 카운트 변화에서 자가치유 — 문서화된 허용 범위("카운트는 근사").

### 7.4 회귀 함정 grep — 모두 회피 확인
- **`Size.fromHeight` 재유입(305984a 회귀)**: FilledButton `minimumSize` 에 **미사용**. 발견된 2건은 (1) `theme.dart:110` 금지 경고 주석, (2) `sort_screen.dart:129` `PreferredSize(preferredSize: Size.fromHeight(3))` = AppBar 하단 LinearProgressIndicator 높이 지정(정당한 용법, 버튼 아님). 테마 버튼 `minimumSize` 는 `Size(64,56)`/`Size(64,52)` 고정폭 유지. 풀너비는 콜사이트 `SizedBox(width: double.infinity)` 옵트인(done_screen:177 등).
- **autoDispose 재진입(I-1)**: `sort_controller_reentry_test`(테스트 +42) 통과 — 재진입마다 새 인스턴스 load() 재실행. UI 개편이 이 로직 미변경.

### 7.5 다크 테마 대비 검토 — 신규 오픈 이슈 (아래 §7.6 참조)
- **홈 히어로/streak 카드**: `primaryContainer`/`tertiaryContainer` 배경에 `onPrimaryContainer` 전경 = 올바른 M3 페어링. 라이트/다크 모두 안전.
- **정리 하단 패널**: `colorScheme.surface`/`onSurfaceVariant` 테마 파생 — 다크 자동 적응. 정리 캔버스 `kSortCanvas`(항상 다크)의 흰색 텍스트도 테마 무관하게 정합.
- **문제 발견**: `Colors.white` 전경을 **다크에서 밝아지는** `scheme.primary`(#FFB68A)/`scheme.tertiary`(#D9D08E) 배경 위에 사용한 3개 지점 → 다크 모드 한정 대비 저하(§7.6 D-1).

### 7.6 신규 오픈 이슈

- **[MEDIUM] D-1. 다크 테마 — 흰색 전경 on 밝은 primary/tertiary 배경(대비 저하, 다크 한정)**
  - **경계면**: 컴포넌트 색상 ↔ ColorScheme(다크). 다크 `primary=#FFB68A`, `tertiary=#D9D08E` 는 **밝은 톤**이라 `Colors.white` 전경과 대비 ~1.7:1(WCAG 그래픽 3:1 미달). 라이트 테마는 `primary=#B85A22`(진함)이라 흰색 대비 ~5.3:1 정상 — **다크에서만** 발생.
  - **지점 3곳**:
    1. `done_screen.dart:78~79` — 완료 체크마크 `Icon(Icons.check_rounded, size:76, color: Colors.white)` on `primary→tertiary` 그라데이션 원. 다크에서 성취 순간(원칙 3·iOS 성취감 보완)의 핵심 마크가 흐려짐.
    2. `sort_screen.dart:381` — `_RoundAction` prominent(="앨범 배정" 버튼) `fg = Colors.white` on `bg = scheme.primary`. 정리 화면 최우선 CTA(원칙 2 "탭 1회") 아이콘 대비 저하. 채운 원 자체는 보이므로 탭은 가능.
    3. `swipeable_card.dart:162·166` — `_HintBadge` "배정"(bg=primary)·"최근 앨범"(bg=tertiary) 배지의 흰색 아이콘/라벨. 스와이프 중 드래그 힌트라 일시적이나 "배정"이 최다 사용 방향.
  - **재현**: 시스템 다크 모드로 앱 실행 → (1) 정리 완료 화면, (2) 정리 화면 배정 버튼, (3) 우측 드래그 힌트 관찰. J-5 자체 기록상 완료 화면은 실기기 미진입(코드리뷰 대체), 스와이프/칩 탭 미실행이라 이 경로들이 육안 검증 사각.
  - **수정 제안**: `Colors.white` → `scheme.onPrimary`(다크=#551D00 진함) / `scheme.onTertiary`. 그라데이션 원(done)은 `onPrimary` 로 통일. 각 1줄. 라이트 테마 영향 없음(onPrimary 라이트=white).
  - **심각도 근거**: 기능·레이아웃 정상, 배경 원/pill 은 보임 — **비차단**. 다만 개편이 명시 강화 목표로 삼은 원칙 2·3 표면이고 다크 테마를 신규 추가한 세션이라 마감 품질 차원에서 커밋 전 수정 권장.

### 7.7 커밋 가능 여부 판정
- **커밋 `0984709`(이미 커밋)**: 게이트 클린 + 실기기 3건 PASS + 경계·불변식(C-4/C-5/캐시/프라이버시) 전부 정합. **문제 없음.**
- **미커밋 working tree(UI 개편)**: 게이트 44/44 + analyze 클린, 경계면·핵심 불변식(광고 위치·판별 기준·프라이버시·캐시) 전원 유지, 회귀 함정(Size.fromHeight·autoDispose) 회피 확인. **커밋 가능**. 단 **D-1(MEDIUM, 다크 대비) 커밋 전 수정 권장** — `Colors.white`→`scheme.onPrimary/onTertiary` 3지점 1줄씩, 비차단이나 트리비얼 픽스. HIGH 이슈 없음.

---

## §8. D5 단건 삭제 검증 (2026-07-07, qa-verifier)

> 대상: 커밋 `74e3848`(core: deleteAsset·supportsDeletion·DeletionLogs v2·streak 합집합) + 미커밋 working tree(SortController.deleteCurrent, 삭제 버튼, 교육 시트, 완료 화면 총계/분해, 분석). SSOT = `06_architect_delete.md §0`(§1~8 폐기·기록보존) + §9, 계약 = `02_integrator_notes.md §G`, 구현 = `02_builder_notes.md §K`.
> 방법: 게이트 직접 실행 + 경계면 교차대조(core 반환 ↔ 컨트롤러 ↔ UI) + 불변식 정적 검증. 실기기 미연결 → 플랫폼 채널 경로는 소스 대조로 폴백(§8.6에 실기기 필수 목록 명시).

### 8.0 품질 게이트 (직접 실행)
| 게이트 | 결과 |
|--------|------|
| `flutter analyze` | **No issues found!** (3.3s) |
| `flutter test` | **All tests passed! — 77/77** (delete_ui_test 14건 포함) |

기대치(77/77)와 일치. 게이트 클린.

### 8.1 불변식 코드 검증 (DEL-1'~8)
| ID | 판정 | 근거(파일:라인) |
|----|------|-----------------|
| DEL-1' (성공 전 원본·큐 보존) | **PASS** | `sort_controller.dart:203-214` — `deleteAsset` 반환 `false` 면 `return false` 로 **상태 무변경**(index·deletedCount·카드 유지). `applyDeletionResult`(`photo_manager_photo_service.dart:248-255`)도 `ok` 일 때만 `_pending`·캐시 정리. OS 동의창 미완료(취소) = 빈 반환 = 보존. |
| DEL-2' (동의창 없는 삭제 경로 부재 / API<30 2중 방어) | **PASS** | 1차: UI `showDelete: supportsDeletion`(`sort_screen.dart:196`, Android=SDK≥30). 2차: `deleteAsset`(`:218-225`)가 Android SDK<30·기타 플랫폼이면 **플랫폼 호출 없이 즉시 false**. 실삭제는 `deleteWithIds`(`:232`)=API30+ `createDeleteRequest`(OS 동의창) 경로만 도달. `supportsDeletion` 미조회 기본값 false(안전). |
| DEL-3'/4 (ProcessedAsset 미기록·markProcessed 미호출) | **PASS** | `deleteCurrent`(`:199-215`)에 `markProcessed` 호출 없음. `logDeletion()`+analytics+index++ 만. streak 원천 union(`processed_repository.dart:98-103`)이 processed 테이블 무오염 확인. |
| DEL-6' (pending 배정 독립·삭제 성공 시 pending 제거) | **PASS** | `applyDeletionResult`(`:250-252`) 성공 시 `_pending.remove(assetId)` — 방어적 제거로 "삭제된 자산이 배정 커밋에 잔존" 원천 차단. |
| DEL-7' (삭제 1건=동의창 1회, commit 동의창=이동만) | **PASS(소스)** | `deleteAsset`가 `deleteWithIds([단일 id])`(`:232`) → createDeleteRequest 1회. commit 경로(`_commitAndroid` moveToAlbums)와 완전 독립. 동의창 실횟수는 실기기 대기(§8.6). |
| DEL-8 (streak = 처리일 ∪ 삭제일) | **PASS** | `streakDays`(`processed_repository.dart:98-103`) = `computeStreak([...processed, ...deleted])`. `logDeletion`(`deletion_dao.dart:16-20`)이 삭제 성공마다 `deletedAt` append → 삭제만 한 날도 인정. done_screen streak future가 이 union 소비. |

### 8.2 경계면 교차대조
- **features → §G 계약만 소비 / photo_manager 타입 누출 0**: `lib/features/` 전체에서 `photo_manager`·`AssetEntity`·`PhotoManager` import **0건**(grep 확인). UI는 `deleteAsset`(bool)·`supportsDeletion`(bool getter)만 사용. **PASS.**
- **deletedCount 전파 CommitOutcome→done_screen**: `SortState.deletedCount`(deleteCurrent에서 ++) → `commit()`가 3경로(pending-empty `:249`, 정상 `:287`, catch `:310`) 모두 `CommitOutcome.deletedCount`에 실음 → `done_screen._totalLine`/분해(`done_screen.dart:42-50,109`)가 소비. **정확 전파.** PASS.
- **isNoop 편입 → 삭제만 세션 완료 전이**: `isNoop`(`:99-100`)에 `deletedCount==0` 편입. pending-empty & deletedCount>0 → isNoop=false → `_finish`가 `context.go('/done')`(`sort_screen.dart:60`). **삭제만 한 세션도 완료 화면 도달.** 단 진입 트리거는 큐 소진 자동 commit(정리 버튼은 pendingCount>0 게이트라 삭제만 세션에선 비활성) — 설계 정합. PASS.
- **sort_session_complete(deleted_count) 발화**: pending-empty branch(`:251-258`)에서 `!isNoop` 시 `logSortSessionComplete(processedCount:0, remaining:초기큐-deleted, deletedCount:)`. 정상 branch(`:292-301`)도 deleted 합산. 상수 `AnalyticsParams.deletedCount='deleted_count'` 단일출처, Local·Firebase 양 구현 매핑(`firebase_analytics_service.dart:100,111`) 확인. PASS.

### 8.3 기존 불변식 회귀
| 항목 | 판정 | 근거 |
|------|------|------|
| 광고 위치(CompletionAdSlot 안 밀림) | **PASS** | `done_screen.dart:197` streak 카드 **아래** 유지. sort_screen은 CompletionAdSlot/AdGate 미참조 → 정리 흐름 내 광고 0(구조적 보장). |
| 미분류=처리 ID 판별 | **PASS** | `loadUnclassifiedQueue`(`:128,141`) `processedIdSet` 대조 유지. 삭제는 processed 미기록이나 Android=MediaStore 소멸·iOS=최근삭제됨 제외로 큐 미재등장(소스), `applyDeletionResult`가 `_queueCache=null`(`:253`)로 명시 무효화 + total 감소로 지문 자가무효화 이중. |
| 프라이버시 | **PASS** | `DeletionLogs` 스키마(`app_database.dart:46-52`)에 자산 id **없음**(deletedAt만). `asset_deleted` 이벤트 속성 없음(`logAssetDeleted`). `deleteAsset`는 id 리스트만 전달(원본 바이트 미접근). "휴지통" 문자열은 금지 주석 1곳뿐(사용자 노출 0). |
| Size.fromHeight 회귀 | **PASS** | 교육 시트·완료 화면 버튼 전부 `SizedBox(width:double.infinity)` 옵트인(`delete_intro_sheet.dart:74,86`). 버튼 minimumSize에 Size.fromHeight 미사용(AppBar bottom PreferredSize의 Size.fromHeight는 무관·정상). |
| autoDispose 재진입 | **PASS** | `deletedCount`는 `SortState` 필드 → `build()` 재실행 시 0으로 리셋. 신규 pub 의존성 0. |

### 8.4 판단 2건 타당성 (§K 기록)
- **교육 시트 [취소] 시 플래그 미설정(재노출)** — **타당.** `_onDelete`(`sort_screen.dart:95-98`)는 `proceed==true` 일 때만 `setSeenDeleteIntro()`. 교육의 목적은 "실제 삭제 진행 전 이해 확인"이므로, 취소=미진행 시 다음 시도에 재노출이 옳다. D5-6·§0.2와 정합. (부수: [삭제] 진행 후 OS 동의창을 취소해도 플래그는 서 있음 — 이미 교육 확인을 거쳤으므로 의도된 동작.)
- **recordFirstSortDateIfAbsent가 삭제만 세션에도 발동** — **타당·정합.** `done_screen.dart:35`가 `successCount>0 || deletedCount>0` 로 확장. DEL-8이 "삭제만 한 날도 정리 세션으로 인정"하므로, 완료 화면에 도달한 삭제만 세션은 진짜 "첫 정리"다. D3(첫 정리일+7일 광고 게이트)의 의미와 일관 — 습관이 붙은 첫 실사용일부터 광고 시계 시작. 상충 없음.

### 8.5 UI 디테일
- **다크 라이트박스 위 error색 삭제 버튼 대비**: `_RoundAction` subdued(`sort_screen.dart:434-436`)가 `error.withValues(alpha:0.10)` 고스트 배경 + `error` 전경. 라이트박스(`kSortCanvas`=웜 차콜) 위에서 error(밝은 산호빛 계열)는 대비 확보 예상이나 **정확 대비값은 실기기 육안 필요**(§8.6). §7.6 D-1(다크 흰색 전경) 계열 주의는 삭제 버튼엔 비해당(전경이 error색). 
- **교육 시트 양 테마**: `delete_intro_sheet.dart` 전부 `Theme.of(context).colorScheme` 파생 → 양 테마 자동. 하드코딩 색 없음. PASS.
- **"휴지통" 표현 부재**: `lib/` grep → 금지 주석 1곳 외 사용자 문구 0. PASS.

### 8.6 실기기 필수 확인 목록 (호스트 미검증 → F-14d' 인계)
1. **Android API30+**: 삭제 버튼 탭 → OS 삭제 동의창 **1회** → 승인 시 영구삭제 → 재스캔 시 큐 **미재등장**(DEL-3'). 삭제+배정 혼합 세션 동의창 수 = 삭제 탭수 + 배정 commit 1.
2. **iOS**: `deleteWithIds` 후 "최근 삭제됨" 이동 + onlyAll 큐 미재등장(DEL-3', 소스상 PASS) / 30일 내 복원 시 재등장(DEL-5' 재정리 기회).
3. **Android API<30 기기**: 삭제 버튼 미노출(supportsDeletion=false) 육안 확인(minSdk=24라 실재 가능 레인지).
4. **다크/라이트 양 테마** 정리 화면에서 삭제 버튼·교육 시트 대비 육안.
5. 교육 시트 [취소]→재노출, [삭제]→무마찰 재사용 실기 흐름.

### 8.7 커밋 가능 여부 판정
- **커밋 `74e3848`(core, 이미 커밋)**: 게이트 클린, DEL-3'/4/8·프라이버시·스키마 v2 마이그레이션(`onUpgrade` createTable) 정합. **문제 없음.**
- **미커밋 working tree(컨트롤러·UI·완료·분석)**: analyze 클린 + test 77/77, 경계면(계약 소비·타입 누출 0·deletedCount 전파·이벤트 발화) 전원 정합, 불변식 DEL-1'~8 소스상 PASS, 기존 불변식(광고 위치·판별 기준·프라이버시·Size.fromHeight·autoDispose) 회귀 0. 판단 2건 타당. **커밋 가능.** HIGH/블로킹 이슈 없음. 잔여는 §8.6 실기기 항목(플랫폼 채널 경로 특성상 호스트 검증 불가)뿐 — 릴리스 전 게이트로 병렬 처리.

### 8.8 실기기 스모크 결과 (2026-07-07 · 삼성 S22 Ultra · Android 16 · 오케스트레이터 직접 수행)

> §8.6 실기기 필수 항목의 Android 분 전량 실측. 소유자 입회, adb 원격 구동. 실삭제 2장(20210519_134033.jpg 포함, 소유자 승인 스모크).

| 항목 | 결과 | 근거(실측) |
|------|------|------|
| 삭제 버튼 노출(supportsDeletion) | **PASS** | API36 기기에서 좌단 저강도 버튼 렌더 |
| 교육 시트 최초 1회 + [취소] 재노출 | **PASS** | 첫 탭 시트 노출 → 취소 → 재탭 시 재노출 → [삭제] 진행 후엔 미노출(재설치 후에도 플래그 유지) |
| OS 동의창 1회/건 (DEL-7') | **PASS** | 삭제 1건당 시스템 동의창 정확히 1회, 대상 사진 미리보기 표시 |
| 동의창 거부 → 통합 문구 (DEL-1') | **PASS** | "삭제하지 못했어요" 스낵 + 카드 유지(1/16052), 상태 무변경 |
| 영구 삭제 실동작 + 오조준 없음 | **PASS** | MediaStore diff로 정확히 대상 1건만 소멸(15449→15448, _id=78). 카드/동의창 미리보기 구도 차이는 EXIF 회전 처리 차이(동일 파일 확인) |
| 큐 미재등장 (DEL-3') | **PASS** | 재진입 시 삭제 자산 미노출, 카운트 16052→16051→16050 정확 감산 |
| streak 삭제일 인정 (DEL-8) | **PASS** | 당일 활동이 삭제뿐인데 streak 1→2일 상승(홈·완료 화면 양쪽) |
| 삭제만 세션 완료 전이 | **FIXED+PASS** | 스모크 중 발견: "정리 (0)" 버튼이 pendingCount만 보고 비활성 → 삭제만 세션이 완료 화면 진입 불가. `sort_screen.dart` 활성 조건에 deletedCount 추가 + 라벨 "마치기" — 수정 후 완료 화면 "1장을 삭제했어요"+streak 정상 |
| 다크 테마 대비 | **PASS** | 완료 화면 체크마크(D-1 수정 실증)·삭제 버튼·교육 시트 모두 다크에서 대비 양호 |

잔여: iOS 전 항목(Mac 필요), Android API<30 실기기(버튼 미노출 확인 — 보유 기기 없음).
