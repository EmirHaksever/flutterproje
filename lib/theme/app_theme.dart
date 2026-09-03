import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Uygulamanın tema sistemi — Material 3 + Poppins.
///
/// Renk/ölçü değerleri, kullanıcının onayladığı tasarım taslağından alındı
/// (yeşil #16A34A, greenSoft #EAF8EE, Poppins, 16-18px köşeler, ince gri
/// kenarlıklı beyaz kartlar, şeffaf app bar).
class AppTheme {
  AppTheme._();

  // --- Renk paleti (tasarım taslağı) --------------------------------------
  static const Color brandGreen = Color(0xFF16A34A);
  static const Color brandGreenDark = Color(0xFF15803D);
  static const Color heroGreenBg = Color(0xFFEAF8EE); // greenSoft

  static const Color bgLight = Color(0xFFF1F4F2);
  static const Color textPrimary = Color(0xFF111827);
  static const Color textSecondary = Color(0xFF6B7280);
  static const Color borderLight = Color(0xFFE5E7EB);

  /// Kartların zeminden "kalkmış" görünmesi için çok yumuşak gölge.
  /// Karanlık temada gölge işe yaramaz (siyahın üstüne siyah) → boş liste döner.
  static List<BoxShadow> softShadow(Brightness brightness) =>
      brightness == Brightness.dark
          ? const []
          : const [
              BoxShadow(
                color: Color(0x0A111827),
                blurRadius: 3,
                offset: Offset(0, 1),
              ),
              BoxShadow(
                color: Color(0x14111827),
                blurRadius: 16,
                offset: Offset(0, 6),
              ),
            ];

  static const Color accentOrange = Color(0xFFF59E0B);
  static const Color accentBlue = Color(0xFF3B82F6);
  static const Color accentPurple = Color(0xFF8B5CF6);

  /// Geriye dönük uyum: bazı eski ekranlar hâlâ `MaterialColor` bekliyor.
  static const MaterialColor seedSwatch = MaterialColor(0xFF16A34A, {
    50: Color(0xFFEAF8EE),
    100: Color(0xFFCBEBD5),
    200: Color(0xFFA6DCB8),
    300: Color(0xFF7FCD9A),
    400: Color(0xFF54BF7E),
    500: Color(0xFF16A34A),
    600: Color(0xFF139443),
    700: Color(0xFF0F8039),
    800: Color(0xFF0B6C30),
    900: Color(0xFF054A20),
  });

  static const double _radius = 18;

  static ThemeData light() => _base(Brightness.light);
  static ThemeData dark() => _base(Brightness.dark);

  static ThemeData _base(Brightness brightness) {
    final isDark = brightness == Brightness.dark;

    final generated = ColorScheme.fromSeed(
      seedColor: brandGreen,
      brightness: brightness,
    );
    final scheme = isDark
        ? generated.copyWith(
            primary: const Color(0xFF34D26A),
            onPrimary: const Color(0xFF06230F),
            primaryContainer: const Color(0xFF12331F),
            onPrimaryContainer: const Color(0xFFBEEDCB),
          )
        : generated.copyWith(
            primary: brandGreen,
            onPrimary: Colors.white,
            primaryContainer: heroGreenBg,
            onPrimaryContainer: brandGreenDark,
            secondary: brandGreen,
            surface: Colors.white,
            onSurface: textPrimary,
            onSurfaceVariant: textSecondary,
            outlineVariant: borderLight,
          );

    final surface = isDark ? scheme.surface : Colors.white;
    final onSurface = scheme.onSurface;

    final baseText = isDark
        ? ThemeData(brightness: Brightness.dark).textTheme
        : ThemeData(brightness: Brightness.light).textTheme;
    final textTheme = GoogleFonts.poppinsTextTheme(baseText).apply(
      bodyColor: onSurface,
      displayColor: onSurface,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      textTheme: textTheme,
      scaffoldBackgroundColor: isDark ? scheme.surface : bgLight,
      primaryColor: scheme.primary,
      appBarTheme: AppBarTheme(
        backgroundColor: isDark ? scheme.surface : bgLight,
        foregroundColor: onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        centerTitle: false,
        titleTextStyle: GoogleFonts.poppins(
          color: onSurface,
          fontSize: 20,
          fontWeight: FontWeight.w800,
        ),
        iconTheme: IconThemeData(color: onSurface),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_radius),
          side: BorderSide(color: scheme.outlineVariant),
        ),
        margin: const EdgeInsets.symmetric(vertical: 6),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark ? scheme.surfaceContainerHighest : Colors.white,
        hintStyle: TextStyle(color: scheme.onSurfaceVariant),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: scheme.primary, width: 1.5),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: scheme.primary,
          foregroundColor: scheme.onPrimary,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          textStyle: GoogleFonts.poppins(
              fontSize: 15, fontWeight: FontWeight.w700),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: scheme.primary,
          foregroundColor: scheme.onPrimary,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
          textStyle: GoogleFonts.poppins(
              fontSize: 15, fontWeight: FontWeight.w700),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: scheme.primary),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: onSurface,
          side: BorderSide(color: scheme.outlineVariant),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        elevation: 2,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: surface,
        indicatorColor: heroGreenBg,
        elevation: 0,
        height: 72,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => GoogleFonts.poppins(
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
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant,
        space: 1,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: surface,
        shape: const StadiumBorder(),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      listTileTheme: const ListTileThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(14)),
        ),
      ),
    );
  }
}
