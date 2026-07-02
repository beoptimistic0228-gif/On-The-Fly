# 02 · 실현성 검토 (Feasibility — platform-integrator)

> 검토 대상: `01_architect_*` 4종 설계 + `photo-library-integration` 스킬.
> 관점: **Flutter + photo_manager로 실제 구현 가능한가**. 설계 단계 실현성 판정(구현 아님).
> 각 항목: **판정[가능/제약/불가] · 근거 · 설계 영향 · 우회/완화안**.
> 근거는 photo_manager 공식 README/문서 + Apple PhotoKit/Android Scoped Storage 실제 제약에 기반. (출처는 문서 맨 끝.)

---

## 결론 먼저 (3줄)

1. **iOS 쪽 설계는 대체로 실현 가능**(앨범 태깅·원본 유지·성공/실패 판별 OK). 단 **limited 접근**과 **백업복원 후 ID 불안정**이 구멍.
2. **Android 쪽 핵심 흐름(폴더 이동)은 설계대로는 불가에 가깝다.** photo_manager의 `copyAssetToPath`는 Android 11+에서 **조용히 실패**(성공 반환·실제 무동작)라 "성공→기록" 불변식을 깨고 유실을 만든다. 실제 이동은 **배치 + 사용자 동의창(write request)** 이어야 하고, 이는 **한 장씩 즉시 배정**하는 정리 UX와 충돌한다. → **설계 변경 필요**.
3. **Android는 이동 시 MediaStore ID가 바뀔 수 있어**(재색인/행 재삽입), ID 집합 기준 미분류 판별에 구멍이 난다(이동한 사진이 새 ID로 다시 미분류로 등장). → **설계 변경/보완 필요**.

---

## R1. [제약→부분 불가] Android 폴더 "이동" — 설계의 핵심 마찰점 ★최고위험

**판정**: 설계에 적힌 "한 장 스와이프 → 즉시 시스템 반영(폴더 이동) → 성공 시 기록"은 **Android 11+(API 30+)에서 photo_manager로 그대로는 실현 불가**.

**근거 (실제 API 제약)**
- `PhotoManager.editor.copyAssetToPath()`: **Android 11+에서 Scoped Storage 때문에 조용히 실패한다 — 성공처럼 반환하면서 실제로는 아무 것도 안 하고 예외도 안 던진다.** → 실패를 프로그램적으로 판별할 수 없음. (README/문서 명시)
- `PhotoManager.editor.android.moveAssetToAnother()`: 문서에 **"Android 30+에서는 시스템 제한으로 이 기능이 막혀 있음(currently blocked)"** 명시.
- Android 11+에서 **앱이 만들지 않은 미디어 파일**을 이동/수정하려면 `MediaStore.createWriteRequest()`(또는 create*Request) 로 **사용자 동의 IntentSender(시스템 팝업)** 가 필수. 카메라 사진은 앱 소유가 아니므로 항상 동의 필요.
- 실질적 경로는 photo_manager의 **배치형 write-request API(`moveAssetsToPath` 류)** 하나뿐. 이건 **여러 자산을 한 번에 묶어 동의창 1회**를 띄우는 모델.

**설계 영향**
- screens §3 "한 항목 처리 내부 순서"(스와이프→즉시 반영→성공 시 기록)와 tasks T4/T5의 **per-asset 원자적 반영 전제가 Android에서 성립하지 않음**. 동의창이 자산마다 뜨면 UX 파탄, 배치로 묶으면 "즉시 반영·즉시 기록"이 아님.
- `assignToAlbum(assetId, album)` 단건 시그니처(architecture §2.1)가 Android 현실과 불일치.

