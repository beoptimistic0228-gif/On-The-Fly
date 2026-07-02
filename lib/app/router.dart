import 'package:go_router/go_router.dart';

import '../features/done/done_screen.dart';
import '../features/home/home_screen.dart';
import '../features/onboarding/onboarding_screen.dart';
import '../features/settings/settings_screen.dart';
import '../features/sort/sort_controller.dart';
import '../features/sort/sort_screen.dart';

/// 앱 라우팅. 온보딩 완료 여부에 따라 시작 위치 결정.
GoRouter buildRouter({required bool onboardingCompleted}) {
  return GoRouter(
    initialLocation: onboardingCompleted ? '/home' : '/onboarding',
    routes: [
      GoRoute(
        path: '/onboarding',
        builder: (context, state) => const OnboardingScreen(),
      ),
      GoRoute(
        path: '/home',
        builder: (context, state) => const HomeScreen(),
      ),
      GoRoute(
        path: '/sort',
        builder: (context, state) => const SortScreen(),
      ),
      GoRoute(
        path: '/done',
        builder: (context, state) {
          // commit 결과를 정리 화면에서 extra 로 전달받는다.
          final outcome = state.extra as CommitOutcome?;
          return DoneScreen(
            outcome: outcome ??
                const CommitOutcome(
                    successCount: 0, failedCount: 0, cancelled: false),
          );
        },
      ),
      GoRoute(
        path: '/settings',
        builder: (context, state) => const SettingsScreen(),
      ),
    ],
  );
}
