# 05 · 정밀 수정 지시서 (final-auditor → platform-integrator)

> 근거: `_workspace/04_final_audit.md` (A-2, A-3, B-4) + photo_manager 3.9.0 소스 직접 확인.
> 대상 수정자: **platform-integrator**. 아래 3건(FIX-1 / FIX-2a / FIX-2b)만 이번 스코프.
> **코드는 지시서대로 integrator가 작성한다.** final-auditor는 코드를 고치지 않는다.
> 지켜야 할 불변: features는 `PhotoService`/`NotificationService` 추상 계약만 본다(02_integrator_notes B). 시그니처를 바꾸지 말고 **구현체 내부만** 고친다. 판별=처리 ID 집합(datamodel §3), stage→commit→성공분만 markProcessed(datamodel §7), D1/D2 확정은 유지.

---

## FIX-1 · 알림 타임존 (04_final_audit A-2, HIGH)

### 1. 정확한 위치
- `lib/core/notifications/local_notification_service.dart`
  - `init()` (라인 29-50) — 타임존 초기화 지점.
  - `_nextInstanceOf(TimeOfDay)` (라인 105-119) — `tz.local` 기준 계산.
  - `scheduleDaily(TimeOfDay)` (라인 74-87) — `zonedSchedule` 호출.

### 2. 현재 무엇이 왜 잘못됐는가
- `init()`은 `tzdata.initializeTimeZones()`만 호출하고 **`tz.local`을 설정하지 않는다**. `timezone` 패키지의 `tz.local` 기본값은 **UTC**다(코드 주석 라인 32-33이 이미 자인).
- 따라서 `_nextInstanceOf`가 `tz.TZDateTime(tz.local, ...)`(라인 107)로 만든 시각은 UTC 기준. KST(UTC+9) 기기에서 사용자가 21:00을 고르면 **21:00 UTC = 익일 06:00 KST**에 발송된다. `inexact`(라인 82)는 분 단위 오차 허용일 뿐 9시간 오프셋과 무관.

### 3. 정확히 어떻게 고쳐야 하는가
- **pubspec 추가 필요**: `flutter_timezone`(기기 IANA 타임존명 획득용). `dependencies:`에 추가 후 `flutter pub get`.
  - 버전 주의: `flutter_timezone`은 버전에 따라 반환 타입이 다르다. 3.x대는 `Future<String> FlutterTimezone.getLocalTimezone()`(예: `"Asia/Seoul"`), 4.x대는 `getLocalTimezone()`이 `TimezonesInfo`(필드 `.identifier`)를 반환. **도입 후 실제 반환 타입을 확인**하고 문자열 IANA 이름을 뽑아 쓸 것.
- **초기화 위치 = `init()` 안, `tzdata.initializeTimeZones()` 직후**(반드시 그 뒤). 순서:
  ```
  tzdata.initializeTimeZones();                 // (기존) DB 로드 — 먼저
  final String name = <flutter_timezone로 IANA 이름 획득>;   // 예: 'Asia/Seoul'
  tz.setLocalLocation(tz.getLocation(name));    // tz.local 을 기기 실제 존으로 교체
  ```
  - `tz.getLocation`은 DB 로드(`initializeTimeZones`) 이후에만 유효 → 순서 역전 금지.
  - `getLocation`이 예외를 던질 수 있으니(알 수 없는 이름) try/catch로 감싸고 실패 시 `tz.setLocalLocation(tz.getLocation('UTC'))` 폴백 + 계속 진행(크래시 금지). init 실패로 앱 부팅이 막히면 안 됨.
- **`scheduleDaily`/`_nextInstanceOf`는 로직 변경 불필요** — `tz.local`이 올바르게 세팅되면 기존 코드가 그대로 정상 동작한다. 단 `scheduleDaily`는 이미 맨 앞에서 `await init()`(라인 75)을 호출하므로, `init()`이 idempotent(`_initialized` 가드, 라인 30)인 점을 유지하면 스케줄 시 항상 tz가 준비된다.
- **부팅 경로 확인**: `main.dart:22`가 `notificationServiceProvider.init()`를 앱 시작 시 1회 호출 → 여기서 tz.local이 세팅되므로 별도 부팅 훅 추가 불필요. (init을 main에서 부르는 구조 유지.)

### 4. 회귀 방지·검증
- **단위 테스트(실기기 불요)**: `flutter_timezone` 호출은 플랫폼 채널이라 테스트에서 직접 못 부른다. 대신 `_nextInstanceOf`를 **테스트 가능하게** 리팩터(예: `tz.Location`을 인자로 받거나 `@visibleForTesting`으로 노출) → `tz.getLocation('Asia/Seoul')`을 수동 주입하고, "21:00 입력 시 반환된 TZDateTime의 hour==21 且 location.name=='Asia/Seoul'"을 검증. tzdata를 테스트 setUp에서 `initializeTimeZones()`로 로드.
  - 경계: 현재 시각이 21:00을 지났을 때 → 반환일이 '내일'인지(라인 115-117) 검증.
