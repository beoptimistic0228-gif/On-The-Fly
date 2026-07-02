---
name: photo-library-integration
description: 그때그때의 핵심·최고위험 연동을 구현할 때 사용. Flutter photo_manager로 iOS PhotoKit/Android MediaStore 사진 접근, 권한 흐름, "처리한 자산 ID" 중복방지 로컬 DB, 앨범 태깅(iOS)/폴더 이동(Android), 로컬 알림을 다룬다. platform-integrator 에이전트 전용.
---

# photo-library-integration — 사진 라이브러리 연동

이 앱의 심장이다. 여기서 정확성이 깨지면(중복 재등장, 미분류 오판) 제품이 무너진다.

## 핵심 불변식 (절대 원칙)
1. **미분류 판별 = 처리 ID 집합 기준.** OS 앨범 소속으로 판단 금지. iOS 앨범은 태그라 정리 후에도 자산이 All Photos에 남는다.
2. **참조만 저장.** 원본 바이트를 앱 저장소·서버로 복사/전송하지 않는다. `AssetEntity.id`만 DB에 남긴다.
3. **자산 ID 안정성 확인.** `AssetEntity.id`는 플랫폼별로 안정적이어야 재실행 시 매칭된다. 재설치/OS 재색인 케이스의 한계를 노트에 기록한다.

## 1. 권한 흐름
- `PhotoManager.requestPermissionExtend()`로 권한 요청. 상태: 허용/제한적(iOS limited)/거부.
- **iOS**: Info.plist에 `NSPhotoLibraryUsageDescription`(+ 필요 시 add-only 설명). 전체 접근 권장, limited면 안내.
- **Android**: API 레벨별 권한(33+ `READ_MEDIA_IMAGES`/`READ_MEDIA_VIDEO`). Scoped Storage 준수.
- 거부 시: 설정 앱으로 유도하는 안내 화면. 부분 접근도 흐름이 깨지지 않게.

## 2. 미분류 자산 로드
```
1) 처리 ID 집합 로드: SELECT id FROM ProcessedAsset  → Set<String>
2) PhotoManager.getAssetPathList(type: image+video) → 전체/최근 자산 순회
   - 성능: lastProcessedAt 이후 createDateTime 자산으로 1차 페이징(getAssetListPaged)
3) 필터: asset.id NOT IN 처리집합  → 미분류 목록
```
썸네일은 `asset.thumbnailDataWithSize`로 캐싱·페이지네이션(드론 라이브러리에서도 부드럽게 — PRD 성능 요구).

## 3. 앨범 배정 (플랫폼 분기)
- **iOS (태깅)**: 자산을 대상 앨범(`AssetPathEntity`)에 추가. 원본은 타임라인에 남는다(정상). "이동"이 아니라 "소속 추가"임을 UI/노트에 명확히.
- **Android (폴더 이동)**: MediaStore 기준 이동. photo_manager의 이동/복사 API 제약을 **실제로 검증**하고, 이동 시 사용자 동의 창(배치 승인)을 사전 안내. 이동 불가 케이스는 우회안(복사+표시)과 함께 보고.
- 새 앨범은 배정 중 인라인 생성 가능(F-04).

## 4. 처리 기록 & 중복방지
- 배정 성공 직후 `ProcessedAsset(id, processedAt, albumId)` INSERT. 실패 시 롤백(기록 안 함).
- 다음 로드에서 자동 제외 → 같은 자산 재등장 없음(F-06).

## 5. 로컬 알림 (F-02)
- `flutter_local_notifications` + `timezone`으로 매일 사용자 지정 시각 스케줄(`zonedSchedule`, `matchDateTimeComponents: time`).
- iOS/Android 알림 권한 별도 요청. 앱 재시작·재부팅 후 스케줄 유지 확인.

## 출력 계약 (feature-builder가 의존)
서비스 공개 인터페이스를 `_workspace/02_integrator_notes.md`에 명시:
- `Future<PermissionState> ensurePermission()`
- `Future<List<AssetEntity>> loadUnsorted({int page})`
- `Future<void> assign(AssetEntity asset, Album album)` (기록까지 원자적)
- `Future<Album> createAlbum(String name)`
- 반환 shape·null 규칙·에러 타입을 QA가 대조할 수 있게 문서화.

## 검증 포인트 (QA에 넘길 것)
- 배정한 자산이 `loadUnsorted` 재호출에서 빠지는가.
- iOS에서 원본이 타임라인에 남아도 미분류 목록에 다시 안 뜨는가.
- 권한 거부/제한 상태에서 크래시 없이 안내로 이어지는가.
