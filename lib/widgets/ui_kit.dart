import 'package:flutter/material.dart';

/// Mockup boyunca tekrar eden küçük yapı taşları. Tek yerde tutuyoruz ki
/// tüm ekranlarda birebir aynı görünsünler.

/// "%65" yazan dairesel ilerleme rozeti.
/// Ana Sayfa hero kartı, Listelerim kartları, Liste Detayı başlığı vb.
class PercentRing extends StatelessWidget {
  const PercentRing({
    super.key,
    required this.value,
    this.size = 52,
    this.stroke = 5,
    this.color,
  });

  /// 0.0 – 1.0 arası tamamlanma oranı.
  final double value;
  final double size;
  final double stroke;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final c = color ?? scheme.primary;
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
              backgroundColor: scheme.outlineVariant.withValues(alpha: 0.4),
              valueColor: AlwaysStoppedAnimation(c),
            ),
          ),
          Text(
            '%$pct',
            style: TextStyle(
              fontSize: size * 0.26,
              fontWeight: FontWeight.w700,
              color: scheme.onSurface,
            ),
          ),
        ],
      ),
    );
  }
}

/// Kenarlıklı beyaz kutu: büyük sayı + küçük etiket.
/// Ana Sayfa (3'lü), İstatistikler (3'lü), Profil (4'lü) satırlarında.
class MiniStatCard extends StatelessWidget {
  const MiniStatCard({
    super.key,
    required this.value,
    required this.label,
    this.icon,
    this.onTap,
  });

  final String value;
  final String label;
  final IconData? icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.6)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 18, color: scheme.primary),
              const SizedBox(height: 6),
            ],
            Text(
              value,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: scheme.onSurface,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11.5,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Bölüm başlığı: kalın başlık + sağda isteğe bağlı "Tümü ›" aksiyonu.
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
        children: [
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: scheme.onSurface,
              ),
            ),
          ),
          if (actionLabel != null)
            GestureDetector(
              onTap: onAction,
              child: Row(
                children: [
                  Text(
                    actionLabel!,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: scheme.primary,
                    ),
                  ),
                  Icon(Icons.chevron_right, size: 18, color: scheme.primary),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
