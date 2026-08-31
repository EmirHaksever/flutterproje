import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Tema modu ve dil tercihini tutar ve SharedPreferences'a kalıcı yazar.
///
/// Eskiden main.dart içinde `_themeMode` / `_locale` state olarak vardı ve
/// uygulama kapanınca sıfırlanıyordu. Artık tek kaynak ve kalıcı.
class SettingsController extends ChangeNotifier {
  SettingsController._();
  static final SettingsController instance = SettingsController._();

  static const _kThemeKey = 'themeMode'; // 'light' | 'dark' | 'system'
  static const _kLocaleKey = 'localeCode'; // 'tr' | 'en'

  ThemeMode _themeMode = ThemeMode.system;
  Locale _locale = const Locale('tr');

  ThemeMode get themeMode => _themeMode;
  Locale get locale => _locale;
  bool get isDark => _themeMode == ThemeMode.dark;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    switch (prefs.getString(_kThemeKey)) {
      case 'light':
        _themeMode = ThemeMode.light;
      case 'dark':
        _themeMode = ThemeMode.dark;
      default:
        _themeMode = ThemeMode.system;
    }
    _locale = Locale(prefs.getString(_kLocaleKey) ?? 'tr');
    notifyListeners();
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    if (_themeMode == mode) return;
    _themeMode = mode;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kThemeKey, mode.name);
  }

  Future<void> toggleDark(bool dark) =>
      setThemeMode(dark ? ThemeMode.dark : ThemeMode.light);

  Future<void> setLocale(Locale locale) async {
    if (_locale.languageCode == locale.languageCode) return;
    _locale = locale;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kLocaleKey, locale.languageCode);
  }
}
