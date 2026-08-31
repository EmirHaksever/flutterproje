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

  String get _uid {
    final id = _client.auth.currentUser?.id;
    if (id == null) throw StateError('Oturum yok.');
    return id;
  }

  /// Sonuç kodları: paylaşımın nasıl sonuçlandığını çağırana anlatır.
  /// UI, kullanıcıya gösterilecek metni buna göre seçer.
  ShareOutcome _ok() => ShareOutcome.success;

  /// Bir listeyi e-posta ile paylaşır.
  Future<ShareOutcome> shareByEmail({
    required String listId,
    required String email,
  }) async {
    final normalized = email.trim().toLowerCase();
    final myEmail = _client.auth.currentUser?.email?.toLowerCase();
    if (normalized.isEmpty || !normalized.contains('@')) {
      return ShareOutcome.invalidEmail;
    }
    if (normalized == myEmail) return ShareOutcome.self;

    final targetUser = await _client
        .from('users')
        .select('id')
        .eq('email', normalized)
        .maybeSingle();
    if (targetUser == null) return ShareOutcome.userNotFound;

    final targetId = targetUser['id'] as String;

    final existing = await _client
        .from('shared_lists')
        .select('id')
        .eq('list_id', listId)
        .eq('user_id', targetId)
        .maybeSingle();
    if (existing != null) return ShareOutcome.alreadyShared;

    await _client.from('shared_lists').insert({
      'list_id': listId,
      'user_id': targetId,
      'user_email': normalized,
      'role': 'editor',
      'shared_by_user_id': _uid,
    });
    return _ok();
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
