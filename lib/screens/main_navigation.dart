import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart'
    show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'friends_screen.dart';
import 'notifications_screen.dart';
import '../constants/categories.dart';
import '../repositories/notifications_repository.dart';
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
  String? _userAvatar;
  int _unread = 0;

  final supabase = Supabase.instance.client;
  final _notifRepo = NotificationsRepository();
  RealtimeChannel? _notifChannel;
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
    _fetchUnread();
    _watchNotifications();

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
          .select('name, avatar_url')
          .eq('id', user.id)
          .maybeSingle();
      if (mounted) {
        setState(() {
          _userName = (response?['name'] as String?)?.trim().isNotEmpty == true
              ? response!['name'] as String
              : 'Kullanıcı';
          _userEmail = user.email ?? '';
          _userAvatar = response?['avatar_url'] as String?;
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

  Future<void> _fetchUnread() async {
    try {
      final n = await _notifRepo.unreadCount();
      if (mounted) setState(() => _unread = n);
    } catch (_) {}
  }

  void _watchNotifications() {
    final uid = supabase.auth.currentUser?.id;
    if (uid == null) return;
    _notifChannel = supabase
        .channel('public:main_nav_notifications')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'notifications',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'user_id',
            value: uid,
          ),
          callback: (_) => _fetchUnread(),
        )
        .subscribe();
  }

  @override
  void dispose() {
    _notifChannel?.unsubscribe();
    super.dispose();
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
            MaterialPageRoute(builder: (_) => const NotificationsScreen()))
        .then((_) => _fetchUnread());
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
    Widget tile(
      IconData icon,
      String label,
      VoidCallback onTap, {
      Color? color,
      bool selected = false,
      Widget? trailing,
    }) {
      final fg = color ?? (selected ? scheme.primary : scheme.onSurface);
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
        child: ListTile(
          dense: true,
          selected: selected,
          selectedTileColor: AppTheme.heroGreenBg,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12)),
          leading: Icon(icon, size: 22, color: fg),
          title: Text(label,
              style: TextStyle(
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: fg)),
          trailing: trailing,
          onTap: () {
            Navigator.pop(context);
            onTap();
          },
        ),
      );
    }

    void go(int pageIndex) => setState(() => _pageIndex = pageIndex);
    void push(Widget page) =>
        Navigator.push(context, MaterialPageRoute(builder: (_) => page));

    final hasAvatar = _userAvatar != null && _userAvatar!.isNotEmpty;

    return Drawer(
      backgroundColor: scheme.surface,
      child: SafeArea(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 22, 20, 14),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 26,
                    backgroundColor: AppTheme.heroGreenBg,
                    backgroundImage:
                        hasAvatar ? NetworkImage(_userAvatar!) : null,
                    child: hasAvatar
                        ? null
                        : Icon(Icons.person, color: scheme.primary),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_userName,
                            style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                                color: scheme.onSurface),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis),
                        Text(_userEmail,
                            style: TextStyle(
                                fontSize: 12,
                                color: scheme.onSurfaceVariant),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: scheme.outlineVariant),
            const SizedBox(height: 6),
            tile(Icons.home_outlined, 'Ana Sayfa', () => go(0),
                selected: _pageIndex == 0),
            tile(Icons.checklist_outlined, 'Listelerim', () => go(1),
                selected: _pageIndex == 1),
            tile(Icons.auto_awesome_outlined, 'AI Asistanı', () => go(2),
                selected: _pageIndex == 2),
            tile(Icons.person_outline, 'Profil', () => go(3),
                selected: _pageIndex == 3),
            tile(Icons.bar_chart_outlined, 'İstatistikler', _openStats),
            Divider(height: 1, color: scheme.outlineVariant),
            const SizedBox(height: 6),
            tile(Icons.group_outlined, 'Arkadaşlar',
                () => push(const FriendsScreen())),
            tile(
              Icons.notifications_outlined,
              'Bildirimler',
              _openNotifications,
              trailing: _unread > 0
                  ? Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: scheme.primary,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        _unread > 99 ? '99+' : '$_unread',
                        style: TextStyle(
                            color: scheme.onPrimary,
                            fontSize: 11,
                            fontWeight: FontWeight.w700),
                      ),
                    )
                  : null,
            ),
            tile(
                Icons.settings_outlined,
                'Ayarlar',
                () => push(SettingsPage(
                      toggleTheme: widget.toggleTheme,
                      changeLocale: widget.changeLocale,
                    ))),
            Divider(height: 1, color: scheme.outlineVariant),
            const SizedBox(height: 6),
            tile(Icons.logout, 'Çıkış Yap', _signOut, color: scheme.error),
          ],
        ),
      ),
    );
  }
}
