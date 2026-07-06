import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models/photo_permission.dart';
import '../../core/providers.dart';
import '../onboarding/permission_help.dart';
import 'home_providers.dart';

/// 홈(F-02): "오늘 미분류 N장" + 정리 시작 + streak. 로딩/빈/정상/에러 상태.
///
/// C-2: 권한 카드/에러의 "설정에서 전체 접근 허용"은 설정 앱을 여는데, 이 호출은
/// 즉시 반환하므로 그 자리에서 권한을 재확인할 수 없다. 대신 앱이 다시 활성화될
/// 때(설정에서 복귀) [homeDataProvider] 를 무효화해 권한·미분류 수를 다시 읽는다.
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 설정 앱에서 권한을 바꾸고 돌아오면(resume) 홈 데이터를 다시 읽어 반영한다.
    if (state == AppLifecycleState.resumed) {
      ref.invalidate(homeDataProvider);
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(homeDataProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('그때그때'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: '설정',
            onPressed: () => context.push('/settings'),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(homeDataProvider),
        child: Stack(
          children: [
            async.when(
              loading: () => const _HomeLoading(),
              error: (err, _) => _HomeError(error: err),
              data: (data) => _HomeBody(data: data),
            ),
            // 정리 완료/설정 복귀 후 재스캔은 대용량 라이브러리(수만 장)에서
            // 수십 초 걸리는데, when 은 그동안 이전 값을 그대로 보여준다
            // (skipLoadingOnRefresh). 갱신 중임을 상단 바로 알린다
            // (2026-07-06 실기기 스모크: 카운트가 안 바뀌는 것처럼 보임).
            if (async.isRefreshing)
              const Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: LinearProgressIndicator(minHeight: 3),
              ),
          ],
        ),
      ),
    );
  }
}

class _HomeLoading extends StatelessWidget {
  const _HomeLoading();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 32, 20, 24),
      children: [
        // 카운트 히어로 스켈레톤.
        Container(
          height: 220,
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainer,
            borderRadius: BorderRadius.circular(28),
          ),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(
                  width: 26,
                  height: 26,
                  child: CircularProgressIndicator(strokeWidth: 2.5),
                ),
                const SizedBox(height: 16),
                Text('미분류 사진을 세는 중...',
                    style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant)),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _HomeError extends ConsumerWidget {
  const _HomeError({required this.error});

  final Object error;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final isPermission = error is PhotoAccessException;
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const SizedBox(height: 72),
        Container(
          width: 96,
          height: 96,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: theme.colorScheme.errorContainer,
            shape: BoxShape.circle,
          ),
          child: Icon(
            isPermission ? Icons.lock_outline : Icons.error_outline,
            size: 48,
            color: theme.colorScheme.onErrorContainer,
          ),
        ),
        const SizedBox(height: 24),
        Text(
          isPermission ? '사진 접근 권한이 필요해요' : '문제가 생겼어요',
          textAlign: TextAlign.center,
          style: theme.textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        Text(
          isPermission
              ? '사진 접근을 허용하면 미분류 사진을 정리할 수 있어요. 이미 거부했다면 설정 앱에서 켜주세요.'
              : '잠시 후 다시 시도해 주세요.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 28),
        // 풀너비 CTA 는 SizedBox 옵트인(테마 minimumSize 무한 너비 금지, theme.dart).
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: () async {
              if (isPermission) {
                // C-2: 먼저 재요청(Android 재질문 가능 상태는 다이얼로그가 뜸).
                // 영구 거부라 다이얼로그 없이 그대로면 설정 앱으로 보낸다 —
                // 복귀(resume) 시 HomeScreen 관찰자가 권한을 재확인한다.
                // limited 로 바뀐 경우는 설정으로 안 보낸다 — 홈 재로드 후
                // LimitedAccessCard 가 전체 접근 유도(D2)를 맡는다.
                final photo = ref.read(photoServiceProvider);
                final perm = await photo.ensurePermission();
                if (perm == PhotoPermission.denied) {
                  await photo.openSystemSettings();
                  return;
                }
              }
              ref.invalidate(homeDataProvider);
            },
            child: Text(isPermission ? '권한 허용하기' : '다시 시도'),
          ),
        ),
      ],
    );
  }
}

