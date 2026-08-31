import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'package:fl_chart/fl_chart.dart';
import 'dart:async';

import 'category_detail_page.dart';
import 'notifications_screen.dart';
import '../constants/categories.dart';
import '../widgets/ui_kit.dart';

/// Haftalık grafik için basit veri modeli.
class WeeklyData {
  final String day;
  final int itemCount;
  WeeklyData({required this.day, required int itemCount})
      : itemCount = itemCount >= 0 ? itemCount : 0;
}

class HomePage extends StatefulWidget {
  final MaterialColor customPrimarySwatch;
  const HomePage({super.key, required this.customPrimarySwatch});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final supabase = Supabase.instance.client;

  String userName = '';
  List<dynamic> shoppingLists = [];
  int totalItems = 0;
  int completedItems = 0;
  List<WeeklyData> weeklyData = [];
  List<Map<String, dynamic>> topProducts = [];
  List<String> suggestedToday = [];
  List<Map<String, dynamic>> _dynamicCategories = [];
  List<Map<String, dynamic>> _allAvailableCategories = [];

  StreamSubscription<List<Map<String, dynamic>>>? _shoppingListSubscription;
  StreamSubscription<List<Map<String, dynamic>>>? _listItemSubscription;

  @override
  void initState() {
    super.initState();
    Intl.defaultLocale = 'tr_TR';
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeDataAndListeners();
    });
  }

  Future<void> _initializeDataAndListeners() async {
    await fetchUserInfo();
    await fetchWeeklyData();
    await fetchTopProducts();
    await fetchSuggestions();
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
        supabase.from('list_items').stream(primaryKey: ['id']).listen((data) {
      if (mounted) {
        fetchStatistics();
        fetchTopProducts();
        fetchSuggestions();
        fetchDynamicCategories();
        fetchUserInfo();
      }
    });
  }

  @override
  void dispose() {
    _shoppingListSubscription?.cancel();
    _listItemSubscription?.cancel();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Veri çekme
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

  Future<void> fetchWeeklyData() async {
    final oneWeekAgo = DateTime.now().subtract(const Duration(days: 7));
    final response = await supabase
        .from('list_items')
        .select('created_at')
        .gte('created_at', oneWeekAgo.toIso8601String());

    final dailyCounts = {
      'Pzt': 0, 'Sal': 0, 'Çar': 0, 'Per': 0, 'Cum': 0, 'Cmt': 0, 'Paz': 0
    };
    for (var item in response) {
      final date = DateTime.parse(item['created_at']);
      final weekday = _turkishDay(date.weekday);
      dailyCounts[weekday] = dailyCounts[weekday]! + 1;
    }
    const orderedDays = ['Pzt', 'Sal', 'Çar', 'Per', 'Cum', 'Cmt', 'Paz'];
    if (!mounted) return;
    setState(() {
      weeklyData = orderedDays
          .map((day) => WeeklyData(day: day, itemCount: dailyCounts[day]!))
          .toList();
    });
  }

  Future<void> fetchTopProducts() async {
    final response =
        await supabase.from('list_items').select('product_name').limit(200);
    final productCount = <String, int>{};
    for (var item in response) {
      final name = item['product_name'];
      if (name != null) productCount[name] = (productCount[name] ?? 0) + 1;
    }
    final sorted = productCount.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    if (!mounted) return;
    setState(() {
      topProducts = sorted
          .take(6)
          .map((e) => {'product_name': e.key, 'count': e.value})
          .toList();
    });
  }

  Future<void> fetchSuggestions() async {
    final recentItems = await supabase
        .from('list_items')
        .select('product_name, is_completed, created_at')
        .order('created_at', ascending: false)
        .limit(50);
    final productCounts = <String, int>{};
    for (var item in recentItems) {
      if (item['is_completed'] == false && item['product_name'] != null) {
        final product = item['product_name'];
        productCounts[product] = (productCounts[product] ?? 0) + 1;
      }
    }
    final sorted = productCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    if (!mounted) return;
    setState(() {
      suggestedToday = sorted.take(3).map((e) => e.key).toList();
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

  String _turkishDay(int weekday) {
    const days = ['Pzt', 'Sal', 'Çar', 'Per', 'Cum', 'Cmt', 'Paz'];
    return days[weekday - 1];
  }

  /// En yeni listenin (varsa) adı + tamamlanan/toplam ürün sayısı.
  ({String name, int done, int total, Map<String, dynamic> raw})? get _activeList {
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

  void _openList(Map<String, dynamic> list) {
    Navigator.pushNamed(context, '/listDetail', arguments: {
      'id': list['id'],
      'name': list['name'],
      'user_id': list['user_id'],
    });
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
                        fontWeight: FontWeight.w700,
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
                      final colors =
                          (category['colors'] as List?)?.cast<Color>() ??
                              const [Color(0xFF90A4AE)];
                      return CheckboxListTile(
                        title: Text(category['name']),
                        secondary: Icon(category['icon'] as IconData,
                            color: colors.first),
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
          onRefresh: _initializeDataAndListeners,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 110),
            children: [
              _header(scheme),
              const SizedBox(height: 18),
              if (_activeList != null)
                _activeListHero(scheme, _activeList!)
              else
                _emptyHero(scheme),
              const SizedBox(height: 16),
              _statRow(scheme),
              const SizedBox(height: 26),
              SectionHeader(
                title: 'Kategoriler',
                actionLabel: 'Tümü',
                onAction: _showCategoryManagementSheet,
              ),
              _categoryRow(scheme),
              const SizedBox(height: 22),
              _aiCard(scheme),
              if (suggestedToday.isNotEmpty) ...[
                const SizedBox(height: 26),
                _suggestionsSection(scheme),
              ],
              if (weeklyData.any((d) => d.itemCount > 0)) ...[
                const SizedBox(height: 26),
                _weeklyChartCard(scheme),
              ],
              if (topProducts.isNotEmpty) ...[
                const SizedBox(height: 26),
                _topProductsCard(scheme),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // --- Header ------------------------------------------------------------

  Widget _header(ColorScheme scheme) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Merhaba, ${userName.isEmpty ? '' : userName} 👋',
                style: TextStyle(
                  fontSize: 21,
                  fontWeight: FontWeight.w800,
                  color: scheme.onSurface,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              Text('Bugün ne planlıyorsun?',
                  style: TextStyle(
                      fontSize: 13, color: scheme.onSurfaceVariant)),
            ],
          ),
        ),
        _CircleIconButton(
          icon: Icons.notifications_none_rounded,
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const NotificationsScreen()),
          ),
        ),
      ],
    );
  }

  // --- Hero: aktif liste ----------------------------------------------

  Widget _activeListHero(
      ColorScheme scheme, ({String name, int done, int total, Map<String, dynamic> raw}) a) {
    final value = a.total == 0 ? 0.0 : a.done / a.total;
    return InkWell(
      onTap: () => _openList(a.raw),
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: scheme.primaryContainer,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Aktif Listen',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: scheme.onPrimaryContainer)),
                  const SizedBox(height: 6),
                  Text(a.name,
                      style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: scheme.onSurface),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 2),
                  Text('${a.done} / ${a.total} ürün',
                      style: TextStyle(
                          fontSize: 13, color: scheme.onSurfaceVariant)),
                ],
              ),
            ),
            const SizedBox(width: 12),
            PercentRing(value: value.toDouble(), size: 60),
          ],
        ),
      ),
    );
  }

  Widget _emptyHero(ColorScheme scheme) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: scheme.primaryContainer,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          Icon(Icons.playlist_add_rounded,
              color: scheme.onPrimaryContainer, size: 34),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Henüz listen yok',
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: scheme.onSurface)),
                const SizedBox(height: 2),
                Text('Alttaki + ile ilk listeni oluştur.',
                    style: TextStyle(
                        fontSize: 13, color: scheme.onSurfaceVariant)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // --- 3'lü istatistik -----------------------------------------------

  Widget _statRow(ColorScheme scheme) {
    final pending = (totalItems - completedItems).clamp(0, 1 << 30);
    return Row(
      children: [
        Expanded(
            child: MiniStatCard(
                value: '$pending', label: 'Bekleyen Ürün')),
        const SizedBox(width: 12),
        Expanded(
            child: MiniStatCard(
                value: '$completedItems', label: 'Tamamlanan')),
        const SizedBox(width: 12),
        Expanded(
            child: MiniStatCard(
                value: '${shoppingLists.length}', label: 'Listelerin')),
      ],
    );
  }

  // --- Kategoriler ---------------------------------------------------

  Widget _categoryRow(ColorScheme scheme) {
    if (_dynamicCategories.isEmpty) {
      return Text('Ürün ekledikçe kategoriler burada görünür.',
          style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13));
    }
    return SizedBox(
      height: 96,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.zero,
        itemCount: _dynamicCategories.length,
        separatorBuilder: (_, __) => const SizedBox(width: 16),
        itemBuilder: (context, i) {
          final cat = _dynamicCategories[i];
          final colors = (cat['colors'] as List?)?.cast<Color>() ??
              const [Color(0xFF90A4AE), Color(0xFF607D8B)];
          final count = (cat['count'] as int?) ?? 0;
          return GestureDetector(
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => CategoryDetailPage(
                  categoryName: cat['name'] as String,
                  customPrimarySwatch: widget.customPrimarySwatch,
                ),
              ),
            ),
            child: SizedBox(
              width: 64,
              child: Column(
                children: [
                  Container(
                    width: 54,
                    height: 54,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(colors: colors),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                        cat['icon'] as IconData? ?? Icons.category_outlined,
                        color: Colors.white,
                        size: 24),
                  ),
                  const SizedBox(height: 6),
                  Text(cat['name'] as String,
                      style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: scheme.onSurface),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  Text(count > 0 ? '$count ürün' : '—',
                      style: TextStyle(
                          fontSize: 10, color: scheme.onSurfaceVariant)),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // --- AI Asistan kartı --------------------------------------------

  Widget _aiCard(ColorScheme scheme) {
    return InkWell(
      onTap: () => Navigator.pushNamed(context, '/aiChat'),
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: scheme.primaryContainer,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: scheme.surface,
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.smart_toy_rounded,
                  color: scheme.primary, size: 24),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('AI Asistan',
                      style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: scheme.onSurface)),
                  const SizedBox(height: 2),
                  Text(
                      'Elindeki malzemelerle ne yapabileceğini sor!',
                      style: TextStyle(
                          fontSize: 12, color: scheme.onSurfaceVariant)),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
          ],
        ),
      ),
    );
  }

  // --- Ek bölümler (mockup'ta yok, faydalı olduğu için altta) ------

  Widget _suggestionsSection(ColorScheme scheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader(title: 'Önerilen ürünler'),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: suggestedToday.map((name) {
            return ActionChip(
              avatar:
                  Icon(Icons.add_rounded, size: 18, color: scheme.primary),
              label: Text(name),
              onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('"$name" için bir listeye ekleyin.')),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _weeklyChartCard(ColorScheme scheme) {
    final maxCount = weeklyData
        .map((e) => e.itemCount)
        .fold<int>(0, (a, b) => a > b ? a : b);
    final maxY = (maxCount == 0 ? 5 : maxCount * 1.2).toDouble();

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(16),
        border:
            Border.all(color: scheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Haftalık Aktivite',
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: scheme.onSurface)),
          const SizedBox(height: 16),
          SizedBox(
            height: 180,
            child: BarChart(
              BarChartData(
                alignment: BarChartAlignment.spaceAround,
                barTouchData: BarTouchData(enabled: false),
                maxY: maxY,
                titlesData: FlTitlesData(
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 28,
                        getTitlesWidget: (v, m) => Text(v.toInt().toString(),
                            style: TextStyle(
                                color: scheme.onSurfaceVariant,
                                fontSize: 10))),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      getTitlesWidget: (v, m) {
                        final i = v.toInt();
                        if (i < 0 || i >= weeklyData.length) {
                          return const SizedBox();
                        }
                        return Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(weeklyData[i].day,
                              style: TextStyle(
                                  color: scheme.onSurfaceVariant,
                                  fontSize: 10)),
                        );
                      },
                    ),
                  ),
                  topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                ),
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  getDrawingHorizontalLine: (v) => FlLine(
                      color: scheme.outlineVariant.withValues(alpha: 0.4),
                      strokeWidth: 1),
                ),
                borderData: FlBorderData(show: false),
                barGroups: List.generate(weeklyData.length, (i) {
                  return BarChartGroupData(x: i, barRods: [
                    BarChartRodData(
                      toY: weeklyData[i].itemCount.toDouble(),
                      color: scheme.primary,
                      width: 16,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ]);
                }),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _topProductsCard(ColorScheme scheme) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(16),
        border:
            Border.all(color: scheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Sıkça Alınanlar',
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: scheme.onSurface)),
          const SizedBox(height: 8),
          ...topProducts.take(4).map((p) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: scheme.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(Icons.shopping_bag_outlined,
                        color: scheme.primary, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(p['product_name'].toString(),
                        style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: scheme.onSurface),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                  ),
                  Text('${p['count']}x',
                      style: TextStyle(
                          color: scheme.onSurfaceVariant,
                          fontWeight: FontWeight.w600)),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}

/// Kenarlıklı, dairesel ikon butonu (başlıktaki zil).
class _CircleIconButton extends StatelessWidget {
  const _CircleIconButton({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: scheme.outlineVariant),
        ),
        child: Icon(icon, size: 22, color: scheme.onSurface),
      ),
    );
  }
}
