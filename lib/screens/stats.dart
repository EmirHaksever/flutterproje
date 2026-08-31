import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:fl_chart/fl_chart.dart'; // Grafikler için FlChart kütüphanesi

class StatsPage extends StatefulWidget {
  final MaterialColor customPrimarySwatch;

  const StatsPage({super.key, required this.customPrimarySwatch});

  @override
  State<StatsPage> createState() => _StatsPageState();
}

class _StatsPageState extends State<StatsPage> {
  final supabase = Supabase.instance.client;
  bool _isLoading = true;
  int _totalLists = 0;
  int _totalItems = 0;
  int _completedItems = 0;
  int _uncompletedItems = 0;
  double _completionRate = 0.0;
  List<Map<String, dynamic>> _topCategories = [];
  List<Map<String, dynamic>> _monthlyActivity = [];
  String _mostFrequentMarket = 'N/A';
  double _avgItemsPerList = 0.0;
  String _mostActiveDay = 'N/A';
  List<Map<String, dynamic>> _topProducts = []; // Yeni: En popüler ürünler
  Map<String, List<FlSpot>> _productActivityData = {}; // Yeni: Ürün aktivitesi çizgi grafik verisi

  @override
  void initState() {
    super.initState();
    _fetchStats();
  }

  Future<void> _fetchStats() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final userId = supabase.auth.currentUser?.id;
      if (userId == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('İstatistikleri görmek için giriş yapmalısınız.')),
          );
        }
        setState(() {
          _isLoading = false;
        });
        return;
      }

      // 1. Toplam liste sayısı
      final listsResponse = await supabase
          .from('shopping_lists')
          .select('id, created_at')
          .eq('user_id', userId)
          .count(CountOption.exact);
      _totalLists = listsResponse.count;

      // 2. Tüm ürünleri çek (tamamlanan ve tamamlanmayan)
      final itemsResponse = await supabase
          .from('list_items')
          .select('is_completed, category, created_at, market, product_name, list_id'); // product_name'i de çek

      _totalItems = itemsResponse.length;
      _completedItems = itemsResponse.where((item) => item['is_completed'] == true).length;
      _uncompletedItems = _totalItems - _completedItems;
      _completionRate = _totalItems > 0 ? _completedItems / _totalItems : 0.0;

      // 3. En popüler kategorileri bul
      final Map<String, int> categoryCounts = {};
      for (var item in itemsResponse) {
        final category = item['category'] as String?;
        if (category != null && category.isNotEmpty) {
          categoryCounts[category] = (categoryCounts[category] ?? 0) + 1;
        }
      }
      _topCategories = categoryCounts.entries.map((e) => {
        'name': e.key,
        'count': e.value,
      }).toList();
      _topCategories.sort((a, b) => (b['count'] as int).compareTo(a['count'] as int));
      _topCategories = _topCategories.take(5).toList();

      // 4. Aylık aktivite verisini hazırla
      final Map<String, int> monthlyCounts = {};
      for (var item in itemsResponse) {
        final createdAt = DateTime.parse(item['created_at']);
        final monthKey = '${createdAt.year}-${createdAt.month.toString().padLeft(2, '0')}';
        monthlyCounts[monthKey] = (monthlyCounts[monthKey] ?? 0) + 1;
      }

      List<Map<String, dynamic>> tempMonthlyActivity = [];
      DateTime now = DateTime.now();
      for (int i = 0; i < 6; i++) {
        DateTime month = DateTime(now.year, now.month - i, 1);
        final monthKey = '${month.year}-${month.month.toString().padLeft(2, '0')}';
        tempMonthlyActivity.add({
          'month': monthKey,
          'count': monthlyCounts[monthKey] ?? 0,
        });
      }
      _monthlyActivity = tempMonthlyActivity.reversed.toList();

      // 5. En çok alışveriş yapılan mağaza
      final Map<String, int> marketCounts = {};
      for (var item in itemsResponse) {
        final market = item['market'] as String?;
        if (market != null && market.isNotEmpty) {
          marketCounts[market] = (marketCounts[market] ?? 0) + 1;
        }
      }
      if (marketCounts.isNotEmpty) {
        _mostFrequentMarket = marketCounts.entries.reduce((a, b) => a.value > b.value ? a : b).key;
      } else {
        _mostFrequentMarket = 'N/A';
      }

      // 6. Ortalama Liste Başına Ürün
      if (_totalLists > 0) {
        _avgItemsPerList = _totalItems / _totalLists;
      } else {
        _avgItemsPerList = 0.0;
      }

      // 7. En Aktif Gün
      final Map<int, int> dayOfWeekCounts = {1: 0, 2: 0, 3: 0, 4: 0, 5: 0, 6: 0, 7: 0};
      for (var item in itemsResponse) {
        final createdAt = DateTime.parse(item['created_at']);
        dayOfWeekCounts[createdAt.weekday] = (dayOfWeekCounts[createdAt.weekday] ?? 0) + 1;
      }
      if (dayOfWeekCounts.values.any((count) => count > 0)) {
        final mostActiveWeekday = dayOfWeekCounts.entries.reduce((a, b) => a.value > b.value ? a : b).key;
        _mostActiveDay = _getDayName(mostActiveWeekday);
      } else {
        _mostActiveDay = 'N/A';
      }

      // 8. En Popüler Ürünler
      final Map<String, int> productCounts = {};
      for (var item in itemsResponse) {
        final productName = item['product_name'] as String?;
        if (productName != null && productName.isNotEmpty) {
          productCounts[productName] = (productCounts[productName] ?? 0) + 1;
        }
      }
      _topProducts = productCounts.entries.map((e) => {
        'name': e.key,
        'count': e.value,
      }).toList();
      _topProducts.sort((a, b) => (b['count'] as int).compareTo(a['count'] as int));
      _topProducts = _topProducts.take(5).toList(); // İlk 5 ürünü al

      // 9. Ürün Aktivitesi Zaman Çizelgesi Verisi
      _productActivityData = _calculateProductActivityOverTime(itemsResponse);

      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('İstatistikler çekilirken hata oluştu: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('İstatistikler yüklenirken bir hata oluştu: $e')),
        );
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  // Ürün aktivitesi zaman çizelgesi verisini hesaplayan yardımcı fonksiyon
  Map<String, List<FlSpot>> _calculateProductActivityOverTime(List<Map<String, dynamic>> items) {
    Map<String, Map<String, int>> productMonthlyCounts = {}; // {productName: {monthKey: count}}

    for (var item in items) {
      final productName = item['product_name'] as String?;
      final createdAt = DateTime.parse(item['created_at']);
      final monthKey = '${createdAt.year}-${createdAt.month.toString().padLeft(2, '0')}';

      if (productName != null && productName.isNotEmpty) {
        productMonthlyCounts.putIfAbsent(productName, () => {});
        productMonthlyCounts[productName]![monthKey] = (productMonthlyCounts[productName]![monthKey] ?? 0) + 1;
      }
    }

    Map<String, List<FlSpot>> activityData = {};
    DateTime now = DateTime.now();
    List<String> lastSixMonthsKeys = [];
    for (int i = 5; i >= 0; i--) { // Son 6 ay (mevcut ay dahil)
      DateTime month = DateTime(now.year, now.month - i, 1);
      lastSixMonthsKeys.add('${month.year}-${month.month.toString().padLeft(2, '0')}');
    }

    // Sadece en popüler 3 ürün için veri oluştur
    final top3Products = _topProducts.take(3).map((e) => e['name'] as String).toList();

    for (var productName in top3Products) {
      List<FlSpot> spots = [];
      for (int i = 0; i < lastSixMonthsKeys.length; i++) {
        final monthKey = lastSixMonthsKeys[i];
        final count = productMonthlyCounts[productName]?[monthKey] ?? 0;
        spots.add(FlSpot(i.toDouble(), count.toDouble()));
      }
      activityData[productName] = spots;
    }
    return activityData;
  }

  String _getDayName(int weekday) {
    switch (weekday) {
      case 1: return 'Pazartesi';
      case 2: return 'Salı';
      case 3: return 'Çarşamba';
      case 4: return 'Perşembe';
      case 5: return 'Cuma';
      case 6: return 'Cumartesi';
      case 7: return 'Pazar';
      default: return 'Bilinmiyor';
    }
  }


  // ---------------------------------------------------------------------------
  // UI
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('İstatistikler',
            style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _fetchStats,
              child: (_totalItems == 0 && _totalLists == 0)
                  ? _emptyState(scheme)
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                      children: [
                        _completionHero(scheme),
                        const SizedBox(height: 16),
                        _kpiGrid(scheme),
                        const SizedBox(height: 24),
                        if (_topCategories.isNotEmpty) ...[
                          _sectionTitle(scheme, 'Kategori Dağılımı'),
                          _categoryCard(scheme),
                          const SizedBox(height: 24),
                        ],
                        _sectionTitle(scheme, 'Aylık Aktivite'),
                        _monthlyCard(scheme),
                        const SizedBox(height: 24),
                        if (_topProducts.isNotEmpty) ...[
                          _sectionTitle(scheme, 'En Çok Alınan Ürünler'),
                          _topProductsCard(scheme),
                          const SizedBox(height: 24),
                        ],
                        if (_productActivityData.isNotEmpty) ...[
                          _sectionTitle(scheme, 'Ürün Trendi (Son 6 Ay)'),
                          _productTrendCard(scheme),
                        ],
                      ],
                    ),
            ),
    );
  }

  Widget _emptyState(ColorScheme scheme) {
    return ListView(
      children: [
        SizedBox(height: MediaQuery.of(context).size.height * 0.25),
        Icon(Icons.insights_rounded, size: 72, color: scheme.primary),
        const SizedBox(height: 16),
        Center(
          child: Text('Henüz istatistik yok',
              style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: scheme.onSurface)),
        ),
        const SizedBox(height: 8),
        Center(
          child: Text('Liste ve ürün ekledikçe burası dolacak.',
              style: TextStyle(color: scheme.onSurfaceVariant)),
        ),
      ],
    );
  }

  Widget _sectionTitle(ColorScheme scheme, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10, left: 2),
      child: Text(text,
          style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: scheme.onSurface)),
    );
  }

  Widget _cardBox(ColorScheme scheme, Widget child, {EdgeInsets? padding}) {
    return Container(
      padding: padding ?? const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(18),
        border:
            Border.all(color: scheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: child,
    );
  }

  // --- Completion hero ---

  Widget _completionHero(ColorScheme scheme) {
    final pct = (_completionRate * 100).round();
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [scheme.primary, Color.lerp(scheme.primary, Colors.black, 0.3)!],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 88,
            height: 88,
            child: Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  width: 88,
                  height: 88,
                  child: CircularProgressIndicator(
                    value: _completionRate,
                    strokeWidth: 8,
                    backgroundColor: Colors.white.withValues(alpha: 0.25),
                    valueColor:
                        const AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                ),
                Text('%$pct',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold)),
              ],
            ),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Tamamlanma',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text('$_completedItems / $_totalItems ürün alındı',
                    style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.9),
                        fontSize: 13)),
                const SizedBox(height: 2),
                Text('$_uncompletedItems ürün bekliyor',
                    style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.9),
                        fontSize: 13)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // --- KPI grid ---

  Widget _kpiGrid(ColorScheme scheme) {
    final tiles = [
      _KpiData(Icons.receipt_long_rounded, '$_totalLists', 'Toplam Liste'),
      _KpiData(Icons.shopping_bag_rounded, '$_totalItems', 'Toplam Ürün'),
      _KpiData(Icons.calculate_rounded,
          _avgItemsPerList.toStringAsFixed(1), 'Ürün / Liste'),
      _KpiData(Icons.event_available_rounded, _mostActiveDay, 'En Aktif Gün'),
      _KpiData(Icons.storefront_rounded, _mostFrequentMarket, 'Favori Mağaza'),
    ];
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: 1.7,
      children: tiles
          .map((t) => _cardBox(
                scheme,
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(t.icon, color: scheme.primary, size: 22),
                    const SizedBox(height: 6),
                    Text(t.value,
                        style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: scheme.onSurface),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                    Text(t.label,
                        style: TextStyle(
                            fontSize: 11, color: scheme.onSurfaceVariant)),
                  ],
                ),
                padding: const EdgeInsets.all(14),
              ))
          .toList(),
    );
  }

  // --- Category pie ---

  Widget _categoryCard(ColorScheme scheme) {
    final palette = [
      scheme.primary,
      scheme.tertiary,
      scheme.secondary,
      Colors.orange.shade400,
      Colors.purple.shade300,
    ];
    final total = _topCategories.fold<int>(
        0, (a, c) => a + (c['count'] as int));

    return _cardBox(
      scheme,
      Column(
        children: [
          SizedBox(
            height: 170,
            child: PieChart(
              PieChartData(
                sectionsSpace: 2,
                centerSpaceRadius: 44,
                sections: List.generate(_topCategories.length, (i) {
                  final c = _topCategories[i];
                  final value = (c['count'] as int).toDouble();
                  return PieChartSectionData(
                    value: value,
                    color: palette[i % palette.length],
                    title: total == 0
                        ? ''
                        : '${((value / total) * 100).round()}%',
                    titleStyle: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.bold),
                    radius: 46,
                  );
                }),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 14,
            runSpacing: 8,
            children: List.generate(_topCategories.length, (i) {
              final c = _topCategories[i];
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                        color: palette[i % palette.length],
                        shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 6),
                  Text('${c['name']} (${c['count']})',
                      style: TextStyle(
                          fontSize: 12, color: scheme.onSurfaceVariant)),
                ],
              );
            }),
          ),
        ],
      ),
    );
  }

  // --- Monthly bar chart ---

  Widget _monthlyCard(ColorScheme scheme) {
    final maxCount = _monthlyActivity
        .map((e) => e['count'] as int)
        .fold<int>(0, (a, b) => a > b ? a : b);
    final maxY = (maxCount == 0 ? 5 : maxCount * 1.25).toDouble();

    String label(String key) {
      final parts = key.split('-');
      const months = [
        'Oca', 'Şub', 'Mar', 'Nis', 'May', 'Haz',
        'Tem', 'Ağu', 'Eyl', 'Eki', 'Kas', 'Ara'
      ];
      final m = int.tryParse(parts.length > 1 ? parts[1] : '1') ?? 1;
      return months[(m - 1).clamp(0, 11)];
    }

    return _cardBox(
      scheme,
      SizedBox(
        height: 180,
        child: BarChart(
          BarChartData(
            alignment: BarChartAlignment.spaceAround,
            maxY: maxY,
            barTouchData: BarTouchData(enabled: false),
            titlesData: FlTitlesData(
              leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 26,
                      getTitlesWidget: (v, m) => Text(v.toInt().toString(),
                          style: TextStyle(
                              color: scheme.onSurfaceVariant, fontSize: 10)))),
              bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                      showTitles: true,
                      getTitlesWidget: (v, m) {
                        final i = v.toInt();
                        if (i < 0 || i >= _monthlyActivity.length) {
                          return const SizedBox();
                        }
                        return Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                              label(_monthlyActivity[i]['month'] as String),
                              style: TextStyle(
                                  color: scheme.onSurfaceVariant,
                                  fontSize: 10)),
                        );
                      })),
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
                    strokeWidth: 1)),
            borderData: FlBorderData(show: false),
            barGroups: List.generate(_monthlyActivity.length, (i) {
              return BarChartGroupData(x: i, barRods: [
                BarChartRodData(
                  toY: (_monthlyActivity[i]['count'] as int).toDouble(),
                  color: scheme.primary,
                  width: 18,
                  borderRadius: BorderRadius.circular(4),
                )
              ]);
            }),
          ),
        ),
      ),
    );
  }

  // --- Top products ranked list ---

  Widget _topProductsCard(ColorScheme scheme) {
    return _cardBox(
      scheme,
      Column(
        children: List.generate(_topProducts.length, (i) {
          final p = _topProducts[i];
          final medalColors = [
            const Color(0xFFFFD700),
            const Color(0xFFC0C0C0),
            const Color(0xFFCD7F32),
          ];
          final badgeColor =
              i < 3 ? medalColors[i] : scheme.surfaceContainerHighest;
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                Container(
                  width: 30,
                  height: 30,
                  alignment: Alignment.center,
                  decoration:
                      BoxDecoration(color: badgeColor, shape: BoxShape.circle),
                  child: Text('${i + 1}',
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                          color: i < 3 ? Colors.black87 : scheme.onSurface)),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(p['name'].toString(),
                      style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: scheme.onSurface),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                ),
                Text('${p['count']} kez',
                    style: TextStyle(
                        color: scheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600)),
              ],
            ),
          );
        }),
      ),
    );
  }

  // --- Product trend line chart ---

  Widget _productTrendCard(ColorScheme scheme) {
    final palette = [scheme.primary, scheme.tertiary, Colors.orange.shade400];
    final entries = _productActivityData.entries.toList();
    double maxY = 3;
    for (final e in entries) {
      for (final s in e.value) {
        if (s.y > maxY) maxY = s.y;
      }
    }

    return _cardBox(
      scheme,
      Column(
        children: [
          SizedBox(
            height: 170,
            child: LineChart(
              LineChartData(
                minY: 0,
                maxY: maxY * 1.2,
                titlesData: FlTitlesData(
                  leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: 24,
                          getTitlesWidget: (v, m) => Text(v.toInt().toString(),
                              style: TextStyle(
                                  color: scheme.onSurfaceVariant,
                                  fontSize: 10)))),
                  bottomTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
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
                        strokeWidth: 1)),
                borderData: FlBorderData(show: false),
                lineBarsData: List.generate(entries.length, (i) {
                  return LineChartBarData(
                    spots: entries[i].value,
                    isCurved: true,
                    color: palette[i % palette.length],
                    barWidth: 3,
                    dotData: const FlDotData(show: false),
                  );
                }),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 14,
            runSpacing: 8,
            children: List.generate(entries.length, (i) {
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                          color: palette[i % palette.length],
                          shape: BoxShape.circle)),
                  const SizedBox(width: 6),
                  Text(entries[i].key,
                      style: TextStyle(
                          fontSize: 12, color: scheme.onSurfaceVariant)),
                ],
              );
            }),
          ),
        ],
      ),
    );
  }
}

class _KpiData {
  final IconData icon;
  final String value;
  final String label;
  _KpiData(this.icon, this.value, this.label);
}
