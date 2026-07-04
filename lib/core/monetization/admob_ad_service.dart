import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import 'ad_service.dart';
import 'monetization_config.dart';

/// [AdService] 의 AdMob(`google_mobile_ads`) 구현(F-09).
///
/// **이 파일이 광고 SDK 를 import 하는 유일한 곳이다.** 완료 화면·게이트·providers
/// 는 추상 [AdService]/[CompletionBanner] 만 안다. 실 ID 교체는
/// [MonetizationConfig] 한 곳에서 한다.
///
/// ## 초기화 크래시 방지
/// `MobileAds.instance.initialize()` 는 AndroidManifest 의 `APPLICATION_ID`
/// meta-data / Info.plist 의 `GADApplicationIdentifier` 가 있어야 정상 동작한다
/// (테스트 App ID 를 매니페스트에 넣어 둠). 그래도 만일에 대비해 [initialize] 는
/// try-catch 로 감싸 실패해도 앱을 죽이지 않는다(광고는 부가 기능).
class AdMobAdService implements AdService {
  bool _initialized = false;

  @override
  bool get isSupported => MonetizationConfig.completionBannerUnitId != null;

  @override
  Future<void> initialize() async {
    if (_initialized || !isSupported) return;
    try {
      await MobileAds.instance.initialize();
      _initialized = true;
    } catch (e) {
      // 초기화 실패 → 광고 없이 앱은 정상 동작. createCompletionBanner 도 실패로.
      debugPrint('[ads] MobileAds 초기화 실패(광고 비활성): $e');
    }
  }

  @override
  CompletionBanner? createCompletionBanner() {
    final unitId = MonetizationConfig.completionBannerUnitId;
    if (!_initialized || unitId == null) return null;
    return _AdMobBanner(unitId);
  }
}

/// AdMob 배너 1개의 수명 핸들. SDK 타입은 여기 안에만 있다.
class _AdMobBanner implements CompletionBanner {
  _AdMobBanner(this._unitId);

  final String _unitId;
  BannerAd? _ad;
  bool _loaded = false;

  // 표준 배너(320x50) 높이. 슬롯 레이아웃 예약용.
  @override
  double get height => AdSize.banner.height.toDouble();

  @override
  Widget? get widget =>
      (_loaded && _ad != null) ? AdWidget(ad: _ad!) : null;

  @override
  Future<bool> load() {
    final completer = Completer<bool>();
    final ad = BannerAd(
      adUnitId: _unitId,
      size: AdSize.banner,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (_) {
          _loaded = true;
          if (!completer.isCompleted) completer.complete(true);
        },
        onAdFailedToLoad: (ad, error) {
          ad.dispose();
          _ad = null;
          if (!completer.isCompleted) completer.complete(false);
        },
      ),
    );
    _ad = ad;
    ad.load();
    return completer.future;
  }

  @override
  void dispose() {
    _ad?.dispose();
    _ad = null;
    _loaded = false;
  }
}
