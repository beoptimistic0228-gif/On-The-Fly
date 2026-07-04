import 'dart:io' show Platform;

/// 수익화 식별자·정책 상수 단일 출처(F-09/F-10).
///
/// ## 왜 한 파일에 모으나
/// AdMob 광고 유닛 ID·IAP 상품 ID·광고 무료 유예일수가 코드 곳곳에 흩어지면
/// 실 계정으로 교체할 때 빠뜨리기 쉽다. 교체 지점을 여기 한 곳으로 고정한다
/// (analytics 의 [AnalyticsEvents] 상수 단일 출처와 같은 철학).
///
/// ## 지금은 전부 "테스트 값" 이다 (중요)
/// AdMob 계정·앱 등록, 스토어 IAP 상품이 아직 없다. 그래서:
/// - 광고: **Google 공식 테스트 App ID·테스트 광고 유닛**을 쓴다. 실 광고를 요청하지
///   않으므로 정책 위반 없이 UI·로드 흐름을 검증할 수 있다.
/// - IAP: 상품 ID 는 정했지만 스토어에 아직 없다 → 조회가 "없음" 으로 돌아온다.
///   구매 UI 가 크래시 없이 우아하게 비활성되게 처리한다([InAppPurchaseService]).
///
/// ## 실 계정/스토어 등록 시 할 일 (교체 절차)
/// 1. AdMob 콘솔에서 앱 등록 → **App ID** 를 발급받아
///    `android/app/src/main/AndroidManifest.xml` 의
///    `com.google.android.gms.ads.APPLICATION_ID` meta-data 와
///    `ios/Runner/Info.plist` 의 `GADApplicationIdentifier` 를 실 값으로 교체.
///    (⚠️ 이 meta-data 가 없거나 틀리면 SDK 초기화 시 앱이 크래시한다.)
/// 2. AdMob 에서 **배너 광고 유닛**을 만들어 [bannerAdUnitIdAndroid]/[bannerAdUnitIdIos]
///    를 실 유닛 ID 로 교체.
/// 3. Play Console / App Store Connect 에서 **비소모성 상품**을 [removeAdsProductId]
///    (`remove_ads`) 로 등록. ID 를 바꾸려면 여기 상수만 바꾼다.
/// 4. `_useTestAds` 를 `false` 로(또는 릴리스 빌드 감지) 두어 실 광고를 노출.
abstract final class MonetizationConfig {
  MonetizationConfig._();

  /// 광고 무료 유예 기간(일). D3 확정: **첫 정리일 + 7일** 이후부터 노출.
  static const int adFreeGraceDays = 7;

  /// 광고 제거 IAP 상품 ID(비소모성). 스토어 등록 시 동일 ID 사용.
  static const String removeAdsProductId = 'remove_ads';

  /// 실 광고를 쓸지. 지금은 계정 미등록이라 항상 테스트 광고.
  /// 실 계정 등록 후 릴리스에서 false 로 전환(또는 kReleaseMode 로 분기).
  static const bool _useTestAds = true;

  // ── Google 공식 테스트 App ID (AndroidManifest / Info.plist 에 넣는 값) ──
  // 실 등록 전까지 이 값을 매니페스트에 두어야 SDK 가 크래시하지 않는다.
  static const String testAppIdAndroid =
      'ca-app-pub-3940256099942544~3347511713';
  static const String testAppIdIos = 'ca-app-pub-3940256099942544~1458002511';

  // ── Google 공식 테스트 배너 광고 유닛 ID ──
  static const String _testBannerAndroid =
      'ca-app-pub-3940256099942544/6300978111';
  static const String _testBannerIos =
      'ca-app-pub-3940256099942544/2934735716';

  // ── 실 배너 광고 유닛 ID (등록 후 교체) ──
  static const String _realBannerAndroid = 'REPLACE_WITH_REAL_ANDROID_BANNER_UNIT';
  static const String _realBannerIos = 'REPLACE_WITH_REAL_IOS_BANNER_UNIT';

  static String get bannerAdUnitIdAndroid =>
      _useTestAds ? _testBannerAndroid : _realBannerAndroid;
  static String get bannerAdUnitIdIos =>
      _useTestAds ? _testBannerIos : _realBannerIos;

  /// 현재 플랫폼의 완료 화면 배너 유닛 ID. iOS/Android 외에는 null(광고 미지원).
  static String? get completionBannerUnitId {
    if (Platform.isAndroid) return bannerAdUnitIdAndroid;
    if (Platform.isIOS) return bannerAdUnitIdIos;
    return null;
  }
}
