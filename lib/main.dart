import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app/router.dart';
import 'app/settings_store.dart';
import 'app/theme.dart';
import 'core/analytics/analytics_service.dart';
import 'core/analytics/firebase_analytics_service.dart';
import 'core/analytics/local_analytics_service.dart';
import 'core/monetization/admob_ad_service.dart';
import 'core/monetization/ad_service.dart';
import 'core/monetization/in_app_purchase_service.dart';
import 'core/monetization/noop_ad_service.dart';
import 'core/monetization/noop_purchase_service.dart';
import 'core/monetization/purchase_service.dart';
import 'core/providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // SharedPreferences 를 부팅 시 한 번 로드해 프로바이더로 주입(동기 접근용).
  final prefs = await SharedPreferences.getInstance();

  // 분석 백엔드 결정: Firebase 초기화가 성공하면 Firebase, 실패하면 로컬 폴백.
  final analyticsService = await _initAnalyticsService();

  // 수익화(P1) 서비스 부팅. 실패해도 앱은 정상 동작(광고·결제는 부가 기능).
  final adService = await _initAdService();
  final purchaseService = await _initPurchaseService(prefs, analyticsService);

  // ProviderScope 를 감싸는 컨테이너(02_integrator_notes D 지침).
  final container = ProviderContainer(
    overrides: [
      sharedPrefsProvider.overrideWithValue(prefs),
      analyticsServiceProvider.overrideWithValue(analyticsService),
      adServiceProvider.overrideWithValue(adService),
      purchaseServiceProvider.overrideWithValue(purchaseService),
    ],
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

/// Firebase 초기화를 시도하고 결과에 맞는 [AnalyticsService] 를 만든다.
///
/// **왜 try-catch 폴백인가:** Firebase 콘솔 프로젝트/설정 파일
/// (`google-services.json`·`GoogleService-Info.plist`·`firebase_options.dart`)이
/// 아직 없으므로 `Firebase.initializeApp()` 은 설정을 못 찾아 예외를 던진다. 이때
/// 앱이 크래시하면 안 되므로(설정은 나중에 붙인다, 02_builder_notes "Firebase
/// 활성화 절차") 실패 시 조용히 [LocalAnalyticsService] 로 폴백한다. 설정이 붙어
/// 초기화가 성공하는 순간부터는 코드 변경 없이 자동으로 Firebase 로 전송된다.
Future<AnalyticsService> _initAnalyticsService() async {
  try {
    await Firebase.initializeApp();
    debugPrint('[analytics] Firebase 초기화 성공 → FirebaseAnalyticsService 사용');
    return FirebaseAnalyticsService(FirebaseAnalytics.instance);
  } catch (e) {
    // 설정 파일 부재(가장 흔함) 또는 초기화 실패 → 로컬 폴백. 크래시 금지.
    debugPrint('[analytics] Firebase 초기화 실패 → LocalAnalyticsService 폴백: $e');
    return LocalAnalyticsService();
  }
}

/// AdMob(F-09) 초기화. 지원 플랫폼이면 `AdMobAdService`, 실패/미지원이면 Noop.
///
/// **왜 폴백인가:** 초기화 크래시(매니페스트 App ID 누락 등)나 미지원 플랫폼에서도
/// 앱이 죽으면 안 된다. `AdMobAdService.initialize()` 자체가 내부 try-catch 지만,
/// 여기서도 방어적으로 감싼다. 광고는 완료 화면 뒤 부가물이므로 없으면 그냥 없다.
Future<AdService> _initAdService() async {
  try {
    final service = AdMobAdService();
    await service.initialize();
    if (!service.isSupported) return NoopAdService();
    return service;
  } catch (e) {
    debugPrint('[ads] 광고 서비스 초기화 실패 → NoopAdService 폴백: $e');
    return NoopAdService();
  }
}

/// 광고 제거 IAP(F-10) 초기화. 정상이면 `InAppPurchaseService`(구매 스트림 구독),
/// 초기화 실패 시 로컬 캐시값을 살린 Noop 로 폴백(이미 구매한 사용자 보호).
Future<PurchaseService> _initPurchaseService(
  SharedPreferences prefs,
  AnalyticsService analytics,
) async {
  try {
    final service =
        InAppPurchaseService(InAppPurchase.instance, prefs, analytics);
    await service.initialize();
    return service;
  } catch (e) {
    debugPrint('[iap] 결제 서비스 초기화 실패 → NoopPurchaseService 폴백: $e');
    // 이미 광고 제거를 산 사용자라면 로컬 캐시로 계속 광고를 막아준다.
    final owned = prefs.getBool('remove_ads_owned') ?? false;
    return NoopPurchaseService(owned);
  }
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
