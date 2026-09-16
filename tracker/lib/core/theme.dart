import 'package:flutter/material.dart';

/// 设计规范常量。
/// 来源：架构设计文档第 10 节。规范层定死，交互层可迭代。
abstract final class AppTheme {
  // 背景与容器
  /// 纯黑底。containers（chips / 卡片 / 浮层）仍用 [surface]，保持层次。
  static const background = Color(0xFF000000);
  static const surface = Color(0xFF444441);
  static const border = Color(0xFF5F5E5A);

  // 文字三级
  static const textPrimary = Color(0xFFD3D1C7);
  static const textSecondary = Color(0xFFB4B2A9);
  static const textTertiary = Color(0xFF888780);

  // 主色与其上文字
  static const accent = Color(0xFF1D9E75);
  static const onAccent = Color(0xFFE1F5EE);

  // 封面占位辅色（由标题 hash 取用）
  static const coverPalette = <Color>[
    Color(0xFF0F6E56),
    Color(0xFF185FA5),
    Color(0xFF085041),
    Color(0xFF0C447C),
  ];

  // 字号
  static const double fontSizeBody = 11;
  static const double fontSizeNormal = 13;
  static const double fontSizeTitle = 17;
  static const double fontSizeMetric = 18;

  // 圆角
  static const double radiusSmall = 6;
  static const double radiusMedium = 8;
  static const double radiusLarge = 12;
  static const double radiusPill = 999;

  // 封面比例 2:3
  static const double coverAspect = 2 / 3;

  static ThemeData build() {
    const base = TextStyle(fontFamily: 'Roboto');
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: background,
      colorScheme: const ColorScheme.dark(
        primary: accent,
        onPrimary: onAccent,
        surface: background,
        onSurface: textPrimary,
        outline: border,
      ),
      textTheme: TextTheme(
        bodySmall: base.copyWith(fontSize: fontSizeBody, color: textTertiary),
        bodyMedium: base.copyWith(fontSize: fontSizeNormal, color: textPrimary),
        titleLarge: base.copyWith(
          fontSize: fontSizeTitle,
          fontWeight: FontWeight.w500,
          color: textPrimary,
        ),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: background,
        foregroundColor: textPrimary,
        elevation: 0,
        titleTextStyle: TextStyle(
          fontSize: fontSizeTitle,
          fontWeight: FontWeight.w500,
          color: textPrimary,
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: surface,
        selectedColor: accent,
        disabledColor: surface,
        side: const BorderSide(color: border, width: 0.5),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusPill)),
        labelStyle: const TextStyle(fontSize: fontSizeBody, color: textSecondary),
        padding: EdgeInsets.zero,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusSmall),
          borderSide: const BorderSide(color: border, width: 0.5),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusSmall),
          borderSide: const BorderSide(color: border, width: 0.5),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusSmall),
          borderSide: const BorderSide(color: accent, width: 0.5),
        ),
        hintStyle: const TextStyle(fontSize: fontSizeBody, color: textTertiary),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: accent,
          foregroundColor: onAccent,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusMedium)),
          textStyle: const TextStyle(fontSize: fontSizeNormal, fontWeight: FontWeight.w500),
        ),
      ),
      dividerTheme: const DividerThemeData(color: surface, thickness: 0.5),
    );
  }
}
