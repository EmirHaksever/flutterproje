import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:fl_chart/fl_chart.dart';

import '../theme/app_theme.dart';
import '../widgets/ui_kit.dart';

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
  double _completionRate = 0.0;
  List<Map<String, dynamic>> _topCategories = [];
  List<Map<String, dynamic>> _monthlyActivity = [];
  List<Map<String, dynamic>> _topProducts = [];

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

      // 5. En Popüler Ürünler
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
      _topProducts = _topProducts.take(5).toList();

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

  // ---------------------------------------------------------------------------
  // UI  (tasarım taslağı: 3 kart + Kategori Dağılımı + Alışveriş Ritmi)
  // ---------------------------------------------------------------------------

  static const List<Color> _palette = [
    AppTheme.brandGreen,
    AppTheme.accentOrange,
    AppTheme.accentBlue,
    AppTheme.accentPurple,
    Color(0xFF14B8A6),
    Color(0xFF9CA3AF),
  ];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(title: const Text('İstatistikler')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _fetchStats,
              child: (_totalItems == 0 && _totalLists == 0)
                  ? _emptyState(scheme)
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
                      children: [
                        _statCardsRow(),
                        const SizedBox(height: 24),
                        if (_topCategories.isNotEmpty) ...[
                          _sectionTitle(scheme, 'Kategori Dağılımı'),
                          const SizedBox(height: 12),
                          _categoryCard(scheme),
                          const SizedBox(height: 20),
                        ],
                        _sectionTitle(scheme, 'Alışveriş Ritmi'),
                        const SizedBox(height: 12),
                        _rhythmCard(scheme),
                        if (_topProducts.isNotEmpty) ...[
                          const SizedBox(height: 20),
                          _sectionTitle(scheme, 'En Çok Alınan Ürünler'),
                          const SizedBox(height: 12),
                          _topProductsCard(scheme),
                        ],
                      ],
                    ),
            ),
    );
  }

  Widget _statCardsRow() {
    return Row(
      children: [
        Expanded(
          child: MiniStatCard(
            value: '%${(_completionRate * 100).round()}',
            label: 'Tamamlama',
            icon: Icons.percent_rounded,
            iconColor: AppTheme.brandGreen,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: MiniStatCard(
            value: '$_totalLists',
            label: 'Liste',
            icon: Icons.checklist_rounded,
            iconColor: AppTheme.accentBlue,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: MiniStatCard(
            value: '$_totalItems',
            label: 'Ürün',
            icon: Icons.shopping_basket_rounded,
            iconColor: AppTheme.accentOrange,
          ),
        ),
      ],
    );
  }

  Widget _sectionTitle(ColorScheme scheme, String text) => Text(
        text,
        style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: scheme.onSurface),
      );

  Widget _cardBox(ColorScheme scheme, {required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: child,
    );
  }

  Widget _categoryCard(ColorScheme scheme) {
    final total =
        _topCategories.fold<int>(0, (s, c) => s + (c['count'] as int));
    return _cardBox(
      scheme,
      child: Row(
        children: [
          SizedBox(
            width: 128,
            height: 128,
            child: PieChart(
              PieChartData(
                sectionsSpace: 2,
                centerSpaceRadius: 34,
                sections: List.generate(_topCategories.length, (i) {
                  final c = _topCategories[i];
                  final value = (c['count'] as int).toDouble();
                  return PieChartSectionData(
                    value: value,
                    color: _palette[i % _palette.length],
                    radius: 26,
                    showTitle: false,
                  );
                }),
              ),
            ),
          ),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: List.generate(_topCategories.length, (i) {
                final c = _topCategories[i];
                final pct = total == 0
                    ? 0
                    : ((c['count'] as int) / total * 100).round();
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                            color: _palette[i % _palette.length],
                            shape: BoxShape.circle),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(c['name'] as String,
                            style: TextStyle(
                                fontSize: 12.5, color: scheme.onSurface),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis),
                      ),
                      Text('%$pct',
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: scheme.onSurfaceVariant)),
                    ],
                  ),
                );
              }),
            ),
          ),
        ],
      ),
    );
  }

  Widget _rhythmCard(ColorScheme scheme) {
    const months = [
      'Oca', 'Şub', 'Mar', 'Nis', 'May', 'Haz',
      'Tem', 'Ağu', 'Eyl', 'Eki', 'Kas', 'Ara'
    ];
    final spots = <FlSpot>[];
    for (var i = 0; i < _monthlyActivity.length; i++) {
      spots.add(FlSpot(
          i.toDouble(), (_monthlyActivity[i]['count'] as int).toDouble()));
    }
    final maxY = spots.isEmpty
        ? 5.0
        : (spots.map((s) => s.y).reduce((a, b) => a > b ? a : b) * 1.25)
            .clamp(4.0, double.infinity);

    return _cardBox(
      scheme,
      child: SizedBox(
        height: 170,
        child: LineChart(
          LineChartData(
            minY: 0,
            maxY: maxY,
            lineTouchData: const LineTouchData(enabled: false),
            gridData: FlGridData(
              show: true,
              drawVerticalLine: false,
              getDrawingHorizontalLine: (v) => FlLine(
                  color: scheme.outlineVariant.withValues(alpha: 0.5),
                  strokeWidth: 1),
            ),
            borderData: FlBorderData(show: false),
            titlesData: FlTitlesData(
              leftTitles: AxisTitles(
                sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 26,
                    getTitlesWidget: (v, m) => Text(v.toInt().toString(),
                        style: TextStyle(
                            fontSize: 10, color: scheme.onSurfaceVariant))),
              ),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  getTitlesWidget: (v, m) {
                    final i = v.toInt();
                    if (i < 0 || i >= _monthlyActivity.length) {
                      return const SizedBox();
                    }
                    final key = _monthlyActivity[i]['month'] as String;
                    final mo = int.tryParse(key.split('-').last) ?? 1;
                    return Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(months[(mo - 1) % 12],
                          style: TextStyle(
                              fontSize: 10,
                              color: scheme.onSurfaceVariant)),
                    );
                  },
                ),
              ),
              topTitles:
                  const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              rightTitles:
                  const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            ),
            lineBarsData: [
              LineChartBarData(
                spots: spots,
                isCurved: true,
                barWidth: 3,
                color: scheme.primary,
                dotData: FlDotData(
                  show: true,
                  getDotPainter: (s, _, __, ___) => FlDotCirclePainter(
                      radius: 3, color: scheme.primary, strokeWidth: 0),
                ),
                belowBarData: BarAreaData(
                  show: true,
                  color: scheme.primary.withValues(alpha: 0.10),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _topProductsCard(ColorScheme scheme) {
    const medals = [
      Color(0xFFF6C445),
      Color(0xFFC0C0C0),
      Color(0xFFCD7F32),
    ];
    final maxCount = _topProducts.isEmpty
        ? 1
        : (_topProducts.first['count'] as int).clamp(1, 1 << 30);

    return _cardBox(
      scheme,
      child: Column(
        children: List.generate(_topProducts.length, (i) {
          final p = _topProducts[i];
          final count = p['count'] as int;
          final color = i < 3 ? medals[i] : scheme.outlineVariant;
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 7),
            child: Row(
              children: [
                Container(
                  width: 24,
                  height: 24,
                  alignment: Alignment.center,
                  decoration:
                      BoxDecoration(color: color, shape: BoxShape.circle),
                  child: Text('${i + 1}',
                      style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: Colors.white)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(p['name'] as String,
                      style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: scheme.onSurface),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                ),
                SizedBox(
                  width: 84,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      value: count / maxCount,
                      minHeight: 6,
                      backgroundColor: AppTheme.heroGreenBg,
                      color: scheme.primary,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Text('$count kez',
                    style: TextStyle(
                        fontSize: 11, color: scheme.onSurfaceVariant)),
              ],
            ),
          );
        }),
      ),
    );
  }

  Widget _emptyState(ColorScheme scheme) {
    return ListView(
      children: [
        SizedBox(height: MediaQuery.of(context).size.height * 0.28),
        Icon(Icons.bar_chart_rounded,
            size: 64, color: scheme.onSurfaceVariant),
        const SizedBox(height: 14),
        Text('Henüz istatistik yok',
            textAlign: TextAlign.center,
            style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: scheme.onSurface)),
        const SizedBox(height: 6),
        Text('Liste oluşturup ürün ekledikçe burası dolacak.',
            textAlign: TextAlign.center,
            style: TextStyle(color: scheme.onSurfaceVariant)),
      ],
    );
  }
}
