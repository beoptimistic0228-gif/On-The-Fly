# 06 · 정리 루프 내 단건 삭제(D5) 설계

> 저자: spec-architect · 2026-07-06 · 헌장: `00_decisions.md` D5(단건 삭제 범위 편입)
> 대상: platform-integrator(실현성 검토 → §6 질문), feature-builder(UI·컨트롤러), qa-verifier(불변식 §4), team-lead/사용자(§7 승인 필요 결정)
> 제약: **단건 삭제만.** 일괄 삭제·중복정리·저장공간 비우기는 여전히 Out of Scope(Phase 1+). 코드 미작성(설계 전용).

---

## 0. 확정 개정판 (2026-07-07, 오케스트레이터 — 사용자 §7 확정 + §9 실현성 검토 반영)

> **이 절이 아래 §1~§8과 상충하면 이 절이 우선한다.** 원문(§1~§8)은 추천안 기록으로 보존. 사용자 확정: `00_decisions.md` D5 확정 세부(1~6). spec-architect 개정 재시도가 세션 한도로 불발 → 하네스 폴백 규칙(좁고 명확한 범위는 오케스트레이터 직접 수행)에 따라 본 절 작성.

### 0.1 확정 모델 (원문과의 차이)

| 항목 | 원문 추천(§1) | **확정** | 근거 |
|------|------|------|------|
| 복구 모델 | 휴지통 30일 | **영구 삭제** — Android `deleteWithIds`→`createDeleteRequest`(§9 Q1). iOS는 플랫폼 한계로 `deleteAssets`→"최근 삭제됨" 30일(**비대칭 감수**) | 사용자 §7-1 |
| 실행 시점 | stage→commit 배치 | **즉시 실행** — 삭제 탭→OS 동의창→확정. stage/pending/커밋 통합 없음 | 사용자 §7-2 |
| 진입점 | 저강도 버튼 | 저강도 버튼 (§2.1 그대로 유효) | 사용자 §7-3 |
| streak | 배정 기준 유지 | **삭제도 인정** — 삭제 기록 테이블 신설(스키마 v2) | 사용자 §7-4 |
| API<30 | 미노출 권장 | **미노출 확정** — minSdk=24 확인(§9 Q3), API<30 `deleteWithIds`는 OS 동의창 없이 직삭제 경로라 안전장치 부재 | 자동확정(D5-5) |
| 취소 안내 | "취소됐어요" | **"삭제하지 못했어요"로 통합** — 취소/실패 플랫폼상 구분 불가(§9 Q4, 빈 반환) | 자동확정(D5-6) |

### 0.2 인터랙션 (원문 §2 대체분)

- **§2.1(버튼)·§2.7(테마) 유효.** §2.3(예약 카드 흐름)·§2.4(스테이징 배너 삭제 표기)·§2.5(삭제 커밋) **폐기**.
- 흐름: 삭제 버튼 탭 → [최초 1회 교육 시트] → `deleteAsset(current)` 호출 → **OS 동의창**(Android "영구 삭제" / iOS 시스템 확인창) → 성공 시 카드 제거·`index` 진행·세션 `deletedCount++` / 빈 반환 시 카드 유지 + 스낵 "삭제하지 못했어요".
- **되돌리기(undo)는 삭제 미적용**(영구+즉시 — OS 동의창이 유일 확인 지점). 삭제는 history에 안 쌓임.
- 교육 시트 문구(플랫폼 분기): Android "삭제하면 **바로 영구 삭제**돼요. 복구할 수 없어요." / iOS "삭제한 사진은 '최근 삭제됨'으로 이동해요(30일 후 영구 삭제)." 공통: "원본은 폰 밖으로 나가지 않아요." 버튼 [삭제] / [취소]. 플래그 `hasSeenDeleteIntro`(settings_store).
- 하단 배너·commit 버튼은 **배정 전용 유지**(삭제는 즉시 처리라 대기 개념 없음).
- 완료 화면(§2.6 수정): 총계 = 배정 성공 + **세션 중 삭제 성공**. 분해 라인 "앨범 10장 · 삭제 2장"(휴지통 표현 금지 — Android는 영구). 삭제 0이면 분해 생략.

### 0.3 계약·데이터 (원문 §3 대체분)

```dart
// PhotoService 추가 — 단건 즉시 삭제(OS 동의창 포함). true=성공.
// false=취소 또는 실패(구분 불가, §9 Q4). photo_manager 타입 비노출 유지.
Future<bool> deleteAsset(AssetRef asset);
// 구현: Android(API30+) editor.deleteWithIds([id]) → createDeleteRequest 1회.
//       iOS editor.deleteWithIds([id]) → deleteAssets(시스템 확인창).
//       API<30: UI에서 버튼 미노출이 1차 방어 + 서비스도 즉시 false 반환(2차 방어).
// 신규 계약 — API<30 노출 차단용.
bool get supportsDeletion; // Android API>=30 또는 iOS
```

- `BatchDeleteResult`·`stageDeletion/unstageDeletion/pendingDeletions/commitDeletions`(§3.3) **폐기**.
- **스키마 v2**: `DeletionLogs(id autoincrement, deletedAt DateTime)` 테이블 신설(삭제 성공 1건당 1행, 자산 id **비저장** — 프라이버시·Option A 유지). 용도: streak 산정 + (선택) 통계. Drift `schemaVersion 1→2`, `onUpgrade`에 createTable.
- **streak**: `streakDays()` 산정을 "처리일(processedAt) ∪ 삭제일(deletedAt)" 날짜 합집합 기준으로 확장.
- 방어 규칙: `deleteAsset` 성공 시 해당 자산이 pending 배정에 있으면 예약 제거(정상 흐름상 current는 pending에 없지만 방어적).
- 스캔 캐시: 삭제 성공 → total 감소 → 지문 미스 → 자가 무효화(§9 Q6, 변경 불요). 단 서비스 내부 `_queueCache`에서 해당 자산 즉시 제거(재진입 전 캐시 적중 시에도 안 보이게).
- ProcessedAsset **미기록** 유지(§3.1 Option A — Android는 자산 소멸, iOS는 최근삭제됨 기본 제외 §9 Q5).

### 0.4 불변식 개정 (원문 §4 대체분)

