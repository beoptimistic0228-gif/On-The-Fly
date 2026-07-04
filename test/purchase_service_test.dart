// F-10 광고 제거 IAP — 스토어 미설정/미지원에서의 우아한 폴백 검증.
//
// 실제 in_app_purchase SDK 는 플랫폼 채널을 타므로 유닛 테스트에서 직접 부를 수
// 없다. 여기서는 폴백 구현([NoopPurchaseService])의 계약 준수만 검증한다:
// 스토어 unavailable · 상품 없음 · 구매/복원 무동작 · 로컬 캐시 권한 유지.

import 'package:flutter_test/flutter_test.dart';

import 'package:on_the_fly/core/monetization/noop_purchase_service.dart';
import 'package:on_the_fly/core/monetization/purchase_service.dart';

void main() {
  test('기본값: 광고 미제거 · 스토어 unavailable · 상품 없음 · 구매 실패', () async {
    final svc = NoopPurchaseService();
    await svc.initialize();

    expect(svc.adsRemoved, isFalse);
    expect(await svc.storeStatus(), StoreStatus.unavailable);
    expect(await svc.loadRemoveAdsProduct(), isNull);
    expect(await svc.buyRemoveAds(), isFalse); // 구매 시작 자체가 불가.
    await svc.restore(); // 예외 없이 무동작.
    svc.dispose();
  });

  test('이미 구매한 사용자(로컬 캐시)는 폴백에서도 광고 제거 유지', () async {
    final svc = NoopPurchaseService(true);
    await svc.initialize();

    expect(svc.adsRemoved, isTrue);
    // 스트림도 즉시 현재값(true)을 방출한다.
    expect(await svc.adsRemovedStream().first, isTrue);
    svc.dispose();
  });

  test('adsRemovedStream 은 구독 즉시 현재값을 1회 방출한다', () async {
    final svc = NoopPurchaseService();
    expect(await svc.adsRemovedStream().first, isFalse);
  });
}
