/// 사진 라이브러리 접근 권한 상태 (플랫폼 타입 노출 금지 — 순수 DTO).
///
/// features 는 이 enum 만 본다. photo_manager 의 `PermissionState` 는
/// core/photo 구현체 내부에서 이 값으로 변환된다.
///
/// - [granted] : 전체 접근 허용. 정리 기능 정상 동작.
/// - [limited] : iOS/Android 제한 접근. D2 확정에 따라 "전체 접근 유도" 안내 필요.
///   (부분 접근 정리는 MVP 미지원 → UI는 전체 접근 요청 화면을 띄운다.)
/// - [denied]  : 거부/미결정/제한(restricted). 설정 앱 유도 안내 필요.
enum PhotoPermission { granted, limited, denied }