| ID | 개정 불변식 |
|----|------|
| DEL-1' | 삭제 성공 전(동의창 취소/실패 포함) 원본은 그대로, 큐에도 잔존 |
| DEL-2' | (폐기 — undo 없음) 대신: **삭제는 OS 동의창 승인 없이는 절대 실행되지 않는다**(API<30 차단 포함) |
| DEL-3' | 삭제 성공 자산은 큐에 재등장하지 않는다(Android=소멸, iOS=최근삭제 기본 제외) |
| DEL-4 | 삭제 자산 ProcessedAsset 미기록(유지) |
| DEL-5' | iOS 한정: 최근 삭제됨 복구 시 재등장(재정리 기회) — Android는 해당 없음 |
| DEL-6' | 삭제와 pending 배정 독립·충돌 없음(삭제 성공 시 pending에서 제거) |
| DEL-7' | 삭제 1건 = OS 동의창 1회. 세션 commit 동의창은 이동 1회 유지 |
| DEL-8 | streak = 처리일 ∪ 삭제일. 삭제만 한 날도 인정 |

### 0.5 작업 분해 개정 (원문 §8 대체분 — 네이티브 작업 0, §9 M1)

| ID | 작업 | 담당 | 의존 |
|----|------|------|------|
| **F-14a'** | core: `deleteAsset`/`supportsDeletion` 구현(deleteWithIds, API<30 차단) + `DeletionLogs` 스키마 v2 + `DeletionRepository`(logDeletion) + streak 합집합 확장 + 단위 테스트 | platform-integrator | — |
| **F-14b'** | SortController: `deleteCurrent()`(즉시 모델), 세션 deletedCount, 큐/index 전이, 스낵 상태 | feature-builder | F-14a' |
| **F-14c'** | UI: 저강도 삭제 버튼(supportsDeletion 조건 노출)·교육 시트·완료 화면 총계+분해·분석 이벤트(`asset_deleted`, `sort_session_complete.deleted_count`) | feature-builder | F-14b' |
| **F-14d'** | QA: DEL-1'~8 검증 + 실기기(동의창·삭제 실동작·streak) | qa-verifier | F-14c' |

부록(분석 이벤트) 유효. §9.3 잔여 실기기 항목 중 트래시 관련(DEL-3 OEM·DEL-5·트래시 카운트)은 영구 삭제 전환으로 **Android에선 무의미**해짐 — iOS 검증 목록으로 이관.

---

## 1. 결정 요약 (추천안) — ⚠️ §0으로 대체됨(기록 보존용)

한 줄: **삭제는 배정과 똑같이 "예약(stage) → 세션 끝 배치 확정(commit)" 흐름에 태우고, 진입점은 새 스와이프 방향이 아니라 정리 화면 하단의 "눈에 덜 띄는 삭제 버튼"으로 하며, Android는 영구삭제가 아닌 휴지통(30일 복구)을 경유한다.**

| 검토 항목 | 추천 | 한 줄 근거 |
|-----------|------|-----------|
| (a) 파괴적 안전장치 | **Android=`createTrashRequest`(휴지통 30일)** / iOS=`deleteAssets`(시스템 확인창+최근 삭제됨 30일) | MVP는 "눈앞에서 치우기"지 "저장공간 비우기"(Phase 1)가 아니다 → 되돌릴 수 있는 휴지통이 정답. 영구삭제(`createDeleteRequest`)는 안전망이 없어 채택 안 함. |
| (b) 제스처 충돌 | **버튼(하단, 축소·error색·저강도)**. 스와이프 4번째 방향(하) 안 씀. | 스와이프 3방향은 전부 비파괴 액션(배정/나중에/최근앨범)에 할당됨 → "스와이프는 안전하다"는 심성 모델 유지. 파괴적 액션에 방향 하나를 더 얹으면 **오조작=오삭제** 위험(헌장 최우선 위배). 버튼은 조준이 필요해 오발이 적고 시각 위계를 낮출 수 있다. |
| (c) stage→commit 정합 | **배치(예약 후 세션 끝 확정)**. 즉시 실행 안 함. | 즉시 삭제면 삭제 1건당 OS 동의창 1회 → 빠른 루프가 매번 끊긴다. 배치면 세션당 삭제 동의창 **1회**, 게다가 commit 전엔 앱 내 "되돌리기"가 공짜로 성립(2중 안전망: 앱 unstage + OS 휴지통). |
| (d) 중복방지 불변식 | **삭제 자산은 `ProcessedAsset`에 기록하지 않음(스키마 무변경)**. | 휴지통/최근삭제된 자산은 OS가 기본 조회에서 제외 → 큐에 자연히 안 뜬다. DB로 막으면 (1) `albumId` non-null FK라 스키마 변경 필요, (2) 30일 내 **복구 시 재정리 기회를 영구 차단**(오히려 나쁨). |

**핵심 트레이드오프(헌장 (c) 명시 요구):** Android에서 한 세션에 **배정 + 삭제를 둘 다** 하면 commit 시 시스템 동의창이 **최대 2회**(배정=`createWriteRequest` 1회, 삭제=`createTrashRequest` 1회) 뜬다. 이 둘은 서로 다른 MediaStore 인텐트라 **하나로 합칠 수 없다**(플랫폼 한계). 각각 개수 무관 1회이므로 상한은 2. iOS는 배정이 태깅(동의창 없음)이라 삭제할 때만 1회. → §7-2 사용자 확인.

---

## 2. 화면 / 인터랙션 스펙

### 2.1 진입점 — 정리 화면 하단 삭제 버튼

현행 하단 패널 액션 행: `[나중에] [되돌리기] [앨범 배정(강조)]` (`sort_screen.dart:292-315`).

**변경:** 액션 행 **맨 왼쪽에 저강도 삭제 버튼을 추가**하되, 시각 위계를 명확히 낮춘다(디자인 원칙 2의 "배정=주인공"을 흐리지 않기 위함).

```
[ 삭제 ]   [ 나중에 ]   [ 되돌리기 ]        [ 앨범 배정 ]
 작게·아웃라인   중립색       secondary          채운 원(강조)
 error색·저채도
```

| 속성 | 값 | 근거 |
|------|----|----|
| 아이콘 | `Icons.delete_outline`(아웃라인) | 채운 아이콘보다 무게 낮춤 |
| 색 | `colorScheme.error`, 배경 `error.withValues(alpha:0.12)`(고스트) | 파괴적 액션 컬러 규칙, 단 저채도로 유혹 억제 |
| 크기 | 나머지 버튼보다 작게(비강조), `prominent=false` | 배정 < 삭제가 되도록 위계 하강 |
| 위치 | 행 좌단, 배정(우단·강조)과 대각 | 실수로 배정 자리 누르다 삭제 눌리는 일 방지(물리적 거리) |
| 라벨 | "삭제" | 명확·오해 없음 |

> 대안 비교(채택 안 함): **① 하 스와이프** — 오발 위험(스크롤 근육기억), 심성 모델 파괴. **② 롱프레스** — 발견성 낮고 2스텝. **③ 카드 위 오버레이 휴지통** — 사진(주인공) 위를 덮어 원칙 1 침해. → 버튼이 "저강도·명시·조준 필요"를 동시에 만족.

