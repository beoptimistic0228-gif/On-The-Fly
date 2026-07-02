---
name: flutter-app-design
description: 그때그때 PRD를 Flutter 구현 설계로 변환할 때 사용. 화면 스펙, 로컬 데이터 모델, 앱 아키텍처(폴더 구조·상태관리·패키지 선정), F-01~F-13 작업 분해를 산출한다. spec-architect 에이전트가 설계 단계에서 반드시 사용.
---

# flutter-app-design — 그때그때 Flutter 설계

PRD를 "바로 짤 수 있는 설계"로 내린다. 산출물은 4개 파일(`_workspace/01_architect_*.md`).

## 1. 권장 기술 선택 (근거와 함께 제시, 사용자 승인 후 확정)

| 영역 | 권장 | 이유 | 대안 |
|------|------|------|------|
| 상태관리 | **Riverpod** | 테스트 쉽고 전역/지역 상태 깔끔, 보일러플레이트 적음 | Provider(더 단순), Bloc(과함) |
| 로컬 DB | **Drift** (SQLite) | 타입 안전, 쿼리 컴파일 검증. `ProcessedAsset` 조회가 빈번 | sqflite(가벼움), Isar(NoSQL) |
| 사진 접근 | **photo_manager** | iOS PhotoKit / Android MediaStore를 한 API로. 앨범 생성·자산 이동 지원 | 직접 플랫폼 채널(비권장) |
| 알림 | **flutter_local_notifications** + timezone | 서버 없이 매일 정시 로컬 알림 | — |
| 라우팅 | **go_router** | 선언형, 온보딩 분기 처리 쉬움 | Navigator 2.0 수동 |

> 사용자는 Flutter 초심자다. 각 선택을 한 줄로 쉽게 설명하고, 왜 이 앱에 맞는지 근거를 단다.

## 2. 화면 스펙 (`01_architect_screens.md`)
PRD 5.5의 6개 화면 각각에 대해: **구성 요소 / 화면 상태(로딩·빈·정상·에러) / 진입·이탈 전이 / 사용자 액션**을 표로. 핵심 사전(온보딩→홈→정리→완료)을 먼저, 완결되게.

## 3. 데이터 모델 (`01_architect_datamodel.md`)
PRD 9절 기준. 원본은 저장하지 않고 참조만.

```
ProcessedAsset { id: String(PK, 플랫폼 자산 ID), processedAt: DateTime, albumId: String }
Album          { id: String(PK), name: String, systemAlbumRef: String?, coverAssetId: String?, updatedAt: DateTime }
```

**미분류 필터 규칙(가장 중요, 명문화):**
> 미분류 = (플랫폼 자산 중) `id NOT IN (ProcessedAsset.id 집합)`. OS의 앨범 소속 여부로 판단하지 않는다 — iOS는 앨범이 태그라 정리 후에도 원본이 남기 때문. 성능을 위해 "마지막 처리 시각 이후 생성분"으로 1차 범위를 좁힐 수 있으나, 최종 판별 기준은 항상 처리 ID 집합이다.

## 4. 아키텍처 (`01_architect_architecture.md`)
**feature-first 레이어링** 권장:
```
lib/
  core/        (DB, 사진 서비스, 알림 서비스, 공통 위젯)
  features/
    onboarding/  home/  sort/  album/  done/  settings/
      (각 feature: presentation 위젯 + state(Riverpod) + 필요 시 로컬 로직)
  main.dart
```
플랫폼 서비스(core)와 UI(features)의 **경계 인터페이스를 명시**한다 — 이 경계가 QA의 검증 지점이자 platform-integrator↔feature-builder 협업 계약이다.

## 5. 작업 분해 (`01_architect_tasks.md`)
F-01~F-13을 구현 태스크로 쪼갠다. 각 태스크: **담당 에이전트 / 의존 태스크 / 완료 기준(수용 조건)**. 핵심 루프(F-01~F-06) 우선, 온보딩(F-07), 부가(F-08~F-13) 순.

## 산출 원칙
- 결론 먼저(역피라미드), 표·구조도 활용.
- PRD에 답 없는 결정(예: 최종 DB)은 임의 확정하지 말고 "사용자 확인 필요"로 플래그해 오케스트레이터에 전달.
