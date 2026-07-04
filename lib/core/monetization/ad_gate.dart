import 'monetization_config.dart';

/// 완료 화면 광고 노출 정책(F-09) — **순수 로직**.
///
/// ## 왜 순수 함수로 분리했나
/// "언제 광고를 보여줄지" 는 이 앱의 최대 불변식(정리 흐름을 광고가 방해하면 안 됨)
/// 을 코드로 표현한 부분이다. 위젯·SDK·시간에 얽히면 검증이 어려우므로, 판정 로직을
/// I/O 없는 순수 함수([shouldShowCompletionAd])로 떼어 단위 테스트로 못박는다.
/// 위젯(완료 화면)은 이 함수의 참/거짓만 소비한다.
///
/// ## 노출 조건 (전부 AND)
/// 1. **광고 미제거**: 광고 제거 IAP(F-10)를 사면 영구히 광고 없음.
/// 2. **첫 정리일 + 7일 경과**(D3): 설치일이 아니라 *첫 정리 완료일* 기준. 습관이
///    붙기 전 첫 주는 광고 없이 정리 경험만 준다. 첫 정리 전(firstSortDate == null)
///    이면 당연히 노출 안 함.
/// 3. **세션당 1회**: 한 앱 실행(세션) 동안 완료 화면 광고는 한 번만.
///
/// 그리고 이 판정이 **완료 화면에서만** 호출된다는 사실이 "완료 화면 뒤에서만"
/// 이라는 위치 불변식을 보장한다(정리 흐름 위젯은 이 함수를 절대 부르지 않는다).
abstract final class AdGate {
  AdGate._();

  /// 완료 화면에 광고를 띄워도 되는지.
  ///
  /// - [firstSortDate] : 첫 정리 완료일(로컬 기록). 없으면(첫 정리 전) 노출 금지.
  /// - [now] : 현재 시각(테스트 주입 위해 인자로 받음).
  /// - [adsRemoved] : 광고 제거 IAP 구매 여부(로컬 캐시).
  /// - [shownThisSession] : 이번 앱 세션에서 이미 완료 광고를 띄웠는지.
  static bool shouldShowCompletionAd({
    required DateTime? firstSortDate,
    required DateTime now,
    required bool adsRemoved,
    required bool shownThisSession,
  }) {
    if (adsRemoved) return false;
    if (shownThisSession) return false;
    if (firstSortDate == null) return false;

    final unlockAt =
        firstSortDate.add(const Duration(days: MonetizationConfig.adFreeGraceDays));
    // now 가 unlock 시점 이상이면 유예 기간 종료 → 노출 가능.
    return !now.isBefore(unlockAt);
  }
}

/// 앱 세션 1회 동안의 광고 노출 상태(세션당 1회 불변식용).
///
/// providerContainer 수명(앱 실행 1회) 동안 유지되는 단일 인스턴스로 주입한다.
/// autoDispose 가 아니므로 여러 정리 세션을 거쳐도 값이 유지된다 → "세션당 1회".
class AdSession {
  /// 이번 세션에서 완료 화면 광고를 이미 노출했는가.
  bool completionAdShown = false;
}