### 2.2 최초 1회 교육 시트 (first-use)

삭제 버튼 **첫 탭 시에만** 바텀시트로 동작·안전망을 고지하고, 이후는 무마찰(바로 예약).

- 문구: "삭제한 사진은 **휴지통으로 이동**해요(30일간 복구 가능). 정리를 마칠 때 한 번에 처리돼요. 원본은 폰 밖으로 나가지 않아요."
- 버튼: [삭제 예약] / [취소]. "다시 보지 않기" 없이 최초 1회만(플래그 `hasSeenDeleteIntro`, `settings_store`에 저장).
- 근거: 로드맵 §5.1 "삭제엔 확정 흐름(일괄 확인·되돌리기 유예)이 별도로 필요"를 **최초 교육 + 커밋시 OS 동의창 + 인앱 되돌리기** 3중으로 충족(퍼탭 확인창은 안 씀 → 루프 속도 보존).

### 2.3 예약 후 카드 흐름 (배정과 동일)

- 삭제 예약 → `_history`에 `wasDelete` 기록 → `index++` → 다음 카드. (배정 `assignCurrent`와 대칭.)
- **되돌리기**(기존 버튼)로 삭제 예약 취소 가능(commit 전이라 안전). `undo()`가 `wasDelete`면 `unstageDeletion`.

### 2.4 하단 스테이징 배너 — 삭제 가시화("일괄 확인")

현행 배너 "옮길 준비 완료 N장"(`sort_screen.dart:324-338`)을 배정+삭제 겸용으로:

| 상태 | 배너 표기 |
|------|-----------|
| 배정만 | "옮길 준비 완료 · **N장**" |
| 삭제만 | "버릴 준비 완료 · **M장**" |
| 둘 다 | "옮길 **N장** · 버릴 **M장**" |
| 없음 | "대기 중인 사진 없음" |

- commit 버튼 라벨 "정리 (N+M)"(전체 대기 수). 버튼 활성 조건: `pendingAssign>0 || pendingDelete>0`.

### 2.5 커밋 흐름 (동의창 순서·부분 실패)

```
사용자 "정리" 탭
  └─ status=committing
     1) 배정 커밋(있으면)  : Android createWriteRequest 1회 / iOS 태깅(무동의창)
        → 성공분 markProcessed (기존 그대로)
     2) 삭제 커밋(있으면)  : Android createTrashRequest 1회 / iOS deleteAssets 1회(시스템 확인창)
        → 성공분은 markProcessed "안 함"(§3), 카운트만 집계
  └─ CommitOutcome(assigned, deleted, 각 failed/cancelled) → /done 또는 인라인 안내
```

- 순서 = **배정 먼저, 삭제 나중**. 근거: 비파괴(안전) 먼저 → 파괴(삭제) 확인창을 마지막에 배치(가장 신중해야 할 조작을 끝에, 축하 직전). 삭제 동의창 취소해도 배정은 이미 성공(독립).
- 삭제 동의창 **취소**: 삭제분은 예약 큐에 유지(배정 C-4와 동일 의미론). "삭제는 취소됐어요. 예약은 그대로예요" 안내.
- **부분 상태 매트릭스:** 배정/삭제는 서로 독립 결과. (배정 성공 + 삭제 취소), (배정 취소 + 삭제 성공) 등 4조합 모두 표현 가능해야 함(§3.3 CommitOutcome).

### 2.6 완료(Done) 화면 통계 — 삭제 포함 방식

현행 "N장을 앨범으로 옮겼어요"(`done_screen.dart:90`)를 확장:

- 헤드라인 총계 = **배정 + 삭제**: "**12장 정리 완료!**"(성취감은 총량으로 크게).
- 그 아래 분해 라인: "앨범에 10장 · 휴지통에 2장". 삭제 0이면 분해 라인 생략(기존 문구 유지).
- 삭제만 한 세션: "휴지통에 2장 정리했어요"(앨범 안내 문구는 숨김).
- 삭제 부분 실패 M>0: 기존 실패 배너 재사용 "M장은 삭제하지 못했어요. 다음에 다시 시도해요."
- streak 시각화·광고 슬롯은 그대로(삭제만 한 세션의 streak 반영 여부는 §7-4 열린 결정).

### 2.7 다크·라이트 양 테마

- 삭제 버튼: 양 테마 모두 `colorScheme.error` 파생색 사용(테마가 명암 자동 처리). 정리 화면은 다크 라이트박스(`kSortCanvas`)라 error색이 충분히 대비되는지 확인(밝은 산호빛 계열 권장, 순수 적색은 라이트박스에서 톤 튐).
- 교육 시트·Done 화면은 `Theme.of(context).colorScheme` 기반이라 양 테마 자동 대응.

---

## 3. 데이터 모델 · PhotoService 계약 변경안 (시그니처 수준)

### 3.1 데이터 모델 — **스키마 변경 없음**(핵심 결정)

`ProcessedAssets.albumId`는 `text().references(Albums)` **non-null FK**(`app_database.dart:28`). 삭제 자산은 앨범이 없다.

**결정: 삭제 자산을 `ProcessedAsset`에 기록하지 않는다.** 따라서 스키마·마이그레이션 **불필요**.

- 중복방지는 **OS 휴지통 메커니즘에 위임**: Android `IS_TRASHED=1`은 MediaStore 기본 쿼리에서 제외, iOS "최근 삭제됨"은 일반 fetch에서 제외 → `loadUnclassifiedQueue()`에 자연히 안 뜸(§4 불변식 D, §6 질문 5로 실측 확인).
- **복구 시 재등장은 의도된 정상 동작**: 30일 내 휴지통 복원 시 자산이 라이브러리로 돌아오면 큐에 다시 나타나 재정리 대상이 됨(바람직). DB로 삭제 id를 막았다면 이 기회를 영구 차단했을 것 → Option 기각.
- 대안(기각): (B) `albumId` nullable로 바꿔 `albumId IS NULL=삭제` 기록 → 스키마 v2 마이그레이션 + 복구자산 영구suppress 부작용. (C) 별도 `DeletedAssets(id, deletedAt)` 테이블 → MVP엔 과설계(스탯은 commit 결과로 충분).

> 파생 영향: **streak/North Star 원천이 `ProcessedAsset.processedAt`**이므로, 삭제만 한 세션은 현재 streak을 올리지 못한다. → §7-4 열린 결정.

### 3.2 F.3 스캔 캐시와의 정합

