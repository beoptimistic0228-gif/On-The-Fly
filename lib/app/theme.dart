// 앱 전역 테마 — "따뜻하고 정돈된, 매일 가볍게 정리한다"는 감각.
//
// 톤: 허니 앰버(따뜻한 주황) 브랜드 컬러 + 웜 페이퍼 배경. streak 의 🔥 와
// 색이 한 계열로 묶여 "성취/습관" 정서를 강화한다(디자인 원칙 3, iOS 성취감 보완).
// 라이트/다크 두 벌을 모두 제공한다 — 알림이 밤(기본 21:00)에 오는 앱이라 다크가
// 실사용 맥락에 잘 맞고, 사진이 어두운 배경에서 더 돋보인다(원칙 1 "사진이 주인공").
import 'package:flutter/material.dart';

/// 브랜드 시드(허니 앰버). ColorScheme 파생의 기준.
const _seed = Color(0xFFCB5E24);

/// 정리(스와이프) 화면 전용 "라이트박스" 캔버스. 라이트/다크 공통으로 깊은 웜
/// 차콜을 써서 사진이 화면의 주인공이 되게 한다(원칙 1). 화면 크롬은 이 위에 최소.
const kSortCanvas = Color(0xFF1C1613);
const kSortCanvasElevated = Color(0xFF2A211B);

ThemeData buildAppTheme() => _themeFor(_lightScheme());
ThemeData buildDarkAppTheme() => _themeFor(_darkScheme());

ColorScheme _lightScheme() {
  final base = ColorScheme.fromSeed(seedColor: _seed);
  return base.copyWith(
    primary: const Color(0xFFB85A22),
    onPrimary: Colors.white,
    primaryContainer: const Color(0xFFFFDBC7),
    onPrimaryContainer: const Color(0xFF351100),
    secondary: const Color(0xFF8A6552),
    onSecondary: Colors.white,
    secondaryContainer: const Color(0xFFFBE0D2),
    onSecondaryContainer: const Color(0xFF3A2318),
    tertiary: const Color(0xFF6C662F),
    tertiaryContainer: const Color(0xFFF6ECA8),
    onTertiaryContainer: const Color(0xFF211E00),
    // 웜 페이퍼 계열 — 순백 대신 아주 옅은 살구빛 종이. 사진이 배경에서 뜬다.
    surface: const Color(0xFFFCF7F2),
    surfaceContainerLowest: Colors.white,
    surfaceContainerLow: const Color(0xFFF8F1EA),
    surfaceContainer: const Color(0xFFF3EAE1),
    surfaceContainerHigh: const Color(0xFFEDE3D9),
    surfaceContainerHighest: const Color(0xFFE7DBCF),
    onSurface: const Color(0xFF231A13),
    onSurfaceVariant: const Color(0xFF5A4A3D),
    outline: const Color(0xFF8C7A6B),
    outlineVariant: const Color(0xFFDDCBBB),
  );
}

ColorScheme _darkScheme() {
  final base = ColorScheme.fromSeed(
    seedColor: _seed,
    brightness: Brightness.dark,
  );
  return base.copyWith(
    primary: const Color(0xFFFFB68A),
    onPrimary: const Color(0xFF551D00),
    primaryContainer: const Color(0xFF7A3A17),
    onPrimaryContainer: const Color(0xFFFFDBC7),
    secondary: const Color(0xFFE7BBA6),
    onSecondary: const Color(0xFF442A1B),
    secondaryContainer: const Color(0xFF5D4030),
    onSecondaryContainer: const Color(0xFFFBE0D2),
    tertiary: const Color(0xFFD9D08E),
    onTertiary: const Color(0xFF393405),
    tertiaryContainer: const Color(0xFF514C1A),
    onTertiaryContainer: const Color(0xFFF6ECA8),
    surface: const Color(0xFF16110D),
    surfaceContainerLowest: const Color(0xFF100C09),
    surfaceContainerLow: const Color(0xFF1D1712),
    surfaceContainer: const Color(0xFF221B15),
    surfaceContainerHigh: const Color(0xFF2C251E),
    surfaceContainerHighest: const Color(0xFF382F27),
    onSurface: const Color(0xFFEFE3D8),
    onSurfaceVariant: const Color(0xFFCFBEAF),
    outline: const Color(0xFF9A8879),
    outlineVariant: const Color(0xFF4E4237),
  );
}

