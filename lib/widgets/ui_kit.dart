import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Tasarım taslağındaki tekrar eden yapı taşları. Tek yerde tutuyoruz ki
/// tüm ekranlarda birebir aynı görünsünler.

/// "%65" yazan dairesel ilerleme rozeti.
class PercentRing extends StatelessWidget {
  const PercentRing({
    super.key,
    required this.value,
    this.size = 54,
    this.stroke = 4,
  });

  /// 0.0 – 1.0 arası tamamlanma oranı.
  final double value;
  final double size;
  final double stroke;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final pct = (value.clamp(0.0, 1.0) * 100).round();
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox(
            width: size,
            height: size,
            child: CircularProgressIndicator(
              value: value.clamp(0.0, 1.0),
              strokeWidth: stroke,
              strokeCap: StrokeCap.round,
              backgroundColor: AppTheme.heroGreenBg,
              valueColor: AlwaysStoppedAnimation(scheme.primary),
            ),
          ),
          Text(
            '%$pct',
            style: TextStyle(
              fontSize: size * 0.2 + 1,
              fontWeight: FontWeight.w800,
              color: scheme.onSurface,
            ),
          ),
        ],
      ),
    );
  }
}

/// Kenarlıklı beyaz kutu: büyük sayı + küçük etiket.
/// Row içinde `Expanded` ile kullanılır.
class MiniStatCard extends StatelessWidget {
  const MiniStatCard({
    super.key,
    required this.value,
    required this.label,
    this.onTap,
  });

  final String value;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(15),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: scheme.outlineVariant),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              value,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: scheme.onSurface,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              label,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Bölüm başlığı: kalın başlık + sağda isteğe bağlı yeşil aksiyon metni.
class SectionHeader extends StatelessWidget {
  const SectionHeader({
    super.key,
    required this.title,
    this.actionLabel,
    this.onAction,
  });

  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(
            child: Text(
              title,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: scheme.onSurface,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (actionLabel != null)
            GestureDetector(
              onTap: onAction,
              child: Text(
                actionLabel!,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: scheme.primary,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Liste kartı: ad + "x / y ürün" + ilerleme çubuğu + sağda %-halka.
class ListCard extends StatelessWidget {
  const ListCard({
    super.key,
    required this.title,
    required this.done,
    required this.total,
    this.subtitle,
    this.onTap,
  });

  final String title;
  final int done;
  final int total;
  final Widget? subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final ratio = total == 0 ? 0.0 : done / total;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: scheme.onSurface,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 5),
                    subtitle ??
                        Text(
                          '$done / $total ürün',
                          style: TextStyle(
                            color: scheme.onSurfaceVariant,
                            fontSize: 11,
                          ),
                        ),
                    const SizedBox(height: 10),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: LinearProgressIndicator(
                        value: ratio,
                        minHeight: 5,
                        backgroundColor: AppTheme.heroGreenBg,
                        color: scheme.primary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 15),
              PercentRing(value: ratio),
            ],
          ),
        ),
      ),
    );
  }
}

/// Yatay kategori kartı: emoji + ad (+ isteğe bağlı adet).
class CategoryCard extends StatelessWidget {
  const CategoryCard({
    super.key,
    required this.title,
    this.emoji,
    this.icon,
    this.count,
    this.onTap,
  });

  final String title;
  final String? emoji;
  final IconData? icon;
  final int? count;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 86,
        margin: const EdgeInsets.only(right: 10),
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: BorderRadius.circular(17),
          border: Border.all(color: scheme.outlineVariant),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (emoji != null)
              Text(emoji!, style: const TextStyle(fontSize: 24))
            else
              Icon(icon ?? Icons.category_outlined,
                  size: 24, color: scheme.primary),
            const SizedBox(height: 5),
            Text(
              title,
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w600,
                color: scheme.onSurface,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            if (count != null && count! > 0)
              Text('$count ürün',
                  style: TextStyle(
                      fontSize: 9, color: scheme.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }
}

/// Ürün küçük görseli: `imageUrl` varsa fotoğraf, yoksa yeşil kutuda emoji.
class ProductThumb extends StatelessWidget {
  const ProductThumb({
    super.key,
    this.imageUrl,
    this.emoji,
    this.size = 44,
    this.radius = 12,
  });

  final String? imageUrl;
  final String? emoji;
  final double size;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fallback = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppTheme.heroGreenBg,
        borderRadius: BorderRadius.circular(radius),
      ),
      child: (emoji != null && emoji!.isNotEmpty)
          ? Text(emoji!, style: TextStyle(fontSize: size * 0.5))
          : Icon(Icons.shopping_basket_outlined,
              size: size * 0.5, color: scheme.primary),
    );

    if (imageUrl == null || imageUrl!.isEmpty) return fallback;

    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: Image.network(
        imageUrl!,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => fallback,
        loadingBuilder: (context, child, progress) =>
            progress == null ? child : fallback,
      ),
    );
  }
}

/// Kategori adına göre emoji tahmini (tasarım taslağındaki gibi).
///
/// Naif `contains` yerine kelime bazlı eşleşme — yoksa "markET" içindeki
/// "et" yüzünden yanlış emoji çıkıyor.
String categoryEmoji(String name) {
  final words = name
      .toLowerCase()
      .split(RegExp(r'[\s/&,+-]+'))
      .where((w) => w.isNotEmpty)
      .toSet();

  bool has(List<String> keys) => keys.any(words.contains);

  if (has(['meyve', 'meyveler'])) return '🍎';
  if (has(['sebze', 'sebzeler', 'yeşillik'])) return '🥦';
  if (has(['süt', 'sütlü', 'kahvaltılık', 'kahvaltı'])) return '🥛';
  if (has(['et', 'balık', 'tavuk', 'şarküteri', 'kırmızı'])) return '🥩';
  if (has(['temizlik', 'deterjan'])) return '🧴';
  if (has(['ekmek', 'fırın', 'unlu', 'pastane'])) return '🍞';
  if (has(['içecek', 'içecekler', 'meşrubat', 'su'])) return '🥤';
  if (has(['bebek'])) return '🍼';
  if (has(['atıştırmalık', 'atıştırmalıklar', 'cips', 'çerez'])) return '🍿';
  if (has(['dondurulmuş', 'donuk'])) return '🧊';
  if (has(['bakliyat', 'kuruyemiş', 'kuru'])) return '🫘';
  if (has(['kişisel', 'bakım', 'kozmetik'])) return '🧼';
  if (has(['kırtasiye', 'ofis'])) return '✏️';
  if (has(['elektronik', 'teknoloji'])) return '🔌';
  if (has(['kıyafet', 'giyim', 'tekstil'])) return '👕';
  if (has(['ev', 'yaşam', 'züccaciye'])) return '🏠';
  if (has(['kahve', 'çay'])) return '☕';
  if (has(['baharat', 'baharatlar'])) return '🧂';
  return '🛒';
}
