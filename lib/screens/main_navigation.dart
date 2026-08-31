import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Kendi ekranlarınızın importları. Dosya yollarının doğru olduğundan emin olun.
import 'home.dart';
import 'create_list.dart';
import 'profile.dart';
import 'settings.dart';
import 'ai_chat.dart';
import 'stats.dart'; // StatsPage import edildi
import 'my_lists.dart'; // my_lists.dart import edildi

class MainNavigationPage extends StatefulWidget {
  final void Function() toggleTheme;
  final void Function(Locale) changeLocale;
  final MaterialColor customPrimarySwatch; // Add this required parameter

  const MainNavigationPage({
    super.key,
    required this.toggleTheme,
    required this.changeLocale,
    required this.customPrimarySwatch, // Make it required
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

  late List<Widget> _pages;
  bool _pagesInitialized = false;

  @override
  void initState() {
    super.initState();
    _fetchUserProfile();

    // _pages, build metodunda Theme.of(context) erişilebilirken oluşturulacak.
    _pages = [];

    _fetchAllAvailableCategories().then((_) {
      if (mounted) {
        setState(() {
          _pagesInitialized = true;
          // Eğer _selectedIndex geçersiz bir değerse veya boşsa 0'a ayarla
          if (_selectedIndex >= _pages.length || _pages.isEmpty) {
            _selectedIndex = 0;
          }
        });
      }
    });

    supabase.auth.onAuthStateChange.listen((data) {
      if (mounted) {
        final AuthChangeEvent event = data.event;
        if (event == AuthChangeEvent.signedIn || event == AuthChangeEvent.initialSession) {
          _fetchUserProfile();
        } else if (event == AuthChangeEvent.signedOut) {
          setState(() {
            _userName = 'Misafir';
            _userEmail = '';
          });
          if (mounted) { // Ensure context is still valid before navigating
            Navigator.pushReplacementNamed(context, '/login');
          }
        }
      }
    });
  }

  Future<void> _fetchAllAvailableCategories() async {
    try {
      List<Map<String, dynamic>> defaultDefinedCategories = [
        {
          'name': 'Market',
          'icon': Icons.local_grocery_store,
          'colors': [const Color(0xFF56AB2F), const Color(0xFFA8E063)],
        },
        {
          'name': 'Kıyafet',
          'icon': Icons.style,
          'colors': [const Color(0xFFF7971E), const Color(0xFFFF5F6D)],
        },
        {
          'name': 'Elektronik',
          'icon': Icons.power,
          'colors': [Colors.blue.shade300, Colors.blue.shade500],
        },
        {
          'name': 'Temizlik',
          'icon': Icons.cleaning_services,
          'colors': [const Color(0xFF4CB8C4), const Color(0xFF3CD3AD)],
        },
        {
          'name': 'Kırtasiye',
          'icon': Icons.school,
          'colors': [const Color(0xFFFFCC33), const Color(0xFFE2B00E)],
        },
        {
          'name': 'Evcil Hayvan',
          'icon': Icons.pets,
          'colors': [const Color(0xFF536976), const Color(0xFF292E49)],
        },
        {
          'name': 'Gıda',
          'icon': Icons.restaurant_menu,
          'colors': [const Color(0xFFA8E063), const Color(0xFF56AB2F)],
        },
        {
          'name': 'Bebek',
          'icon': Icons.child_care,
          'colors': [Colors.pink.shade50, Colors.pink.shade200],
        },
      ];

      final response = await supabase
          .from('list_items')
          .select('category');

      Set<String> uniqueListItemCategories = {};
      for (var item in response) {
        final categoryName = item['category'] as String?;
        if (categoryName != null && categoryName.isNotEmpty) {
          uniqueListItemCategories.add(categoryName);
        }
      }

      List<Map<String, dynamic>> tempAllAvailableCategories = [];
      tempAllAvailableCategories.addAll(defaultDefinedCategories);

      for (String categoryName in uniqueListItemCategories) {
        if (!tempAllAvailableCategories.any((cat) => cat['name'].toLowerCase() == categoryName.toLowerCase())) {
          tempAllAvailableCategories.add({
            'name': categoryName,
            'icon': Icons.category_outlined,
            'colors': [Colors.blueGrey.shade300, Colors.blueGrey.shade500],
          });
        }
      }

      if (mounted) {
        setState(() {
          _allAvailableCategories = tempAllAvailableCategories;
        });
      }
    } catch (e) {
      debugPrint('Tüm mevcut kategoriler çekilemedi: $e');
    }
  }

  Future<void> _fetchUserProfile() async {
    final user = supabase.auth.currentUser;
    if (user != null) {
      try {
        final response = await supabase
            .from('users')
            .select('name')
            .eq('id', user.id)
            .single();

        if (mounted) { // Check mounted before setState
          setState(() {
            _userName = response['name'] as String? ?? 'Kullanıcı';
            _userEmail = user.email ?? 'E-posta Yok';
          });
        }
      } catch (e) {
        debugPrint('Kullanıcı profili çekilemedi: $e');
        if (mounted) { // Check mounted before setState
          setState(() {
            _userName = 'Kullanıcı';
            _userEmail = user.email ?? 'E-posta Yok';
          });
        }
      }
    } else {
      if (mounted) { // Check mounted before setState
        setState(() {
          _userName = 'Misafir';
          _userEmail = '';
        });
      }
    }
  }

  void _onNavTapped(int index) {
    final MaterialColor safePrimarySwatch = widget.customPrimarySwatch;

    // "Ekle" butonu (index 3) için özel durum: Yeni bir sayfa açıyoruz, ana indeksi değiştirmemeliyiz.
    if (index == 3) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => CreateListPage(
            availableCategories: _allAvailableCategories,
            customPrimarySwatch: safePrimarySwatch, // Parametre olarak gönderildi
          ),
        ),
      );
    } else {
      // Diğer tüm butonlar için _selectedIndex'i güncelleyerek IndexedStack'in sayfa değiştirmesini sağlıyoruz.
      setState(() {
        _selectedIndex = index;
      });
    }
  }

  Future<void> _signOut() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('email');
    await prefs.remove('password');
    await prefs.setBool('rememberMe', false);

    await supabase.auth.signOut();
  }

  @override
  Widget build(BuildContext context) {
    if (!_pagesInitialized) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    final Color globalPrimaryColor = Theme.of(context).primaryColor;
    final MaterialColor safePrimarySwatch = widget.customPrimarySwatch;

    // Sayfaları burada, build metodu içinde ve Theme.of(context) erişilebilirken oluşturuyoruz.
    // 'Ekle' (index 3) için boş bir Container veya varsayılan bir sayfa bırakın,
    // çünkü bu tab doğrudan Navigator.push ile başka bir sayfa açacak.
    _pages = [
      HomePage(customPrimarySwatch: safePrimarySwatch), // index 0
      StatsPage(customPrimarySwatch: safePrimarySwatch), // index 1
      const AIChatPage(), // index 2
      Container(), // index 3: 'Ekle' butonu için yer tutucu, çünkü Navigator.push kullanılıyor
      MyListsPage(customPrimarySwatch: safePrimarySwatch), // index 4
      const ProfilePage(), // index 5
    ];


    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      drawer: Drawer(
        child: ListView(
          padding: EdgeInsets.zero,
          children: <Widget>[
            DrawerHeader(
              decoration: BoxDecoration(
                color: globalPrimaryColor,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  CircleAvatar(
                    radius: 30,
                    backgroundColor: Colors.white.withAlpha((255 * 0.8).round()),
                    child: const Icon(Icons.person, color: Colors.white, size: 24),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    _userName,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    _userEmail,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
            ListTile(
              leading: Icon(Icons.home_outlined, color: globalPrimaryColor),
              title: const Text('Ana Sayfa', style: TextStyle(fontWeight: FontWeight.w500)),
              onTap: () {
                Navigator.pop(context);
                _onNavTapped(0); // Ana Sayfa'ya geçiş
              },
            ),
            ListTile(
              leading: Icon(Icons.psychology_outlined, color: globalPrimaryColor),
              title: const Text('AI Asistanı', style: TextStyle(fontWeight: FontWeight.w500)),
              onTap: () {
                Navigator.pop(context);
                _onNavTapped(2); // AI Asistanı'na geçiş
              },
            ),
            ListTile(
              leading: Icon(Icons.bar_chart_outlined, color: globalPrimaryColor),
              title: const Text('İstatistikler', style: TextStyle(fontWeight: FontWeight.w500)),
              onTap: () {
                Navigator.pop(context);
                _onNavTapped(1); // İstatistikler'e geçiş
              },
            ),
            ListTile(
              leading: Icon(Icons.history_outlined, color: globalPrimaryColor),
              title: const Text('Geçmiş Listeler', style: TextStyle(fontWeight: FontWeight.w500)),
              onTap: () {
                Navigator.pop(context);
                _onNavTapped(4); // Geçmiş Listeler'e geçiş (MyListsPage)
              },
            ),
            ListTile(
              leading: Icon(Icons.person_outline, color: globalPrimaryColor),
              title: const Text('Profil', style: TextStyle(fontWeight: FontWeight.w500)),
              onTap: () {
                Navigator.pop(context);
                _onNavTapped(5); // Profil'e geçiş
              },
            ),
            const Divider(),
            ListTile(
              leading: Icon(Icons.settings_outlined, color: globalPrimaryColor),
              title: const Text('Ayarlar', style: TextStyle(fontWeight: FontWeight.w500)),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(context, MaterialPageRoute(builder: (context) => SettingsPage(
                    toggleTheme: widget.toggleTheme,
                    changeLocale: widget.changeLocale,
                )));
              },
            ),
            ListTile(
              leading: const Icon(Icons.logout, color: Colors.red),
              title: const Text('Çıkış Yap', style: TextStyle(fontWeight: FontWeight.w500, color: Colors.red)),
              onTap: _signOut,
            ),
          ],
        ),
      ),
      body: IndexedStack(
        index: _selectedIndex,
        children: _pages,
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: _onNavTapped,
        selectedItemColor: globalPrimaryColor,
        unselectedItemColor: Colors.grey.shade600,
        type: BottomNavigationBarType.fixed,
        showUnselectedLabels: true,
        selectedLabelStyle: const TextStyle(fontWeight: FontWeight.bold),
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.home_outlined),
            activeIcon: Icon(Icons.home_rounded),
            label: 'Ana Sayfa',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.bar_chart_outlined),
            activeIcon: Icon(Icons.bar_chart_rounded),
            label: 'İstatistikler',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.psychology_outlined),
            activeIcon: Icon(Icons.psychology),
            label: 'AI Asistan',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.add_circle_outline),
            activeIcon: Icon(Icons.add_circle_rounded),
            label: 'Ekle',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.history_outlined),
            activeIcon: Icon(Icons.history_rounded),
            label: 'Geçmiş',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person_outline),
            activeIcon: Icon(Icons.person_rounded),
            label: 'Profil',
          ),
        ],
      ),
      floatingActionButton: (_selectedIndex == 0 || _selectedIndex == 3) && _pagesInitialized
          ? FloatingActionButton.extended(
              onPressed: () {
                // Use widget.customPrimarySwatch which is already a MaterialColor
                final MaterialColor safePrimarySwatch = widget.customPrimarySwatch;

                // CreateListPage'i FAB'dan açarken de Navigator.push kullanıyoruz.
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => CreateListPage(
                      availableCategories: _allAvailableCategories,
                      customPrimarySwatch: safePrimarySwatch, // Parametre olarak gönderildi
                    ),
                  ),
                );
              },
              label: const Text("Yeni Liste Oluştur", style: TextStyle(fontWeight: FontWeight.bold)),
              icon: const Icon(Icons.add),
              backgroundColor: globalPrimaryColor,
              foregroundColor: Colors.white,
            )
          : null,
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    );
  }
}