`loadUnclassifiedQueue()` 지문 캐시(`02_integrator_notes.md` F.3) = `(전체 자산수, 처리수, 마지막 처리시각)`. 삭제(휴지통 이동)로 **전체 자산수가 감소**하면 지문이 바뀌어 캐시 미스 → 정확 재스캔. 즉 삭제를 DB에 안 남겨도 캐시는 자가 무효화된다. → §6 질문 6으로 실측 확인.

### 3.3 PhotoService 계약 확장 (경계 인터페이스)

배정 3종(`stage/unstage/pending`)과 **대칭**으로 삭제 3종 + 커밋 1종 추가. photo_manager 타입은 계약에 노출 안 함(기존 규칙 유지).

```dart
// 삭제 "예약"(stage). 즉시 실행·기록 없음. 같은 자산 재예약은 무시(idempotent).
void stageDeletion(AssetRef asset);

// 예약분 되돌리기(commit 전).
void unstageDeletion(String assetId);

// 현재 삭제 예약 목록("버릴 M장" 표시용).
List<AssetRef> pendingDeletions();

// 삭제 배치 확정 — 세션 끝 1회. 배정 commit 과 별개 동의창.
//  - Android(API30+): createTrashRequest(uris) 1회 → 휴지통(30일).
//  - iOS           : PHAssetChangeRequest.deleteAssets([...]) 1회(시스템 확인창) → 최근 삭제됨.
// 성공분은 markProcessed "안 함"(§3.1). 실패·취소분은 예약 큐 유지.
Future<BatchDeleteResult> commitDeletions();
```

신규 결과 타입(`BatchAssignResult`와 대칭):

```dart
class BatchDeleteResult {
  final List<String> deleted;   // 성공적으로 휴지통 이동된 assetId
  final List<String> failed;    // 실패분 → 예약 유지
  final bool cancelled;         // 사용자가 삭제 동의창 취소(전량 미반영). true면 deleted=[]
  bool get isEmpty => deleted.isEmpty && failed.isEmpty;
}
```

### 3.4 SortController 변경 (feature 레이어)

- `_SwipeAction`에 `wasDelete` 종류 추가(`wasAssign`/skip/delete 3분기).
- `deleteCurrent()` 신규: `photo.stageDeletion(current)` → history 기록 → `index++`. (`assignCurrent` 대칭.)
- `undo()`: `wasDelete`면 `photo.unstageDeletion`.
- `commit()`: 배정 커밋 후 **`pendingDeletions()` 있으면 `commitDeletions()` 추가 호출**. 두 결과를 합쳐 `CommitOutcome` 구성.
- `CommitOutcome` 확장: `deletedCount`, `deleteFailedCount`, `deleteCancelled` 추가(기존 `successCount`=배정 성공 유지).
- `remainingUnclassified` 계산: `_sessionInitialQueueSize - assignedSuccess - deletedSuccess`(삭제분도 큐를 떠나므로 차감).
- `SortState`에 `pendingDeleteCount` 추가(배너·버튼용).

### 3.5 완료화면(Done) 계약

`CommitOutcome`의 새 필드(`deletedCount` 등)만 읽어 §2.6 표기. 총계 = `successCount + deletedCount`.

---

## 4. 불변식 (qa-verifier 검증 경계)

| ID | 불변식 | 확인 방법 |
|----|--------|-----------|
| DEL-1 | stage ≠ 삭제. `stageDeletion` 후 commit 전에는 원본이 그대로 살아 있고 큐 재로드 시 여전히 존재 | fake PhotoService로 stage 후 `loadUnclassifiedQueue`에 잔존 확인 |
| DEL-2 | 되돌리기 안전. commit 전 `undo`(=`unstageDeletion`) 후 자산이 예약에서 빠지고 index 복귀 | 컨트롤러 단위 테스트 |
| DEL-3 | **휴지통 자산 큐 미재등장.** commit(삭제 성공) 후 `loadUnclassifiedQueue`에서 제외 | 실기기: Android `IS_TRASHED`·iOS 최근삭제 기본 제외(§6-5) |
| DEL-4 | 삭제 자산은 `ProcessedAsset`에 기록되지 않음(`albumId` 오염 없음) | commit 후 `processedIdSet`에 삭제 id 부재 확인 |
| DEL-5 | **복구 재등장.** 30일 내 휴지통 복원 시 자산이 큐에 다시 등장(재정리 가능) | 실기기: 휴지통 복원 후 재스캔 |
| DEL-6 | 배정·삭제 독립. 삭제 동의창 취소해도 배정 성공분은 이미 markProcessed(롤백 없음) | 부분상태 매트릭스(§2.5) 테스트 |
| DEL-7 | 세션당 삭제 동의창 ≤ 1회(배치). 배정+삭제 세션은 총 ≤ 2회 | 실기기 logcat/관찰 |

> 단위 테스트: `AppDatabase.forTesting` + fake PhotoService에 `stageDeletion/commitDeletions` override로 구성 가능(기존 E절 패턴 계승).

---

## 5. 플랫폼별 동작 매트릭스

| | 예약(stage) | 커밋 메커니즘 | 동의창 | 복구 | 큐 제외 원리 |
|---|---|---|---|---|---|
| **Android 11+ (API 30+)** | 인메모리 | `MediaStore.createTrashRequest(uris)` 배치 1회(네이티브 채널 필요, §6-1) | 삭제 1회 (+배정 있으면 별도 이동 1회 = 최대 2) | 휴지통 30일 | `IS_TRASHED=1` 기본 쿼리 제외 |
| **Android 10 이하 (API 29-)** | — | `createTrashRequest` 미지원 → **삭제 버튼 숨김/비활성 권장** | — | — | (해당 없음) |
| **iOS 14+** | 인메모리 | `PHAssetChangeRequest.deleteAssets([...])` 배치 1회(photo_manager `deleteWithIds`) | 시스템 확인창 1회(강제·내장) | 최근 삭제됨 30일 | 일반 fetch에서 기본 제외 |

- Android 10 이하 처리: `createTrashRequest`는 API 30+ 전용. `RecoverableSecurityException` 퍼아이템 동의 경로는 네이티브 부담 크고 배치 불가 → MVP는 **API<30에서 삭제 미노출** 권장. 단 **앱 minSdk가 이미 30이면 이 행 자체가 무의미**(§6-3 확인 → 확정 시 이 분기 삭제).
- iOS는 삭제 경로가 시스템 확인창 강제 + 최근삭제됨 30일이라 **본질적으로 안전**(추가 안전장치 불필요).

---

## 6. platform-integrator 실현성 질문 목록

> 이 질문들이 해소돼야 §3 계약이 실현 가능으로 확정된다. 특히 1·5가 최우선(전자는 "휴지통이냐 영구냐"를 가르고, 후자는 중복방지 불변식 DEL-3의 근간).