- **실기기에서만 확인**: 실제 알림이 설정 시각(로컬)에 발화하는지. Android inexact 특성상 ±수분 편차는 정상.

### 5. 지켜야 할 제약
- `NotificationService` 추상 계약(`init/requestPermission/scheduleDaily/cancelAll`) 시그니처 변경 금지 — features 무영향.
- inexact 유지(00_decisions/R7: `SCHEDULE_EXACT_ALARM` 권한 회피). exact로 바꾸지 말 것.
- 타임존명 획득 실패가 크래시로 이어지지 않도록 폴백 필수.

---

## FIX-2a · iOS 빈(신규) 앨범 commit 실패 (04_final_audit A-3, HIGH·실기기 검증 필수)

### 1. 정확한 위치
- `lib/core/photo/photo_manager_photo_service.dart`
  - `_commitDarwin(...)` (라인 129-168) — iOS 태깅 commit.
  - `_resolveDarwinPath(String ref)` (라인 310-319) — 앨범 재해석.
  - `createAlbum(String name)` (라인 266-289) — 신규 앨범 생성/systemAlbumRef 저장.

### 2. 현재 무엇이 왜 잘못됐는가
- commit 시 대상 앨범을 `_resolveDarwinPath`가 **`getAssetPathList(hasAll:false, type:common)` 전체 목록을 훑어 `path.id == ref`로 선형 매칭**(라인 311-317)한다.
- 방금 만든 앨범은 **자산이 0개**다. photo_manager 3.9.0에는 `getAssetPathList`에 "빈 앨범 포함" 스위치(`containsEmptyAlbum`)가 **없고**, 목록에 빈 컬렉션이 안 잡히거나 필터의 날짜 조건에 걸려 누락될 수 있다 → `path == null`(라인 149) → 그 앨범에 예약된 **전량 failed**.
- 결과: "새 앨범 생성 → 배정 → commit"(MVP의 단 하나뿐인 첫 여정)이 iOS 첫 회부터 실패. 유실은 없으나(실패분 큐 유지) Aha moment 파손.

### 3. 정확히 어떻게 고쳐야 하는가
- **핵심: 목록 스캔을 버리고 localIdentifier로 직접 해석.** photo_manager 3.9.0은 `AssetPathEntity.fromId(String id, {FilterOptionGroup? filterOption, RequestType type, int albumType})`를 제공한다(`lib/src/types/entity.dart:54`). 이는 컬렉션을 **id로 직접 fetch**하므로 빈 앨범도 잡힌다.
  - `_resolveDarwinPath`를 다음 의미로 교체:
    ```
    Future<AssetPathEntity?> _resolveDarwinPath(String ref) async {
      try {
        return await AssetPathEntity.fromId(
          ref,
          type: RequestType.common,   // 사진+영상
          albumType: 1,               // 1 = 일반 앨범(user album). createAlbum이 만든 타입.
        );
      } catch (_) {
        return null;                  // 못 찾으면 null → 호출부가 failed 처리(기존 흐름 유지)
      }
    }
    ```
  - `AssetPathEntity.fromId`는 성공 시 `Future<AssetPathEntity>`(못 찾으면 StateError throw)이므로 **반드시 try/catch**로 감싸 null 폴백. 기존 `_commitDarwin`의 `path == null → failed`(라인 149-152) 분기는 그대로 두면 됨(안전).
  - 캐시 로직(`pathCache`, 라인 134/144-148)은 유지 가능 — 키가 ref 문자열이라 그대로 동작.
- **systemAlbumRef == null 안전 처리(신규 앨범 경합 방어)**: 현재 `_commitDarwin`은 `ref == null`이면 무조건 failed(라인 140-142). 신규 앨범이 아직 systemAlbumRef를 못 채운 순간(생성 직후 DB 반영 지연·앱 재시작 등)에 그 앨범 전량이 실패한다. 다음으로 보강:
  - `_commitDarwin` 루프에서 `ref == null`일 때 즉시 failed 하지 말고, **그 자리에서 darwin 앨범을 생성/재확보**한다:
    ```
    if (ref == null) {
      final created = await PhotoManager.editor.darwin.createAlbum(pa.album.name);
      if (created == null) { failed.add(pa.assetId); continue; }
      ref = created.id;
      await _albumRepo.setSystemRef(pa.album.id, ref);  // DB에 참조 채움(이후 commit 재사용)
      pathCache[ref] = created;                          // 방금 만든 path 재사용
    }
    ```
  - 주의: 동일 세션에서 같은 albumId가 여러 pending에 걸쳐 있으므로, 위에서 `setSystemRef`로 DB를 갱신하고 `pathCache`에도 넣어 **앨범당 1회만 생성**되게 할 것(중복 생성 방지). `pa.album`은 stage 시점 스냅샷이라 ref가 낡을 수 있으니, 판단은 `pa.album.systemAlbumRef` 대신 pathCache/DB 최신값을 우선하도록 순서를 잡을 것.
