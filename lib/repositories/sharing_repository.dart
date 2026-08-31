import 'package:supabase_flutter/supabase_flutter.dart';

/// `shared_lists` tablosu için veri erişimi (liste paylaşımı).
///
/// RLS tarafında: yalnızca listenin sahibi paylaşım kaydı ekleyebilir; yalnızca
/// ilgili kullanıcı kendi paylaşım kayıtlarını görebilir/silebilir (bkz.
/// supabase/migrations/..._tighten_shared_lists_rls.sql).
class SharingRepository {
  SharingRepository({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  /// Bir listeyi e-posta ile paylaşır.
  ///
  /// Asıl iş veritabanındaki `share_list_by_email` fonksiyonunda yapılır
  /// (SECURITY DEFINER): sahiplik kontrolü, kullanıcı arama, çift-paylaşım
  /// kontrolü ve karşı tarafa bildirim — hepsi atomik ve baypas edilemez.
  Future<ShareOutcome> shareByEmail({
    required String listId,
    required String email,
  }) async {
    final normalized = email.trim().toLowerCase();
    if (normalized.isEmpty || !normalized.contains('@')) {
      return ShareOutcome.invalidEmail;
    }

    final result = await _client.rpc('share_list_by_email',
        params: {'p_list_id': listId, 'p_email': normalized});

    return switch (result) {
      'ok' => ShareOutcome.success,
      'self' => ShareOutcome.self,
      'not_found' => ShareOutcome.userNotFound,
      'already' => ShareOutcome.alreadyShared,
      _ => ShareOutcome.success,
    };
  }

  /// Bir listenin paylaşıldığı kullanıcıların e-postaları.
  Future<List<String>> fetchSharedEmails(String listId) async {
    final rows = await _client
        .from('shared_lists')
        .select('user_email, users(email)')
        .eq('list_id', listId);

    return rows
        .map<String?>((r) =>
            (r['user_email'] as String?) ??
            (r['users'] is Map ? r['users']['email'] as String? : null))
        .whereType<String>()
        .toList();
  }

  /// Paylaşımı kaldırır (liste sahibi veya paylaşılan kullanıcı yapabilir).
  Future<void> unshare({required String listId, required String userId}) async {
    await _client
        .from('shared_lists')
        .delete()
        .eq('list_id', listId)
        .eq('user_id', userId);
  }
}

enum ShareOutcome {
  success,
  invalidEmail,
  self,
  userNotFound,
  alreadyShared,
}
