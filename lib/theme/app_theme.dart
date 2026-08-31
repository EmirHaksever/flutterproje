import 'package:flutter/material.dart';

/// Uygulamanın tema sistemi — Material 3, tek "seed" renkten türetilmiş
/// uyumlu açık/koyu paletler ve tutarlı şekil/boşluk kuralları.
///
/// Eskiden main.dart içinde `createMaterialColor` + `primarySwatch` vardı
/// (deprecated `.red/.green/.blue/.value` kullanıyordu). Artık tek kaynak burası.
class AppTheme {
  AppTheme._();

  /// Ana renk tohumu — eski turkuazın (#4DB6AC) modern tonu.
  static const Color seed = Color(0xFF14B8A6);

  /// Bazı eski ekranlar hâlâ `MaterialColor` (shade'li) bekliyor; onlar için
  /// elle tanımlı swatch. Yeni/yeniden yazılan ekranlar
  /// `Theme.of(context).colorScheme` kullanmalı.
  static const MaterialColor seedSwatch = MaterialColor(0xFF14B8A6, {
    50: Color(0xFFE6FAF7),
    100: Color(0xFFC0F2E9),
    200: Color(0xFF96E9DA),
    300: Color(0xFF6BE0CB),
    400: Color(0xFF4CD9C0),
    500: Color(0xFF14B8A6),
    600: Color(0xFF10A192),
    700: Color(0xFF0C8578),
    800: Color(0xFF096A60),
    900: Color(0xFF054A43),
  });

  static const double _radius = 16;

  static ThemeData light() => _base(Brightness.light);
  static ThemeData dark() => _base(Brightness.dark);

  static ThemeData _base(Brightness brightness) {
    final scheme = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: brightness,
    );
    final isDark = brightness == Brightness.dark;

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor:
          isDark ? scheme.surface : const Color(0xFFF7F8F9),
      // Geriye dönük uyum: eski kod Theme.of(context).primaryColor kullanıyor.
      primaryColor: scheme.primary,
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: scheme.onPrimary,
          fontSize: 20,
          fontWeight: FontWeight.w700,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: scheme.surface,
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
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
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
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      listTileTheme: const ListTileThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(12)),
        ),
      ),
    );
  }
}
