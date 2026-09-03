import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../theme/app_theme.dart';
import '../widgets/ui_kit.dart';
import 'create_list.dart';

class CategoryDetailPage extends StatefulWidget {
  final String categoryName;
  final MaterialColor customPrimarySwatch;

  const CategoryDetailPage({
    super.key,
    required this.categoryName,
    required this.customPrimarySwatch,
  });

  @override
  State<CategoryDetailPage> createState() => _CategoryDetailPageState();
}

class _CategoryDetailPageState extends State<CategoryDetailPage> {
  final supabase = Supabase.instance.client;
  List<Map<String, dynamic>> _items = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    setState(() => _isLoading = true);
    try {
      final response = await supabase
          .from('list_items')
          .select('*')
          .eq('category', widget.categoryName);
      if (mounted) {
        setState(() {
          _items = List<Map<String, dynamic>>.from(response as List);
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Kategori detayları çekilemedi: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  int get _completed =>
      _items.where((i) => i['is_completed'] == true).length;

  int get _thisMonth {
    final now = DateTime.now();
    return _items.where((i) {
      final d = DateTime.tryParse(i['created_at']?.toString() ?? '');
      return d != null && d.year == now.year && d.month == now.month;
    }).length;
  }

  String get _lastPurchase {
    DateTime? latest;
    for (final i in _items) {
      final d = DateTime.tryParse(i['created_at']?.toString() ?? '');
      if (d != null && (latest == null || d.isAfter(latest))) latest = d;
    }
    if (latest == null) return '—';
    final diff = DateTime.now().difference(latest).inDays;
    if (diff <= 0) return 'bugün';
    if (diff == 1) return 'dün';
    return '$diff gün önce';
  }

  /// Ürün adına göre {count, imageUrl} — en çok alınanlar.
  List<({String name, int count, String? image})> get _topProducts {
    final map = <String, ({int count, String? image})>{};
    for (final i in _items) {
      final name = (i['product_name'] ?? '') as String;
      if (name.isEmpty) continue;
      final prev = map[name];
      map[name] = (
        count: (prev?.count ?? 0) + 1,
        image: prev?.image ?? i['image_url'] as String?,
      );
    }
    final list = map.entries
        .map((e) => (name: e.key, count: e.value.count, image: e.value.image))
        .toList()
      ..sort((a, b) => b.count.compareTo(a.count));
    return list.take(6).toList();
  }

  void _startShopping() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CreateListPage(
          initialFilterCategory: widget.categoryName,
          availableCategories: [
            {'name': widget.categoryName}
          ],
          customPrimarySwatch: widget.customPrimarySwatch,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final emoji = categoryEmoji(widget.categoryName);
    final top = _topProducts;
    final maxCount = top.isEmpty ? 1 : top.first.count;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(title: Text('$emoji  ${widget.categoryName}')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _items.isEmpty
          ? EmptyState(
              icon: Icons.history_rounded,
              title: 'Bu kategoride geçmiş yok',
              message: '$emoji ${widget.categoryName} kategorisinde bir şey '
                  'aldıkça istatistikler ve en çok alınanlar burada dolar.',
              actionLabel: 'Alışverişe Başla',
              onAction: _startShopping,
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 30),
              children: [
                Text('Bu kategorideki alışveriş geçmişin',
                    style: TextStyle(color: scheme.onSurfaceVariant)),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: MiniStatCard(
                        value: '${_items.length}',
                        label: 'Toplam',
                        icon: Icons.inventory_2_rounded,
                        iconColor: AppTheme.accentBlue,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: MiniStatCard(
                        value: '$_completed',
                        label: 'Tamamlanan',
                        icon: Icons.check_circle_rounded,
                        iconColor: AppTheme.brandGreen,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: MiniStatCard(
                        value: '$_thisMonth',
                        label: 'Bu Ay',
                        icon: Icons.calendar_month_rounded,
                        iconColor: AppTheme.accentOrange,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Icon(Icons.schedule,
                        size: 15, color: scheme.onSurfaceVariant),
                    const SizedBox(width: 6),
                    Text('Son alışveriş: $_lastPurchase',
                        style: TextStyle(
                            fontSize: 12, color: scheme.onSurfaceVariant)),
                  ],
                ),
                const SizedBox(height: 24),
                Text('En Çok Alınan Ürünler',
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: scheme.onSurface)),
                const SizedBox(height: 12),
                if (top.isEmpty)
                  Text('Bu kategoride henüz ürün yok.',
                      style: TextStyle(color: scheme.onSurfaceVariant))
                else
                  ...top.map((p) => _productRow(scheme, p, maxCount)),
                const SizedBox(height: 24),
                SizedBox(
                  height: 52,
                  child: FilledButton.icon(
                    onPressed: _startShopping,
                    icon: const Icon(Icons.shopping_cart_outlined),
                    label: const Text('Alışverişe Başla'),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _productRow(ColorScheme scheme,
      ({String name, int count, String? image}) p, int maxCount) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          ProductThumb(
            imageUrl: p.image,
            emoji: categoryEmoji(widget.categoryName),
            size: 38,
            radius: 10,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(p.name,
                style: TextStyle(
                    fontWeight: FontWeight.w600, color: scheme.onSurface),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
          ),
          SizedBox(
            width: 80,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: p.count / maxCount,
                minHeight: 6,
                backgroundColor: scheme.primary.withValues(alpha: 0.12),
                color: scheme.primary,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Text('${p.count} kez',
              style: TextStyle(
                  fontSize: 11, color: scheme.onSurfaceVariant)),
        ],
      ),
    );
  }
}
