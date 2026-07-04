import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../analytics/analytics_service.dart';
import 'monetization_config.dart';
import 'purchase_service.dart';

/// [PurchaseService] 의 `in_app_purchase`(공식) 구현(F-10).
///
/// **이 파일이 IAP SDK 를 import 하는 유일한 곳이다.** 설정 화면은 추상
/// [PurchaseService] 만 안다.
///
/// ## 진실의 원천 (서버 없음)
/// 광고 제거 권한은 SharedPreferences 의 bool 한 개([_kOwnedKey])로 로컬 캐시된다.
/// 스토어 구매/복원 이벤트([_iap.purchaseStream])가 도착하면 이 캐시를 켜고
/// 스트림([_controller])으로 UI 에 알린다. 영수증 검증은 스토어/SDK 에 위임한다.
///
/// ## 프라이버시
/// IAP SDK 에는 상품 ID 와 결제 흐름만 오간다. 사진·자산 ID·개인정보는 일절
/// 전달하지 않는다.
class InAppPurchaseService implements PurchaseService {
  InAppPurchaseService(this._iap, this._prefs, this._analytics);

  final InAppPurchase _iap;
  final SharedPreferences _prefs;
  final AnalyticsService _analytics;

  static const String _kOwnedKey = 'remove_ads_owned';

  final StreamController<bool> _controller = StreamController<bool>.broadcast();
  StreamSubscription<List<PurchaseDetails>>? _sub;

  @override
  Future<void> initialize() async {
    // 스토어 구매/복원 이벤트 구독. 앱이 살아 있는 동안 여기로 결과가 도착한다.
    _sub = _iap.purchaseStream.listen(
      _onPurchaseUpdates,
      onError: (Object e) => debugPrint('[iap] purchaseStream 오류: $e'),
    );
  }

  @override
  bool get adsRemoved => _prefs.getBool(_kOwnedKey) ?? false;

  @override
  Stream<bool> adsRemovedStream() async* {
    yield adsRemoved; // 구독 즉시 현재값 1회.
    yield* _controller.stream;
  }

  @override
  Future<StoreStatus> storeStatus() async {
    try {
      final available = await _iap.isAvailable();
      return available ? StoreStatus.available : StoreStatus.unavailable;
    } catch (e) {
      debugPrint('[iap] isAvailable 실패: $e');
      return StoreStatus.unavailable;
    }
  }

  @override
  Future<RemoveAdsProduct?> loadRemoveAdsProduct() async {
    try {
      if (!await _iap.isAvailable()) return null;
      final resp = await _iap
          .queryProductDetails({MonetizationConfig.removeAdsProductId});
      // 스토어 미등록(notFoundIDs) 또는 조회 오류 → 조용히 null(UI 비활성).
      if (resp.error != null || resp.productDetails.isEmpty) return null;
      final pd = resp.productDetails.first;
      return RemoveAdsProduct(id: pd.id, title: pd.title, price: pd.price);
    } catch (e) {
      debugPrint('[iap] 상품 조회 실패: $e');
      return null;
    }
  }

  @override
  Future<bool> buyRemoveAds() async {
    try {
      if (!await _iap.isAvailable()) return false;
      final resp = await _iap
          .queryProductDetails({MonetizationConfig.removeAdsProductId});
      if (resp.productDetails.isEmpty) return false;
      final param = PurchaseParam(productDetails: resp.productDetails.first);
      // 비소모성 → buyNonConsumable. 결과는 purchaseStream 으로 도착.
      return await _iap.buyNonConsumable(purchaseParam: param);
    } catch (e) {
      debugPrint('[iap] 구매 시작 실패: $e');
      return false;
    }
  }

  @override
  Future<void> restore() async {
    try {
      await _iap.restorePurchases();
    } catch (e) {
      debugPrint('[iap] 복원 실패: $e');
    }
  }

  /// 스토어에서 도착한 구매/복원 이벤트 처리.
  Future<void> _onPurchaseUpdates(List<PurchaseDetails> purchases) async {
    for (final p in purchases) {
      if (p.productID != MonetizationConfig.removeAdsProductId) {
        // 우리 상품이 아니지만, 대기 상태면 완료 처리는 해줘야 스트림이 막히지 않음.
        if (p.pendingCompletePurchase) await _iap.completePurchase(p);
        continue;
      }
      switch (p.status) {
        case PurchaseStatus.purchased:
          await _grantAdsRemoved(restored: false);
        case PurchaseStatus.restored:
          await _grantAdsRemoved(restored: true);
        case PurchaseStatus.error:
        case PurchaseStatus.canceled:
        case PurchaseStatus.pending:
          // 권한 변화 없음. (pending 은 사용자 결제 진행 중)
          break;
      }
      // 어떤 상태든 대기 중인 트랜잭션은 완료 처리(스토어 요구).
      if (p.pendingCompletePurchase) await _iap.completePurchase(p);
    }
  }

  Future<void> _grantAdsRemoved({required bool restored}) async {
    final wasOwned = adsRemoved;
    await _prefs.setBool(_kOwnedKey, true);
    _controller.add(true);
    // 분석: 신규 구매 vs 복원 구분(개인정보 없음).
    if (restored) {
      _analytics.logRemoveAdsRestored();
    } else if (!wasOwned) {
      _analytics.logRemoveAdsPurchased();
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    _controller.close();
  }
}
