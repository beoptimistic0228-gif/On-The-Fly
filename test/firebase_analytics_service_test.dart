// FirebaseAnalyticsService 매핑 검증(F-12, D3).
//
// 이 테스트가 지키는 것: 타입 안전 메서드 각각이 (1) 올바른 이벤트 이름 상수와
// (2) 올바른 속성 키·값을 Firebase 로 보내는가. 특히 Firebase 가 허용하지 않는
// bool 값이 int(1/0)로 강제되는지 확인한다(SDK 는 String/num 만 허용).
//
// 플랫폼 채널 없이 검증하려고 실제 FirebaseAnalytics 대신 withSink 생성자로
// 기록 sink 를 주입한다(= 이 클래스의 진짜 로직인 "이름·속성 매핑" 만 격리 검증).

import 'package:flutter_test/flutter_test.dart';

import 'package:on_the_fly/core/analytics/analytics_service.dart';
import 'package:on_the_fly/core/analytics/firebase_analytics_service.dart';

void main() {
  late List<AnalyticsEvent> sent;
  late FirebaseAnalyticsService service;

  setUp(() {
    sent = [];
    service = FirebaseAnalyticsService.withSink(
      (name, params) => sent.add(AnalyticsEvent(name, params)),
    );
  });

  test('logAppOpen → app_open, 속성 없음', () {
    service.logAppOpen();
    expect(sent.single.name, AnalyticsEvents.appOpen);
    expect(sent.single.params, isEmpty);
  });

  test('logOnboardingComplete → bool notifyEnabled 가 int(1/0)로 강제된다', () {
    service.logOnboardingComplete(
      notifyHour: 21,
      notifyMinute: 30,
      notifyEnabled: true,
    );
    final e = sent.single;
    expect(e.name, AnalyticsEvents.onboardingComplete);
    expect(e.params[AnalyticsParams.notifyHour], 21);
    expect(e.params[AnalyticsParams.notifyMinute], 30);
    // Firebase 는 bool 을 거부 → 1/0 num 이어야 한다.
    expect(e.params[AnalyticsParams.notifyEnabled], 1);
    expect(e.params[AnalyticsParams.notifyEnabled], isA<int>());

    service.logOnboardingComplete(
      notifyHour: 9,
      notifyMinute: 0,
      notifyEnabled: false,
    );
    expect(sent.last.params[AnalyticsParams.notifyEnabled], 0);
  });

  test('logSortSessionStart → sort_session_start(미분류수)', () {
    service.logSortSessionStart(unclassifiedCount: 42);
    final e = sent.single;
    expect(e.name, AnalyticsEvents.sortSessionStart);
    expect(e.params[AnalyticsParams.unclassifiedCount], 42);
  });

  test('logAssetAssigned → asset_assigned(albumId 로컬 UUID)', () {
    service.logAssetAssigned(albumId: 'local-uuid-1');
    final e = sent.single;
    expect(e.name, AnalyticsEvents.assetAssigned);
    expect(e.params[AnalyticsParams.albumId], 'local-uuid-1');
  });

  test('logAssetSkipped → asset_skipped, 속성 없음', () {
    service.logAssetSkipped();
    expect(sent.single.name, AnalyticsEvents.assetSkipped);
    expect(sent.single.params, isEmpty);
  });

  test('logSortSessionComplete → sort_session_complete(처리수·남은수·삭제수)', () {
    service.logSortSessionComplete(
        processedCount: 5, remainingUnclassified: 3, deletedCount: 2);
    final e = sent.single;
    expect(e.name, AnalyticsEvents.sortSessionComplete);
    expect(e.params[AnalyticsParams.processedCount], 5);
    expect(e.params[AnalyticsParams.remainingUnclassified], 3);
    expect(e.params[AnalyticsParams.deletedCount], 2);
  });

  test('logAssetDeleted → asset_deleted, 속성 없음(D5)', () {
    service.logAssetDeleted();
    expect(sent.single.name, AnalyticsEvents.assetDeleted);
    expect(sent.single.params, isEmpty);
  });

  test('logNotificationOpened → notification_opened, 속성 없음', () {
    service.logNotificationOpened();
    expect(sent.single.name, AnalyticsEvents.notificationOpened);
    expect(sent.single.params, isEmpty);
  });

  test('logAdShown → ad_shown, 속성 없음(F-09)', () {
    service.logAdShown();
    expect(sent.single.name, AnalyticsEvents.adShown);
    expect(sent.single.params, isEmpty);
  });

  test('logRemoveAdsPurchased → remove_ads_purchased, 속성 없음(F-10)', () {
    service.logRemoveAdsPurchased();
    expect(sent.single.name, AnalyticsEvents.removeAdsPurchased);
    expect(sent.single.params, isEmpty);
  });

  test('logRemoveAdsRestored → remove_ads_restored, 속성 없음(F-10)', () {
    service.logRemoveAdsRestored();
    expect(sent.single.name, AnalyticsEvents.removeAdsRestored);
    expect(sent.single.params, isEmpty);
  });

  test('전송되는 모든 속성 값은 String 또는 num 뿐이다(Firebase 제약)', () {
    service.logAppOpen();
    service.logOnboardingComplete(
        notifyHour: 21, notifyMinute: 0, notifyEnabled: true);
    service.logSortSessionStart(unclassifiedCount: 10);
    service.logAssetAssigned(albumId: 'a');
    service.logAssetSkipped();
    service.logSortSessionComplete(
        processedCount: 1, remainingUnclassified: 9, deletedCount: 0);
    service.logNotificationOpened();

    for (final e in sent) {
      for (final value in e.params.values) {
        expect(value is String || value is num, isTrue,
            reason: '${e.name} 의 속성 값 $value 는 String/num 이어야 한다');
      }
    }
  });
}
