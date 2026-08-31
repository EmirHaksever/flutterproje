import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart'
    show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'controllers/settings_controller.dart';
import 'theme/app_theme.dart';
import 'screens/login_screen.dart';
import 'screens/list_detail.dart';
import 'screens/profile.dart';
import 'screens/settings.dart';
import 'screens/main_navigation.dart';
import 'screens/ai_chat.dart';

/// FCM arka plan mesajı işleyici — üst seviye fonksiyon olmak zorunda.
@pragma('vm:entry-point')
Future<void> _firebaseBackgroundHandler(RemoteMessage message) async {
  // Sistem tepsisindeki bildirimi FCM otomatik gösterir; burada iş yapmıyoruz.
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // .env dosyasını yükle (GEMINI_API_KEY vb. burada okunur).
  await dotenv.load(fileName: ".env");

  // Push bildirim yalnızca Android'de.
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
    try {
      await Firebase.initializeApp();
      FirebaseMessaging.onBackgroundMessage(_firebaseBackgroundHandler);
    } catch (e) {
      debugPrint('Firebase init hata: $e');
    }
  }

  await Future.wait([
    Supabase.initialize(
      url: 'https://uwlqoutitixoxflpchwe.supabase.co',
      anonKey:
          'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InV3bHFvdXRpdGl4b3hmbHBjaHdlIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NDM1MTE2NjUsImV4cCI6MjA1OTA4NzY2NX0.9uLwlSUd_mgjtAuX8kyQg__d1AYhnx_6ZFQLJmhZJ1g',
    ),
    initializeDateFormatting('tr_TR', null),
    SettingsController.instance.load(),
  ]);

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = SettingsController.instance;

    // Eski ekranlar hâlâ MaterialColor "customPrimarySwatch" bekliyor;
    // Faz 5 ilerledikçe ekranlar Theme.of(context).colorScheme'e geçecek.
    const swatch = AppTheme.seedSwatch;

    void toggleTheme() =>
        settings.toggleDark(settings.themeMode != ThemeMode.dark);
    void changeLocale(Locale locale) => settings.setLocale(locale);

    return ListenableBuilder(
      listenable: settings,
      builder: (context, _) {
        return MaterialApp(
          title: 'Alışveriş Listem',
          debugShowCheckedModeBanner: false,
          themeMode: settings.themeMode,
          theme: AppTheme.light(),
          darkTheme: AppTheme.dark(),
          locale: settings.locale,
          supportedLocales: const [Locale('tr'), Locale('en')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: StreamBuilder<AuthState>(
            stream: Supabase.instance.client.auth.onAuthStateChange,
            builder: (context, snapshot) {
              final signedIn = snapshot.hasData &&
                  snapshot.data!.event == AuthChangeEvent.signedIn;
              if (signedIn) {
                return MainNavigationPage(
                  toggleTheme: toggleTheme,
                  changeLocale: changeLocale,
                  customPrimarySwatch: swatch,
                );
              }
              return const LoginScreen();
            },
          ),
          onGenerateRoute: (routeSettings) {
            if (routeSettings.name == '/listDetail') {
              final args = routeSettings.arguments as Map<String, dynamic>;
              return MaterialPageRoute(
                builder: (context) => ListDetailPage(listData: args),
              );
            }

            switch (routeSettings.name) {
              case '/home':
                return MaterialPageRoute(
                  builder: (context) => MainNavigationPage(
                    toggleTheme: toggleTheme,
                    changeLocale: changeLocale,
                    customPrimarySwatch: swatch,
                  ),
                );
              case '/login':
                return MaterialPageRoute(
                    builder: (context) => const LoginScreen());
              case '/profile':
                return MaterialPageRoute(
                    builder: (context) => const ProfilePage());
              case '/settings':
                return MaterialPageRoute(
                  builder: (context) => SettingsPage(
                    toggleTheme: toggleTheme,
                    changeLocale: changeLocale,
                  ),
                );
              case '/aiChat':
                return MaterialPageRoute(
                    builder: (context) => const AIChatPage());
              default:
                return MaterialPageRoute(
                    builder: (context) => const LoginScreen());
            }
          },
        );
      },
    );
  }
}