- **`createAlbum`(라인 266-289) 자체는 변경 최소화**: 이미 생성 후 `setSystemRef`로 저장(284-286)하므로 정상 경로에선 ref가 채워진다. 위 보강은 어디까지나 ref==null 경합 폴백.

### 4. 회귀 방지·검증
- **실기기(iOS)에서만 확인 가능(필수)**: (1) 신규 빈 앨범 생성 → 그 앨범으로 배정 → commit → `succeeded`에 포함되는지, (2) 다음 큐 로드에서 해당 자산이 제외되는지(태깅 후에도 원본 타임라인 잔존하나 재등장 없어야 함, datamodel §3.1 iOS 불변식), (3) 기존(자산 있는) 앨범 commit도 여전히 성공하는지(회귀 없음).
- **단위 테스트(실기기 불요, 부분)**: `_resolveDarwinPath`는 플랫폼 채널이라 직접 테스트 불가. 대신 `_commitDarwin`의 **ref==null → 생성 폴백 분기**를 검증하려면 photo editor 호출을 추상화(주입)해야 하므로 이번 스코프에선 과투자. 정적 대조 + 실기기 스모크로 갈음하고, PR 설명에 "iOS 실기기 스모크 통과" 근거를 남길 것.

### 5. 지켜야 할 제약
- `PhotoService` 계약(`commitAssignments`→`BatchAssignResult`) 시그니처·반환 shape 불변(02_integrator_notes B.3). 성공/실패 분류 의미 유지(datamodel §7.2).
- iOS는 **태깅(copyAssetToPath)** 유지 — 이동/삭제로 바꾸지 말 것(D1: iOS=태깅, 원본 타임라인 유지).
- 다중 배정 금지 유지: `_pending`은 assetId당 1앨범(라인 27) — 구조 변경 금지.

---

## FIX-2b · Android id 재발급 best-effort 매칭 오기록 (04_final_audit B-4, MEDIUM·실기기 검증 필수)

### 1. 정확한 위치
- `lib/core/photo/photo_manager_photo_service.dart`
  - `_resolveAndroidFinalIds(AlbumRef, List<AssetEntity>)` (라인 233-261).
  - 호출부 `_commitAndroid`의 성공 기록 루프 (라인 213-224) — `finalIds[i] ?? pairs[i].$2.id`.

### 2. 현재 무엇이 왜 잘못됐는가
- 이동 후 원래 id가 죽으면(`AssetEntity.fromId`가 null, 라인 240-245) 대상 앨범 최신분에서 **순서 기반 추정 매칭**(라인 253-260: `getAssetListPaged`로 최근 N개 받아 앞에서부터 채움)을 한다.
- 두 가지 오류 경로:
  - **오매칭 → 간접 유실**: 추정이 어긋나 엉뚱한 자산 id를 기록하면, 실제로 정리되지 않은 그 자산이 처리 기록에 들어가 **다음 큐에서 영구 제외**(사용자 인지 없는 유실). markProcessed는 datamodel §7.2의 "성공→기록 원자성"을 어기게 됨.
  - **폴백 매칭의 앨범 오선택**: `_resolveAndroidPathByName`(라인 322-331)은 **폴더 표시명만** 비교 → 동명 폴더(`DCIM/여행` vs `Pictures/여행`) 오선택 가능.
- 게다가 매칭 실패 시 `finalIds[i]`가 null → 호출부(라인 218)가 `?? pairs[i].$2.id`로 **이동 전(죽은) id를 기록** → 그 id는 라이브러리에 없어 큐에선 안 뜨지만, 실제 이동된 자산은 새 id로 재등장(중복 노동). 즉 현재 폴백은 "유실 또는 재등장" 둘 다 유발.

### 3. 정확히 어떻게 고쳐야 하는가 — "확실하면 기록, 불확실하면 실패로"
핵심 원칙: **정확 매칭이 확실한 것만 성공(markProcessed 대상)으로 두고, 불확실하면 그 자산을 `failed`로 돌려 stage 큐에 유지**한다. "재등장(다시 정리하면 됨)"은 감수하되 **"간접 유실"은 절대 만들지 않는다**(유실 > 재등장 우선순위).

