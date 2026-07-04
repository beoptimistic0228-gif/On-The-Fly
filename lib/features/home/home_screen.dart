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
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(homeDataProvider),
        child: async.when(
          loading: () => const _HomeLoading(),
          error: (err, _) => _HomeError(error: err),
          data: (data) => _HomeBody(data: data),
        ),
      ),
    );
  }
}

class _HomeLoading extends StatelessWidget {
  const _HomeLoading();

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: const [
        SizedBox(height: 120),
        Center(child: CircularProgressIndicator()),
        SizedBox(height: 16),
        Center(child: Text('미분류 사진을 세는 중...')),
      ],
    );
  }
}

class _HomeError extends ConsumerWidget {
  const _HomeError({required this.error});

  final Object error;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isPermission = error is PhotoAccessException;
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const SizedBox(height: 80),
        Icon(
          isPermission ? Icons.lock_outline : Icons.error_outline,
          size: 64,
          color: Theme.of(context).colorScheme.error,
        ),
        const SizedBox(height: 16),
        Text(
          isPermission ? '사진 접근 권한이 필요해요' : '문제가 생겼어요',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        Text(
          isPermission
              ? '사진 접근을 허용하면 미분류 사진을 정리할 수 있어요. 이미 거부했다면 설정 앱에서 켜주세요.'
              : '잠시 후 다시 시도해 주세요.',
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        FilledButton(
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
      ],
    );
  }
}

class _HomeBody extends ConsumerWidget {
  const _HomeBody({required this.data});

  final HomeData data;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final empty = data.isEmpty;

    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
      children: [
        const SizedBox(height: 24),
        if (data.permission == PhotoPermission.limited) ...[
          const LimitedAccessCard(),
          const SizedBox(height: 20),
        ],
        // 미분류 카운트 / 빈 상태.
        Center(
          child: Column(
            children: [
              Text(
                empty ? '오늘은 다 정리했어요 🎉' : '오늘 미분류',
                style: theme.textTheme.titleMedium
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 8),
              if (!empty)
                Text(
                  '${data.unclassifiedCount}장',
                  style: theme.textTheme.displayMedium
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
              if (empty)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    '내일 새 사진이 쌓이면 다시 알려드릴게요.',
                    style: theme.textTheme.bodyMedium,
                    textAlign: TextAlign.center,
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 32),
        // streak.
        _StreakCard(days: data.streakDays),
        const SizedBox(height: 40),
        FilledButton.icon(
          onPressed: empty
              ? null
              : () async {
                  await context.push('/sort');
                  // 정리 후 홈 큐 갱신.
                  ref.invalidate(homeDataProvider);
                },
          icon: const Icon(Icons.swipe),
          label: Text(empty ? '정리할 사진이 없어요' : '정리 시작'),
        ),
      ],
    );
  }
}

class _StreakCard extends StatelessWidget {
  const _StreakCard({required this.days});

  final int days;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 24),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text('🔥', style: TextStyle(fontSize: 32)),
          const SizedBox(width: 12),
          Text(
            days > 0 ? '$days일 연속 정리 중' : '오늘부터 시작해요',
            style: theme.textTheme.titleLarge?.copyWith(
              color: theme.colorScheme.onPrimaryContainer,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
