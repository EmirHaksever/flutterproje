import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:fl_chart/fl_chart.dart'; // Grafikler için FlChart kütüphanesi
import 'package:intl/intl.dart'; // Tarih formatlama için

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

  // İstatistik kutucuğu için yardımcı widget
  Widget _buildStatCard(String title, String value, IconData icon, Color color) {
    return Expanded(
      child: Card(
        elevation: 5, // Daha belirgin gölge
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)), // Daha yuvarlak köşeler
        margin: const EdgeInsets.all(8.0), // Dış boşluk
        child: Padding(
          padding: const EdgeInsets.all(20.0), // İç boşluk
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 48, color: color), // Daha büyük ikon
              const SizedBox(height: 12),
              Text(
                value,
                style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.black87), // Daha büyük ve koyu
              ),
              const SizedBox(height: 6),
              Text(
                title,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 15, color: Colors.grey.shade600, fontWeight: FontWeight.w500), // Daha okunaklı
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Aylık aktivite grafiği için yardımcı widget
  Widget _buildMonthlyActivityChart() {
    if (_monthlyActivity.isEmpty || _monthlyActivity.every((element) => element['count'] == 0)) {
      return Container(
        height: 250, // Sabit yükseklik
        alignment: Alignment.center,
        child: Text(
          'Aylık aktivite verisi bulunmamaktadır.',
          style: TextStyle(color: Colors.grey.shade600, fontSize: 16),
          textAlign: TextAlign.center,
        ),
      );
    }

    List<String> monthLabels = _monthlyActivity.map((e) {
      final parts = e['month'].split('-');
      final month = int.parse(parts[1]);
      return DateFormat.MMM('tr_TR').format(DateTime(int.parse(parts[0]), month)); // Ay adını al
    }).toList();

    double maxY = _monthlyActivity.map((e) => e['count'] as int).reduce((a, b) => a > b ? a : b).toDouble() * 1.2;
    if (maxY == 0) maxY = 5;

    return AspectRatio(
      aspectRatio: 1.6,
      child: Card(
        elevation: 5,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        margin: const EdgeInsets.all(8.0),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 10),
          child: BarChart(
            BarChartData(
              barTouchData: BarTouchData(
                touchTooltipData: BarTouchTooltipData(
                  getTooltipColor: (group) => widget.customPrimarySwatch.shade700.withOpacity(0.9),
                  getTooltipItem: (group, groupIndex, rod, rodIndex) {
                    return BarTooltipItem(
                      '${monthLabels[groupIndex]} ${rod.toY.toInt()} Ürün',
                      const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    );
                  },
                ),
              ),
              titlesData: FlTitlesData(
                show: true,
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 40,
                    getTitlesWidget: (value, meta) {
                      final index = value.toInt();
                      if (index >= 0 && index < monthLabels.length) {
                        return Padding(
                          padding: const EdgeInsets.only(top: 8.0),
                          child: Text(
                            monthLabels[index],
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.grey.shade600, fontSize: 11),
                          ),
                        );
                      }
                      return const Text('');
                    },
                  ),
                ),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 35,
                    getTitlesWidget: (value, meta) {
                      return Text(
                        value.toInt().toString(),
                        style: TextStyle(color: Colors.grey.shade600, fontSize: 11),
                      );
                    },
                  ),
                ),
                topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              ),
              borderData: FlBorderData(
                show: true,
                border: Border.all(color: Colors.grey.shade200, width: 1),
              ),
              barGroups: _monthlyActivity.asMap().entries.map((entry) {
                int index = entry.key;
                Map<String, dynamic> data = entry.value;
                return BarChartGroupData(
                  x: index,
                  barRods: [
                    BarChartRodData(
                      toY: (data['count'] as int).toDouble(),
                      color: widget.customPrimarySwatch.shade600, // Daha koyu ton
                      width: 20, // Daha geniş çubuklar
                      borderRadius: BorderRadius.circular(6), // Daha yuvarlak
                      backDrawRodData: BackgroundBarChartRodData(
                        show: true,
                        toY: maxY,
                        color: Colors.grey.shade100,
                      ),
                    ),
                  ],
                );
              }).toList(),
              gridData: FlGridData(
                show: true,
                drawVerticalLine: false,
                getDrawingHorizontalLine: (value) => FlLine(
                  color: Colors.grey.shade100,
                  strokeWidth: 1,
                ),
              ),
              maxY: maxY,
            ),
          ),
        ),
      ),
    );
  }

  // Kategori pasta grafiği için yardımcı widget
  Widget _buildCategoryPieChart() {
    if (_topCategories.isEmpty || _topCategories.every((element) => element['count'] == 0)) {
      return Container(
        height: 250, // Sabit yükseklik
        alignment: Alignment.center,
        child: Text(
          'Kategori verisi bulunmamaktadır.',
          style: TextStyle(color: Colors.grey.shade600, fontSize: 16),
          textAlign: TextAlign.center,
        ),
      );
    }

    List<PieChartSectionData> sections = [];
    double total = _topCategories.fold(0, (sum, item) => sum + (item['count'] as int));
    List<Color> pieColors = [
      widget.customPrimarySwatch.shade800,
      widget.customPrimarySwatch.shade600,
      widget.customPrimarySwatch.shade400,
      widget.customPrimarySwatch.shade200,
      Colors.grey.shade300,
    ];

    for (int i = 0; i < _topCategories.length; i++) {
      final category = _topCategories[i];
      final value = (category['count'] as int).toDouble();
      final percentage = (value / total * 100).toStringAsFixed(1);
      sections.add(
        PieChartSectionData(
          color: pieColors[i % pieColors.length],
          value: value,
          title: '${category['name']}\n%${percentage}',
          radius: 80, // Dilim yarıçapı
          titleStyle: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
          titlePositionPercentageOffset: 0.55,
        ),
      );
    }

    return AspectRatio(
      aspectRatio: 1.3,
      child: Card(
        elevation: 5,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        margin: const EdgeInsets.all(8.0),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: PieChart(
            PieChartData(
              sections: sections,
              borderData: FlBorderData(show: false),
              sectionsSpace: 2, // Dilimler arası boşluk
              centerSpaceRadius: 40, // Ortadaki boşluk
            ),
          ),
        ),
      ),
    );
  }

  // Yeni: Ürün aktivitesi çizgi grafiği için yardımcı widget
  Widget _buildProductActivityLineChart() {
    if (_productActivityData.isEmpty || _productActivityData.values.every((list) => list.every((spot) => spot.y == 0))) {
      return Container(
        height: 250,
        alignment: Alignment.center,
        child: Text(
          'Ürün aktivitesi verisi bulunmamaktadır.',
          style: TextStyle(color: Colors.grey.shade600, fontSize: 16),
          textAlign: TextAlign.center,
        ),
      );
    }

    List<String> monthLabels = [];
    DateTime now = DateTime.now();
    for (int i = 5; i >= 0; i--) {
      DateTime month = DateTime(now.year, now.month - i, 1);
      monthLabels.add(DateFormat.MMM('tr_TR').format(month));
    }

    double maxY = 0;
    _productActivityData.values.forEach((list) {
      list.forEach((spot) {
        if (spot.y > maxY) maxY = spot.y;
      });
    });
    maxY = maxY * 1.2; // Biraz boşluk bırak

    List<LineChartBarData> lines = [];
    List<Color> lineColors = [
      Colors.blue.shade400,
      Colors.green.shade400,
      Colors.orange.shade400,
      Colors.purple.shade400,
      Colors.red.shade400,
    ];

    int colorIndex = 0;
    _productActivityData.forEach((productName, spots) {
      lines.add(
        LineChartBarData(
          spots: spots,
          isCurved: true,
          color: lineColors[colorIndex % lineColors.length],
          barWidth: 3,
          isStrokeCapRound: true,
          dotData: const FlDotData(show: false), // Noktaları gizle
          belowBarData: BarAreaData(
            show: true,
            color: lineColors[colorIndex % lineColors.length].withOpacity(0.3),
          ),
        ),
      );
      colorIndex++;
    });

    return AspectRatio(
      aspectRatio: 1.6,
      child: Card(
        elevation: 5,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        margin: const EdgeInsets.all(8.0),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 10),
          child: LineChart(
            LineChartData(
              lineTouchData: LineTouchData(
                touchTooltipData: LineTouchTooltipData(
                  getTooltipColor: (touchedSpot) => Colors.blueGrey,
                  getTooltipItems: (touchedSpots) {
                    return touchedSpots.map((touchedSpot) {
                      final productName = _productActivityData.keys.elementAt(touchedSpot.barIndex);
                      return LineTooltipItem(
                        '$productName\n${monthLabels[touchedSpot.x.toInt()]}: ${touchedSpot.y.toInt()} Ürün',
                        const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                      );
                    }).toList();
                  },
                ),
              ),
              gridData: FlGridData(
                show: true,
                drawVerticalLine: false,
                getDrawingHorizontalLine: (value) => FlLine(
                  color: Colors.grey.shade100,
                  strokeWidth: 1,
                ),
              ),
              titlesData: FlTitlesData(
                show: true,
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 40,
                    getTitlesWidget: (value, meta) {
                      final index = value.toInt();
                      if (index >= 0 && index < monthLabels.length) {
                        return Padding(
                          padding: const EdgeInsets.only(top: 8.0),
                          child: Text(
                            monthLabels[index],
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.grey.shade600, fontSize: 11),
                          ),
                        );
                      }
                      return const Text('');
                    },
                  ),
                ),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 35,
                    getTitlesWidget: (value, meta) {
                      return Text(
                        value.toInt().toString(),
                        style: TextStyle(color: Colors.grey.shade600, fontSize: 11),
                      );
                    },
                  ),
                ),
                topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              ),
              borderData: FlBorderData(
                show: true,
                border: Border.all(color: Colors.grey.shade200, width: 1),
              ),
              lineBarsData: lines,
              maxY: maxY,
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final MaterialColor primaryColor = widget.customPrimarySwatch;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Alışveriş İstatistikleri', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        backgroundColor: primaryColor,
        iconTheme: const IconThemeData(color: Colors.white),
        elevation: 0,
        centerTitle: true,
      ),
      backgroundColor: Colors.grey[50], // Daha açık arka plan
      body: _isLoading
          ? Center(child: CircularProgressIndicator(color: primaryColor))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Genel İstatistikler Başlığı
                  Text(
                    'Genel Bakış',
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey.shade800,
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Genel İstatistik Kartları (İlk Satır)
                  Row(
                    children: [
                      _buildStatCard(
                        'Toplam Liste',
                        _totalLists.toString(),
                        Icons.library_books_rounded,
                        primaryColor.shade700,
                      ),
                      _buildStatCard(
                        'Toplam Ürün',
                        _totalItems.toString(),
                        Icons.shopping_basket_rounded,
                        primaryColor.shade500,
                      ),
                    ],
                  ),
                  // Genel İstatistik Kartları (İkinci Satır)
                  Row(
                    children: [
                      _buildStatCard(
                        'Tamamlandı',
                        _completedItems.toString(),
                        Icons.check_circle_rounded,
                        Colors.green.shade600,
                      ),
                      _buildStatCard(
                        'Tamamlanmadı',
                        _uncompletedItems.toString(),
                        Icons.cancel_rounded,
                        Colors.red.shade600,
                      ),
                    ],
                  ),
                  // Genel İstatistik Kartları (Üçüncü Satır)
                  Row(
                    children: [
                      _buildStatCard(
                        'Ort. Ürün/Liste',
                        _avgItemsPerList.toStringAsFixed(1),
                        Icons.format_list_numbered_rounded,
                        primaryColor.shade400,
                      ),
                      _buildStatCard(
                        'En Aktif Gün',
                        _mostActiveDay,
                        Icons.calendar_today_rounded,
                        primaryColor.shade600,
                      ),
                    ],
                  ),
                  const SizedBox(height: 30),

                  // Tamamlama Oranı (LinearProgressIndicator)
                  Text(
                    'Genel Tamamlama Oranı: ${(_completionRate * 100).toStringAsFixed(1)}%',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey.shade800,
                    ),
                  ),
                  const SizedBox(height: 12),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: LinearProgressIndicator(
                      value: _completionRate,
                      backgroundColor: Colors.grey[300],
                      color: primaryColor.shade700,
                      minHeight: 20,
                    ),
                  ),
                  const SizedBox(height: 40),

                  // Aylık Aktivite Başlığı ve Grafiği
                  Text(
                    'Aylık Ürün Aktivitesi',
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey.shade800,
                    ),
                  ),
                  const SizedBox(height: 15),
                  _buildMonthlyActivityChart(),
                  const SizedBox(height: 40),

                  // En Popüler Kategoriler Başlığı ve Pasta Grafiği
                  Text(
                    'Kategori Dağılımı',
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey.shade800,
                    ),
                  ),
                  const SizedBox(height: 15),
                  _buildCategoryPieChart(),
                  const SizedBox(height: 40),

                  // En Popüler Kategoriler Listesi
                  Text(
                    'En Popüler Kategoriler',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey.shade800,
                    ),
                  ),
                  const SizedBox(height: 15),
                  _topCategories.isEmpty
                      ? Center(
                          child: Text(
                            'Henüz popüler kategori verisi bulunmamaktadır.',
                            style: TextStyle(color: Colors.grey.shade600, fontSize: 16),
                            textAlign: TextAlign.center,
                          ),
                        )
                      : ListView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: _topCategories.length,
                          itemBuilder: (context, index) {
                            final category = _topCategories[index];
                            return Card(
                              margin: const EdgeInsets.symmetric(vertical: 8),
                              elevation: 3,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              child: ListTile(
                                leading: Icon(Icons.category_rounded, color: primaryColor.shade600, size: 28),
                                title: Text(
                                  category['name'] ?? 'Bilinmiyor',
                                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                                ),
                                trailing: Text(
                                  '${category['count']} Ürün',
                                  style: TextStyle(fontSize: 15, color: Colors.grey.shade700, fontWeight: FontWeight.bold),
                                ),
                              ),
                            );
                          },
                        ),
                  const SizedBox(height: 40),

                  // Yeni: En Popüler Ürünler Başlığı ve Listesi
                  Text(
                    'En Popüler Ürünler',
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey.shade800,
                    ),
                  ),
                  const SizedBox(height: 15),
                  _topProducts.isEmpty
                      ? Center(
                          child: Text(
                            'Henüz popüler ürün verisi bulunmamaktadır.',
                            style: TextStyle(color: Colors.grey.shade600, fontSize: 16),
                            textAlign: TextAlign.center,
                          ),
                        )
                      : ListView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: _topProducts.length,
                          itemBuilder: (context, index) {
                            final product = _topProducts[index];
                            return Card(
                              margin: const EdgeInsets.symmetric(vertical: 8),
                              elevation: 3,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              child: ListTile(
                                leading: Icon(Icons.shopping_bag_rounded, color: primaryColor.shade600, size: 28),
                                title: Text(
                                  product['name'] ?? 'Bilinmiyor',
                                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                                ),
                                trailing: Text(
                                  '${product['count']} Kez Alındı',
                                  style: TextStyle(fontSize: 15, color: Colors.grey.shade700, fontWeight: FontWeight.bold),
                                ),
                              ),
                            );
                          },
                        ),
                  const SizedBox(height: 40),

                  // Yeni: Ürün Aktivitesi Zaman Çizelgesi Başlığı ve Grafiği
                  Text(
                    'Ürün Aktivitesi Zaman Çizelgesi',
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey.shade800,
                    ),
                  ),
                  const SizedBox(height: 15),
                  _buildProductActivityLineChart(),
                  const SizedBox(height: 40),

                  // En Çok Alışveriş Yapılan Mağaza Kartı
                  Text(
                    'Mağaza Analizi',
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey.shade800,
                    ),
                  ),
                  const SizedBox(height: 15),
                  Card(
                    elevation: 5,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                    margin: const EdgeInsets.all(8.0),
                    child: Padding(
                      padding: const EdgeInsets.all(20.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.store_mall_directory_rounded, size: 48, color: primaryColor.shade700),
                              const SizedBox(width: 15),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'En Çok Alışveriş Yapılan Mağaza:',
                                    style: TextStyle(fontSize: 16, color: Colors.grey.shade600),
                                  ),
                                  const SizedBox(height: 5),
                                  Text(
                                    _mostFrequentMarket,
                                    style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.black87),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            ),
    );
  }
}
