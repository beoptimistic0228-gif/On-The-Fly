import 'package:flutter/material.dart' show TimeOfDay;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// SharedPreferences 인스턴스. `main()` 에서 override 로 실제 값 주입.
///
/// core 레이어는 온보딩 완료 여부·알림 시각 같은 UI 로컬 설정을 저장하지
/// 않으므로(02_integrator_notes 에 설정 저장소 계약 없음), features 레이어에서
/// SharedPreferences 로 최소한만 보관한다.
final sharedPrefsProvider = Provider<SharedPreferences>(
  (ref) => throw UnimplementedError('sharedPrefsProvider must be overridden'),
);

/// 온보딩 완료 여부·알림 시각 등 앱 로컬 설정 접근기.
class AppSettings {
  AppSettings(this._prefs);

  final SharedPreferences _prefs;

  static const _kOnboardingDone = 'onboarding_completed';
  static const _kNotifyHour = 'notify_hour';
  static const _kNotifyMinute = 'notify_minute';
  static const _kNotifyEnabled = 'notify_enabled';

  bool get onboardingCompleted => _prefs.getBool(_kOnboardingDone) ?? false;

  Future<void> setOnboardingCompleted(bool value) =>
      _prefs.setBool(_kOnboardingDone, value);

  /// 알림 시각(기본 21:00).
  TimeOfDay get notifyTime => TimeOfDay(
        hour: _prefs.getInt(_kNotifyHour) ?? 21,
        minute: _prefs.getInt(_kNotifyMinute) ?? 0,
      );

  Future<void> setNotifyTime(TimeOfDay time) async {
    await _prefs.setInt(_kNotifyHour, time.hour);
    await _prefs.setInt(_kNotifyMinute, time.minute);
  }

  bool get notifyEnabled => _prefs.getBool(_kNotifyEnabled) ?? false;

  Future<void> setNotifyEnabled(bool value) =>
      _prefs.setBool(_kNotifyEnabled, value);
}

final appSettingsProvider = Provider<AppSettings>(
  (ref) => AppSettings(ref.watch(sharedPrefsProvider)),
);
