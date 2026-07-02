# 01 · 작업 분해 (Task Breakdown)

> SSOT: `그때그때_PRD_v1.0.md` 6절(F-01~F-13). 각 태스크: **담당 에이전트 / 의존 태스크 / 완료 기준(수용 조건)**.
> 담당: **PI** = platform-integrator(core 서비스·플랫폼 API), **FB** = feature-builder(화면·상태·UI). 일부는 협업.
> 우선순위: **핵심 루프(F-01~F-06) 최우선 → 온보딩(F-07) → 영상/분석(F-08,F-12) → 부가(F-09~F-11,F-13)**.

---

## 결론 먼저 — 구현 순서 그래프

```
T0(스캐폴딩)
  └ T1(DB/Drift) ─┬─ T2(PhotoService: 미분류큐 F-01)
                  │       └ T3(앨범 생성/목록 F-04) ─ T4(시스템반영 F-05)
                  │                                         └ T5(처리기록 F-06)
                  ├────────────────── T6(정리 스와이프 UI F-03) ── T7(앨범선택 모달 F-04)
                  ├─ T8(알림 F-02)
                  └─ T9(홈 F-01표시)
T2..T9 ─ T10(완료화면 F-05완결) ─ T11(온보딩 F-07)
그 후: T12(영상 F-08) · T13(분석 F-12) · T14(광고 F-09) · T15(IAP F-10) · T16(건너뛰기 F-11) · T17(프라이버시 F-13)
```

---

## Phase 0 — 기반 (핵심 루프 착수 전 필수)

### T0. 프로젝트 스캐폴딩
- **담당**: PI · **의존**: 없음
- **내용**: `flutter create`, pubspec에 확정 패키지 추가(riverpod, drift, photo_manager, flutter_local_notifications, timezone, go_router), 폴더 구조(`core/`, `features/`) 생성, `ProviderScope`·`MaterialApp.router` 뼈대.
- **완료 기준**: 빈 앱이 iOS·Android에서 빌드·실행됨. `core/`·`features/` 폴더와 라우터가 홈 placeholder를 띄운다. CLAUDE.md "개발 환경 & 명령어" 채워짐.

### T1. 로컬 DB (Drift) — 스키마
- **담당**: PI · **의존**: T0
- **관련 F**: (기반, F-06 토대) · **문서**: `01_architect_datamodel.md`
- **내용**: `ProcessedAsset`, `Album` 테이블 + DAO(`processedIdSet`, `lastProcessedAt`, `markProcessed`, `streakDays`, `listAlbums`).
- **완료 기준**: 두 테이블 생성/마이그레이션 동작. DAO 단위 테스트 통과. `ProcessedRepository` 인터페이스(§2.2) 충족. Android 기록 id는 이동 후 최종 id를 저장(datamodel §3.1.1).
- **확정**: DB = Drift(D3). 착수 차단 없음.

---

## Phase 1 — 핵심 루프 (F-01~F-06) ★ 최우선

### T2. PhotoService — 미분류 큐 생성 (F-01)
- **담당**: PI · **의존**: T1
- **완료 기준**: 권한 허용 시 `loadUnclassifiedQueue()`가 **datamodel §3 규칙**대로 `id NOT IN ProcessedAsset` 자산만 반환. 시간 프리필터는 성능용, 최종은 ID 대조. 대량 라이브러리에서 페이지네이션 동작.
- **⚠️ 조기 검증**: `AssetEntity.id` 안정성(재설치/복원 후) — datamodel ⚠️2.

### T3. PhotoService — 앨범 생성·목록 (F-04, core측)
- **담당**: PI · **의존**: T2
- **완료 기준**: `createAlbum(name)`이 시스템 앨범(iOS)/폴더(Android)를 만들고 `AlbumRef.systemAlbumRef` 채움. `listAlbums()`가 평면 목록 반환(중첩 없음).

### T4. PhotoService — 배치 스테이징 + 확정 반영 (F-05, D1)
- **담당**: PI · **의존**: T3
- **내용**: `stageAssignment`/`unstageAssignment`/`pendingAssignments`(즉시 반영 없는 예약) + `commitAssignments()`(배치 확정). 플랫폼 차이는 구현체에 캡슐화(architecture §2.1, §5).
- **완료 기준**:
  - `stageAssignment`는 시스템 반영·기록 없이 예약 큐에만 쌓음(즉시 반영 아님).
  - `commitAssignments()`가 iOS=앨범 태깅 즉시 / Android=시스템 동의창 1회 후 배치 이동(`moveAssetsToPath`)을 **실제 라이브러리에 반영**.
  - 결과를 `BatchAssignResult`(성공 목록[이동 후 최종 id 포함]/실패 목록/사용자 취소)로 명확히 반환. **`copyAssetToPath` 경로 사용 금지**(조용한 실패, 02_feasibility R5).
  - 실패·취소분은 예약 큐에 유지.

