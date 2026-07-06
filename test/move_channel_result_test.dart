// 단위 테스트 (QA C-5/C-4): 네이티브 배치 이동 채널 응답 파싱.
//
// parseMoveChannelResult 는 플랫폼 채널 없는 순수 함수라 직접 테스트 가능.
// 핵심: 취소(cancelled)·미지원(unsupported)·부분성공(moved/failed) 구분이 정확해야
// 소비자(_commitAndroid → sort_screen.dart:34 cancelled 분기)가 오안내하지 않는다.

import 'package:flutter_test/flutter_test.dart';

import 'package:on_the_fly/core/photo/photo_manager_photo_service.dart';

void main() {
  group('parseMoveChannelResult', () {
    test('취소(RESULT_CANCELED) → cancelled=true, moved/failed 비어 있음 (C-4)', () {
      final r = parseMoveChannelResult(<Object?, Object?>{
        'unsupported': false,
        'cancelled': true,
        'moved': <Object?>[],
        'failed': <Object?>[],
      });
      expect(r.cancelled, isTrue);
      expect(r.unsupported, isFalse);
      expect(r.moved, isEmpty);
      expect(r.failed, isEmpty);
    });

    test('API<30 → unsupported=true (레거시 폴백 신호)', () {
      final r = parseMoveChannelResult(<Object?, Object?>{
        'unsupported': true,
        'cancelled': false,
        'moved': <Object?>[],
        'failed': <Object?>[],
      });
      expect(r.unsupported, isTrue);
      expect(r.cancelled, isFalse);
    });

    test('부분 성공 → moved/failed 를 문자열 id 로 분리', () {
      final r = parseMoveChannelResult(<Object?, Object?>{
        'unsupported': false,
        'cancelled': false,
        // 네이티브가 숫자/문자 혼재로 보내도 문자열화한다.
        'moved': <Object?>[47, '48', 59],
        'failed': <Object?>['12'],
      });
      expect(r.moved, ['47', '48', '59']);
      expect(r.failed, ['12']);
      expect(r.cancelled, isFalse);
      expect(r.unsupported, isFalse);
    });

    test('전량 성공 → failed 비어 있음', () {
      final r = parseMoveChannelResult(<Object?, Object?>{
        'unsupported': false,
        'cancelled': false,
        'moved': <Object?>['1', '2'],
        'failed': <Object?>[],
      });
      expect(r.moved, ['1', '2']);
      expect(r.failed, isEmpty);
    });

    test('알 수 없는 응답(null/비-Map) → 아무것도 이동 안 됨(안전 폴백)', () {
      for (final bad in <Object?>[null, 'oops', 42, <Object?>[]]) {
        final r = parseMoveChannelResult(bad);
        expect(r.unsupported, isFalse);
        expect(r.cancelled, isFalse);
        expect(r.moved, isEmpty);
        expect(r.failed, isEmpty);
      }
    });

    test('키 누락 → 기본값(false/빈 목록)으로 견고하게 파싱', () {
      final r = parseMoveChannelResult(<Object?, Object?>{'moved': <Object?>['9']});
      expect(r.unsupported, isFalse);
      expect(r.cancelled, isFalse);
      expect(r.moved, ['9']);
      expect(r.failed, isEmpty);
    });
  });
}
