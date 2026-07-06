/// 분석 계측 경계 계약(F-12, monetization-and-analytics SKILL §3).
///
/// features 는 이 추상 타입만 import 한다(구현체 아님). 지금은 로컬/Noop
/// 구현([LocalAnalyticsService])이 주입되고, **나중에 FirebaseAnalyticsService**
/// 로 교체해도 호출 지점(features)은 그대로 유지된다.
///
/// ## 설계 선택 — 왜 "제네릭 logEvent" 가 아니라 "타입 안전 메서드" 인가
/// SKILL 이 명시한 최대 리스크는 *"이벤트 이름·속성 오타가 지표를 망친다"* 이다.
/// `logEvent('sort_sesion_start', {'unclasified': n})` 같은 오타는 컴파일 타임에
/// 잡히지 않는다. 그래서 이 코드베이스의 다른 경계 계약(NotificationService 의
/// init/requestPermission/... 처럼)과 동일하게 **이벤트별 명시 메서드**를 노출한다.
/// 호출측은 문자열을 절대 직접 타이핑하지 않으므로 오타가 원천 차단된다.
/// 문자열 이름·속성 키는 [AnalyticsEvents]/[AnalyticsParams] 상수로만 관리되어
/// 구현체(및 테스트)가 단일 출처를 공유한다.
///
/// ## 반환 타입 — 왜 `void` 인가
/// 분석은 fire-and-forget 다. `void` 로 두면 동기 콜사이트(예: 스와이프 핸들러)
/// 에서 `await`/`unawaited` 없이 호출할 수 있어 콜사이트가 깨끗하다. Firebase 로
/// 교체할 때는 구현체 내부에서 `unawaited(_fa.logEvent(...))` 로 감싸면 되므로
/// 계약을 바꿀 필요가 없다.
///
/// ## 프라이버시(PRD 최소 수집, SKILL 프라이버시)
/// 어떤 이벤트도 사진 내용·개인정보·원본 자산 ID 를 담지 않는다. 카운트,
/// 로컬 앨범 ID(앱 내부 UUID), 화면/액션 이벤트만 전송한다.
abstract class AnalyticsService {
  /// 앱 실행(콜드 스타트). SKILL: `app_open` — 속성 없음.
  void logAppOpen();

  /// 온보딩 완료(마지막 스텝에서 정리로 진입하며 확정). SKILL: `onboarding_complete`
  /// — 속성 = 설정된 알림 시각(개인정보 아님).
  void logOnboardingComplete({
    required int notifyHour,
    required int notifyMinute,
    required bool notifyEnabled,
  });

  /// 정리 세션 시작(정리 화면 큐 로드 완료). SKILL: `sort_session_start`
  /// — 속성 = 미분류수.
  void logSortSessionStart({required int unclassifiedCount});

  /// 배정 성공(commit 으로 시스템에 실제 반영된 자산 1건). SKILL: `asset_assigned`
  /// — 속성 = albumId(로컬 앱 앨범 UUID). 성공분마다 1회 호출.
  void logAssetAssigned({required String albumId});

  /// 건너뛰기("나중에"). SKILL: `asset_skipped` — 속성 없음.
  void logAssetSkipped();

  /// 단건 삭제 성공(D5, F-14c'). `asset_deleted` — 속성 없음(asset_skipped 와 동형).
  /// 사진 내용·id 미포함. 삭제 성공분마다 1회.
  void logAssetDeleted();

  /// 정리 세션 완료(완료 화면 전이 = commit 실반영 또는 세션 삭제분 존재).
  /// SKILL: `sort_session_complete` — 속성 = 처리수, 남은 미분류수, 삭제수(D5).
  void logSortSessionComplete({
    required int processedCount,
    required int remainingUnclassified,
    required int deletedCount,
  });

  /// 알림 탭으로 앱 진입. SKILL: `notification_opened` — 속성 없음.
  void logNotificationOpened();

  /// 완료 화면 광고 노출(F-09). 세션당 1회 실제 표시 시점. 속성 없음.
  ///
  /// SKILL §3 기본 표에는 없지만, 광고 노출 규칙(첫 정리+7일·세션당 1회)이 실제로
  /// 지켜지는지와 수익화 퍼널을 지표로 확인하려면 노출 이벤트가 필요하다. 광고 내용·
  /// 개인정보는 담지 않는다(카운트 목적).
  void logAdShown();

  /// 광고 제거 신규 구매 완료(F-10). 속성 없음(가격·영수증 등 개인정보 제외).
  void logRemoveAdsPurchased();

  /// 광고 제거 구매 복원 완료(F-10, 재설치·기기변경). 속성 없음.
  void logRemoveAdsRestored();
}

/// 이벤트 이름 단일 출처(SKILL §3 표). **오타 방지용 상수** — 절대 콜사이트에서
/// 문자열을 직접 쓰지 말 것.
abstract final class AnalyticsEvents {
  static const String appOpen = 'app_open';
  static const String onboardingComplete = 'onboarding_complete';
  static const String sortSessionStart = 'sort_session_start';
  static const String assetAssigned = 'asset_assigned';
  static const String assetSkipped = 'asset_skipped';
  static const String assetDeleted = 'asset_deleted';
  static const String sortSessionComplete = 'sort_session_complete';
  static const String notificationOpened = 'notification_opened';
  static const String adShown = 'ad_shown';
  static const String removeAdsPurchased = 'remove_ads_purchased';
  static const String removeAdsRestored = 'remove_ads_restored';
}

/// 이벤트 속성(파라미터) 키 단일 출처.
abstract final class AnalyticsParams {
  static const String notifyHour = 'notify_hour';
  static const String notifyMinute = 'notify_minute';
  static const String notifyEnabled = 'notify_enabled';
  static const String unclassifiedCount = 'unclassified_count';
  static const String albumId = 'album_id';
  static const String processedCount = 'processed_count';
  static const String remainingUnclassified = 'remaining_unclassified';
  static const String deletedCount = 'deleted_count';
}

/// 기록된 분석 이벤트 1건(로컬 구현·테스트 검증용 값 객체).
class AnalyticsEvent {
  const AnalyticsEvent(this.name, [this.params = const {}]);

  final String name;
  final Map<String, Object?> params;

  @override
  String toString() =>
      params.isEmpty ? 'AnalyticsEvent($name)' : 'AnalyticsEvent($name, $params)';
}