### T5. 처리 완료 기록 (F-06, commit 성공분)
- **담당**: PI · **의존**: T4, T1
- **완료 기준**: `commitAssignments()`가 반환한 **성공분(`BatchAssignResult.succeeded`)에 한해서만** `markProcessed`(Android는 이동 후 최종 id로). 기록된 자산은 다음 `loadUnclassifiedQueue`에서 제외됨(통합 테스트로 검증). 실패/취소분은 기록 안 함 → 예약/큐 유지. stage만 되고 commit 안 된 자산도 미기록(다음 큐 재등장).

### T6. 정리(스와이프) UI — stage→commit (F-03, D1)
- **담당**: FB · **의존**: T2(큐), 인터페이스 합의(architecture §2)
- **완료 기준**: 한 손 스와이프로 항목 **배정 예약(stage)**/건너뛰기, 예약 후 다음 항목 자동 이동. "옮길 N장 대기 중" 스테이징 상태 표시. [정리]=commit 버튼(또는 큐 소진 시 자동 commit). commit 결과(성공 N/실패 M/취소)를 UI에 반영(실패분 큐 유지). Undo=예약 취소. screens §3 상태(로딩/정상/commit중/부분성공/취소/에러) 렌더. 스와이프 매핑은 잠정값으로 구현 후 조정.

### T7. 앨범 선택 모달 (F-04, UI측)
- **담당**: FB · **의존**: T3, T6
- **완료 기준**: 기존 앨범 리스트 + [+ 새 앨범] 즉석 생성. 선택 시 정리 화면으로 앨범 전달 → **stage 예약** 트리거(즉시 반영 아님, commit에서 확정). 빈/로딩/에러 상태(screens §4).

### T8. 매일 알림 (F-02)
- **담당**: PI(스케줄) + FB(시간 설정 UI) · **의존**: T0
- **완료 기준**: 설정 시간에 로컬 알림 발송(timezone 반영). 시간 변경 시 재스케줄. 앱 재부팅 후에도 유지.

### T9. 홈 화면 (F-01 표시)
- **담당**: FB · **의존**: T2, T5(streak)
- **완료 기준**: "오늘 미분류 N장" + streak + [정리 시작]. 상태 4종(로딩/정상/빈/에러). 재진입 시 큐 재계산(screens §2).

### T10. 완료 화면 (핵심 루프 마감, F-05 여정 완결)
- **담당**: FB · **의존**: T5, T9
- **완료 기준**: "정리 완료! N장"(**N = commit 성공분 기준**) + streak 갱신 + [홈으로]. 부분 성공 시 "M장 다시 시도" 보조 안내. (광고/IAP 슬롯은 자리만, T14/T15에서 채움). 큐 소진 → commit 완료 시 정리→완료 자동 전이(commit 결과 전달).

> **여기까지 = MVP 핵심 여정 end-to-end 동작**(온보딩 제외). CLAUDE.md 골든룰 3 충족.

---

## Phase 2 — 온보딩 (F-07)

### T11. 온보딩 플로우 (F-07)
- **담당**: FB(UI) + PI(권한 API) · **의존**: T2(사진권한), T8(알림권한/시간)
- **완료 기준**: 가치소개 → 사진권한 → 알림권한+시간 → 첫 정리 유도까지 매끄럽게. 권한 거부 처리 + **제한(limited) 접근 시 전체 접근 유도**(부분 접근 정리 미지원, D2)(screens §1). 완료 시 `onboardingCompleted` 저장 → 다음 실행부터 홈 진입.

---

## Phase 3 — 필수 부가 (P0: 영상·분석)

### T12. 영상 지원 (F-08)
- **담당**: PI(썸네일/재생 핸들) + FB(UI) · **의존**: T6
- **완료 기준**: 영상 썸네일 + 길이 표시, 탭 시 간이 재생. 풀 플레이어·편집 없음(Out of Scope 준수).

