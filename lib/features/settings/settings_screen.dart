import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/settings_store.dart';
import '../../core/providers.dart';
import 'remove_ads_section.dart';

/// 설정(F-02/F-13 일부) — 알림 시각·토글·프라이버시 안내 + 광고 제거(F-10).
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
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('설정')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          // 알림.
          _Section(
            title: '알림',
            child: Column(
              children: [
                SwitchListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                  title: const Text('매일 정리 알림'),
                  subtitle: const Text('정한 시간에 하루 한 번 알려드려요.'),
                  value: _enabled,
                  onChanged: _toggle,
                ),
                const Divider(indent: 16, endIndent: 16),
                ListTile(
                  enabled: _enabled,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                  leading: const Icon(Icons.access_time),
                  title: const Text('알림 시각'),
                  trailing: Text(
                    _time.format(context),
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: _enabled
                          ? theme.colorScheme.primary
                          : theme.disabledColor,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  onTap: _enabled ? _pickTime : null,
                ),
              ],
            ),
          ),
          // 프라이버시.
          _Section(
            title: '프라이버시',
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.secondaryContainer,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.shield_outlined,
                        size: 22,
                        color: theme.colorScheme.onSecondaryContainer),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      '사진·영상은 폰 밖으로 나가지 않습니다. 모든 정리는 기기 안에서만 '
                      '이뤄지며, 원본이 외부 서버로 전송되지 않습니다.',
                      style: theme.textTheme.bodyMedium?.copyWith(height: 1.5),
                    ),
                  ),
                ],
              ),
            ),
          ),
          // 광고 제거(F-10) — 자체 섹션 스타일로 렌더.
          _Section(
            title: '광고',
            child: const RemoveAdsSection(),
          ),
        ],
      ),
    );
  }
}

/// 설정의 그룹 섹션 — 헤더 + 카드로 묶어 정돈감을 준다.
class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child});
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 16, 8, 8),
          child: Text(
            title,
            style: theme.textTheme.labelLarge?.copyWith(
              color: theme.colorScheme.primary,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.2,
            ),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: theme.colorScheme.outlineVariant),
          ),
          clipBehavior: Clip.antiAlias,
          child: child,
        ),
      ],
    );
  }
}