1. **[최우선] Android 휴지통 경로.** photo_manager `PhotoManager.editor.deleteWithIds`가 Android 30+에서 `createTrashRequest`(휴지통)를 쓰는가, `createDeleteRequest`(영구)를 쓰는가? 만약 영구라면, C-5의 `MediaMoveHandler` 패턴대로 **네이티브 채널에 `trashAssets(ids)` → `createTrashRequest`를 신설**해야 한다. 신설 가능한가? 신규 `requestCode`(45317 이동/40071 photo_manager와 비충돌) 확보 가능한가?
2. **삭제 단일 동의창(배치).** 전체 삭제 예약을 **한 번의** `createTrashRequest(uris)` / iOS `deleteAssets([...])`로 묶어 동의창 **정확히 1회**가 되는가?(C-5 이동과 동일 패턴 기대)
3. **minSdk 확인.** 앱 `minSdkVersion`이 30(Android 11) 이상인가? (`02_integrator_notes` F.6에 "minSdk 대상 실기기(Android 11+)" 언급 있음.) ≥30이면 §5의 "Android 10 이하" 분기와 관련 폴백을 전부 삭제하고 설계 단순화.
4. **iOS 취소/실패 신호.** `deleteWithIds`(내부 `PHPhotoLibrary.performChanges`)에서 사용자가 시스템 확인창을 **취소**한 것과 실패를 구분할 수 있는가? `BatchDeleteResult.cancelled`로 매핑하려면 관측 가능한 신호(에러코드/completion 결과)가 필요.
5. **[최우선] 큐 트래시 제외 실측(불변식 DEL-3).** `loadUnclassifiedQueue()`(내부 `getAssetListPaged`)가 Android `IS_TRASHED=1` 자산과 iOS 최근삭제됨 자산을 **기본 제외**하는가? OEM(삼성 One UI 등)에서도 그러한가? 만약 일부 경로에서 트래시 자산이 큐에 뜨면 **Option A가 깨지므로**(삭제 id를 DB에 남겨야 함) 반드시 실기기 확인.
6. **캐시 무효화 실측.** 삭제(휴지통 이동) 후 F.3 지문의 "전체 자산수(`assetCountAsync`)"가 감소해 스캔 캐시가 미스→재스캔 되는가? 트래시가 카운트에서 빠지는지 확인.
7. **커밋 2연속 인텐트.** 한 세션에서 `createWriteRequest`(배정) 직후 `createTrashRequest`(삭제)를 연달아 `startIntentSenderForResult` 할 때 `MainActivity.onActivityResult` 라우팅이 두 requestCode를 정확히 분기하는가?(기존 위임 구조에 삭제 requestCode 추가)
8. **id 안정성(저순위).** iOS 삭제는 자산 소멸이라 무관. Android 트래시/복원 시 `_id` 변동은 Option A(삭제 id 미기록)라 영향 없음 — 참고만.

---

## 7. 열린 결정 (사용자 승인 필요)

> §1 추천안을 기본으로, 아래는 사용자가 명시 승인해야 확정된다(헌장: PRD/로드맵에 답 없는 파괴적 결정은 임의 확정 금지).

1. **복구 모델(Android).** 추천 = **휴지통(`createTrashRequest`, 30일 복구)**. 대안 = 영구삭제(`createDeleteRequest`). MVP 목적이 "눈앞에서 치우기"(≠저장공간 비우기)라 휴지통이 부합. → **휴지통으로 확정해도 되는가?**
2. **세션당 최대 2회 동의(Android).** 배정+삭제를 같이 한 세션은 commit 시 이동 동의창 1 + 삭제 동의창 1 = **2회**(플랫폼상 병합 불가). → **수용 가능한가?** (불가하면 "한 세션에 배정과 삭제를 섞지 않게" 유도하는 대안이 필요 — 비추천.)
3. **진입점 = 저강도 삭제 버튼.** 추천 = 하단 액션행 좌단의 축소·error색 버튼(+최초 1회 교육 시트). 스와이프 4번째 방향은 오삭제 위험으로 배제. → **버튼 방식 승인?**
4. **삭제만 한 세션의 streak 인정 여부.** streak 원천이 `ProcessedAsset.processedAt`이라, 삭제만 하고 배정 0인 세션은 현재 streak을 못 올린다. 추천 = **MVP는 배정 기준 유지**(삭제는 세션 내 보너스 액션, 순수 삭제 세션은 드물다고 가정). 대안 = 별도 `DeletedAssets(deletedAt)` 테이블로 streak에 합산(경미한 추가 구현). → **어느 쪽?**
5. **완료 화면 카운트 표기.** 추천 = 헤드라인 총계(배정+삭제) + 분해 라인("앨범 10 · 휴지통 2"). → **문구/표기 승인?**
6. **(integrator 확인 후) Android 10 이하 삭제 미노출.** minSdk<30이면 구버전에서 삭제 버튼 숨김. minSdk≥30이면 무의미. → §6-3 결과에 따라 자동 확정(사용자 승인 불요, integrator 확인 사항).

---

## 8. 작업 분해 (F-14 계열)

| ID | 작업 | 담당 | 의존 | 완료 기준 |
|----|------|------|------|-----------|
| **F-14a** | PhotoService 계약 확장 구현: `stageDeletion/unstageDeletion/pendingDeletions/commitDeletions` + `BatchDeleteResult`. Android 네이티브 `trashAssets(ids)`→`createTrashRequest`(MediaMoveHandler 확장, 신 requestCode), iOS 배치 `deleteWithIds`. 취소/실패 매핑. | platform-integrator | §6-1·2·4 해소 | 단일 동의창으로 배치 삭제, 취소=cancelled 매핑, 성공분 반환 |
| **F-14b** | 실현성 검토(§6 질문 답): 휴지통 여부·큐 트래시 제외(DEL-3)·minSdk·캐시무효화 실기기 확인 | platform-integrator | — | §6 8항 답변 → §7-1·2·6 확정 |
| **F-14c** | SortController 삭제 배선: `deleteCurrent`, `undo(wasDelete)`, `commit`에 `commitDeletions` 통합, `CommitOutcome`/`SortState` 확장, remaining 재계산 | feature-builder | F-14a | DEL-1·2·6 단위테스트 통과 |
| **F-14d** | SortScreen UI: 저강도 삭제 버튼, 최초 교육 시트(`hasSeenDeleteIntro`), 배너 "옮길 N·버릴 M", commit 버튼 카운트, 양 테마 | feature-builder (core-loop-ui) | F-14a, F-14c | §2 스펙대로 렌더·동작 |
| **F-14e** | DoneScreen 통계: 총계=배정+삭제, 분해 라인, 삭제 부분실패 배너 | feature-builder | F-14c | §2.6 표기 |
| **F-14f** | 분석 이벤트: `asset_deleted`(성공분마다 1회, 속성 없음) + `sort_session_complete`에 `deleted_count` 파라미터 추가 + 상수(`AnalyticsEvents/Params`) | feature-builder (monetization-and-analytics) | F-14c | 이벤트 발화·오타상수 단일출처 |
| **F-14g** | 불변식 검증(DEL-1~7), 특히 DEL-3/5 실기기(트래시 미재등장·복구 재등장), 2회 동의창 관찰 | qa-verifier | F-14a~f | §4 전 항목 PASS |
| **F-14h** | (선택) 릴리스 전 파괴적 작업 안전 최종 감사 | final-auditor | F-14g | 영구삭제 오경로·권한 누출 0 |