ThemeData _themeFor(ColorScheme scheme) {
  final isLight = scheme.brightness == Brightness.light;
  return ThemeData(
    colorScheme: scheme,
    useMaterial3: true,
    scaffoldBackgroundColor: scheme.surface,
    splashFactory: InkSparkle.splashFactory,
    textTheme: _textTheme(scheme),
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface,
      surfaceTintColor: Colors.transparent,
      foregroundColor: scheme.onSurface,
      elevation: 0,
      scrolledUnderElevation: 0.5,
      centerTitle: false,
      titleTextStyle: TextStyle(
        color: scheme.onSurface,
        fontSize: 22,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.3,
      ),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: scheme.surfaceContainerLow,
      surfaceTintColor: Colors.transparent,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        // ⚠️ Size.fromHeight(56) = 최소 너비 무한대 금지. Row/ListTile trailing 등
        // 가로 무한 컨텍스트에서 레이아웃 예외 → 화면 전체가 하얗게 죽는다
        // (2026-07-06 S22 실기기: 정리 화면 배너의 커밋 버튼에서 확인).
        // 풀너비 CTA 는 콜사이트에서 SizedBox(width: double.infinity)로 옵트인.
        minimumSize: const Size(64, 56),
        textStyle: const TextStyle(
            fontSize: 17, fontWeight: FontWeight.w700, letterSpacing: -0.1),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(64, 52),
        side: BorderSide(color: scheme.outlineVariant),
        foregroundColor: scheme.onSurface,
        textStyle:
            const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: scheme.primary,
        textStyle:
            const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: scheme.surfaceContainerHigh,
      side: BorderSide.none,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      labelStyle: TextStyle(
        color: scheme.onSurface,
        fontWeight: FontWeight.w600,
        fontSize: 14,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: scheme.surfaceContainerLow,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: scheme.surfaceContainerLow,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: scheme.inverseSurface,
      contentTextStyle: TextStyle(color: scheme.onInverseSurface),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surfaceContainerHighest,
      isDense: true,
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: scheme.primary, width: 1.6),
      ),
    ),
    listTileTheme: ListTileThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
    dividerTheme: DividerThemeData(
      color: scheme.outlineVariant,
      thickness: 1,
      space: 1,
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: scheme.primary,
      linearTrackColor: scheme.surfaceContainerHighest,
      circularTrackColor: isLight ? scheme.surfaceContainerHigh : null,
    ),
  );
}

/// 타이포그래피 — 기본(Roboto/시스템 CJK) 위에 트래킹·굵기만 손봐 "의도된" 느낌.
/// 새 폰트 파일/네트워크 폰트는 추가하지 않는다(오프라인·의존성 최소).
TextTheme _textTheme(ColorScheme scheme) {
  final base =
      (scheme.brightness == Brightness.light ? Typography.blackMountainView
          : Typography.whiteMountainView);
  return base.copyWith(
    displayLarge: base.displayLarge
        ?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -1.5),
    displayMedium: base.displayMedium
        ?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -1.0),
    displaySmall: base.displaySmall
        ?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.5),
    headlineMedium: base.headlineMedium
        ?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.5),
    headlineSmall: base.headlineSmall
        ?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.3),
    titleLarge: base.titleLarge
        ?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.2),
    titleMedium: base.titleMedium?.copyWith(fontWeight: FontWeight.w600),
    bodyLarge: base.bodyLarge?.copyWith(height: 1.45),
    bodyMedium: base.bodyMedium?.copyWith(height: 1.45),
    labelLarge: base.labelLarge?.copyWith(fontWeight: FontWeight.w600),
  ).apply(
    bodyColor: scheme.onSurface,
    displayColor: scheme.onSurface,
  );
}
