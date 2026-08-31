import 'package:flutter/material.dart';

/// Uygulamanın tema sistemi — Material 3, tek "seed" renkten türetilmiş
/// uyumlu açık/koyu paletler ve tutarlı şekil/boşluk kuralları.
///
/// Tasarım referansı: 12 ekranlık mockup seti (yeşil marka, beyaz kartlar,
/// beyaz app bar, alt navigasyonda ortada yeşil FAB).
class AppTheme {
  AppTheme._();

  /// Marka yeşili — mockup'taki buton/FAB/vurgu rengi.
  static const Color brandGreen = Color(0xFF33A852);
  static const Color brandGreenDark = Color(0xFF1E7E3E);

  /// Açık yeşil zemin — "hero" kartların arkası (Ana Sayfa, AI kartı vb.).
  static const Color heroGreenBg = Color(0xFFE9F5EC);

  /// Geriye dönük uyum: bazı eski ekranlar hâlâ `MaterialColor` (shade'li)
  /// bekliyor. Yeni/yeniden yazılan ekranlar `colorScheme` kullanmalı.
  static const MaterialColor seedSwatch = MaterialColor(0xFF33A852, {
    50: Color(0xFFE8F6EC),
    100: Color(0xFFC6E9CF),
    200: Color(0xFF9FDBAF),
    300: Color(0xFF77CD8E),
    400: Color(0xFF59C275),
    500: Color(0xFF33A852),
    600: Color(0xFF2C9C49),
    700: Color(0xFF238D3E),
    800: Color(0xFF1B7E33),
    900: Color(0xFF0C6421),
  });

  static const double _radius = 16;

  static ThemeData light() => _base(Brightness.light);
  static ThemeData dark() => _base(Brightness.dark);

  static ThemeData _base(Brightness brightness) {
    final isDark = brightness == Brightness.dark;

    final generated = ColorScheme.fromSeed(
      seedColor: brandGreen,
      brightness: brightness,
    );
    // Marka yeşilini birebir tuttuğumuz için primary'yi elle sabitliyoruz;
    // fromSeed onu ton kurallarına göre koyulaştırıyor.
    final scheme = isDark
        ? generated.copyWith(
            primary: const Color(0xFF4ADE80),
            onPrimary: const Color(0xFF06230F),
            primaryContainer: const Color(0xFF10381E),
            onPrimaryContainer: const Color(0xFFB7F0C6),
          )
        : generated.copyWith(
            primary: brandGreen,
            onPrimary: Colors.white,
            primaryContainer: heroGreenBg,
            onPrimaryContainer: brandGreenDark,
            secondary: brandGreen,
          );

    final surface = isDark ? scheme.surface : Colors.white;
    final onSurface = scheme.onSurface;

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor:
          isDark ? scheme.surface : const Color(0xFFF6F7F9),
      primaryColor: scheme.primary,
      appBarTheme: AppBarTheme(
        backgroundColor: surface,
        foregroundColor: onSurface,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: onSurface,
          fontSize: 20,
          fontWeight: FontWeight.w700,
        ),
        iconTheme: IconThemeData(color: onSurface),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_radius),
          side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.5)),
        ),
        margin: const EdgeInsets.symmetric(vertical: 6),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark ? scheme.surfaceContainerHighest : Colors.white,
        hintStyle: TextStyle(color: scheme.onSurfaceVariant),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: scheme.primary, width: 2),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: scheme.primary,
          foregroundColor: scheme.onPrimary,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle:
              const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: scheme.primary,
          foregroundColor: scheme.onPrimary,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          textStyle:
              const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: scheme.primary),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        elevation: 2,
        shape: const CircleBorder(),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: surface,
        indicatorColor: Colors.transparent,
        elevation: 0,
        height: 64,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w500,
            color: states.contains(WidgetState.selected)
                ? scheme.primary
                : scheme.onSurfaceVariant,
          ),
        ),
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            size: 24,
            color: states.contains(WidgetState.selected)
                ? scheme.primary
                : scheme.onSurfaceVariant,
          ),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant.withValues(alpha: 0.6),
        space: 1,
      ),
      chipTheme: ChipThemeData(
        shape: const StadiumBorder(),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      listTileTheme: const ListTileThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(12)),
        ),
      ),
    );
  }
}
