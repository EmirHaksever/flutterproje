import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart'
    show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'friends_screen.dart';
import 'notifications_screen.dart';
import '../constants/categories.dart';
import '../services/push_service.dart';
import '../theme/app_theme.dart';
import 'home.dart';
import 'create_list.dart';
import 'profile.dart';
import 'settings.dart';
import 'ai_chat.dart';
import 'stats.dart';
import 'my_lists.dart';

class MainNavigationPage extends StatefulWidget {
  final void Function() toggleTheme;
  final void Function(Locale) changeLocale;
  final MaterialColor customPrimarySwatch;

  const MainNavigationPage({
    super.key,
    required this.toggleTheme,
    required this.changeLocale,
    required this.customPrimarySwatch,
  });

  @override
  State<MainNavigationPage> createState() => _MainNavigationPageState();
}

class _MainNavigationPageState extends State<MainNavigationPage> {
  /// Görünür sekme indexi: 0=Ana Sayfa, 1=Listeler, 2=AI, 3=Profil.
  /// (Ortadaki "+" bir sekme değil, sadece Liste Oluştur'u açar.)
  int _pageIndex = 0;
  String _userName = 'Misafir';
  String _userEmail = '';

  final supabase = Supabase.instance.client;
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  List<Map<String, dynamic>> _allAvailableCategories = [];
  late final List<Widget> _pages;

  @override
  void initState() {
    super.initState();
    final swatch = widget.customPrimarySwatch;
    _pages = [
      HomePage(
        customPrimarySwatch: swatch,
        onMenuTap: () => _scaffoldKey.currentState?.openDrawer(),
      ),
      MyListsPage(customPrimarySwatch: swatch),
      const AIChatPage(),
      const ProfilePage(),
    ];

    _fetchUserProfile();
    _fetchAllAvailableCategories();
    _initPush();

    supabase.auth.onAuthStateChange.listen((data) {
      if (!mounted) return;
      final event = data.event;
      if (event == AuthChangeEvent.signedIn ||
          event == AuthChangeEvent.initialSession) {
        _fetchUserProfile();
      } else if (event == AuthChangeEvent.signedOut) {
        setState(() {
          _userName = 'Misafir';
          _userEmail = '';
        });
        Navigator.pushReplacementNamed(context, '/login');
      }
    });
  }

  Future<void> _fetchAllAvailableCategories() async {
    try {
      final response = await supabase.from('list_items').select('category');
      final discovered = response
          .map((item) => item['category'] as String?)
          .whereType<String>();
      if (mounted) {
        setState(() {
          _allAvailableCategories = mergeDiscoveredCategories(discovered);
        });
      }
    } catch (e) {
      debugPrint('Kategoriler çekilemedi: $e');
    }
  }

  Future<void> _fetchUserProfile() async {
    final user = supabase.auth.currentUser;
    if (user == null) {
      if (mounted) {
        setState(() {
          _userName = 'Misafir';
          _userEmail = '';
        });
      }
      return;
    }
    try {
      final response = await supabase
          .from('users')
          .select('name')
          .eq('id', user.id)
          .maybeSingle();
      if (mounted) {
        setState(() {
          _userName = (response?['name'] as String?)?.trim().isNotEmpty == true
              ? response!['name'] as String
              : 'Kullanıcı';
          _userEmail = user.email ?? '';
        });
      }
    } catch (e) {
      debugPrint('Profil çekilemedi: $e');
      if (mounted) {
        setState(() {
          _userName = 'Kullanıcı';
          _userEmail = user.email ?? '';
        });
      }
    }
  }

