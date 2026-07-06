import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models/photo_permission.dart';
import '../../core/providers.dart';
import '../../app/settings_store.dart';
import 'permission_help.dart';

/// 온보딩(F-07): 가치 → 사진 권한 → 알림 권한·시각 → 첫 정리 진입.
/// 프라이버시 문구("사진은 폰 밖으로 안 나감", F-13)를 첫 스텝에서 노출.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _pageController = PageController();
  int _step = 0;

  PhotoPermission? _photoPermission;
  bool _requestingPhoto = false;

  bool _notifGranted = false;
  bool _requestingNotif = false;
  TimeOfDay _notifTime = const TimeOfDay(hour: 21, minute: 0);

  int? _unclassifiedCount;
  bool _countLoading = false;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _goTo(int step) {
    setState(() => _step = step);
    _pageController.animateToPage(
      step,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  Future<void> _requestPhoto() async {
    setState(() => _requestingPhoto = true);
    final perm = await ref.read(photoServiceProvider).ensurePermission();
    if (!mounted) return;
    setState(() {
      _photoPermission = perm;
      _requestingPhoto = false;
    });
    if (perm == PhotoPermission.granted) _goTo(2);
  }

  Future<void> _requestNotif() async {
    setState(() => _requestingNotif = true);
    final granted =
        await ref.read(notificationServiceProvider).requestPermission();
    if (!mounted) return;
    setState(() {
      _notifGranted = granted;
      _requestingNotif = false;
    });
  }

  Future<void> _pickTime() async {
    final picked =
        await showTimePicker(context: context, initialTime: _notifTime);
    if (picked != null && mounted) setState(() => _notifTime = picked);
  }

  Future<void> _confirmNotifAndNext() async {
    final settings = ref.read(appSettingsProvider);
    await settings.setNotifyTime(_notifTime);
    if (_notifGranted) {
      await ref.read(notificationServiceProvider).scheduleDaily(_notifTime);
      await settings.setNotifyEnabled(true);
    }
    if (!mounted) return;
    // 대용량 라이브러리(수만 장)는 스캔이 수십 초 걸린다 — 스캔을 기다리지 않고
    // 즉시 다음 스텝으로 넘어가고, 개수는 뒤에서 세며 스텝 4가 로딩을 표시한다
    // (2026-07-06 실기기 스모크: 여기서 대기하면 앱이 멈춘 것처럼 보임).
    _goTo(3);
    _loadUnclassifiedCount();
  }

  /// 미분류 개수 백그라운드 로드(스텝 4 노출용). 실패해도 온보딩은 계속
  /// 진행 가능해야 하므로 조용히 무시한다(정리 화면이 자체 재시도).
  Future<void> _loadUnclassifiedCount() async {
    setState(() => _countLoading = true);
    try {
      final queue = await ref.read(photoServiceProvider).loadUnclassifiedQueue();
      if (!mounted) return;
      setState(() => _unclassifiedCount = queue.length);
    } catch (_) {
      // 개수 미상 → 스텝 4는 "준비됐어요!" 폴백 문구를 쓴다.
    } finally {
      if (mounted) setState(() => _countLoading = false);
    }
  }

  Future<void> _finishToSort() async {
    final settings = ref.read(appSettingsProvider);
    await settings.setOnboardingCompleted(true);
    // 분석: 온보딩 완료 — 확정된 알림 시각·활성 여부 첨부(개인정보 아님).
    ref.read(analyticsServiceProvider).logOnboardingComplete(
          notifyHour: _notifTime.hour,
          notifyMinute: _notifTime.minute,
          notifyEnabled: settings.notifyEnabled,
        );
    if (!mounted) return;
    context.go('/sort');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            _StepIndicator(current: _step, total: 4),
            Expanded(
              child: PageView(
                controller: _pageController,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  _valueStep(),
                  _photoStep(),
                  _notifStep(),
                  _firstSortStep(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // 스텝 1 — 가치 소개 + 프라이버시.
  Widget _valueStep() {
    final theme = Theme.of(context);
    return _StepScaffold(
      children: [
        const Spacer(),
        const _HeroIcon(Icons.auto_awesome_mosaic),
        const SizedBox(height: 32),
        Text('하루 한 번, 스와이프로 정리',
            style: theme.textTheme.headlineSmall
                ?.copyWith(fontWeight: FontWeight.bold),
            textAlign: TextAlign.center),
        const SizedBox(height: 12),
        Text('밀린 사진·영상을 매일 조금씩,\n앨범으로 가볍게 정리해요.',
            style: theme.textTheme.bodyLarge
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            textAlign: TextAlign.center),
        const SizedBox(height: 24),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: theme.colorScheme.secondaryContainer,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: theme.colorScheme.onSecondaryContainer
                      .withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.lock_outline,
                    size: 22, color: theme.colorScheme.onSecondaryContainer),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  '사진은 폰 밖으로 나가지 않아요. 모든 정리는 기기 안에서만 이뤄져요.',
                  style: TextStyle(
                      color: theme.colorScheme.onSecondaryContainer,
                      height: 1.4),
                ),
              ),
            ],
          ),
        ),
        const Spacer(),
        // 풀너비 CTA 는 SizedBox 옵트인(테마 minimumSize 무한 너비 금지, theme.dart).
        SizedBox(
          width: double.infinity,
          child: FilledButton(
              onPressed: () => _goTo(1), child: const Text('시작하기')),
        ),
      ],
    );
  }

  // 스텝 2 — 사진/영상 권한.
  Widget _photoStep() {
    final theme = Theme.of(context);
    final perm = _photoPermission;
    return _StepScaffold(
      children: [
        const Spacer(),
        const _HeroIcon(Icons.photo_library_outlined),
        const SizedBox(height: 24),
        Text('사진 접근을 허용해 주세요',
            style: theme.textTheme.titleLarge, textAlign: TextAlign.center),
        const SizedBox(height: 12),
        const Text(
          '미분류 사진·영상을 찾아 정리하려면 접근 권한이 필요해요. '
          'iOS 에서는 "모든 사진" 전체 접근을 선택해 주세요.',
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 20),
        if (perm == PhotoPermission.limited) const LimitedAccessCard(),
        if (perm == PhotoPermission.denied)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: theme.colorScheme.errorContainer,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Text(
              '접근이 거부됐어요. 이 앱의 핵심 기능을 쓰려면 접근이 필요해요. '
              '설정 앱에서 허용하거나 다시 시도해 주세요.',
              style: TextStyle(color: theme.colorScheme.onErrorContainer),
            ),
          ),
        const Spacer(),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: _requestingPhoto ? null : _requestPhoto,
            child: _requestingPhoto
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : Text(perm == null ? '사진 접근 허용' : '다시 시도'),
          ),
        ),
        if (perm == PhotoPermission.limited || perm == PhotoPermission.granted)
          TextButton(
            onPressed: () => _goTo(2),
            child: const Text('다음'),
          ),
      ],
    );
  }

  // 스텝 3 — 알림 권한 + 시각.
  Widget _notifStep() {
    final theme = Theme.of(context);
    return _StepScaffold(
      children: [
        const Spacer(),
        const _HeroIcon(Icons.notifications_active_outlined),
        const SizedBox(height: 24),
        Text('매일 정리 알림',
            style: theme.textTheme.titleLarge, textAlign: TextAlign.center),
        const SizedBox(height: 12),
        const Text('하루 한 번 정리 시간을 알려드릴게요. 알림을 허용해 주세요.',
            textAlign: TextAlign.center),
        const SizedBox(height: 24),
        OutlinedButton.icon(
          onPressed: _requestingNotif ? null : _requestNotif,
          icon: Icon(_notifGranted ? Icons.check : Icons.notifications),
          label: Text(_notifGranted ? '알림 허용됨' : '알림 허용'),
        ),
        const SizedBox(height: 24),
        ListTile(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: theme.colorScheme.outlineVariant),
          ),
          leading: const Icon(Icons.access_time),
          title: const Text('알림 시각'),
          trailing: Text(
            _notifTime.format(context),
            style: theme.textTheme.titleMedium,
          ),
          onTap: _pickTime,
        ),
        const Spacer(),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: _confirmNotifAndNext,
            child: const Text('다음'),
          ),
        ),
        TextButton(
          onPressed: _confirmNotifAndNext,
          child: const Text('나중에 설정'),
        ),
      ],
    );
  }

  // 스텝 4 — 첫 정리 유도.
  Widget _firstSortStep() {
    final theme = Theme.of(context);
    final count = _unclassifiedCount;
    return _StepScaffold(
      children: [
        const Spacer(),
        const _HeroIcon(Icons.swipe),
        const SizedBox(height: 24),
        // 개수 스캔 중(대용량 라이브러리는 수십 초)에는 멈춘 게 아니라
        // 세는 중임을 명시한다 — 홈 로딩 문구와 동일 톤.
        if (_countLoading) ...[
          const Center(
            child: SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            '미분류 사진을 세는 중...',
            style: theme.textTheme.titleLarge,
            textAlign: TextAlign.center,
          ),
        ] else
          Text(
            count == null
                ? '준비됐어요!'
                : count == 0
                    ? '지금은 미분류 사진이 없어요'
                    : '오늘 미분류 $count장이 있어요',
            style: theme.textTheme.titleLarge,
            textAlign: TextAlign.center,
          ),
        const SizedBox(height: 12),
        const Text('스와이프 한 번으로 앨범에 배정해 보세요.',
            textAlign: TextAlign.center),
        const Spacer(),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: _finishToSort,
            child: const Text('지금 첫 정리 시작'),
          ),
        ),
      ],
    );
  }
}

class _StepScaffold extends StatelessWidget {
  const _StepScaffold({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    );
  }
}

class _StepIndicator extends StatelessWidget {
  const _StepIndicator({required this.current, required this.total});
  final int current;
  final int total;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 24),
      child: Row(
        children: [
          for (var i = 0; i < total; i++)
            Expanded(
              // 현재 스텝은 더 길게 강조(진행감). 지난/현재는 primary, 남은 건 흐리게.
              flex: i == current ? 3 : 2,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOut,
                height: 5,
                margin: const EdgeInsets.symmetric(horizontal: 3),
                decoration: BoxDecoration(
                  color: i <= current
                      ? theme.colorScheme.primary
                      : theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 온보딩 히어로 아이콘 — 브랜드 톤의 부드러운 그라데이션 원 안에 아이콘.
class _HeroIcon extends StatelessWidget {
  const _HeroIcon(this.icon);
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Container(
        width: 116,
        height: 116,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [scheme.primaryContainer, scheme.tertiaryContainer],
          ),
        ),
        child: Icon(icon, size: 56, color: scheme.onPrimaryContainer),
      ),
    );
  }
}
