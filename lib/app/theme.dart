import 'package:flutter/material.dart';

/// 앱 전역 테마. 따뜻하고 정돈된 톤 — "가볍게 매일 정리한다"는 감각.
ThemeData buildAppTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: const Color(0xFF3D5AFE),
    brightness: Brightness.light,
  );
  return ThemeData(
    colorScheme: scheme,
    useMaterial3: true,
    scaffoldBackgroundColor: scheme.surface,
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface,
      elevation: 0,
      centerTitle: false,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        // ⚠️ Size.fromHeight(56) = 최소 너비 무한대 금지. Row/ListTile trailing 등
        // 가로 무한 컨텍스트에서 레이아웃 예외 → 화면 전체가 하얗게 죽는다
        // (2026-07-06 S22 실기기: 정리 화면 배너의 커밋 버튼에서 확인).
        // 풀너비 CTA 는 콜사이트에서 SizedBox(width: double.infinity)로 옵트인.
        minimumSize: const Size(64, 56),
        textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),
    ),
  );
}
