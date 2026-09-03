import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/app_notification.dart';
import '../repositories/notifications_repository.dart';
import '../theme/app_theme.dart';
import '../widgets/ui_kit.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  final NotificationsRepository _repo = NotificationsRepository();
  bool _loading = true;
  List<AppNotification> _items = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final list = await _repo.fetchMine();
      if (!mounted) return;
      setState(() {
        _items = list;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
      _snack('Bildirimler yüklenemedi.');
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _markAllRead() async {
    try {
      await _repo.markAllRead();
      _load();
    } catch (_) {}
  }

  Future<void> _tap(AppNotification n) async {
    if (n.isRead) return;
    try {
      await _repo.markRead(n.id);
      final i = _items.indexWhere((e) => e.id == n.id);
      if (i != -1 && mounted) {
        setState(() => _items[i] = AppNotification(
              id: n.id,
              userId: n.userId,
              message: n.message,
              isRead: true,
              createdAt: n.createdAt,
            ));
      }
    } catch (_) {}
  }

  Future<void> _delete(AppNotification n) async {
    final i = _items.indexWhere((e) => e.id == n.id);
    setState(() => _items.removeWhere((e) => e.id == n.id));
    try {
      await _repo.delete(n.id);
    } catch (_) {
      if (i != -1 && mounted) setState(() => _items.insert(i, n));
    }
  }

  // --- yardımcılar -----------------------------------------------------

  String _dayKey(DateTime d) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final that = DateTime(d.year, d.month, d.day);
    final diff = today.difference(that).inDays;
    if (diff <= 0) return 'Bugün';
    if (diff == 1) return 'Dün';
    return 'Daha Önce';
  }

  String _timeLabel(DateTime d) {
    final key = _dayKey(d);
    if (key == 'Daha Önce') return DateFormat('dd MMM', 'tr_TR').format(d);
    return DateFormat('HH:mm').format(d);
  }

  IconData _iconFor(String message) {
    final m = message.toLowerCase();
    if (m.contains('arkadaşlık')) return Icons.person_add_alt_1_outlined;
    if (m.contains('paylaş')) return Icons.ios_share_outlined;
    if (m.contains('tamamla')) return Icons.check_circle_outline;
    if (m.contains('ekle') || m.contains('güncelle') || m.contains('sil')) {
      return Icons.shopping_basket_outlined;
    }
    return Icons.notifications_none_rounded;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final hasUnread = _items.any((n) => !n.isRead);

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Bildirimler'),
        actions: [
          if (hasUnread)
            IconButton(
              tooltip: 'Tümünü okundu yap',
              icon: const Icon(Icons.done_all),
              onPressed: _markAllRead,
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _items.isEmpty
              ? _empty(scheme)
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 30),
                    children: _buildGrouped(scheme),
                  ),
                ),
    );
  }

  List<Widget> _buildGrouped(ColorScheme scheme) {
    final widgets = <Widget>[];
    String? lastKey;
    for (final n in _items) {
      final key = _dayKey(n.createdAt);
      if (key != lastKey) {
        widgets.add(Padding(
          padding: EdgeInsets.only(top: lastKey == null ? 0 : 14, bottom: 8),
          child: Text(key,
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: scheme.onSurface)),
        ));
        lastKey = key;
      }
      widgets.add(_item(scheme, n));
    }
    return widgets;
  }

  Widget _item(ColorScheme scheme, AppNotification n) {
    final card = Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: n.isRead ? scheme.surface : AppTheme.heroGreenBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: scheme.surface,
            child: Icon(_iconFor(n.message), size: 18, color: scheme.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              n.message,
              style: TextStyle(
                fontSize: 12.5,
                height: 1.35,
                fontWeight: n.isRead ? FontWeight.w500 : FontWeight.w600,
                color: scheme.onSurface,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(_timeLabel(n.createdAt),
                  style: TextStyle(
                      fontSize: 10, color: scheme.onSurfaceVariant)),
              if (!n.isRead) ...[
                const SizedBox(height: 6),
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                      color: scheme.primary, shape: BoxShape.circle),
                ),
              ],
            ],
          ),
        ],
      ),
    );

    return Dismissible(
      key: ValueKey(n.id),
      direction: DismissDirection.endToStart,
      background: Container(
        margin: const EdgeInsets.only(bottom: 10),
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 22),
        decoration: BoxDecoration(
          color: scheme.error.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Icon(Icons.delete_outline, color: scheme.error),
      ),
      onDismissed: (_) => _delete(n),
      child: InkWell(
        onTap: () => _tap(n),
        borderRadius: BorderRadius.circular(16),
        child: card,
      ),
    );
  }

  Widget _empty(ColorScheme scheme) {
    return const EmptyState(
      icon: Icons.notifications_none_rounded,
      title: 'Bildirim yok',
      message: 'Liste paylaşımı, arkadaşlık isteği ve güncellemeler '
          'burada görünür.',
    );
  }
}
