import 'package:flutter/foundation.dart';

import 'analytics_service.dart';

/// [AnalyticsService] 의 로컬/Noop 구현.
///
/// 지금은 **debugPrint 로그 + 인메모리 기록**만 한다(서버·SDK 없음, PRD 7절
/// "서버 없이"). North Star/D7 산출용 이벤트 스키마를 **먼저 확정**해 코드 전반에
/// 심어 두고, 실제 전송 백엔드(Firebase Analytics)는 나중에 이 파일만 교체한다.
///
/// ### 나중에 FirebaseAnalyticsService 로 교체할 때
/// 1. `firebase_core` / `firebase_analytics` 의존성을 pubspec 에 추가하고
///    `flutterfire configure` 로 설정 파일 생성(지금은 추가하지 않음 — 사용자 확정).
/// 2. 이 파일과 동일한 [AnalyticsService] 를 구현하는 `FirebaseAnalyticsService`
///    를 만들고, 각 메서드에서 `_analytics.logEvent(name: ..., parameters: ...)`
///    (fire-and-forget: `unawaited(...)`) 를 호출한다. 이름·속성 키는 그대로
///    [AnalyticsEvents]/[AnalyticsParams] 를 재사용한다.
/// 3. `providers.dart` 의 `analyticsServiceProvider` 반환만 새 구현으로 바꾼다.
///    features 콜사이트는 **한 줄도 바뀌지 않는다**(추상 타입만 의존하므로).
class LocalAnalyticsService implements AnalyticsService {
  LocalAnalyticsService({this.keepHistory = true});

  /// 최근 이벤트를 인메모리로 보관할지(디버깅/QA 편의). 프로덕션 전송 아님.
  final bool keepHistory;

  static const int _maxHistory = 200;
  final List<AnalyticsEvent> _history = [];

  /// 세션 동안 기록된 이벤트(읽기 전용). 디버깅·수동 QA 용.
  List<AnalyticsEvent> get history => List.unmodifiable(_history);

  /// 모든 이벤트가 지나가는 단일 지점 — Firebase 로 교체 시 여기만 바뀐다.
  void _log(String name, [Map<String, Object?> params = const {}]) {
    if (keepHistory) {
      _history.add(AnalyticsEvent(name, params));
      if (_history.length > _maxHistory) _history.removeAt(0);
    }
    // TODO(P1, analytics): FirebaseAnalyticsService 로 교체 시 이 debugPrint 를
    // `unawaited(_analytics.logEvent(name: name, parameters: params))` 로 대체.
    debugPrint('[analytics] $name ${params.isEmpty ? '' : params}');
  }

  @override
  void logAppOpen() => _log(AnalyticsEvents.appOpen);

  @override
  void logOnboardingComplete({
    required int notifyHour,
    required int notifyMinute,
    required bool notifyEnabled,
  }) =>
      _log(AnalyticsEvents.onboardingComplete, {
        AnalyticsParams.notifyHour: notifyHour,
        AnalyticsParams.notifyMinute: notifyMinute,
        AnalyticsParams.notifyEnabled: notifyEnabled,
      });

  @override
  void logSortSessionStart({required int unclassifiedCount}) =>
      _log(AnalyticsEvents.sortSessionStart, {
        AnalyticsParams.unclassifiedCount: unclassifiedCount,
      });

  @override
  void logAssetAssigned({required String albumId}) =>
      _log(AnalyticsEvents.assetAssigned, {
        AnalyticsParams.albumId: albumId,
      });

  @override
  void logAssetSkipped() => _log(AnalyticsEvents.assetSkipped);

  @override
  void logSortSessionComplete({
    required int processedCount,
    required int remainingUnclassified,
  }) =>
      _log(AnalyticsEvents.sortSessionComplete, {
        AnalyticsParams.processedCount: processedCount,
        AnalyticsParams.remainingUnclassified: remainingUnclassified,
      });

  @override
  void logNotificationOpened() => _log(AnalyticsEvents.notificationOpened);

  @override
  void logAdShown() => _log(AnalyticsEvents.adShown);

  @override
  void logRemoveAdsPurchased() => _log(AnalyticsEvents.removeAdsPurchased);

  @override
  void logRemoveAdsRestored() => _log(AnalyticsEvents.removeAdsRestored);
}