**우회/완화안 (2개)**
1. **[권장] 세션 배치 커밋 모델.** 스와이프 중에는 "이 자산 → 이 앨범"을 **로컬 pending 큐(메모리/DB의 임시 상태)** 에만 쌓고, 화면상 다음 카드로 넘어간다. 앨범 그룹별로 모아서 **세션 종료(또는 앨범 전환) 시 `moveAssetsToPath` 배치 1회 → 동의창 1회 → 반환된 성공 자산만 `markProcessed`.** 부분 실패분은 pending 유지(큐 잔존). 온보딩/정리 진입 시 "정리한 사진을 옮기려면 한 번 동의가 필요해요" 사전 안내로 마찰 완화.
   - 근거: write-request는 배치일수록 동의창 횟수↓. 성공/실패가 반환으로 판별되어 불변식 유지 가능.
   - 인터페이스 변경: `assignToAlbum` 단건 → `stageAssignment()`(즉시, 반영 안 함) + `Future<BatchAssignResult> commitAssignments()`(배치 반영·성공목록 반환)로 분리.
2. **[대안] "앨범 = 앱 소유 폴더로 복사 후 원본 유지" 모델(이동 포기).** 앱이 만든 하위 폴더(앱 소유)에는 write-request 없이 쓰기 가능. 단 이는 **원본 삭제가 아니라 사본 생성**이라 (a) 저장공간 2배, (b) "정리했다"는 물리적 실감이 약함, (c) 프라이버시 원칙엔 위배 안 되나 원본 삭제엔 또 동의창 필요. → iOS의 "태깅" 모델과 사실상 동일한 성격(원본 남음)이 되므로, **"Android도 이동이 아니라 태깅/사본"으로 제품 컨셉을 통일**하는 선택지. 제품 결정 필요.

> 두 우회안 모두 "카메라 원본을 조용히 다른 폴더로 옮긴다"는 기대를 **완전히는** 못 지킨다. 이건 photo_manager 한계가 아니라 **Android Scoped Storage 자체의 제약**이다.

---

## R2. [제약] Android 자산 ID가 이동 후 바뀔 수 있음 — 미분류 판별 구멍 ★고위험

**판정**: `AssetEntity.id`(Android=MediaStore `_ID`)는 **이동/재색인 시 변경될 수 있어**, "ID 집합 NOT IN" 기준 미분류 판별이 이동한 자산에서 깨질 수 있다.

**근거**
- Android `_ID`는 MediaStore DB의 행 식별자. 파일이 폴더 이동될 때 구현에 따라 (a) `RELATIVE_PATH`만 update(같은 id 유지) 또는 (b) 행 삭제+재삽입(**새 id 부여**)이 일어난다. OEM/스캐너/안드로이드 버전에 따라 (b)가 발생.
- 재부팅·미디어 재스캔·기기 초기화 후 복원 시에도 `_ID`는 재발급될 수 있음(영속 보장 없음). photo_manager 문서도 `fromId` 결과가 null일 수 있음을 경고.
- 결과: 이동으로 새 id가 붙으면 `새 id NOT IN ProcessedAsset` → **방금 정리한 사진이 다음 큐에 다시 등장**(datamodel §3 핵심 불변식 위반).

**설계 영향**
- datamodel §3 "미분류 = id NOT IN ProcessedAsset"이 **Android 이동 경로에서 자기모순**을 낳음(정리 = 이동 = id 변경 = 재등장).
- datamodel ⚠️2("ID 안정성 검증 필요")의 우려가 **iOS보다 Android에서 실제로 현실화**됨.

**우회/완화안 (2개)**
1. **[권장] 이동 반환 자산의 새 id를 기록.** 배치 이동 API(R1)가 반환하는 **이동 후 AssetEntity**의 id로 `markProcessed`한다(이동 전 id가 아니라). 즉 "성공적으로 옮겨진 그 자산의 현재 id"를 기록. 반환에 이동 후 엔티티가 없다면, 이동 직후 대상 앨범을 재조회해 매칭.
   - 근거: 재등장 방지는 "현재 라이브러리에 존재하는 id"와 대조하는 것이므로, 기록도 현재 id여야 함.
