import 'package:flutter/material.dart' show TimeOfDay;

/// 로컬 알림 경계 계약(architecture §2.3, F-02).
abstract class NotificationService {
  /// 플러그인·타임존 초기화. 앱 시작 시 1회 호출.
  Future<void> init();

  /// 알림 권한 요청(Android 13+ POST_NOTIFICATIONS / iOS alert·badge·sound).
  /// 허용되면 true.
  Future<bool> requestPermission();

  /// 매일 [time] 에 반복 알림 예약(기존 예약은 갱신).
  Future<void> scheduleDaily(TimeOfDay time);

  /// 예약된 모든 알림 취소.
  Future<void> cancelAll();

  /// 이번 앱 실행이 **알림 탭으로 시작됐는지**(콜드 스타트) 반환.
  /// 분석 `notification_opened` 계측용(F-12). [init] 이후 1회 조회한다.
  /// 알림과 무관한 일반 실행이면 false.
  Future<bool> didAppLaunchFromNotification();
}
