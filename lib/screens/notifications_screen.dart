import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/app_notification.dart';
import '../repositories/notifications_repository.dart';

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
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bildirimler yüklenemedi.')),
      );
    }
  }

  Future<void> _markAllRead() async {
    try {
      await _repo.markAllRead();
      _load();
    } catch (_) {}
  }

  Future<void> _tap(AppNotification n) async {
    if (!n.isRead) {
      try {
        await _repo.markRead(n.id);
        setState(() {
          final i = _items.indexWhere((e) => e.id == n.id);
          if (i != -1) {
            _items[i] = AppNotification(
              id: n.id,
              userId: n.userId,
              message: n.message,
              isRead: true,
              createdAt: n.createdAt,
            );
          }
        });
      } catch (_) {}
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final primary = scheme.primary;
    final hasUnread = _items.any((n) => !n.isRead);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Bildirimler'),
        backgroundColor: primary,
        foregroundColor: Colors.white,
        actions: [
          if (hasUnread)
            TextButton(
              onPressed: _markAllRead,
              child: const Text('Tümünü okundu yap',
                  style: TextStyle(color: Colors.white)),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _items.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.notifications_none,
                          size: 64, color: scheme.onSurfaceVariant),
                      const SizedBox(height: 12),
                      Text('Bildirim yok.',
                          style: TextStyle(
                              color: scheme.onSurfaceVariant, fontSize: 16)),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.separated(
                    itemCount: _items.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, i) {
                      final n = _items[i];
                      return ListTile(
                        leading: Icon(
                          n.isRead
                              ? Icons.notifications_none
                              : Icons.notifications_active,
                          color: n.isRead ? Colors.grey : primary,
                        ),
                        title: Text(
                          n.message,
                          style: TextStyle(
                              fontWeight: n.isRead
                                  ? FontWeight.normal
                                  : FontWeight.w600),
                        ),
                        subtitle: Text(DateFormat('dd MMM yyyy, HH:mm', 'tr_TR')
                            .format(n.createdAt)),
                        tileColor:
                            n.isRead ? null : primary.withValues(alpha: 0.06),
                        onTap: () => _tap(n),
                      );
                    },
                  ),
                ),
    );
  }
}
