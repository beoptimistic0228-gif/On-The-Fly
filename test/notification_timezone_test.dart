// FIX-1 (04_final_audit A-2) 단위 테스트: 알림 예약 로컬 타임존.
//
// flutter_timezone 는 플랫폼 채널이라 테스트에서 직접 못 부른다. 대신 tz.Location 을
// 주입받는 순수 함수(LocalNotificationService.nextInstanceOf)와 IANA명→Location
// 폴백(resolveLocation)을 검증한다. tzdata 는 setUp 에서 로드.

import 'package:flutter/material.dart' show TimeOfDay;
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'package:on_the_fly/core/notifications/local_notification_service.dart';

void main() {
  setUpAll(tzdata.initializeTimeZones);

  group('resolveLocation (IANA명 → tz.Location, 폴백)', () {
    test('유효한 IANA 이름은 해당 존을 반환한다', () {
      final loc = LocalNotificationService.resolveLocation('Asia/Seoul');
      expect(loc.name, 'Asia/Seoul');
    });

    test('알 수 없는 이름은 UTC 로 폴백한다(크래시 없음)', () {
      final loc = LocalNotificationService.resolveLocation('Not/AZone');
      expect(loc.name, 'UTC');
    });

    test('null/빈 문자열도 UTC 로 폴백한다', () {
      expect(LocalNotificationService.resolveLocation(null).name, 'UTC');
      expect(LocalNotificationService.resolveLocation('').name, 'UTC');
    });
  });

  group('nextInstanceOf (로컬 타임존 기준 다음 예약 시각)', () {
    test('KST 에서 21:00 예약은 KST 21:00 으로 잡힌다 (UTC 오프셋 버그 방지)', () {
      final seoul = tz.getLocation('Asia/Seoul');
      // 기준시각: 2026-07-02 09:00 KST → 아직 오늘 21:00 전.
      final now = tz.TZDateTime(seoul, 2026, 7, 2, 9);
      final next = LocalNotificationService.nextInstanceOf(
        const TimeOfDay(hour: 21, minute: 0),
        seoul,
        now: now,
      );
      expect(next.location.name, 'Asia/Seoul');
      expect(next.hour, 21);
      expect(next.minute, 0);
      expect(next.day, 2); // 오늘(2일).
    });

    test('예약 시각이 이미 지났으면 다음 날로 넘긴다', () {
      final seoul = tz.getLocation('Asia/Seoul');
      // 기준시각: 2026-07-02 22:00 KST → 오늘 21:00 은 지남.
      final now = tz.TZDateTime(seoul, 2026, 7, 2, 22);
      final next = LocalNotificationService.nextInstanceOf(
        const TimeOfDay(hour: 21, minute: 0),
        seoul,
        now: now,
      );
      expect(next.hour, 21);
      expect(next.day, 3); // 내일(3일)로 이월.
    });

    test('UTC 폴백 존에서도 지정 시각이 그대로 유지된다', () {
      final utc = tz.getLocation('UTC');
      final now = tz.TZDateTime(utc, 2026, 7, 2, 8);
      final next = LocalNotificationService.nextInstanceOf(
        const TimeOfDay(hour: 21, minute: 30),
        utc,
        now: now,
      );
      expect(next.location.name, 'UTC');
      expect(next.hour, 21);
      expect(next.minute, 30);
    });
  });
}