2. **[Android 한정 보조 신호] "이미 사용자 대상 앨범/폴더에 속함"을 2차 제외 필터로.** 불변식(스킬 원칙 1: OS 앨범 소속으로 판단 금지)은 **iOS 태깅 때문의 원칙**이다. Android는 "이동"이라 사용자가 만든 정리 폴더(=버킷)에 있으면 이미 정리된 것으로 봐도 논리적 모순이 적다. **iOS는 ID집합만, Android는 ID집합 + (앱이 만든 정리 앨범 버킷 소속) 보조 제외**로 플랫폼 분기.
   - 단, 이는 원칙의 플랫폼별 완화이므로 **spec-architect 승인 필요**(임의 결정 금지). datamodel §3에 "Android 예외" 명문화 요함.

---

## R3. [제약] iOS 자산 ID — 재설치는 OK, 백업복원/기기이전은 불안정

**판정**: iOS `localIdentifier`는 **앱 재설치 후에도 동일**(라이브러리 소유 식별자라 앱과 무관) → 재설치 자체엔 강함. 그러나 **iCloud/기기 복원·기기 이전 후에는 바뀔 수 있어** 저장된 id가 안 맞는다.

**근거**
- `localIdentifier`는 PHAsset의 기기 로컬 식별자. 같은 기기·같은 라이브러리 수명 동안은 안정적이라 앱 재설치와 무관하게 유지됨.
- 그러나 **iCloud 백업 복원/기기 마이그레이션 후 저장해둔 localIdentifier로 fetch하면 결과가 비는(no items)** 사례가 개발자 포럼·문서에 다수 보고. OS 대규모 업데이트 시 변동 보고도 있음. Apple은 이 때문에 `cloudIdentifiers(forLocalIdentifiers:)` 변환 API를 별도 제공.

**설계 영향**
- datamodel ⚠️2·⚠️3과 직접 연결. 다만 **MVP는 로컬 DB만**이라, 백업복원 시엔 어차피 **앱 DB(ProcessedAsset)도 함께 복원/유실**되므로:
  - 기기 백업으로 앱 데이터까지 복원 → DB의 옛 id vs 라이브러리 새 id **불일치** → 정리했던 사진 재등장(구멍 실재).
  - 앱 재설치(DB만 소실) → 어차피 처리기록 전무라 전부 재등장(datamodel ⚠️3에서 이미 감수 결정).

**우회/완화안 (2개)**
1. **[MVP 권장] 감수 + 고지.** 백업복원 후 일부 재등장 가능성을 온보딩/설정 프라이버시 안내에 짧게 명시("기기 복원 후 일부 사진이 다시 나타날 수 있어요"). 서버 없는 MVP 원칙과 정합. **사용자 승인 필요 신규 고지 항목.**
2. **[후순위] PHCloudIdentifier 매핑 저장.** cloudIdentifier를 보조 키로 저장해 복원 후 재매핑. 단 photo_manager가 이 API를 노출하지 않아 **커스텀 platform channel 필요(비용 큼)** → MVP Out, 백로그.

---

## R4. [가능] iOS 앨범 태깅 (원본 타임라인 유지)

**판정**: **가능.** photo_manager `editor`(iOS/darwin)의 `createAlbum` + `addAssetToAlbum`로 자산을 앨범에 **추가(태깅)**, 원본은 All Photos에 그대로 유지 — 설계 의도와 정확히 일치.

**근거**
- iOS PhotoKit의 `PHAssetCollectionChangeRequest.addAssets`는 앨범 "소속 추가"이며 원본은 라이브러리에 유지되는 표준 동작. photo_manager가 이를 래핑.
- 성공/실패가 반환으로 판별 가능 → "성공→기록" 불변식 유지 가능(R5 참조).

**설계 영향**: 없음(설계 그대로 진행 가능). 단 **전체 접근 권한 필요**(R6). limited 상태에서는 임의 자산의 앨범 관리가 제약됨.

**완화안**: createAlbum은 앱 내부 Album 행 생성 → 시스템 앨범 생성 → `systemAlbumRef`(PHAssetCollection.localIdentifier) 채움 순서(datamodel §2.2 nullable 설계와 일치)로 구현.

---

