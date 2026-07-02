import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app/router.dart';
import 'app/settings_store.dart';
import 'app/theme.dart';
import 'core/providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // SharedPreferences 를 부팅 시 한 번 로드해 프로바이더로 주입(동기 접근용).
  final prefs = await SharedPreferences.getInstance();

  // ProviderScope 를 감싸는 컨테이너(02_integrator_notes D 지침).
  final container = ProviderContainer(
    overrides: [sharedPrefsProvider.overrideWithValue(prefs)],
  );

  // 앱 시작 시 알림 서비스 1회 초기화(NotificationService.init, notes A·D).
  await container.read(notificationServiceProvider).init();

  // 분석: 앱 실행(app_open). + 알림 탭으로 콜드 스타트됐으면 notification_opened.
  final analytics = container.read(analyticsServiceProvider);
  analytics.logAppOpen();
  final fromNotification =
      await container.read(notificationServiceProvider).didAppLaunchFromNotification();
  if (fromNotification) analytics.logNotificationOpened();

  final onboardingCompleted =
      container.read(appSettingsProvider).onboardingCompleted;

  runApp(
    UncontrolledProviderScope(
      container: container,
      child: OnTheFlyApp(onboardingCompleted: onboardingCompleted),
    ),
  );
}

class OnTheFlyApp extends StatefulWidget {
  const OnTheFlyApp({super.key, required this.onboardingCompleted});

  final bool onboardingCompleted;

  @override
  State<OnTheFlyApp> createState() => _OnTheFlyAppState();
}

class _OnTheFlyAppState extends State<OnTheFlyApp> {
  late final _router =
      buildRouter(onboardingCompleted: widget.onboardingCompleted);

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: '그때그때',
      theme: buildAppTheme(),
      debugShowCheckedModeBanner: false,
      routerConfig: _router,
    );
  }
}
