import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:async';

import 'category_detail_page.dart';
import 'notifications_screen.dart';
import 'my_lists.dart';
import 'create_list.dart';
import 'friends_screen.dart';
import '../constants/categories.dart';
import '../widgets/ui_kit.dart';
import '../theme/app_theme.dart';

class HomePage extends StatefulWidget {
  final MaterialColor customPrimarySwatch;
  final VoidCallback? onMenuTap;
  const HomePage({
    super.key,
    required this.customPrimarySwatch,
    this.onMenuTap,
  });

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final supabase = Supabase.instance.client;

  String userName = '';
  List<dynamic> shoppingLists = [];
  int totalItems = 0;
  int completedItems = 0;
  List<Map<String, dynamic>> _dynamicCategories = [];
  List<Map<String, dynamic>> _allAvailableCategories = [];
  int _unread = 0;

  StreamSubscription<List<Map<String, dynamic>>>? _shoppingListSubscription;
  StreamSubscription<List<Map<String, dynamic>>>? _listItemSubscription;
  StreamSubscription<List<Map<String, dynamic>>>? _notifSubscription;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _initialize());
  }

  Future<void> _initialize() async {
    await fetchUserInfo();
    await fetchDynamicCategories();
    _setupRealtimeListeners();
  }

  void _setupRealtimeListeners() {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return;

    _shoppingListSubscription = supabase
        .from('shopping_lists')
        .stream(primaryKey: ['id'])
        .eq('user_id', userId)
        .order('created_at', ascending: false)
        .listen((data) {
      if (mounted) {
        setState(() => shoppingLists = data);
        fetchStatistics();
      }
    });

    _listItemSubscription =
        supabase.from('list_items').stream(primaryKey: ['id']).listen((_) {
      if (mounted) {
        fetchStatistics();
        fetchDynamicCategories();
        fetchUserInfo();
      }
    });

    _notifSubscription = supabase
        .from('notifications')
        .stream(primaryKey: ['id'])
        .eq('user_id', userId)
        .listen((rows) {
      if (mounted) {
        setState(() =>
            _unread = rows.where((r) => r['is_read'] != true).length);
      }
    });
  }

  @override
  void dispose() {
    _shoppingListSubscription?.cancel();
    _listItemSubscription?.cancel();
    _notifSubscription?.cancel();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Veri
  // ---------------------------------------------------------------------------

  Future<void> fetchUserInfo() async {
    final session = supabase.auth.currentSession;
    if (session == null) {
      if (mounted) Navigator.pushReplacementNamed(context, '/login');
      return;
    }
    final userId = session.user.id;
    final userResponse = await supabase
        .from('users')
        .select('name')
        .eq('id', userId)
        .maybeSingle();

    final listResponse = await supabase
        .from('shopping_lists')
        .select('*, list_items(is_completed)')
        .eq('user_id', userId)
        .order('created_at', ascending: false);

    if (!mounted) return;
    setState(() {
      userName = userResponse?['name'] ?? 'Kullanıcı';
      shoppingLists = listResponse;
    });
    await fetchStatistics();
  }

  Future<void> fetchStatistics() async {
    if (shoppingLists.isEmpty) {
      if (mounted) {
        setState(() {
          totalItems = 0;
          completedItems = 0;
        });
      }
      return;
    }
    final listIds = shoppingLists.map((e) => e['id']).toList();
    final response = await supabase
        .from('list_items')
        .select('is_completed')
        .filter('list_id', 'in', '(${listIds.join(',')})');

    final completed =
        response.where((item) => item['is_completed'] == true).length;
    if (!mounted) return;
    setState(() {
      totalItems = response.length;
      completedItems = completed;
    });
  }

  Future<void> fetchDynamicCategories() async {
    try {
      final allListItemsResponse =
          await supabase.from('list_items').select('category, is_completed');

      final Map<String, int> categoryCounts = {};
      final Set<String> uniqueListItemCategories = {};
      for (var item in allListItemsResponse) {
        final categoryName = item['category'] as String?;
        if (categoryName != null && categoryName.isNotEmpty) {
          categoryCounts[categoryName] =
              (categoryCounts[categoryName] ?? 0) + 1;
          uniqueListItemCategories.add(categoryName);
        }
      }

      final tempAllAvailable =
          mergeDiscoveredCategories(uniqueListItemCategories);
      final userId = supabase.auth.currentUser?.id;
      List<String> preferredCategoryNames = [];
      if (userId != null) {
        final userResponse = await supabase
            .from('users')
            .select('preferred_categories')
            .eq('id', userId)
            .maybeSingle();
        if (userResponse != null &&
            userResponse['preferred_categories'] != null) {
          preferredCategoryNames =
              List<String>.from(userResponse['preferred_categories']);
        }
      }

      List<Map<String, dynamic>> categoriesToDisplay = [];
      if (preferredCategoryNames.isNotEmpty) {
        for (String pName in preferredCategoryNames) {
          final matched = tempAllAvailable.firstWhere(
            (cat) => cat['name'].toLowerCase() == pName.toLowerCase(),
            orElse: () => {
              'name': pName,
              'icon': Icons.category_outlined,
              'colors': [Colors.blueGrey.shade300, Colors.blueGrey.shade500],
            },
          );
          categoriesToDisplay.add({
            ...matched,
            'count': categoryCounts[matched['name']] ?? 0,
          });
        }
      } else {
        final temp = <Map<String, dynamic>>[];
        for (var catData in tempAllAvailable) {
          temp.add({
            'name': catData['name'],
            'icon': catData['icon'],
            'colors': catData['colors'],
            'count': categoryCounts[catData['name']] ?? 0,
          });
        }
        temp.sort(
            (a, b) => (b['count'] as int).compareTo(a['count'] as int));
        categoriesToDisplay = temp.take(8).toList();
      }

      if (!mounted) return;
      setState(() {
        _allAvailableCategories = tempAllAvailable;
        _dynamicCategories = categoriesToDisplay;
      });
    } catch (e) {
      debugPrint('Dinamik kategoriler çekilemedi: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // Yardımcılar
  // ---------------------------------------------------------------------------

  ({String name, int done, int total, Map<String, dynamic> raw})?
      get _activeList {
    if (shoppingLists.isEmpty) return null;
    final l = shoppingLists.first as Map<String, dynamic>;
    final items = (l['list_items'] as List?) ?? const [];
    final done = items.where((e) => e['is_completed'] == true).length;
    return (
      name: (l['name'] ?? 'İsimsiz') as String,
      done: done,
      total: items.length,
      raw: l,
    );
  }

  int _listItemCount(Map<String, dynamic> l) =>
      ((l['list_items'] as List?) ?? const []).length;

  int _listDoneCount(Map<String, dynamic> l) =>
      ((l['list_items'] as List?) ?? const [])
          .where((e) => e['is_completed'] == true)
          .length;

  void _openList(Map<String, dynamic> list) {
    Navigator.pushNamed(context, '/listDetail', arguments: {
      'id': list['id'],
      'name': list['name'],
      'user_id': list['user_id'],
    });
  }

  void _openAllLists() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            MyListsPage(customPrimarySwatch: widget.customPrimarySwatch),
      ),
    );
  }

  /// Boş liste (ya da şablon adı verilirse o şablonla dolu) oluşturma ekranı.
  void _createList({String? template}) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CreateListPage(
          availableCategories: _allAvailableCategories,
          customPrimarySwatch: widget.customPrimarySwatch,
          initialTemplate: template,
        ),
      ),
    );
  }

  void _openFriends() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const FriendsScreen()),
    );
  }

  void _showCategoryManagementSheet() {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return;
    List<String> selected =
        _dynamicCategories.map((e) => e['name'] as String).toList();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (bc) {
        return StatefulBuilder(builder: (context, modalSetState) {
          final scheme = Theme.of(context).colorScheme;
          return Container(
            height: MediaQuery.of(context).size.height * 0.8,
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Popüler Kategorileri Yönet',
                    style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: scheme.onSurface)),
                const SizedBox(height: 6),
                Text('Ana sayfada göstermek istediklerini seç (en fazla 8).',
                    style: TextStyle(
                        fontSize: 13, color: scheme.onSurfaceVariant)),
                const SizedBox(height: 12),
                Expanded(
                  child: ListView.builder(
                    itemCount: _allAvailableCategories.length,
                    itemBuilder: (context, index) {
                      final category = _allAvailableCategories[index];
                      final isSelected = selected.contains(category['name']);
                      return CheckboxListTile(
                        title: Text(category['name']),
                        secondary: Text(
                            categoryEmoji(category['name'] as String),
                            style: const TextStyle(fontSize: 22)),
                        value: isSelected,
                        onChanged: (v) {
                          modalSetState(() {
                            if (v == true) {
                              if (selected.length < 8) {
                                selected.add(category['name'] as String);
                              }
                            } else {
                              selected.remove(category['name'] as String);
                            }
                          });
                        },
                      );
                    },
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () async {
                      try {
                        await supabase
                            .from('users')
                            .update({'preferred_categories': selected})
                            .eq('id', userId);
                        if (mounted) {
                          Navigator.pop(context);
                          await fetchDynamicCategories();
                        }
                      } catch (e) {
                        debugPrint('Kategori tercihleri kaydedilemedi: $e');
                      }
                    },
                    child: const Text('Kaydet'),
                  ),
                ),
              ],
            ),
          );
        });
      },
    );
  }

  // ---------------------------------------------------------------------------
  // UI
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          onRefresh: _initialize,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 22, 20, 30),
            children: [
              _header(scheme),
              const SizedBox(height: 20),
              if (_activeList != null)
                _activeListHero(scheme, _activeList!)
              else
                _emptyHero(scheme),
              const SizedBox(height: 16),
              _quickActions(scheme),
              const SizedBox(height: 16),
              _statRow(scheme),
              const SizedBox(height: 24),
              SectionHeader(
                title: 'Kategoriler',
                actionLabel: 'Tümü',
                onAction: _showCategoryManagementSheet,
              ),
              _categoryRow(scheme),
              const SizedBox(height: 20),
              SectionHeader(
                title: 'Listeler',
                actionLabel: 'Tümünü Gör',
                onAction: _openAllLists,
              ),
              ..._listCards(),
              const SizedBox(height: 4),
              _aiCard(scheme),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header(ColorScheme scheme) {
    return Row(
      children: [
        if (widget.onMenuTap != null) ...[
          IconButton(
            onPressed: widget.onMenuTap,
            icon: const Icon(Icons.menu_rounded),
            padding: EdgeInsets.zero,
            visualDensity: VisualDensity.compact,
            constraints: const BoxConstraints(),
          ),
          const SizedBox(width: 10),
        ],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Merhaba, ${userName.isEmpty ? '' : userName} 👋',
                style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: scheme.onSurface),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              Text('Bugün ne planlıyoruz?',
                  style: TextStyle(
                      fontSize: 13, color: scheme.onSurfaceVariant)),
            ],
          ),
        ),
        IconButton(
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const NotificationsScreen()),
          ),
          icon: Badge(
            isLabelVisible: _unread > 0,
            label: Text(_unread > 99 ? '99+' : '$_unread'),
            backgroundColor: scheme.error,
            child: const Icon(Icons.notifications_none_rounded),
          ),
        ),
      ],
    );
  }

  Widget _activeListHero(ColorScheme scheme,
      ({String name, int done, int total, Map<String, dynamic> raw}) a) {
    final ratio = a.total == 0 ? 0.0 : a.done / a.total;
    return GestureDetector(
      onTap: () => _openList(a.raw),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFFE1F7E6), Color(0xFFF5FBF6)],
          ),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: const Color(0xFFD4EFD9)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Aktif Liste',
                      style: TextStyle(
                          color: scheme.primary,
                          fontSize: 12,
                          fontWeight: FontWeight.w600)),
                  const SizedBox(height: 5),
                  Text(a.name,
                      style: const TextStyle(
                          fontSize: 17, fontWeight: FontWeight.w800),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 5),
                  Text('${a.done} / ${a.total} ürün',
                      style: TextStyle(
                          color: scheme.onSurfaceVariant, fontSize: 12)),
                ],
              ),
            ),
            const SizedBox(width: 12),
            PercentRing(value: ratio, size: 62),
          ],
        ),
      ),
    );
  }

  Widget _emptyHero(ColorScheme scheme) {
    const templates = ['Haftalık Market', 'Kahvaltılık', 'Temizlik', 'Bebek'];
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFE1F7E6), Color(0xFFF5FBF6)],
        ),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFD4EFD9)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: scheme.primary.withValues(alpha: 0.14),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.playlist_add_rounded,
                    color: scheme.primary, size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Haydi başlayalım',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 2),
                    Text('İlk alışveriş listeni birkaç saniyede oluştur.',
                        style: TextStyle(
                            fontSize: 12, color: scheme.onSurfaceVariant)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () => _createList(),
              icon: const Icon(Icons.add, size: 20),
              label: const Text('İlk Listeni Oluştur'),
            ),
          ),
          const SizedBox(height: 12),
          Text('Ya da hazır bir şablonla:',
              style:
                  TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final t in templates)
                ActionChip(
                  label: Text(t),
                  labelStyle: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w600),
                  backgroundColor: Colors.white,
                  side: const BorderSide(color: Color(0xFFD4EFD9)),
                  onPressed: () => _createList(template: t),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _quickActions(ColorScheme scheme) {
    Widget tile(
        IconData icon, String label, Color color, VoidCallback onTap) {
      return Expanded(
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 14),
            decoration: BoxDecoration(
              color: scheme.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: scheme.outlineVariant),
              boxShadow: AppTheme.softShadow(Theme.of(context).brightness),
            ),
            child: Column(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, color: color, size: 21),
                ),
                const SizedBox(height: 8),
                Text(label,
                    style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: scheme.onSurface)),
              ],
            ),
          ),
        ),
      );
    }

    return Row(
      children: [
        tile(Icons.add_shopping_cart_rounded, 'Yeni Liste', scheme.primary,
            () => _createList()),
        const SizedBox(width: 10),
        tile(Icons.auto_awesome_rounded, 'AI Asistan',
            const Color(0xFF8B5CF6), () => Navigator.pushNamed(context, '/aiChat')),
        const SizedBox(width: 10),
        tile(Icons.group_add_rounded, 'Arkadaş Ekle', const Color(0xFF3B82F6),
            _openFriends),
      ],
    );
  }

  Widget _statRow(ColorScheme scheme) {
    final pending = (totalItems - completedItems).clamp(0, 1 << 30);
    return Row(
      children: [
        Expanded(
          child: MiniStatCard(
            value: '$pending',
            label: 'Bekleyen',
            icon: Icons.pending_actions_rounded,
            iconColor: AppTheme.accentOrange,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: MiniStatCard(
            value: '$completedItems',
            label: 'Tamamlanan',
            icon: Icons.check_circle_rounded,
            iconColor: scheme.primary,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: MiniStatCard(
            value: '${shoppingLists.length}',
            label: 'Listeler',
            icon: Icons.checklist_rounded,
            iconColor: AppTheme.accentBlue,
          ),
        ),
      ],
    );
  }

  Widget _categoryRow(ColorScheme scheme) {
    if (_dynamicCategories.isEmpty) {
      return Text('Ürün ekledikçe kategoriler burada görünür.',
          style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13));
    }
    return SizedBox(
      height: 102,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.only(bottom: 6),
        itemCount: _dynamicCategories.length,
        itemBuilder: (context, i) {
          final cat = _dynamicCategories[i];
          final name = cat['name'] as String;
          return CategoryCard(
            title: name,
            emoji: categoryEmoji(name),
            count: (cat['count'] as int?) ?? 0,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => CategoryDetailPage(
                  categoryName: name,
                  customPrimarySwatch: widget.customPrimarySwatch,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  List<Widget> _listCards() {
    if (shoppingLists.isEmpty) {
      return [
        Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
                color: Theme.of(context).colorScheme.outlineVariant),
          ),
          child: Text('Henüz listen yok.',
              style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant)),
        ),
      ];
    }
    return shoppingLists.take(3).map<Widget>((l) {
      final list = l as Map<String, dynamic>;
      return ListCard(
        title: (list['name'] ?? 'İsimsiz') as String,
        done: _listDoneCount(list),
        total: _listItemCount(list),
        onTap: () => _openList(list),
      );
    }).toList();
  }

  Widget _aiCard(ColorScheme scheme) {
    return GestureDetector(
      onTap: () => Navigator.pushNamed(context, '/aiChat'),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: scheme.outlineVariant),
          boxShadow: AppTheme.softShadow(Theme.of(context).brightness),
        ),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: AppTheme.heroGreenBg,
              child: Icon(Icons.auto_awesome, color: scheme.primary),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('AI Asistan',
                      style: TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Text('Elindeki malzemelerle ne yapabileceğini keşfet.',
                      style: TextStyle(
                          fontSize: 11, color: scheme.onSurfaceVariant)),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: scheme.primary),
          ],
        ),
      ),
    );
  }
}
