// F-09 광고 노출 게이트 순수 로직 검증.
//
// 불변식: 광고는 (첫 정리일 + 7일) 이후 · 광고 미제거 · 세션당 1회 일 때만
// 완료 화면에 노출된다. 이 판정은 시간·SDK 없이 순수 함수로 격리 검증한다.

import 'package:flutter_test/flutter_test.dart';

import 'package:on_the_fly/core/monetization/ad_gate.dart';
import 'package:on_the_fly/core/monetization/monetization_config.dart';

void main() {
  // 기준 시각.
  final firstSort = DateTime(2026, 1, 1, 21, 0);
  final grace = MonetizationConfig.adFreeGraceDays; // 7

  bool gate({
    DateTime? firstSortDate,
    required DateTime now,
    bool adsRemoved = false,
    bool shownThisSession = false,
  }) =>
      AdGate.shouldShowCompletionAd(
        firstSortDate: firstSortDate,
        now: now,
        adsRemoved: adsRemoved,
        shownThisSession: shownThisSession,
      );

  test('첫 정리 전(firstSortDate == null)이면 노출 안 함', () {
    expect(gate(firstSortDate: null, now: firstSort), isFalse);
  });

  test('유예 기간(첫 정리일 + 7일) 안에서는 노출 안 함', () {
    // 같은 날.
    expect(gate(firstSortDate: firstSort, now: firstSort), isFalse);
    // 6일 후(아직 7일 미만).
    expect(
      gate(firstSortDate: firstSort, now: firstSort.add(Duration(days: grace - 1))),
      isFalse,
    );
    // 7일에서 1초 모자란 순간.
    expect(
      gate(
          firstSortDate: firstSort,
          now: firstSort.add(Duration(days: grace)).subtract(const Duration(seconds: 1))),
      isFalse,
    );
  });

  test('첫 정리일 + 정확히 7일 경과 시점부터 노출', () {
    expect(
      gate(firstSortDate: firstSort, now: firstSort.add(Duration(days: grace))),
      isTrue,
    );
    expect(
      gate(firstSortDate: firstSort, now: firstSort.add(Duration(days: grace + 3))),
      isTrue,
    );
  });

  test('광고 제거 구매 시 유예 지나도 노출 안 함', () {
    expect(
      gate(
          firstSortDate: firstSort,
          now: firstSort.add(Duration(days: grace + 10)),
          adsRemoved: true),
      isFalse,
    );
  });

  test('이번 세션에 이미 노출했으면(세션당 1회) 노출 안 함', () {
    expect(
      gate(
          firstSortDate: firstSort,
          now: firstSort.add(Duration(days: grace + 10)),
          shownThisSession: true),
      isFalse,
    );
  });

  test('AdSession 은 세션 동안 노출 상태를 보관한다', () {
    final session = AdSession();
    expect(session.completionAdShown, isFalse);
    session.completionAdShown = true;
    expect(session.completionAdShown, isTrue);
  });
}
