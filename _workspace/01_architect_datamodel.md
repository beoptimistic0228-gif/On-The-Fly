# 01 · 데이터 모델 (Local Data Model)

> SSOT: `그때그때_PRD_v1.0.md` 9절 + CLAUDE.md 기술 가드레일.
> **가장 중요한 경계 계약**: 아래 "미분류 필터 규칙"은 platform-integrator와 feature-builder가 반드시 동일하게 구현해야 하는 단일 진실이다. QA는 이 규칙을 검증 기준으로 삼는다.

---

## 결론 먼저 (3줄)
1. **원본 사진·영상은 절대 저장하지 않는다.** 로컬 DB엔 "처리한 자산의 ID"와 "앨범 참조"만 저장한다(프라이버시 = 핵심).
2. **테이블 2개**: `ProcessedAsset`(처리 기록) + `Album`(로컬 앨범 참조/캐시).
3. **미분류 판단은 OS 앨범 소속이 아니라 `ProcessedAsset.id` 집합 기준.** iOS 앨범은 "태그"라 정리 후에도 원본이 타임라인에 남기 때문.

---

## 1. 저장 원칙 (프라이버시)
- 저장하는 것: **자산 ID(플랫폼이 주는 식별자)**, 처리 시각, 배정 앨범 참조, 앨범 메타.
- 저장하지 않는 것: **사진·영상 바이너리, 썸네일 영구본, 위치/EXIF 등 원본 데이터**.
- 썸네일은 `photo_manager`가 실시간으로 라이브러리에서 읽어와 **메모리/디스크 캐시**로만 다룬다(영구 사본 아님).

---

## 2. 스키마 (Drift / SQLite — **확정**, 00_decisions D3)

> 용어 풀이: **Drift** = SQLite(폰에 내장된 작은 관계형 DB)를 Dart에서 타입 안전하게 쓰게 해주는 라이브러리. C#의 EF Core와 비슷한 느낌(쿼리를 코드로, 컴파일 때 검증).

### 2.1 `ProcessedAsset` — 처리한 자산 기록 (중복 방지의 핵심)
| 필드 | 타입 | 제약 | 설명 |
|------|------|------|------|
| `id` | String | **PK** | 플랫폼 자산 ID (iOS `PHAsset.localIdentifier` / Android MediaStore ID). photo_manager의 `AssetEntity.id`. **Android는 이동 후 최종(재발급된) assetId를 기록**(D1, 재등장 방지) |
| `processedAt` | DateTime | NOT NULL, index | 처리(배정) 완료 시각. "마지막 처리 이후" 계산·streak에 사용 |
| `albumId` | String | FK → Album.id, NOT NULL | 어느 앨범에 배정했는지 |
| `mediaType` | int | NOT NULL | 0=사진, 1=영상 (통계·표시용, 선택적) |

인덱스: `processedAt`(범위 조회), `albumId`(앨범별 집계).

### 2.2 `Album` — 로컬 앨범 참조/캐시
| 필드 | 타입 | 제약 | 설명 |
|------|------|------|------|
| `id` | String | **PK** | 앱 내부 앨범 ID(UUID) |
| `name` | String | NOT NULL | 사용자가 지은 앨범명 |
| `systemAlbumRef` | String? | nullable | 실제 시스템 앨범 식별자(iOS PHAssetCollection localIdentifier / Android 폴더 경로·버킷 ID). 시스템 반영의 목적지 |
| `coverAssetId` | String? | nullable | 커버 썸네일로 쓸 자산 ID(원본 아님, 참조만) |
| `updatedAt` | DateTime | NOT NULL | 정렬(최근 사용 순)·동기화용 |

> **왜 `systemAlbumRef`가 nullable인가**: 새 앨범을 앱에서 만들 때, 먼저 로컬 Album 행을 만들고 → 시스템에 실제 앨범/폴더를 생성한 뒤 그 참조를 채운다. 생성 직후 짧은 순간 null일 수 있다.

### 2.3 관계
```
Album 1 ──< ProcessedAsset   (한 앨범에 여러 처리 자산; albumId FK)
```
- **다중 배정 없음**(PRD 8절 Out of Scope) → ProcessedAsset은 albumId 하나만.
- **중첩 폴더 없음** → Album에 parentId 없음(평면 구조).

---

## 3. 미분류 필터 규칙 ★ (가장 중요 — 명문화)

