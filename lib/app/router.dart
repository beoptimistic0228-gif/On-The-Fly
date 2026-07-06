import 'package:flutter/material.dart';
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
        pageBuilder: (context, state) =>
            _fade(state, const OnboardingScreen()),
      ),
      GoRoute(
        path: '/home',
        pageBuilder: (context, state) => _fade(state, const HomeScreen()),
      ),
      GoRoute(
        path: '/sort',
        pageBuilder: (context, state) => _fade(state, const SortScreen()),
      ),
      GoRoute(
        path: '/done',
        pageBuilder: (context, state) {
          // commit 결과를 정리 화면에서 extra 로 전달받는다.
          final outcome = state.extra as CommitOutcome?;
          return _fade(
            state,
            DoneScreen(
              outcome: outcome ??
                  const CommitOutcome(
                      successCount: 0, failedCount: 0, cancelled: false),
            ),
          );
        },
      ),
      GoRoute(
        path: '/settings',
        pageBuilder: (context, state) => _fade(state, const SettingsScreen()),
      ),
    ],
  );
}

/// 부드러운 페이드 + 살짝 떠오르는 전환. 정리 루프가 "차분하게" 이어지게 한다
/// (급격한 좌우 슬라이드보다 정돈된 느낌). 뒤로가기도 자동으로 역재생된다.
CustomTransitionPage<void> _fade(GoRouterState state, Widget child) {
  return CustomTransitionPage<void>(
    key: state.pageKey,
    transitionDuration: const Duration(milliseconds: 320),
    reverseTransitionDuration: const Duration(milliseconds: 240),
    child: child,
    transitionsBuilder: (context, animation, secondary, child) {
      final curved =
          CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
      return FadeTransition(
        opacity: curved,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 0.02),
            end: Offset.zero,
          ).animate(curved),
          child: child,
        ),
      );
    },
  );
}