### T13. 분석 이벤트 (F-12) — P0
- **담당**: PI(서비스) + FB(호출 지점) · **의존**: T5, T10
- **완료 기준**: **Firebase Analytics** 기반 `AnalyticsService`로 앱오픈·세션완료(commit 성공 매수)·배정 이벤트 수집 → North Star(주간 정리 완료자)·D7·세션당 감소 산출 가능.
- **확정**: 분석 SDK = Firebase Analytics(D3). 착수 차단 없음.

---

## Phase 4 — P1 부가

### T14. 광고 (F-09)
- **담당**: PI(AdService·정책) + FB(완료화면 슬롯) · **의존**: T10
- **완료 기준**: **첫 정리일 +7일 경과** & 미구매 & 세션1회일 때만, 완료 축하 **뒤** 전면광고 1회. 정리 중·사진 사이 노출 없음. `shouldShowAd()` 정책 한 곳 캡슐화.
- **확정**: 광고 SDK = AdMob(`google_mobile_ads`), 노출 트리거 = 첫 정리일 +7일(D3). 착수 차단 없음.

### T15. 광고 제거 IAP (F-10)
- **담당**: PI · **의존**: T14
- **완료 기준**: 일회성 구매로 광고 영구 제거, 구매 복원 동작. 구매 시 `shouldShowAd()`가 false.
- **확정**: IAP 래퍼 = 공식 `in_app_purchase`(D3). 착수 차단 없음.

### T16. 건너뛰기 / 나중에 (F-11)
- **담당**: FB · **의존**: T6
- **완료 기준**: 건너뛴 항목은 ProcessedAsset에 기록 안 함 → 다음 큐에 다시 등장(datamodel §3.4).

### T17. 프라이버시 안내 (F-13)
- **담당**: FB · **의존**: T11, 설정화면
- **완료 기준**: "사진·영상은 폰 밖으로 나가지 않음"을 온보딩·설정에 명시(screens §1,§6).

---

## 담당·의존 요약표

| Task | F | 담당 | 의존 | Phase |
|------|---|------|------|-------|
| T0 스캐폴딩 | — | PI | — | 0 |
| T1 DB | — | PI | T0 | 0 |
| T2 미분류큐 | F-01 | PI | T1 | 1★ |
| T3 앨범 생성/목록 | F-04 | PI | T2 | 1★ |
| T4 시스템반영 | F-05 | PI | T3 | 1★ |
| T5 처리기록 | F-06 | PI | T4,T1 | 1★ |
| T6 스와이프 UI | F-03 | FB | T2 | 1★ |
| T7 앨범 모달 | F-04 | FB | T3,T6 | 1★ |
| T8 알림 | F-02 | PI+FB | T0 | 1★ |
| T9 홈 | F-01 | FB | T2,T5 | 1★ |
| T10 완료 | F-05 | FB | T5,T9 | 1★ |
| T11 온보딩 | F-07 | FB+PI | T2,T8 | 2 |
| T12 영상 | F-08 | PI+FB | T6 | 3 |
| T13 분석 | F-12 | PI+FB | T5,T10 | 3 |
| T14 광고 | F-09 | PI+FB | T10 | 4 |
| T15 IAP | F-10 | PI | T14 | 4 |
| T16 건너뛰기 | F-11 | FB | T6 | 4 |
| T17 프라이버시 | F-13 | FB | T11 | 4 |

> **Out of Scope(PRD 8절)** — 삭제·중복정리 / 태그 / AI 그룹핑 / 중첩폴더 / 다중배정 / 통계 / 계정·클라우드 = **태스크 없음(구현 금지)**.

---

## 확정 사항 (00_decisions — 착수 차단 없음)
1. **DB = Drift**(D3). ✅
2. **분석 SDK = Firebase Analytics**(D3). ✅
3. **광고 SDK = AdMob + 노출 트리거 = 첫 정리일 +7일**(D3). ✅
4. **IAP 래퍼 = 공식 in_app_purchase**(D3). ✅
5. **정리 반영 = stage→commit 배치 모델**(D1), **제한 접근 = 전체 접근 유도**(D2). ✅

### 남은 미결(구현 중 조정 — 착수 차단 아님)
- **스와이프 방향 매핑** — T6 잠정 구현 후 손맛 테스트로 확정(00_decisions 미결).
- **백업복원 후 재등장** — 발생 시 고지 문구로 완화(감수).