## R5. ["성공→기록" 트랜잭션] 플랫폼별 판별 가능성

**판정**: **iOS=가능, Android=조건부 가능(배치)** — 단 **`copyAssetToPath` 경로는 판별 불가라 금지**.

**근거·판별표**

| 경로 | 성공/실패 판별 | 불변식 적용 |
|------|----------------|-------------|
| iOS `addAssetToAlbum` | 반환으로 판별 O | 성공 시 `markProcessed` — OK |
| Android `copyAssetToPath` | **판별 불가**(11+에서 무동작·성공 반환) | **사용 금지**(유실 유발) |
| Android `moveAssetToAnother` | 30+에서 차단 | 사용 불가 |
| Android `moveAssetsToPath`(배치 write-request) | 동의 후 반환으로 판별 O(**단 자산 단위 결과 코드 확인은 구현 시 실검증 필요**) | 배치 성공분만 `markProcessed` |

**설계 영향**
- `AssignResult`(architecture §2.1) 단건 성공/실패 모델을 **배치 결과(성공 id 목록 / 실패 id 목록 / 사용자 취소)** 로 확장해야 Android를 담을 수 있음.
- screens §3의 "실패 시 인라인 토스트 + 큐 유지"는 **배치 커밋 실패/취소 시점**으로 이동. 스와이프 순간엔 아직 "확정 아님"임을 UX에 반영(예: 하단에 "옮길 3장 대기 중").

**완화안**: 계약을 `Future<BatchAssignResult commitAssignments(List<PendingAssignment>)`로. iOS 구현은 내부적으로 자산별 즉시 태깅을 배치로 감싸 동일 인터페이스 충족(플랫폼차는 구현체에 가둠 — architecture §5 원칙 유지).

---

## R6. [제약] iOS 제한 접근(limited) — 핵심 가치와 충돌

**판정**: limited 상태에서는 이 앱의 "미분류 전체를 훑어 정리"라는 전제가 **성립하기 어렵다**(선택된 사진만 보임).

**근거**
- iOS 14+ limited 접근은 **사용자가 고른 사진만** 앱에 노출. `getAssetPathList`/큐에 **전체 미분류가 안 잡히고**, 이후 새로 찍은 사진도 자동으로 안 들어옴.
- limited에선 임의 자산의 앨범 태깅도 제약(선택 범위 밖 자산 관리 불가). `presentLimited()`로 선택 확장은 되나, "매일 밀린 것 전부 정리"라는 UX와 상극.

**설계 영향**
- screens §1·§2, datamodel/스킬 권한 흐름에 이미 "전체 접근 권장"은 있으나, **limited를 '지원 degraded 모드'로 볼지 '기능 차단+안내'로 볼지 미결**(screens ⚠️3).

**우회/완화안 (2개)**
1. **[권장] 정리 기능은 전체 접근 필요로 명시.** limited면 정리 화면 진입 시 "전체 접근이 필요해요" 카드 + 설정 딥링크 + `presentLimited()` 재선택 안내. 큐는 비활성/제한 메시지.
2. **[대안] limited 부분 지원.** 보이는 선택분만 큐로 제공하고 "일부만 보임 · 더 추가" 배너 상시 노출. 구현 가능하나 제품 가치 훼손 + 혼란. → 비권장.
   - **사용자 승인 필요**: limited 정책(차단 안내 vs 부분 지원) 확정.

---

## R7. [가능·주의] 로컬 알림 지속성

**판정**: **가능.** `flutter_local_notifications` + `timezone` `zonedSchedule(matchDateTimeComponents: DateTimeComponents.time)`로 매일 반복. 단 플랫폼 설정 주의사항 있음.