**의존 순서:** F-14b(실현성) ∥ F-14a(구현 착수) → F-14c → {F-14d, F-14e, F-14f} → F-14g → F-14h.
**착수 게이트:** §7-1·2·3 사용자 승인 + §6-1·5 integrator "휴지통·큐제외 가능" 확인 후 F-14a 코딩 시작.

---

### 부록 · 분석 이벤트 정의(F-12 계열)

```
asset_deleted              // 삭제 성공분마다 1회. 속성 없음(asset_skipped 와 동형). 사진 내용·id 미포함.
sort_session_complete { processed_count, remaining_unclassified, deleted_count(신규) }
```
- 프라이버시: 삭제 이벤트도 카운트만. 원본 id·내용 절대 미전송(기존 계약 준수).
- North Star("주간 정리 완료자")·세션 가치 산출 시 `deleted_count`를 정리량에 합산할지는 §7-4 결정과 연동.

---

## 9. 실현성 검토 결과 (platform-integrator · 2026-07-06)

> 검토 방법: 코드 수정 없이 pub 캐시의 photo_manager **3.9.0 소스**(Android Kotlin / iOS ObjC / Dart)와 앱 현행 코드를 직접 열람. 실기기 미연결 → 소스·플랫폼 문서 기반 판정 + "실기기 확인 필요" 명시.
> 근거 경로 약칭: `PM/` = `~/AppData/Local/Pub/Cache/hosted/pub.dev/photo_manager-3.9.0/`.

> **개정(2026-07-06, 2차):** 사용자가 §7을 확정 — **(1) 영구삭제(`createDeleteRequest`, 휴지통 미경유), (2) 즉시 실행(stage→commit 미적용, 삭제 탭마다 OS 동의창), (3) 저강도 버튼, (4) streak 삭제 인정(기록 테이블 추가)**. `00_decisions.md` D5 확정 반영. 아래는 이 확정 기준의 재검토다(초안 검토에서 "휴지통 전제"였던 항목을 전량 교체).

### 9.0 한 줄 결론

**착수 게이트 통과 — 영구+즉시 결정으로 구현이 오히려 단순해졌다.** photo_manager 3.9.0의 `PhotoManager.editor.deleteWithIds(ids)`가 Android에서 정확히 `MediaStore.createDeleteRequest`(**영구삭제**)를 호출하므로 **결정과 완전 일치, 네이티브 채널 신설 불필요·그대로 재사용**. 단 두 가지 제약이 남는다: **(A) minSdk=24라 API 24–29에서는 즉시-영구 삭제 경로가 photo_manager 내부에서 갈라진다**(§Q3), **(B) 삭제 탭당 OS 동의창 1회**는 photo_manager API 구조상 불가피(회피 불가, 결정에 이미 수용됨). 큐 재등장 문제는 Android 영구삭제로 소멸, iOS "최근 삭제됨"만 확인 필요 → **소스상 제외 확인됨**.

### 9.1 §6 질문별 답 (확정 기준 재검토, 근거 포함)

**Q1 [최우선·재정의] — deleteWithIds가 Android에서 `createDeleteRequest`(영구)를 쓰는가 → 그대로 재사용 가능한가**

**그렇다. 그대로 재사용.** Dart `PhotoManager.editor.deleteWithIds(ids)` → 채널 `deleteWithIds` → Android 네이티브 분기(`PM/android/.../core/PhotoManagerPlugin.kt:613-634`):

| API 레벨 | 호출 경로 | 실제 동작 | 근거 |
|---|---|---|---|
| **API 30+ (R+)** | `deleteManager.deleteInApi30(uris)` → `MediaStore.createDeleteRequest(cr, uris)` | **영구삭제** + 시스템 동의창 1회 | `PhotoManagerPlugin.kt:616-618`, `PhotoManagerDeleteManager.kt:109-121` |
| **API 29 (Q)** | `deleteManager.deleteJustInApi29(...)` → `cr.delete(uri)` (+ `RecoverableSecurityException` 시 per-item 동의) | 영구삭제(자산당 동의 가능성) | `PhotoManagerPlugin.kt:619-625`, `PhotoManagerDeleteManager.kt:146-191` |
| **API 28-** | `deleteManager.deleteInApi28(ids)` → `cr.delete(... _ID in (...))` | 영구삭제(동의창 없음) | `PhotoManagerPlugin.kt:626-628`, `PhotoManagerDeleteManager.kt:92-99` |

- **결론:** 결정 1(영구삭제)과 photo_manager 기본 `deleteWithIds`가 **정확히 일치**. `createTrashRequest`(휴지통)를 쓰는 별도 API(`moveToTrash`)는 **호출하지 않는다.** 커스텀 네이티브 채널·MediaMoveHandler 확장·신규 requestCode **전부 불필요.** F-14a의 Android 네이티브 작업 항목은 **삭제**하고 "Dart `deleteWithIds([id])` 호출"로 대체(초안 §3.3·§5·§6-1·§8 정정).
- **iOS 경로:** `deleteWithIds` → `PMManager.m:1267` → `performChanges` 안 `[PHAssetChangeRequest deleteAssets:]` → **시스템 확인창 강제 + "최근 삭제됨" 30일**. iOS는 영구삭제가 불가능(PhotoKit 한계)하여 항상 30일 복구 경유 → **플랫폼 비대칭은 결정에 이미 수용됨**(decisions D5-1). OS 표준 동의창이 안전장치.
- **취소/실패 신호(재정의된 Q4 통합):** 반환 = 성공 id 리스트. Android `deleteInApi30`은 RESULT_OK면 요청 ids 전량, 취소면 `[]`(`PhotoManagerDeleteManager.kt:81-90`). iOS는 success면 ids, 실패/취소면 `@[]`(`PMManager.m:1275-1281`). **즉시-단건 삭제에선 이 신호가 깔끔하다**: `deleteWithIds([id])` 반환이 `[id]` 포함 = 삭제됨(기록·index++·analytics), `[]` = 취소 또는 실패(카드 유지, "삭제되지 않았어요"). 취소와 실패를 구분할 필요가 없다(둘 다 "자산 그대로 → 그 자리 유지"). **초안 M3(cancelled 문구 통합)는 즉시 모델에서 자연 해소.**

