import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/app_notification.dart';

/// `notifications` tablosu için veri erişimi (kullanıcının kendi bildirimleri).
class NotificationsRepository {
  NotificationsRepository({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  String get _uid {
    final id = _client.auth.currentUser?.id;
    if (id == null) throw StateError('Oturum yok.');
    return id;
  }

  Future<List<AppNotification>> fetchMine() async {
    final rows = await _client
        .from('notifications')
        .select()
        .eq('user_id', _uid)
        .order('created_at', ascending: false)
        .limit(100);
    return rows.map<AppNotification>(AppNotification.fromMap).toList();
  }

  Future<int> unreadCount() async {
    final res = await _client
        .from('notifications')
        .select('id')
        .eq('user_id', _uid)
        .eq('is_read', false)
        .count(CountOption.exact);
    return res.count;
  }

  Future<void> markRead(String id) async {
    await _client
        .from('notifications')
        .update({'is_read': true}).eq('id', id);
  }

  Future<void> markAllRead() async {
    await _client
        .from('notifications')
        .update({'is_read': true})
        .eq('user_id', _uid)
        .eq('is_read', false);
  }

  Future<void> delete(String id) async {
    await _client.from('notifications').delete().eq('id', id);
  }

  /// Bildirimlerin canlı akışı (yeni bildirim geldiğinde tetiklenir).
  Stream<List<AppNotification>> watchMine() {
    return _client
        .from('notifications')
        .stream(primaryKey: ['id'])
        .eq('user_id', _uid)
        .order('created_at', ascending: false)
        .map((rows) => rows.map<AppNotification>(AppNotification.fromMap).toList());
  }
}
