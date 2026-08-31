import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/friend.dart';

/// `friends` / `friend_requests` için veri erişimi.
///
/// İki tarafı da ilgilendiren işlemler (istek gönder/yanıtla, çıkar) veritabanı
/// tarafındaki SECURITY DEFINER fonksiyonlar üzerinden yapılır — bkz.
/// supabase/migrations/..._friends_notifications_rls_and_rpcs.sql
class FriendsRepository {
  FriendsRepository({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  String get _uid {
    final id = _client.auth.currentUser?.id;
    if (id == null) throw StateError('Oturum yok.');
    return id;
  }

  /// Kabul edilmiş arkadaşlar.
  Future<List<Friend>> fetchFriends() async {
    final rows = await _client
        .from('friends')
        .select()
        .eq('user_id', _uid)
        .eq('status', 'accepted')
        .order('added_at', ascending: false);
    return rows.map<Friend>((r) => Friend.fromMap(r)).toList();
  }

  /// Bana gelen bekleyen istekler (gönderenin e-postasıyla).
  Future<List<FriendRequest>> fetchIncomingRequests() async {
    final rows = await _client
        .from('friend_requests')
        .select('*, sender:sender_id(email)')
        .eq('receiver_id', _uid)
        .eq('status', 'pending')
        .order('created_at', ascending: false);
    return rows
        .map<FriendRequest>((r) => FriendRequest.fromMap(
              r,
              otherEmail: _emailOf(r['sender']),
            ))
        .toList();
  }

  /// Benim gönderdiğim bekleyen istekler (alıcının e-postasıyla).
  Future<List<FriendRequest>> fetchOutgoingRequests() async {
    final rows = await _client
        .from('friend_requests')
        .select('*, receiver:receiver_id(email)')
        .eq('sender_id', _uid)
        .eq('status', 'pending')
        .order('created_at', ascending: false);
    return rows
        .map<FriendRequest>((r) => FriendRequest.fromMap(
              r,
              otherEmail: _emailOf(r['receiver']),
            ))
        .toList();
  }

  /// E-posta ile arkadaşlık isteği gönderir. Hata durumunda [Exception] fırlatır
  /// (mesajı doğrudan kullanıcıya gösterilebilir).
  Future<void> sendRequest(String email) async {
    await _client.rpc('send_friend_request', params: {'target_email': email});
  }

  /// Bana gelen bir isteği kabul/ret eder.
  Future<void> respond(String requestId, {required bool accept}) async {
    await _client.rpc('respond_friend_request',
        params: {'request_id': requestId, 'accept': accept});
  }

  /// Gönderdiğim bekleyen isteği geri çeker.
  Future<void> cancelRequest(String requestId) async {
    await _client.from('friend_requests').delete().eq('id', requestId);
  }

  /// Arkadaşlıktan çıkar (her iki taraf da temizlenir).
  Future<void> removeFriend(String friendEmail) async {
    await _client.rpc('remove_friend',
        params: {'friend_email_param': friendEmail});
  }

  static String _emailOf(dynamic joined) {
    if (joined is Map && joined['email'] is String) return joined['email'];
    return '';
  }
}
