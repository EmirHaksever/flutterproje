import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/friend.dart';

/// `friends` / `friend_requests` için veri erişimi.
///
/// İki tarafı da ilgilendiren işlemler veritabanındaki SECURITY DEFINER
/// fonksiyonlarla yapılır (send/respond/remove). Arkadaşlık artık `friend_id`
/// üzerinden bağlanır; e-posta yalnızca gösterim içindir.
class FriendsRepository {
  FriendsRepository({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  String get _uid {
    final id = _client.auth.currentUser?.id;
    if (id == null) throw StateError('Oturum yok.');
    return id;
  }

  Future<List<Friend>> fetchFriends() async {
    final rows = await _client
        .from('friends')
        .select('*, friend:friend_id(email, name, avatar_url)')
        .eq('user_id', _uid)
        .eq('status', 'accepted')
        .order('added_at', ascending: false);
    return rows.map<Friend>((r) => Friend.fromMap(r)).toList();
  }

  Future<List<FriendRequest>> fetchIncomingRequests() async {
    final rows = await _client
        .from('friend_requests')
        .select('*, sender:sender_id(email, name, avatar_url)')
        .eq('receiver_id', _uid)
        .eq('status', 'pending')
        .order('created_at', ascending: false);
    return rows
        .map<FriendRequest>(
            (r) => FriendRequest.fromMap(r, otherKey: 'sender'))
        .toList();
  }

  Future<List<FriendRequest>> fetchOutgoingRequests() async {
    final rows = await _client
        .from('friend_requests')
        .select('*, receiver:receiver_id(email, name, avatar_url)')
        .eq('sender_id', _uid)
        .eq('status', 'pending')
        .order('created_at', ascending: false);
    return rows
        .map<FriendRequest>(
            (r) => FriendRequest.fromMap(r, otherKey: 'receiver'))
        .toList();
  }

  Future<void> sendRequest(String email) async {
    await _client.rpc('send_friend_request', params: {'target_email': email});
  }

  /// İsim veya e-posta ile kullanıcı arar (arkadaş eklemek için).
  Future<List<({String id, String? name, String email, String? avatarUrl})>>
      searchUsers(String query) async {
    final q = query.trim();
    if (q.length < 2) return [];
    final rows = await _client.rpc('search_users', params: {'q': q}) as List;
    return rows
        .map<({String id, String? name, String email, String? avatarUrl})>(
            (r) => (
                  id: r['id'] as String,
                  name: r['name'] as String?,
                  email: (r['email'] ?? '') as String,
                  avatarUrl: r['avatar_url'] as String?,
                ))
        .toList();
  }

  Future<void> respond(String requestId, {required bool accept}) async {
    await _client.rpc('respond_friend_request',
        params: {'request_id': requestId, 'accept': accept});
  }

  Future<void> cancelRequest(String requestId) async {
    await _client.from('friend_requests').delete().eq('id', requestId);
  }

  Future<void> removeFriend(String otherUserId) async {
    await _client
        .rpc('remove_friend', params: {'other_user_id': otherUserId});
  }
}
