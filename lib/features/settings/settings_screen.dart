import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/settings_store.dart';
import '../../core/providers.dart';

/// 설정(F-02/F-13 일부) — 알림 시각·토글·프라이버시 안내.
/// 광고 제거(IAP)는 P1 이라 여기서 구현하지 않음.
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  late TimeOfDay _time;
  late bool _enabled;

  @override
  void initState() {
    super.initState();
    final s = ref.read(appSettingsProvider);
    _time = s.notifyTime;
    _enabled = s.notifyEnabled;
  }

  Future<void> _pickTime() async {
    final picked =
        await showTimePicker(context: context, initialTime: _time);
    if (picked == null || !mounted) return;
    setState(() => _time = picked);
    await ref.read(appSettingsProvider).setNotifyTime(picked);
    if (_enabled) {
      await ref.read(notificationServiceProvider).scheduleDaily(picked);
    }
  }

  Future<void> _toggle(bool value) async {
    setState(() => _enabled = value);
    final settings = ref.read(appSettingsProvider);
    final notif = ref.read(notificationServiceProvider);
    await settings.setNotifyEnabled(value);
    if (value) {
      final granted = await notif.requestPermission();
      if (granted) {
        await notif.scheduleDaily(_time);
      } else if (mounted) {
        setState(() => _enabled = false);
        await settings.setNotifyEnabled(false);
      }
    } else {
      await notif.cancelAll();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('설정')),
      body: ListView(
        children: [
          SwitchListTile(
            title: const Text('매일 정리 알림'),
            value: _enabled,
            onChanged: _toggle,
          ),
          ListTile(
            enabled: _enabled,
            leading: const Icon(Icons.access_time),
            title: const Text('알림 시각'),
            trailing: Text(_time.format(context)),
            onTap: _enabled ? _pickTime : null,
          ),
          const Divider(),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text('프라이버시',
                style: TextStyle(fontWeight: FontWeight.bold)),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              '사진·영상은 폰 밖으로 나가지 않습니다. 모든 정리는 기기 안에서만 '
              '이뤄지며, 원본이 외부 서버로 전송되지 않습니다.',
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
