// FIX-2b (04_final_audit B-4) 단위 테스트: Android id 재발급 안정 속성 매칭.
//
// 핵심 원칙 검증: "유일 정확 매칭만 확정, 불확실(0/다중)은 null(=실패)".
// 순서 기반 추정 매칭을 제거했으므로 오배정(간접 유실)이 발생하지 않아야 한다.
// matchByStableProps 는 플랫폼 채널 없는 순수 함수라 직접 테스트 가능.

import 'package:flutter_test/flutter_test.dart';

import 'package:on_the_fly/core/photo/photo_manager_photo_service.dart';

AssetFingerprint fp(
  String id, {
  String? title,
  int width = 100,
  int height = 200,
  int? createSecond = 1000,
  int duration = 0,
}) =>
    AssetFingerprint(
      id: id,
      title: title,
      width: width,
      height: height,
      createSecond: createSecond,
      duration: duration,
    );

void main() {
  group('matchByStableProps', () {
    test('유일 정확 일치 → 그 후보 id 로 확정', () {
      final captured = [fp('old', title: 'IMG_1.jpg', createSecond: 111)];
      final candidates = [
        fp('newA', title: 'IMG_1.jpg', createSecond: 111),
        fp('newB', title: 'OTHER.jpg', createSecond: 999),
      ];
      expect(matchByStableProps(captured, candidates), ['newA']);
    });

    test('후보 없음 → null (확정 불가 = 실패)', () {
      final captured = [fp('old', createSecond: 111)];
      final candidates = [fp('newB', createSecond: 999)];
      expect(matchByStableProps(captured, candidates), [null]);
    });

    test('다중 후보(모호) → null (오배정 대신 실패)', () {
      // 같은 안정 속성 후보 2개 → 어느 것이 이동분인지 불확실.
      final captured = [fp('old', createSecond: 111)];
      final candidates = [
        fp('newA', createSecond: 111),
        fp('newB', createSecond: 111),
      ];
      expect(matchByStableProps(captured, candidates), [null]);
    });

    test('한 후보는 최대 하나에만 배정(중복 배정 금지)', () {
      // captured 2개가 서로 다른 유일 후보에 각각 매칭.
      final captured = [
        fp('o1', title: 'A', createSecond: 1),
        fp('o2', title: 'B', createSecond: 2),
      ];
      final candidates = [
        fp('n1', title: 'A', createSecond: 1),
        fp('n2', title: 'B', createSecond: 2),
      ];
      expect(matchByStableProps(captured, candidates), ['n1', 'n2']);
    });

    test('동일 속성 중복 자산은 양쪽 모두 실패(간접 유실 금지)', () {
      final captured = [
        fp('o1', createSecond: 5),
        fp('o2', createSecond: 5),
      ];
      final candidates = [
        fp('n1', createSecond: 5),
        fp('n2', createSecond: 5),
      ];
      // 각 captured 가 후보 2개를 보므로 모두 모호 → 전부 null.
      expect(matchByStableProps(captured, candidates), [null, null]);
    });

    test('title 이 한쪽 null 이면 나머지 속성으로만 판단(오탈락 방지)', () {
      final captured = [fp('old', title: null, createSecond: 42)];
      final candidates = [fp('new', title: 'IMG.jpg', createSecond: 42)];
      expect(matchByStableProps(captured, candidates), ['new']);
    });

    test('createSecond 만 달라도 불일치로 본다', () {
      final captured = [fp('old', createSecond: 100)];
      final candidates = [fp('new', createSecond: 101)];
      expect(matchByStableProps(captured, candidates), [null]);
    });

    test('빈 captured → 빈 결과', () {
      expect(matchByStableProps([], [fp('x')]), isEmpty);
    });
  });
}
