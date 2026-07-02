import 'dart:io';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/material.dart' show TimeOfDay;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'notification_service.dart';

/// flutter_local_notifications + timezone 기반 구현.
///
/// 매일 지정 시각 반복(`zonedSchedule` + `matchDateTimeComponents: time`).
/// Android 는 재부팅 지속(RECEIVE_BOOT_COMPLETED)·inexact 알람으로 설정
/// (02_feasibility R7 — 정시 리마인더라 inexact 허용, 권한 최소화).
class LocalNotificationService implements NotificationService {
  LocalNotificationService([FlutterLocalNotificationsPlugin? plugin])
      : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;

  static const int _dailyNotificationId = 1001;
  static const String _channelId = 'daily_reminder';
  static const String _channelName = '매일 정리 알림';
  static const String _channelDesc = '매일 지정 시각 정리 리마인더';

  bool _initialized = false;

  @override
  Future<void> init() async {
    if (_initialized) return;

    // 1) 타임존 DB 로드 — 반드시 getLocation 호출보다 먼저(순서 역전 금지).
    tzdata.initializeTimeZones();
    // 2) 기기 실제 IANA 타임존명을 얻어 tz.local 을 교체(FIX-1, A-2).
    //    timezone 패키지의 tz.local 기본값은 UTC 라, 이 설정이 없으면
    //    KST(UTC+9) 기기에서 21:00 예약이 익일 06:00 KST 로 발화한다.
    //    flutter_timezone 5.x: getLocalTimezone() → TimezoneInfo(.identifier).
    //    획득/해석 실패 시 UTC 로 폴백하고 계속 진행(부팅 차단·크래시 금지).
    String? tzName;
    try {
      final TimezoneInfo info = await FlutterTimezone.getLocalTimezone();
      tzName = info.identifier; // 예: 'Asia/Seoul'
    } catch (_) {
      tzName = null;
    }
    tz.setLocalLocation(resolveLocation(tzName));

    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    // 권한은 requestPermission() 에서 명시적으로 요청(초기화 시 요청 안 함).
    const darwinInit = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    const settings = InitializationSettings(
      android: androidInit,
      iOS: darwinInit,
      macOS: darwinInit,
    );
    await _plugin.initialize(settings: settings);
    _initialized = true;
  }

  @override
  Future<bool> requestPermission() async {
    if (Platform.isIOS || Platform.isMacOS) {
      final impl = _plugin.resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin>();
      final granted = await impl?.requestPermissions(
        alert: true,
        badge: true,
        sound: true,
      );
      return granted ?? false;
    }
    if (Platform.isAndroid) {
      final impl = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      final granted = await impl?.requestNotificationsPermission();
      return granted ?? false;
    }
    return false;
  }

  @override
  Future<void> scheduleDaily(TimeOfDay time) async {
    await init();
    await cancelAll();
    await _plugin.zonedSchedule(
      id: _dailyNotificationId,
      scheduledDate: _nextInstanceOf(time),
      notificationDetails: _details,
      // inexact: 정시 ±오차 허용 → SCHEDULE_EXACT_ALARM 권한 회피(리마인더 용도).
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      title: '그때그때',
      body: '오늘 미분류 사진을 정리해볼까요?',
      matchDateTimeComponents: DateTimeComponents.time, // 매일 반복
    );
  }

  @override
  Future<void> cancelAll() => _plugin.cancelAll();

  @override
  Future<bool> didAppLaunchFromNotification() async {
    // getNotificationAppLaunchDetails: 읽기 전용, 예약/타임존에 영향 없음.
    // 알림 탭으로 콜드 스타트된 경우에만 didNotificationLaunchApp == true.
    // (앱이 이미 떠 있을 때의 포그라운드/백그라운드 탭 계측은 후속 확장 —
    //  onDidReceiveNotificationResponse 콜백 배선 필요. 지금은 콜드 스타트만.)
    try {
      final details = await _plugin.getNotificationAppLaunchDetails();
      return details?.didNotificationLaunchApp ?? false;
    } catch (_) {
      return false;
    }
  }

  NotificationDetails get _details => const NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          channelDescription: _channelDesc,
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
        ),
        iOS: DarwinNotificationDetails(),
        macOS: DarwinNotificationDetails(),
      );

  /// 다음 [time] 시각의 TZDateTime(오늘 지났으면 내일). `tz.local` 기준.
  tz.TZDateTime _nextInstanceOf(TimeOfDay time) =>
      nextInstanceOf(time, tz.local);

  /// IANA 타임존명 → tz.Location. 알 수 없는 이름/`null` 이면 UTC 로 폴백.
  ///
  /// 반드시 [tzdata.initializeTimeZones] 이후에 호출해야 한다(DB 필요).
  /// 순수 함수라 단위 테스트로 폴백 동작을 검증할 수 있다.
  @visibleForTesting
  static tz.Location resolveLocation(String? name) {
    if (name != null && name.isNotEmpty) {
      try {
        return tz.getLocation(name);
      } catch (_) {
        // 알 수 없는 이름 → UTC 폴백(크래시 금지).
      }
    }
    return tz.getLocation('UTC');
  }

  /// 다음 [time] 시각을 [location] 기준으로 계산(오늘 지났으면 내일).
  ///
  /// 플랫폼 채널 없이 테스트 가능하도록 [location]·[now] 를 주입받는 순수 함수.
  @visibleForTesting
  static tz.TZDateTime nextInstanceOf(
    TimeOfDay time,
    tz.Location location, {
    tz.TZDateTime? now,
  }) {
    final current = now ?? tz.TZDateTime.now(location);
    var scheduled = tz.TZDateTime(
      location,
      current.year,
      current.month,
      current.day,
      time.hour,
      time.minute,
    );
    if (!scheduled.isAfter(current)) {
      scheduled = scheduled.add(const Duration(days: 1));
    }
    return scheduled;
  }
}
