import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'screens/login_screen.dart';
import 'screens/list_detail.dart';
import 'screens/profile.dart';
import 'screens/settings.dart';
import 'screens/main_navigation.dart';
import 'screens/ai_chat.dart';


// Helper function to create a MaterialColor from a single Color
// Tek bir renkten MaterialColor oluşturmak için yardımcı fonksiyon
MaterialColor createMaterialColor(Color color) {
  List strengths = <double>[.05];
  Map<int, Color> swatch = {};
  final int r = color.red, g = color.green, b = color.blue;

  for (int i = 1; i < 10; i++) {
    strengths.add(0.1 * i);
  }
  for (var strength in strengths) {
    final double ds = 0.5 - strength;
    swatch[(strength * 1000).round()] = Color.fromRGBO(
      r + ((ds < 0 ? r : (255 - r)) * ds).round(),
      g + ((ds < 0 ? g : (255 - g)) * ds).round(),
      b + ((ds < 0 ? b : (255 - b)) * ds).round(),
      1,
    );
  }
  return MaterialColor(color.value, swatch);
}


void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // .env dosyasını yükle (GEMINI_API_KEY vb. burada okunur).
  await dotenv.load(fileName: ".env");

  await Future.wait([
    Supabase.initialize(
      url: 'https://uwlqoutitixoxflpchwe.supabase.co',
      anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InV3bHFvdXRpdGl4b3hmbHBjaHdlIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NDM1MTE2NjUsImV4cCI6MjA1OTA4NzY2NX0.9uLwlSUd_mgjtAuX8kyQg__d1AYhnx_6ZFQLJmhZJ1g',

    ),
    initializeDateFormatting('tr_TR', null),
  ]);

  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  ThemeMode _themeMode = ThemeMode.light;
  Locale _locale = const Locale('tr', 'TR');

  void _toggleThemeMode() {
    setState(() {
      _themeMode =
          _themeMode == ThemeMode.light ? ThemeMode.dark : ThemeMode.light;
    });
  }

  void _changeLocale(Locale locale) {
    setState(() {
      _locale = locale;
    });
  }

  @override
  Widget build(BuildContext context) {
    // İstenen 0xFF4DB6AC rengi kullanılarak özel bir MaterialColor oluşturuldu
    final MaterialColor customPrimaryColor = createMaterialColor(const Color(0xFF4DB6AC)); 

    return MaterialApp(
      title: 'Alışveriş Listem',
      debugShowCheckedModeBanner: false,
      themeMode: _themeMode,
      theme: ThemeData(
        primarySwatch: customPrimaryColor, // Ana renk paleti olarak yeni özel renk kullanıldı
        primaryColor: const Color(0xFF4DB6AC), // primaryColor'ı açıkça ayarla
        scaffoldBackgroundColor: Colors.grey[100],
        appBarTheme: const AppBarTheme( // AppBar teması da yeni ana rengi kullanır
          backgroundColor: Color(0xFF4DB6AC), // AppBar rengini de açıkça ayarla
          foregroundColor: Colors.white,
        ),
      ),
      darkTheme: ThemeData(
        brightness: Brightness.dark,
        primarySwatch: customPrimaryColor, // Koyu tema için de yeni özel ana renk kullanıldı
        primaryColor: const Color(0xFF4DB6AC), // primaryColor'ı açıkça ayarla
        scaffoldBackgroundColor: Colors.grey[800],
        appBarTheme: const AppBarTheme( // Koyu tema AppBar teması da yeni özel ana rengi kullanır
          backgroundColor: Color(0xFF4DB6AC), // AppBar rengini de açıkça ayarla
          foregroundColor: Colors.white,
        ),
      ),
      locale: _locale,
      supportedLocales: const [
        Locale('tr', 'TR'),
        Locale('en', 'US'),
      ],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: StreamBuilder<AuthState>(
        stream: Supabase.instance.client.auth.onAuthStateChange,
        builder: (context, snapshot) {
          if (snapshot.hasData && snapshot.data!.event == AuthChangeEvent.signedIn) {
            // Kullanıcı giriş yapmışsa ana navigasyon sayfasına git
            return MainNavigationPage(
              toggleTheme: _toggleThemeMode,
              changeLocale: _changeLocale,
              customPrimarySwatch: customPrimaryColor, // customPrimarySwatch'i buraya ekleyin
            );
          }
          // Kullanıcı giriş yapmamışsa veya session yoksa login sayfasına git
          return const LoginScreen(); // LoginPage import edildiğini varsayalım
        },
      ),

      onGenerateRoute: (settings) {
        if (settings.name == '/listDetail') {
          final args = settings.arguments as Map<String, dynamic>;
          return MaterialPageRoute(
            builder: (context) => ListDetailPage(listData: args),
          );
        }

        switch (settings.name) {
          case '/home':
            return MaterialPageRoute(
              builder: (context) => MainNavigationPage(
                toggleTheme: _toggleThemeMode,
                changeLocale: _changeLocale,
                customPrimarySwatch: customPrimaryColor, // customPrimarySwatch'i buraya da ekleyin
              ),
            );
          case '/login':
            return MaterialPageRoute(builder: (context) => const LoginScreen());
          case '/profile':
            return MaterialPageRoute(builder: (context) => const ProfilePage());
          case '/settings':
            return MaterialPageRoute(
              builder: (context) => SettingsPage(
                toggleTheme: _toggleThemeMode,
                changeLocale: _changeLocale,
              ),
            );
          case '/aiChat':
            return MaterialPageRoute(builder: (context) => const AIChatPage());

          default:
            return MaterialPageRoute(builder: (context) => const LoginScreen());
        }
      },
    );
  }
}
