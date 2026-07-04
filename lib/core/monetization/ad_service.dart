import 'package:flutter/widgets.dart';

/// 광고 서비스 경계 계약(F-09).
///
/// features(완료 화면)는 이 추상 타입만 의존한다. 실제 AdMob SDK
/// (`google_mobile_ads`)는 [AdMobAdService] 구현에만 갇혀 있어, 광고 SDK 로
/// 사진·개인정보가 흘러갈 여지를 애초에 화면 코드에서 차단한다.
///
/// ## 왜 배너(banner)인가 — 형태 선택 근거
/// 완료 화면 와이어프레임의 광고 자리는 "축하·streak **통계 아래의 박스형 슬롯**"
/// 이다. 이는 인라인으로 자리 잡는 배너 계열에 정확히 대응한다. 전면(interstitial)
/// 은 화면을 가로채 정리 완료의 성취감을 덮어버리고, 네이티브는 MVP 에 과하다.
/// 그래서 **완료 화면 하단 인라인 배너 하나**만 쓴다(과설계 금지).
///
/// ## 로드 실패는 UX 를 인질로 잡지 않는다
/// [CompletionBanner.load] 가 실패하면 위젯은 광고 슬롯 없이 완료 화면을 그대로
/// 보여준다. 광고는 어디까지나 완료 "뒤"의 부가물이다.
abstract class AdService {
  /// SDK 1회 초기화. 실패해도 예외를 던지지 않는다(광고는 부가 기능).
  Future<void> initialize();

  /// 이 플랫폼에서 광고를 지원하는지(iOS/Android 만).
  bool get isSupported;

  /// 완료 화면용 배너 핸들 생성. 미지원 플랫폼이면 null.
  ///
  /// 반환된 핸들은 호출측(위젯)이 [CompletionBanner.load] 로 로드하고,
  /// [CompletionBanner.dispose] 로 반드시 폐기한다(위젯 dispose 시).
  CompletionBanner? createCompletionBanner();
}

/// 완료 화면 배너 1개의 수명 핸들.
///
/// 위젯이 소유하며 load → (성공 시) [widget] 표시 → dispose 순으로 쓴다.
/// SDK 타입([BannerAd]/[AdWidget])은 구현체 안에만 존재한다.
abstract class CompletionBanner {
  /// 광고를 로드한다. 성공 시 true, 실패(네트워크·미填充 등) 시 false.
  Future<bool> load();

  /// 로드 성공 후 표시할 위젯(로드 전/실패 시 null).
  Widget? get widget;

  /// 배너 높이(px 논리 픽셀). 슬롯 레이아웃 예약용.
  double get height;

  /// 자원 해제. 위젯 dispose 에서 반드시 호출.
  void dispose();
}
