// 앱 루트 위젯 스모크 테스트.
//
// core 서비스는 실기기/플랫폼 채널에 의존하므로 여기서는 온보딩 화면이
// 위젯 트리에 정상적으로 올라오는지만 확인한다(플랫폼 호출 없음).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:on_the_fly/app/theme.dart';
import 'package:on_the_fly/features/onboarding/onboarding_screen.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:on_the_fly/app/settings_store.dart';

void main() {
  testWidgets('온보딩 첫 스텝에 프라이버시 문구가 노출된다',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [sharedPrefsProvider.overrideWithValue(prefs)],
        child: MaterialApp(
          theme: buildAppTheme(),
          home: const OnboardingScreen(),
        ),
      ),
    );
    await tester.pump();

    expect(find.textContaining('폰 밖으로 나가지 않'), findsOneWidget);
    expect(find.text('시작하기'), findsOneWidget);
  });
}
