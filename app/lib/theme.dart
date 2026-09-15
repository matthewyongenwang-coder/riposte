import 'package:flutter/material.dart';

import 'models.dart';

/// The same palette as the landing page, with the same meaning. Orange is
/// Fencer A, blue is Fencer B, red is LOST and nothing else.
class Brand {
  static const bg = Color(0xFF101318);
  static const surface = Color(0xFF181B21);
  static const raised = Color(0xFF21252C);
  static const line = Color(0xFF2C3139);
  static const ink = Color(0xFFF3F4F7);
  static const muted = Color(0xFFAAB0BA);
  static const faint = Color(0xFF7D838E);
  static const accent = Color(0xFFF4913F);
  static const blueText = Color(0xFF7FACF4);
  static const lost = Color(0xFFF0625F);
  static const ok = Color(0xFF52CB8E);
  static const warn = Color(0xFFE8B34A);

  /// The exact colours main.py draws on the output video, so a box you draw
  /// here looks like the box you get back.
  static const boxA = Color(0xFFFF8C00);
  static const boxB = Color(0xFF005AFF);

  static Color box(Fencer f) => f == Fencer.a ? boxA : boxB;

  /// For text, where the video's pure blue is too dark to read on this
  /// background.
  static Color text(Fencer f) => f == Fencer.a ? accent : blueText;
}

TextStyle mono({double size = 12, Color color = Brand.muted, FontWeight weight = FontWeight.w400}) => TextStyle(
      fontFamily: 'SF Mono',
      fontFamilyFallback: const ['Menlo', 'Monaco', 'Courier'],
      fontSize: size,
      color: color,
      fontWeight: weight,
      fontFeatures: const [FontFeature.tabularFigures()],
    );

ThemeData buildTheme() {
  final base = ThemeData(brightness: Brightness.dark, useMaterial3: true);
  final scheme = ColorScheme.fromSeed(seedColor: Brand.accent, brightness: Brightness.dark).copyWith(
    primary: Brand.accent,
    onPrimary: const Color(0xFF1C1307),
    secondary: Brand.blueText,
    surface: Brand.surface,
    onSurface: Brand.ink,
    outline: Brand.line,
    outlineVariant: Brand.line,
    error: Brand.lost,
  );
  return base.copyWith(
    colorScheme: scheme,
    scaffoldBackgroundColor: Brand.bg,
    dividerColor: Brand.line,
    textTheme: base.textTheme.apply(bodyColor: Brand.ink, displayColor: Brand.ink),
    sliderTheme: SliderThemeData(
      activeTrackColor: Brand.accent,
      inactiveTrackColor: Brand.line,
      thumbColor: Brand.accent,
      overlayColor: Brand.accent.withValues(alpha: 0.12),
      trackHeight: 3,
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: Brand.raised,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Brand.line),
      ),
      textStyle: const TextStyle(color: Brand.ink, fontSize: 12),
      waitDuration: const Duration(milliseconds: 400),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? const Color(0xFF1C1307) : Brand.muted),
      trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? Brand.accent : Brand.raised),
      trackOutlineColor: WidgetStateProperty.all(Brand.line),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(color: Brand.accent, linearTrackColor: Brand.line),
  );
}
