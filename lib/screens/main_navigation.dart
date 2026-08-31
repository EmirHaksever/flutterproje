import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'friends_screen.dart';
import 'notifications_screen.dart';
import '../constants/categories.dart';
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
  int _selectedIndex = 0;
  String _userName = 'Misafir';
  String _userEmail = '';

  final supabase = Supabase.instance.client;
  List<Map<String, dynamic>> _allAvailableCategories = [];
  late final List<Widget> _pages;

  @override
  void initState() {
    super.initState();
    final swatch = widget.customPrimarySwatch;
    _pages = [
      HomePage(customPrimarySwatch: swatch),
      StatsPage(customPrimarySwatch: swatch),
      const AIChatPage(),
      MyListsPage(customPrimarySwatch: swatch),
      const ProfilePage(),
    ];

    _fetchUserProfile();
    _fetchAllAvailableCategories();

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

  Future<void> _signOut() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('email');
    await prefs.setBool('rememberMe', false);
    await supabase.auth.signOut();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      drawer: _buildDrawer(scheme),
      body: IndexedStack(index: _selectedIndex, children: _pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (i) => setState(() => _selectedIndex = i),
        destinations: const [
          NavigationDestination(
              icon: Icon(Icons.home_outlined),
              selectedIcon: Icon(Icons.home_rounded),
              label: 'Ana Sayfa'),
          NavigationDestination(
              icon: Icon(Icons.bar_chart_outlined),
              selectedIcon: Icon(Icons.bar_chart_rounded),
              label: 'İstatistik'),
          NavigationDestination(
              icon: Icon(Icons.psychology_outlined),
              selectedIcon: Icon(Icons.psychology_rounded),
              label: 'AI'),
          NavigationDestination(
              icon: Icon(Icons.receipt_long_outlined),
              selectedIcon: Icon(Icons.receipt_long_rounded),
              label: 'Listeler'),
          NavigationDestination(
              icon: Icon(Icons.person_outline),
              selectedIcon: Icon(Icons.person_rounded),
              label: 'Profil'),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _openCreateList,
        tooltip: 'Yeni Liste',
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildDrawer(ColorScheme scheme) {
    Widget tile(IconData icon, String label, VoidCallback onTap,
        {Color? color}) {
      return ListTile(
        leading: Icon(icon, color: color ?? scheme.onSurfaceVariant),
        title: Text(label,
            style: TextStyle(
                fontWeight: FontWeight.w500, color: color)),
        onTap: () {
          Navigator.pop(context);
          onTap();
        },
      );
    }

    void go(int i) => setState(() => _selectedIndex = i);
    void push(Widget page) => Navigator.push(
        context, MaterialPageRoute(builder: (_) => page));

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
              backgroundColor: scheme.onPrimary,
              child: Icon(Icons.person, color: scheme.primary),
            ),
          ),
          tile(Icons.home_outlined, 'Ana Sayfa', () => go(0)),
          tile(Icons.bar_chart_outlined, 'İstatistikler', () => go(1)),
          tile(Icons.psychology_outlined, 'AI Asistanı', () => go(2)),
          tile(Icons.receipt_long_outlined, 'Listelerim', () => go(3)),
          tile(Icons.person_outline, 'Profil', () => go(4)),
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