class _HomeBody extends ConsumerWidget {
  const _HomeBody({required this.data});

  final HomeData data;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final empty = data.isEmpty;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 28),
      children: [
        if (data.permission == PhotoPermission.limited) ...[
          const LimitedAccessCard(),
          const SizedBox(height: 16),
        ],
        _CountHero(count: data.unclassifiedCount, empty: empty),
        const SizedBox(height: 16),
        _StreakCard(days: data.streakDays),
        const SizedBox(height: 28),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: empty
                ? null
                : () async {
                    await context.push('/sort');
                    // 정리 후 홈 큐 갱신.
                    ref.invalidate(homeDataProvider);
                  },
            icon: Icon(empty ? Icons.check_circle_outline : Icons.swipe),
            label: Text(empty ? '정리할 사진이 없어요' : '정리 시작'),
          ),
        ),
        if (!empty) ...[
          const SizedBox(height: 12),
          Center(
            child: Text(
              '30초면 충분해요 · 한 번에 한 장씩',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ),
        ],
      ],
    );
  }
}

/// 미분류 카운트 히어로 — 홈의 시선 1순위. 빈 상태는 축하 톤.
class _CountHero extends StatelessWidget {
  const _CountHero({required this.count, required this.empty});

  final int count;
  final bool empty;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    if (empty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 44, horizontal: 24),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [scheme.primaryContainer, scheme.tertiaryContainer],
          ),
          borderRadius: BorderRadius.circular(28),
        ),
        child: Column(
          children: [
            const Text('🎉', style: TextStyle(fontSize: 48)),
            const SizedBox(height: 16),
            Text(
              '오늘은 다 정리했어요',
              style: theme.textTheme.headlineSmall?.copyWith(
                color: scheme.onPrimaryContainer,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '내일 새 사진이 쌓이면 다시 알려드릴게요.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.onPrimaryContainer.withValues(alpha: 0.8),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            scheme.primaryContainer,
            Color.alphaBlend(
                scheme.primaryContainer.withValues(alpha: 0.45),
                scheme.surfaceContainerLow),
          ],
        ),
        borderRadius: BorderRadius.circular(28),
      ),
      child: Column(
        children: [
          Text(
            '오늘 미분류',
            style: theme.textTheme.titleMedium?.copyWith(
              color: scheme.onPrimaryContainer.withValues(alpha: 0.85),
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                '$count',
                style: theme.textTheme.displayLarge?.copyWith(
                  color: scheme.onPrimaryContainer,
                  height: 1.0,
                ),
              ),
              const SizedBox(width: 4),
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  '장',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    color: scheme.onPrimaryContainer,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StreakCard extends StatelessWidget {
  const _StreakCard({required this.days});

  final int days;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    // 이번 주 습관 시각화: 7칸 중 streak 만큼 채움(7 초과는 가득). 원칙 3.
    final filled = days.clamp(0, 7);

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: days > 0
                  ? scheme.primaryContainer
                  : scheme.surfaceContainerHigh,
              shape: BoxShape.circle,
            ),
            child: Text(days > 0 ? '🔥' : '✨',
                style: const TextStyle(fontSize: 26)),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  days > 0 ? '$days일 연속 정리 중' : '오늘부터 시작해요',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    for (var i = 0; i < 7; i++)
                      Expanded(
                        child: Container(
                          height: 6,
                          margin: EdgeInsets.only(right: i == 6 ? 0 : 5),
                          decoration: BoxDecoration(
                            color: i < filled
                                ? scheme.primary
                                : scheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
