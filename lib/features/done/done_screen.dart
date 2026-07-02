import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../home/home_providers.dart';
import '../sort/sort_controller.dart';

/// 완료(Done, F-09) — 성취 보상 화면. iOS 성취감 보완의 핵심.
///
/// N = commit **성공분** 기준(stage 예약 수 아님). 부분 실패 시 보조 안내.
class DoneScreen extends ConsumerStatefulWidget {
  const DoneScreen({super.key, required this.outcome});

  final CommitOutcome outcome;

  @override
  ConsumerState<DoneScreen> createState() => _DoneScreenState();
}

class _DoneScreenState extends ConsumerState<DoneScreen> {
  late final Future<int> _streakFuture;

  @override
  void initState() {
    super.initState();
    // markProcessed 반영 후의 최신 streak.
    _streakFuture = ref.read(processedRepositoryProvider).streakDays();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final o = widget.outcome;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const Spacer(),
              // 축하 애니메이션(간단 스케일 인).
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0.6, end: 1),
                duration: const Duration(milliseconds: 500),
                curve: Curves.elasticOut,
                builder: (context, scale, child) =>
                    Transform.scale(scale: scale, child: child),
                child: Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.check_rounded,
                      size: 72, color: theme.colorScheme.onPrimaryContainer),
                ),
              ),
              const SizedBox(height: 24),
              Text(
                '정리 완료!',
                style: theme.textTheme.headlineMedium
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                '${o.successCount}장을 앨범으로 옮겼어요',
                style: theme.textTheme.titleMedium,
              ),
              if (o.failedCount > 0) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.errorContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${o.failedCount}장은 반영하지 못했어요. 다음에 다시 시도해요.',
                    style: TextStyle(color: theme.colorScheme.onErrorContainer),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
              const SizedBox(height: 32),
              // streak 시각화.
              FutureBuilder<int>(
                future: _streakFuture,
                builder: (context, snap) {
                  final streak = snap.data ?? 0;
                  return Container(
                    padding: const EdgeInsets.symmetric(
                        vertical: 20, horizontal: 28),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Column(
                      children: [
                        const Text('🔥', style: TextStyle(fontSize: 40)),
                        const SizedBox(height: 8),
                        Text(
                          streak > 0 ? '$streak일 연속 정리 중!' : '오늘부터 시작이에요',
                          style: theme.textTheme.titleLarge?.copyWith(
                            color: theme.colorScheme.onPrimaryContainer,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),

              // TODO(P1, monetization-and-analytics): 광고 슬롯.
              // 첫 정리일 +7일(D3)부터 세션당 1회, 이 축하 "뒤"에만 노출.
              // core 의 shouldShowAd() 정책 함수로 트리거 판정. (지금 구현하지 않음)

              const Spacer(),
              FilledButton(
                onPressed: () {
                  // 홈 카운트/streak 갱신 후 이동.
                  ref.invalidate(homeDataProvider);
                  context.go('/home');
                },
                child: const Text('홈으로'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