  void _openCreateList() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CreateListPage(
          availableCategories: _allAvailableCategories,
          customPrimarySwatch: widget.customPrimarySwatch,
        ),
      ),
    );
  }

  void _openStats() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            StatsPage(customPrimarySwatch: widget.customPrimarySwatch),
      ),
    );
  }

  Future<void> _signOut() async {
    await PushService.instance.clearOnLogout();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('email');
    await prefs.setBool('rememberMe', false);
    await supabase.auth.signOut();
  }

  void _initPush() {
    PushService.instance.start();
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    // Bildirime dokununca (arka plan / kapalıyken) Bildirimler'e git.
    FirebaseMessaging.onMessageOpenedApp.listen((_) => _openNotifications());
    FirebaseMessaging.instance.getInitialMessage().then((m) {
      if (m != null) _openNotifications();
    });
  }

  void _openNotifications() {
    if (!mounted) return;
    Navigator.push(context,
        MaterialPageRoute(builder: (_) => const NotificationsScreen()));
  }

  /// Alt bar tıklama: 0,1 doğrudan sekme; 2 = "+" (Liste Oluştur); 3,4 sekme.
  void _onNavTap(int i) {
    if (i == 2) {
      _openCreateList();
      return;
    }
    setState(() => _pageIndex = i > 2 ? i - 1 : i);
  }

  int get _selectedNavIndex => _pageIndex >= 2 ? _pageIndex + 1 : _pageIndex;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      drawer: _buildDrawer(scheme),
      body: IndexedStack(index: _pageIndex, children: _pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedNavIndex,
        onDestinationSelected: _onNavTap,
        destinations: [
          const NavigationDestination(
              icon: Icon(Icons.home_outlined),
              selectedIcon: Icon(Icons.home_rounded),
              label: 'Ana Sayfa'),
          const NavigationDestination(
              icon: Icon(Icons.checklist_outlined),
              selectedIcon: Icon(Icons.checklist_rounded),
              label: 'Listeler'),
          NavigationDestination(
            icon: Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: scheme.primary,
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.add, color: scheme.onPrimary, size: 26),
            ),
            label: '',
          ),
          const NavigationDestination(
              icon: Icon(Icons.auto_awesome_outlined),
              selectedIcon: Icon(Icons.auto_awesome),
              label: 'AI'),
          const NavigationDestination(
              icon: Icon(Icons.person_outline),
              selectedIcon: Icon(Icons.person_rounded),
              label: 'Profil'),
        ],
      ),
    );
  }

  Widget _buildDrawer(ColorScheme scheme) {
    Widget tile(IconData icon, String label, VoidCallback onTap,
        {Color? color}) {
      return ListTile(
        leading: Icon(icon, color: color ?? scheme.onSurfaceVariant),
        title: Text(label,
            style: TextStyle(fontWeight: FontWeight.w500, color: color)),
        onTap: () {
          Navigator.pop(context);
          onTap();
        },
      );
    }

    void go(int pageIndex) => setState(() => _pageIndex = pageIndex);
    void push(Widget page) =>
        Navigator.push(context, MaterialPageRoute(builder: (_) => page));

    return Drawer(
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          UserAccountsDrawerHeader(
            decoration: BoxDecoration(color: scheme.primary),
            accountName: Text(_userName,
                style: const TextStyle(fontWeight: FontWeight.bold)),
            accountEmail: Text(_userEmail),
            currentAccountPicture: CircleAvatar(
              backgroundColor: AppTheme.heroGreenBg,
              child: Icon(Icons.person, color: scheme.primary),
            ),
          ),
          tile(Icons.home_outlined, 'Ana Sayfa', () => go(0)),
          tile(Icons.checklist_outlined, 'Listelerim', () => go(1)),
          tile(Icons.auto_awesome_outlined, 'AI Asistanı', () => go(2)),
          tile(Icons.person_outline, 'Profil', () => go(3)),
          tile(Icons.bar_chart_outlined, 'İstatistikler', _openStats),
          const Divider(),
          tile(Icons.group_outlined, 'Arkadaşlar',
              () => push(const FriendsScreen())),
          tile(Icons.notifications_outlined, 'Bildirimler',
              () => push(const NotificationsScreen())),
          tile(
              Icons.settings_outlined,
              'Ayarlar',
              () => push(SettingsPage(
                    toggleTheme: widget.toggleTheme,
                    changeLocale: widget.changeLocale,
                  ))),
          const Divider(),
          tile(Icons.logout, 'Çıkış Yap', _signOut, color: scheme.error),
        ],
      ),
    );
  }
}