**근거·주의**
- **Android 재부팅 지속**: `RECEIVE_BOOT_COMPLETED` 권한 + 플러그인 boot receiver 등록 필요(자동 아님). 누락 시 재부팅 후 스케줄 소실.
- **Android 12+ 정확 알람**: `SCHEDULE_EXACT_ALARM`/`USE_EXACT_ALARM` 필요. 매일 리마인더는 **inexact 허용**으로 두면 권한 회피 가능(정시 ±오차 감수). 제품상 리마인더라 inexact 권장.
- **Android 13+**: `POST_NOTIFICATIONS` 런타임 권한 별도 요청(온보딩 3스텝에 반영됨 — OK).
- **iOS**: 로컬 알림 자체는 지속. 권한 별도 요청 필요(설계 반영됨).

**설계 영향**: T8 완료 기준 "재부팅 후 유지"는 **Android 매니페스트/receiver 설정 없이는 미충족**. 구현 체크리스트에 명시 필요(설계 변경은 아님).

**완화안**: inexact 반복 알람 + boot receiver 등록을 기본값으로. 정확 시각이 꼭 필요하면 별도 권한 유도(비권장).

---

## R8. [가능] 미분류 큐 로드 · 페이지네이션 · 썸네일

**판정**: **가능.** `getAssetPathList` → `getAssetListPaged`(생성일 필터·페이징) + `thumbnailDataWithSize`로 설계대로 구현 가능. 대량 라이브러리도 페이지네이션으로 부드럽게(성능 NFR 충족 가능).

**근거**: photo_manager 표준 기능. datamodel §3.2 시간 프리필터 + ID 대조 확정 로직과 정합.

**설계 영향**: 없음. 단 R2(Android id 변경)로 인해 "ID 대조"의 신뢰성이 흔들리는 점만 R2에서 보완.

---

## 종합: 설계를 바꿔야 하는 항목 (spec-architect 회신 필요)

1. **[R1·R5] per-asset 즉시 반영 → 세션 배치 커밋으로 변경.** `assignToAlbum` 단건 계약을 `stageAssignment()` + `commitAssignments()→BatchAssignResult`로 분리. screens §3 "한 항목 처리 순서"와 tasks T4/T5 수정. Android 동의창(1회/배치) UX를 정리·완료 화면에 신설.
2. **[R2] datamodel §3 불변식에 "Android 예외" 명문화.** 기록 id = 이동 후 id, 그리고(선택) Android는 "앱이 만든 정리 앨범 소속"을 보조 제외 필터로 허용. **원칙 완화라 아키텍트 승인 필수.**
3. **[R6] limited 접근 정책 확정**(전체 접근 필수화 vs 부분 지원). screens ⚠️3 종결.
4. **[R5] `AssignResult` → 배치/부분성공 모델로 인터페이스 개정**(architecture §2.1).

## 사용자(제품) 승인이 필요한 신규 이슈

- **A. Android "이동 vs 사본" 컨셉 결정 (R1).** 진짜 이동은 배치+동의창이 불가피(마찰). 회피하려면 "앱 폴더로 사본 + 원본 유지"라 iOS 태깅과 동일 성격이 됨. **"그때그때"의 정리 = 물리 이동인가, 소속 태깅인가**를 제품 차원에서 통일할지 결정 필요.
- **B. 백업복원 후 재등장 고지 (R3).** "기기 복원/이전 후 일부 사진이 다시 미분류로 보일 수 있음"을 사용자에게 고지할지.
- **C. limited 접근 UX (R6).** 전체 접근 강제 안내로 갈지, 부분 지원할지.
- **D. Android 정시 알림 정확도 (R7).** inexact(권한 최소·±오차) 기본으로 갈지.

---

## 출처
- photo_manager 공식 문서/README (fluttercandies/flutter_photo_manager) — editor(copyAssetToPath/moveAssetToAnother/moveAssetsToPath), Android 30+ 제한, PermissionState/limited/presentLimited, AssetEntity.id·fromId 경고.
  - https://pub.dev/packages/photo_manager
  - https://github.com/fluttercandies/flutter_photo_manager
- Android Scoped Storage (createWriteRequest/createDeleteRequest 사용자 동의): https://source.android.com/docs/core/storage/scoped
- iOS localIdentifier 복원 불안정: https://developer.apple.com/forums/thread/105366 , https://www.swiftjectivec.com/icloud-photo-handling/