> **정의**: `미분류 = (현재 플랫폼 라이브러리의 모든 자산) 중, id가 ProcessedAsset.id 집합에 없는 것.`
>
> 즉 `assetId NOT IN (SELECT id FROM ProcessedAsset)`.

### 3.1 반드시 지킬 것
- **OS의 앨범 소속 여부로 판단하지 않는다.** iOS는 앨범이 "태그"라, 앨범에 담아도 원본이 전체 타임라인(및 다른 앨범)에 그대로 남는다. OS 상태로 "정리됨"을 판단하면 이미 처리한 사진이 다음 날 또 뜬다.
- **최종 판별 기준은 언제나 `ProcessedAsset.id` 집합.** 시간 필터는 프리필터(§3.2)일 뿐, 최종 판별은 처리 ID 집합 대조로 확정한다.

### 3.1.1 Android ID 재발급 대응 (D1 확정 — 유실·재등장 방지) ★
> Android는 정리가 **실제 폴더 이동**이라, 이동 시 MediaStore `_ID`가 **재발급**될 수 있다(OEM/스캐너에 따라 행 삭제+재삽입). 이동 전 id로 기록하면 이동된 사진이 **새 id로 다시 미분류에 등장**한다(§3 불변식 자기모순).
- **기록 id = 이동 후 최종 assetId.** commit(배치 이동)이 반환한 이동 후 자산의 현재 id로 `markProcessed`한다(이동 전 id 아님). 반환에 이동 후 엔티티가 없으면 대상 앨범 재조회로 매칭.
- 이 규칙은 iOS(태깅=id 불변)에는 영향 없다. **최종 판별은 두 플랫폼 공통으로 처리 ID 집합 기준**을 유지한다.

### 3.2 성능 최적화(허용, 단 판별의 대체가 아님)
- **1차 범위 좁히기**: `마지막 처리 시각(max(processedAt)) 이후 생성된 자산`으로 스캔 범위를 먼저 줄일 수 있다(photo_manager의 생성일 필터/페이지네이션).
- 하지만 이 시간 필터는 **성능용 프리필터일 뿐**, 최종 미분류 여부는 항상 ID 집합 대조로 확정한다.
  - 이유: 사용자가 과거 사진을 나중에 라이브러리에 추가(에어드롭/다운로드)하면 생성일이 과거라 시간 필터에 안 걸릴 수 있음 → 그래서 시간 필터는 "빠른 1차", ID 대조가 "정답".

### 3.3 의사코드 (platform-integrator ↔ feature-builder 공통 계약)
```dart
// core/photo 서비스가 제공, feature/home·sort가 소비
Future<List<AssetRef>> loadUnclassifiedQueue() async {
  final DateTime? since = await db.lastProcessedAt();      // 성능 프리필터(nullable)
  final assets = await photo.fetchAssets(createdAfter: since); // 1차 범위
  final processedIds = await db.processedIdSet();          // Set<String>
  return assets.where((a) => !processedIds.contains(a.id)).toList(); // 최종 판별
}
```

### 3.4 엣지 케이스
| 상황 | 처리 |
|------|------|
| 사용자가 갤러리에서 사진 직접 삭제 | 큐 로드 시 라이브러리에 없으므로 자연히 안 뜸. ProcessedAsset 잔재는 무해(참조만) |
| 같은 사진 재추가(같은 ID) | 이미 ProcessedAsset에 있으면 미분류 아님 |
| 건너뛰기(F-11) 항목 | **ProcessedAsset에 기록하지 않는다** → 다음 큐에 다시 등장. (건너뛰기 = 미처리) |
| 스와이프만 하고 commit 안 함 | 배정은 **stage(임시)** 상태일 뿐 → ProcessedAsset 미기록 → 다음 큐에 다시 등장(commit 전엔 미처리) |
| commit 부분 실패/취소(F-05) | **성공분만** `markProcessed`, 실패·취소분은 stage 큐에 유지(유실 방지). 사용자 동의창 취소 시 전량 미반영 |
| Android 이동 후 id 재발급 | 이동 후 최종 id로 기록(§3.1.1) → 재등장 방지 |
| 큐-실제 어긋남(PRD 리스크) | 기준이 "앱 처리 여부"임을 고수. 필요 시 재동기화는 ID 집합 재대조로 |

---