- **(a) id 유지 케이스는 그대로 확정**: 라인 241-243 `AssetEntity.fromId(moved[i].id) != null` → 그 id로 성공 기록(정확). 변경 없음.
- **(b) id 재발급(추정) 케이스는 성공에서 제외**: `_resolveAndroidFinalIds`의 순서 기반 추정 매칭(라인 249-260)을 **제거하거나, 신뢰 가능한 정확 매칭으로 대체**한다. 정확 매칭 근거가 없으면 해당 index를 **null이 아니라 "실패 표식"으로 반환**하고, 호출부에서 `succeeded`가 아닌 `failed`에 넣는다.
  - 호출부(라인 213-224) 수정: `finalIds[i]`가 확정 id면 `succeeded`에 추가+`_pending.remove`, 확정 불가면 **`failed.add(pa.assetId)` 하고 `_pending`에서 제거하지 않는다**(재시도 대상 유지).
  - ⚠️ 주의: 이 경우 파일은 이미 물리 이동됐는데 기록은 안 된 상태 → 다음 큐에 **이동된 자산이 재등장**한다. 재배정 시 같은 폴더로 재이동은 no-op/중복이므로 데이터 안전(유실 없음). 이 "재등장 감수"는 00_decisions 미결 B("백업복원/재색인 후 일부 재등장 감수 + 고지")와 정합 — 고지 문구로 완화.
  - 더 정확히 하려면(선택, 여력 시): 추정 매칭 대신 **이동 직전 각 자산의 안정 속성(파일명 `title`, `size`, `createDateTime`)을 캡처**해 두고, 이동 후 대상 앨범 자산을 같은 (title,size,createDateTime) 조합으로 **정확 일치**시킨다. 1건이라도 다중 후보면 그 건은 실패 처리(불확실 → 유실 금지).
- **(c) 앨범 매칭 정확도 개선**: `_resolveAndroidPathByName`(표시명 비교, 라인 322-331)을 사용하는 대신, 이동 목적지 경로(`_androidTargetPath` = RELATIVE_PATH, 예 `Pictures/여행`)로 매칭하도록 `path.name`이 아니라 실제 버킷 경로를 비교할 것. 동명 폴더 오선택을 없앤다. (photo_manager의 AssetPathEntity에서 RELATIVE_PATH를 직접 얻기 어렵다면, 최소한 후보가 유일할 때만 사용하고 복수면 실패 처리.)

### 4. 회귀 방지·검증
- **단위 테스트(실기기 불요, 로직 부분만)**: 추정 매칭을 순수 함수로 분리(예: `List<String?> matchByStableProps(captured, movedCandidates)`)해 (1) 유일 정확 일치 → 그 id, (2) 후보 0 또는 다중 → null(=실패)을 검증. 플랫폼 채널 없는 순수 로직이라 테스트 가능.
- **실기기에서만 확인(필수)**: Android 다기종 — 최소 **삼성 One UI + Pixel(AOSP)** 2종에서 (a) 이동 후 원래 id 유지 여부(OEM별 상이), (b) 재발급 발생 시 신규안이 오기록 없이 실패로 빠지는지, (c) 동의창 승인/취소 동작. 04_final_audit A-5(동의창 취소=cancelled 구분)는 이번 스코프 밖이나 같은 실기기 세션에서 함께 관찰해 두면 후속 수정에 유리.

### 5. 지켜야 할 제약
- datamodel §3.1.1 "기록 id = 이동 후 최종 assetId" 유지. 확정 불가 시 기록하지 않는 것이 이 규칙의 안전한 해석(잘못된 id 기록 금지).
- "성공분만 markProcessed" 불변식(datamodel §7.2) 절대 유지 — 불확실 자산을 성공으로 밀어넣지 말 것.
- Android는 **물리 이동(moveAssetsToPath)** 유지(D1). copyAssetToPath 금지(Android 11+ 조용한 실패, 코드 주석 라인 201-202).
- `BatchAssignResult` shape·`_pending` 구조 불변(계약).

---

## 요약 (integrator 착수용)
| FIX | 파일 | 핵심 조치 | pubspec |
|-----|------|-----------|---------|
| FIX-1 | local_notification_service.dart | `init()`에서 flutter_timezone로 IANA명 획득 → `tz.setLocalLocation` (initializeTimeZones 뒤, 실패 시 UTC 폴백) | **추가 필요**: `flutter_timezone` |
| FIX-2a | photo_manager_photo_service.dart | `_resolveDarwinPath`를 `AssetPathEntity.fromId(ref, albumType:1)`로 교체(빈 앨범 해석) + ref==null 시 darwin 앨범 생성 폴백 | 불필요 |
| FIX-2b | photo_manager_photo_service.dart | 재발급 추정 매칭 제거/정확화 — 불확실 자산은 `failed`로(간접 유실 금지), 앨범 매칭은 경로 기준·유일 후보만 | 불필요 |

> FIX-2a/2b는 실기기(iOS 1종·Android 2종) 스모크가 **머지 게이트**. FIX-1은 단위 테스트로 대부분 커버 가능.