**Q2 — 동의창 횟수 (재정의: 즉시 모델)**

즉시 실행이므로 **삭제 1건 = 동의창 1회**(배치 아님). `deleteWithIds([singleId])`가 매 탭 호출되어 `createDeleteRequest(단일 uri)` → 동의창 1회. 이는 결정 2에 **이미 수용된 트레이드오프**("단건마다 동의창 뜨는 트레이드오프 수용"). 세션 끝 배정 commit 동의창(이동 1회)은 그대로 유지 → 삭제 3건 + 배정 세션이면 동의창 = 삭제 3 + 이동 1 = 4회. **결정 문서와 일치**(배치 삭제로 줄이는 최적화는 결정이 "즉시"를 택해 의도적으로 포기). 소스 기준 확정, 실기기 관측은 잔여.

**Q3 — minSdk (영향 재평가)**

**minSdk = 24**(Android 7.0). 근거: `android/app/build.gradle.kts:28`(`minSdk = flutter.minSdkVersion`) + Flutter 기본값 `FlutterExtension.kt:26`(`minSdkVersion = 24`). override 없음.

- **영구삭제 결정에서 이 사실의 의미가 바뀐다(초안보다 완화):** 휴지통이라면 `createTrashRequest`가 API 30+ 전용이라 폴백이 필수였지만, **영구삭제 `deleteWithIds`는 API 24–29에서도 동작한다**(위 표: API29=`deleteJustInApi29`, API28-=`deleteInApi28`). 즉 **삭제 버튼을 구버전에서 숨길 필요가 없다** — 기능은 전 레인지에서 성립.
- **단, 동의 UX가 API 레벨별로 다르다(정직 보고):**
  - API 30+: 표준 삭제 동의창 1회(가장 매�us러움).
  - API 29: `cr.delete` 시도 → 대개 `RecoverableSecurityException` → **자산당 개별 동의창**(`AndroidQDeleteTask`, `PhotoManagerDeleteManager.kt:31-57,146-176`). 즉시-단건이라 탭당 1회로 자연 수렴하나, 첫 접근 시 권한 흐름이 다를 수 있음.
  - API 28-: 동의창 **없이** 즉시 영구삭제(`cr.delete` 직접). 파괴성이 가장 높음 — OS 안전장치 부재. **UX 경고 문구/최초 교육 시트를 이 레벨에서 특히 강조** 권장(단, 구형 기기 비중이 낮으면 우선순위 낮음).
- **권고:** minSdk 상향 불요(영구삭제는 24+ 동작). §5의 "API<30 삭제 미노출" 분기는 **폐기**(휴지통 전제였음). 대신 §5를 "API별 동의 UX 차이" 주석으로 교체. §7-6은 "삭제 전 레인지 노출, API28-는 무동의 즉시삭제 주의"로 확정.

**Q4 — 취소/실패 구분** → Q1에 통합(즉시-단건 모델에서 `[]`=미삭제로 일원화, 별도 이슈 아님).

**Q5 [축소] — iOS "최근 삭제됨" 자산이 onlyAll 큐에 노출되는가**

**Android는 문제 소멸**(영구삭제 → MediaStore에서 자산 제거 → `getAssetListPaged`에 원천적으로 없음 → 큐 재등장 불가). iOS만 확인 필요:

**iOS도 제외됨(소스 기준).** `loadUnclassifiedQueue`의 `getAssetPathList(onlyAll: true)`는 iOS에서 **`PHAssetCollectionSubtypeSmartAlbumUserLibrary`**(사용자 라이브러리)로 매핑된다(`PMManager.m:61`, `:243` `entity.isAll = ...SmartAlbumUserLibrary`). "최근 삭제됨"은 별도 스마트앨범(`SmartAlbumRecentlyDeleted`)이고, User Library fetch는 이를 **포함하지 않는다**(PhotoKit 기본: 삭제 요청된 자산은 일반 `PHFetchResult`에서 제외, `getAssetOptions`가 `includeAssetSourceTypes`/RecentlyDeleted를 명시 포함하지 않음 — `PMManager.m:1223+`). → iOS에서 `deleteAssets` 후 자산은 onlyAll 큐에 **재등장하지 않는다.** 30일 뒤 완전 소멸 또는 사용자가 "최근 삭제됨"에서 복원 시에만 라이브러리로 귀환(=재정리 대상, 바람직).

- **잔여 실기기 확인:** iOS 실기기에서 `deleteWithIds` 직후 재스캔 시 큐 미재등장 실측(소스상 PASS, 실기기 미연결).

**Q6 — 스캔 캐시 지문 상호작용 (즉시 삭제)**

성립하나 **서비스에서 명시적 캐시 무효화 필요**(한 줄 확인 요청 답). 영구삭제로 `assetCountAsync`(total)가 감소 → `_ScanSignature` 불일치 → 다음 `loadUnclassifiedQueue`가 캐시 미스로 재스캔(`photo_manager_photo_service.dart:96,104-107`)되므로 **자가 무효화는 된다.** 단 즉시 삭제는 세션 **도중** 발생하므로, 배정 commit이 하듯(`commitAssignments` 성공 시 `_queueCache = null`, `:180-182`) **삭제 메서드도 성공 시 `_queueCache = null`을 명시 호출**하도록 F-14a에 넣기를 권장(카운트 지문에만 의존하지 말고 명시 무효화 → 방어적). 세션 내 in-memory 큐(컨트롤러가 세션 시작 시 1회 로드)에는 영향 없음(삭제 대상=현재 카드, 이미 index 통과).

**Q7 [신규 확인] — 즉시 삭제와 진행 중 세션 상태 충돌**