## 4. 파생 데이터 (저장 안 함, 계산으로)
| 값 | 계산 방법 |
|----|----------|
| 오늘 미분류 N장 | `loadUnclassifiedQueue().length` |
| streak(연속일수) | `ProcessedAsset.processedAt`의 날짜 집합에서 연속 일 계산 |
| 세션당 정리 매수 | 세션 시작~완료 사이 기록된 ProcessedAsset 수 (F-12 분석 이벤트) |

---

## 7. 데이터 흐름 — 배치 스테이징 → 확정 (D1 확정) ★ 가장 중요

> 기존 "스와이프 → 즉시 앨범 복사/이동 → 즉시 기록" 흐름은 **폐기**. Android Scoped Storage에서 per-asset 즉시 이동이 불가(동의창 남발·`copyAssetToPath` 조용한 실패, 02_feasibility R1/R5)하기 때문. 아래 **stage → commit** 흐름으로 전면 교체한다.

### 7.1 단계 정의
```
[스와이프]  = 배정 예약(stage)
             └ "이 assetId → 이 albumId"를 메모리/임시 상태(PendingAssignment 큐)에만 쌓음.
               ProcessedAsset·시스템 라이브러리 반영 없음. 다음 카드로 즉시 진행. Undo 가능.

[세션 끝]   = commit (배치 확정)
             ├ Android : 시스템 동의창(write request) 1회 → 배치 이동(moveAssetsToPath)
             └ iOS     : 앨범 태깅 즉시 반영(동의창 없음), UX 일관성 위해 동일 commit 경로 사용

[commit 결과] = BatchAssignResult (성공 id 목록 / 실패 id 목록 / 사용자 취소)
             ├ 성공분만 ProcessedAsset 기록
             │   └ Android : 이동 후 최종 assetId로 기록(§3.1.1)
             │   └ iOS     : 태깅된 자산의 id(불변)로 기록
             └ 실패·취소분 : stage 큐(PendingAssignment)에 유지 → 재시도/다음 commit 대상
```

### 7.2 불변식 (QA 검증 기준)
- **stage ≠ 처리**: stage만 된 자산은 아직 미분류(ProcessedAsset 미기록). commit 성공이 유일한 "처리" 확정 트리거.
- **성공→기록 원자성**: commit이 반환한 **성공 id에 한해서만** `markProcessed`. 시스템 반영 안 된 자산이 기록되어 유실되는 일이 없어야 함.
- **부분 성공 허용**: commit은 성공 N / 실패 M로 갈릴 수 있다(동의창 부분 승인·이동 실패). 실패분은 큐 잔존, UI는 성공 N/실패 M을 표시.

### 7.3 의사코드 (platform-integrator ↔ feature-builder 공통 계약)
```dart
// 스와이프 중: 즉시 반영 없이 예약만
void onSwipe(AssetRef a, AlbumRef album) {
  pending.stage(a.id, album);        // 메모리/임시 큐. 시스템 반영·기록 없음
}

// 세션 종료(큐 소진 또는 사용자가 commit): 배치 확정
Future<void> commitSession() async {
  final BatchAssignResult r = await photo.commitAssignments(); // Android=동의창1회 배치이동 / iOS=즉시태깅
  for (final s in r.succeeded) {     // s.finalAssetId = 이동 후 최종 id(Android) / 불변 id(iOS)
    await db.markProcessed(assetId: s.finalAssetId, albumId: s.albumId, mediaType: s.mediaType);
  }
  // r.failed / r.cancelled 는 pending 큐에 유지 → 재시도
}
```

---

## 확정/감수 사항 (00_decisions 반영)
1. **로컬 DB = Drift(SQLite) 확정**(D3). 더 이상 대안 검토 없음.
2. **자산 ID 안정성**: iOS `localIdentifier`는 재설치엔 안정, 백업복원/기기이전 후 변동 가능(02_feasibility R3). Android는 이동 시 id 재발급 가능 → **이동 후 최종 id 기록으로 대응(§3.1.1 확정)**. 백업복원 후 일부 재등장은 **감수 + 고지**(D 미결, 고지 문구로 완화).
3. **앱 재설치/백업복원 시 데이터**: 로컬 DB 소실 시 처리 기록도 사라져 "이미 정리한 것"이 다시 미분류로 뜸. MVP는 로컬 전용(백엔드 없음) 확정이므로 **감수**, 온보딩/설정 프라이버시 안내에 짧게 고지.
