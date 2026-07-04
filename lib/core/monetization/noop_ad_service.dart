import 'ad_service.dart';

/// [AdService] 의 무동작(Noop) 구현.
///
/// 광고를 아예 띄우지 않는다. 두 상황에서 쓰인다:
/// 1. **테스트/미지원 환경**: providers 기본값(플랫폼 채널 없이 안전).
/// 2. **폴백**: `main()` 이 AdMob 초기화에 실패하면 이걸 주입해 앱을 지킨다.
///
/// [createCompletionBanner] 가 항상 null 이므로 완료 화면은 광고 슬롯 없이 뜬다.
class NoopAdService implements AdService {
  @override
  Future<void> initialize() async {}

  @override
  bool get isSupported => false;

  @override
  CompletionBanner? createCompletionBanner() => null;
}