- **큐 index:** 삭제=현재 카드 대상 → `deleteCurrent()`가 `deleteWithIds` 성공 후 `index++`(배정 `assignCurrent`와 동형). 미삭제(`[]` 반환)면 `index` 불변·카드 유지. 충돌 없음.
- **pending 배정과의 충돌(핵심 확인 요청):** 정상 흐름에선 현재 카드는 아직 배정 안 됨 → 삭제 대상이 `_pending`(배정 예약)에 있을 일은 없다. **그러나 방어적으로**, `deleteCurrent()`는 삭제 성공 시 **`unstageAssignment(assetId)`도 호출**할 것을 권장한다(만약 이전에 배정 예약했다가 되돌리기→다시 그 카드에서 삭제하는 경로 등 엣지에서, 세션 끝 `commitAssignments`가 이미 사라진 자산을 이동 시도 → `AssetEntity.fromId`가 null → `failed` 처리는 되지만 불필요한 실패 카운트/혼선 유발). **성공한 삭제 id는 pending 배정에서 즉시 제거**해 "삭제된 자산이 배정 커밋에 남는" 상태를 원천 차단.
- **remaining/통계:** 삭제분도 큐를 떠나므로 `remainingUnclassified` 계산에 `deletedSuccess`를 차감(초안 §3.4 유지, 단 "즉시"라 세션 누적 카운터로).

**Q8 — id 안정성**: 무관(삭제 id를 dedup DB에 안 남김). 참고만.

### 9.2 streak용 삭제 기록 최소 스키마 (결정 4)

**날짜(타임스탬프)만으로 충분. 자산 id 불요.** 근거:
- streak/North Star의 원천은 "그 날 정리 활동이 있었는가"(`ProcessedAsset.processedAt`의 날짜 집합). 삭제를 streak에 넣으려면 **삭제가 일어난 시각**만 있으면 된다.
- 자산 id를 저장할 이유가 없다: (a) **중복방지 재등장 방지 불요** — 영구삭제(Android)/최근삭제됨(iOS)은 자산이 큐에서 이미 사라짐(Q5). (b) **undo 불요** — 결정상 삭제엔 인앱 되돌리기 미적용(OS 동의창이 유일 확인). (c) **프라이버시** — id 미저장이 헌장의 "참조만·최소수집"에 부합.

권장 스키마(Drift):
```dart
// 삭제 활동(streak 집계 전용). 자산 id·내용 미저장 — 시각만.
class DeletedActivities extends Table {
  IntColumn get id => integer().autoIncrement()();      // 서러게이트 PK
  DateTimeColumn get deletedAt => dateTime()();          // 삭제 성공 시각(로컬)
}
```
- 삭제 1건 성공 = 1행 append(`deletedAt = DateTime.now()`). 배치 아님(즉시 모델).
- **streak 쿼리 =** `ProcessedAsset.processedAt`의 날짜집합 ∪ `DeletedActivities.deletedAt`의 날짜집합 → distinct day 기준 연속일 계산. (streak 로직이 날짜 집합만 받으면 원천 2개를 합치는 얇은 수정으로 끝.)
- `deleted_count` 분석 파라미터(부록)는 이 테이블의 세션 구간 count 또는 세션 인메모리 카운터로 산출(둘 다 가능, 인메모리가 더 쌈).
- 마이그레이션: 신규 테이블 추가 = 스키마 버전 +1(기존 `ProcessedAssets`/`Albums` 무변경, non-breaking). `app_database.dart`의 `schemaVersion` 상향 + `onUpgrade`에 `m.createTable(deletedActivities)`.
- **대안(기각):** 날짜별 count 집계 테이블(`DailyDeleteCount(day, count)`)은 조회는 싸지만 append마다 upsert 로직 필요 → MVP엔 append-only 행이 더 단순. 자산 id 포함안은 프라이버시·무용성으로 기각.

### 9.3 설계 수정 필요 항목 (확정 기준 최종)

| # | 대상 절 | 초안/현재 | 확정 반영 |
|---|---|---|---|
| M1 | §3.3, §5, §6-1, §8(F-14a) | 네이티브 trash 채널 신설 | **삭제.** `deleteWithIds([id])` 직접 재사용(영구삭제, 결정 일치). 네이티브·MainActivity 작업 0 |
| M2 | 3.x stage/commit(삭제) 전체 | 삭제도 stage→commit 배치 | **즉시 실행으로 교체.** `stageDeletion/unstageDeletion/pendingDeletions/commitDeletions`·`BatchDeleteResult` 폐기. 대신 `Future<bool> deleteImmediately(AssetRef)`(반환=삭제성공 여부) 단일 메서드. undo 미적용 |
| M3 | §5, §7-6 | API<30 삭제 미노출 | **폐기.** 영구삭제는 API24+ 동작 → 전 레인지 노출. §5는 "API별 동의 UX 차이(30+ 표준 / 29 per-item / 28- 무동의)" 주석으로 교체 |
| M4 | §3.1 데이터모델 | 스키마 무변경 | **`DeletedActivities` 테이블 추가**(§9.2). schemaVersion +1. streak 원천 2개 union |
| M5 | §3.4 컨트롤러 | `deleteCurrent`가 stage | **즉시 삭제로 교체**: `deleteWithIds` 성공 시 `DeletedActivities` append + `unstageAssignment(id)` 방어 호출 + `_queueCache=null` + index++. 실패/취소(`[]`)면 카드 유지 |

### 9.4 잔여 실기기 확인 항목 (현재 미연결)

- **iOS**: `deleteWithIds` 후 재스캔 시 자산이 onlyAll 큐에 미재등장(Q5, 소스상 PASS).
- **Android API 29 실기기**: `deleteWithIds`가 `RecoverableSecurityException` 경유 per-item 동의로 뜨는지, 즉시-단건에서 UX 수용 가능한지.
- **Android API 28- 실기기**: 무동의 즉시 영구삭제 실제 동작(파괴성 최고 — 교육 시트 강조 필요).
- **동의창 횟수**: 삭제 탭당 1회(즉시) + 배정 commit 1회 관찰(Q2).
- **Q6**: 세션 도중 삭제 후 다음 로드가 캐시 미스 재스캔 되는지(명시 무효화 반영 후).

### 9.5 착수 게이트 판정

- **결론: 착수 가능** ✅. 영구+즉시 결정은 photo_manager `deleteWithIds`와 **정확히 일치**하여 네이티브 작업이 사라졌고, 큐 재등장(DEL-3/5) 리스크가 Android에선 소멸, iOS는 소스상 제외 확인. 착수 리스크는 초안 대비 **낮음**.
- **코딩 착수 조건:** 위 M1~M5를 spec-architect가 §2·§3·§5에 반영(특히 stage→immediate 전환, `DeletedActivities` 테이블) → feature-builder 착수. 실기기 검증(§9.4)은 릴리스 전 게이트(F-14g)로 병렬.
- **프라이버시 확인:** 삭제 경로는 자산 참조(id)만 다루고 원본 바이트를 읽거나 내보내지 않음(`deleteWithIds`는 id 리스트만 전달). `DeletedActivities`도 시각만 저장 → 헌장 "참조만·최소수집" 준수.
