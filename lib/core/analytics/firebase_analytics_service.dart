import 'dart:async';

import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:flutter/foundation.dart';

import 'analytics_service.dart';

/// [AnalyticsService] 의 Firebase Analytics 구현(F-12, D3 확정).
///
/// [LocalAnalyticsService] 와 **완전히 동일한 이벤트/속성**을 만들되, 최종 목적지가
/// debugPrint 가 아니라 Firebase 로 바뀐다. 계약([AnalyticsService])·이름 상수
/// ([AnalyticsEvents]/[AnalyticsParams])는 그대로 재사용하므로 features 콜사이트는
/// 한 줄도 바뀌지 않는다(추상 타입만 의존).
///
/// ## 설계 선택 1 — 왜 fire-and-forget(`unawaited`) 인가
/// 계약이 `void` 를 약속한다(동기 콜사이트에서 `await` 없이 호출 가능해야 함, 예:
/// 스와이프 핸들러). `FirebaseAnalytics.logEvent` 는 `Future` 를 돌려주지만 분석은
/// 실패해도 사용자 흐름을 막으면 안 되므로 `unawaited(...)` 로 흘려보낸다. 네트워크
/// 전송 자체는 SDK 가 내부 배치·재시도로 처리한다.
///
/// ## 설계 선택 2 — 왜 bool 을 int(1/0)로 바꾸는가 (중요)
/// Firebase Analytics 는 이벤트 속성 값으로 **String 또는 num 만** 허용한다(SDK 가
/// 런타임 assert 로 강제). 계약의 `notify_enabled` 는 bool 이므로 그대로 보내면
/// 예외가 난다. 그래서 모든 값이 지나는 단일 지점([_log])에서 bool → int(true=1,
/// false=0)로 강제한다. 이 coercion 을 콜사이트가 아니라 여기 한 곳에 두면
/// 타입 안전 메서드들은 [LocalAnalyticsService] 와 글자 그대로 같아진다.
///
/// ## 설계 선택 3 — 왜 전송 sink 를 주입 가능하게 했는가(테스트)
/// `FirebaseAnalytics` 인스턴스는 네이티브 플랫폼 채널에 붙어 있어 유닛 테스트에서
/// 직접 부를 수 없다. 그래서 "이벤트 이름·속성 매핑" 이라는 이 클래스의 진짜 로직을
/// SDK 없이 검증할 수 있도록, 내부 전송을 [_AnalyticsSink] 함수로 추상화하고
/// 테스트용 [FirebaseAnalyticsService.withSink] 생성자로 임의 sink 를 주입한다.
/// 프로덕션 생성자는 이 sink 를 실제 `FirebaseAnalytics.logEvent` 로 연결한다.
///
/// ## 프라이버시(PRD 최소 수집)
/// 계약이 이미 보장하듯 사진 내용·개인정보·원본 자산 ID 를 담지 않는다. 이 클래스는
/// 이벤트를 추가/변경하지 않고 그대로 전달만 한다.
class FirebaseAnalyticsService implements AnalyticsService {
  /// 프로덕션: 실제 [FirebaseAnalytics] 인스턴스로 전송(fire-and-forget).
  FirebaseAnalyticsService(FirebaseAnalytics analytics)
      : _send = ((name, params) => unawaited(
              analytics.logEvent(
                name: name,
                parameters: params.isEmpty ? null : params.cast<String, Object>(),
              ),
            ));

  /// 테스트 전용: SDK/플랫폼 채널 없이 이름·속성 매핑을 검증하기 위한 sink 주입구.
  @visibleForTesting
  FirebaseAnalyticsService.withSink(this._send);

  final _AnalyticsSink _send;

  /// 모든 이벤트가 지나는 단일 지점 — coercion(§설계 2) 후 전송한다.
  void _log(String name, [Map<String, Object?> params = const {}]) {
    _send(name, _coerceForFirebase(params));
  }

  /// Firebase 가 허용하지 않는 값 타입(bool)을 num 으로 강제. 그 외는 그대로.
  static Map<String, Object?> _coerceForFirebase(Map<String, Object?> params) {
    if (params.isEmpty) return const {};
    return {
      for (final entry in params.entries)
        entry.key:
            entry.value is bool ? ((entry.value as bool) ? 1 : 0) : entry.value,
    };
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
  void logAssetDeleted() => _log(AnalyticsEvents.assetDeleted);

  @override
  void logSortSessionComplete({
    required int processedCount,
    required int remainingUnclassified,
    required int deletedCount,
  }) =>
      _log(AnalyticsEvents.sortSessionComplete, {
        AnalyticsParams.processedCount: processedCount,
        AnalyticsParams.remainingUnclassified: remainingUnclassified,
        AnalyticsParams.deletedCount: deletedCount,
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

/// 내부 전송 sink. 프로덕션은 `FirebaseAnalytics.logEvent`, 테스트는 기록 함수.
typedef _AnalyticsSink = void Function(String name, Map<String, Object?> params);
