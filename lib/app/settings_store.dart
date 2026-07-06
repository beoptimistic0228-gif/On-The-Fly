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
  static const _kFirstSortAt = 'first_sort_at_ms';
  static const _kSeenDeleteIntro = 'seen_delete_intro';

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

  /// 첫 정리 완료일(없으면 null). 광고 노출 게이트 기준(D3: 첫 정리일 + 7일).
  ///
  /// **왜 설치일이 아니라 첫 정리일인가:** 습관이 붙기 전 첫 주는 광고 없이 정리
  /// 경험만 주기 위해서다(00_decisions D3). 설치만 하고 안 쓰는 사용자에겐 애초에
  /// 광고 기준 자체가 시작되지 않는다.
  DateTime? get firstSortDate {
    final ms = _prefs.getInt(_kFirstSortAt);
    return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
  }

  /// 첫 정리 완료일을 아직 없을 때만 기록(idempotent). 완료 화면 진입 시 호출.
  Future<void> recordFirstSortDateIfAbsent(DateTime when) async {
    if (_prefs.getInt(_kFirstSortAt) != null) return;
    await _prefs.setInt(_kFirstSortAt, when.millisecondsSinceEpoch);
  }

  /// 삭제 최초 1회 교육 시트를 이미 봤는지(D5, §0.2). 삭제 버튼 첫 사용 시 시트를
  /// 띄우고, 사용자가 [삭제]로 진행하면 true 로 기록해 이후엔 무마찰로 바로 삭제한다.
  bool get hasSeenDeleteIntro => _prefs.getBool(_kSeenDeleteIntro) ?? false;

  Future<void> setSeenDeleteIntro() =>
      _prefs.setBool(_kSeenDeleteIntro, true);
}

final appSettingsProvider = Provider<AppSettings>(
  (ref) => AppSettings(ref.watch(sharedPrefsProvider)),
);
