/// Kabul edilmiş bir arkadaşlık (`friends` tablosu, tek yön).
class Friend {
  final String id;
  final String userId;
  final String friendId;
  final String friendEmail;
  final String? friendName;
  final String? avatarUrl;
  final String status; // 'pending' | 'accepted'
  final DateTime addedAt;

  const Friend({
    required this.id,
    required this.userId,
    required this.friendId,
    required this.friendEmail,
    this.friendName,
    this.avatarUrl,
    required this.status,
    required this.addedAt,
  });

  String get displayName =>
      (friendName?.trim().isNotEmpty ?? false) ? friendName! : friendEmail;

  factory Friend.fromMap(Map<String, dynamic> m) {
    final u = m['friend'] is Map ? m['friend'] as Map : const {};
    return Friend(
      id: m['id'] as String,
      userId: (m['user_id'] ?? '') as String,
      friendId: (m['friend_id'] ?? '') as String,
      friendEmail:
          (u['email'] ?? m['friend_email'] ?? '') as String,
      friendName: u['name'] as String?,
      avatarUrl: u['avatar_url'] as String?,
      status: (m['status'] ?? 'pending') as String,
      addedAt: DateTime.tryParse(m['added_at']?.toString() ?? '') ??
          DateTime.now(),
    );
  }
}

/// `friend_requests` tablosu — bekleyen/işlenmiş bir arkadaşlık isteği.
class FriendRequest {
  final String id;
  final String senderId;
  final String receiverId;
  final String status; // 'pending' | 'accepted' | 'rejected'
  final DateTime createdAt;
  final String otherEmail;
  final String? otherName;
  final String? otherAvatarUrl;

  const FriendRequest({
    required this.id,
    required this.senderId,
    required this.receiverId,
    required this.status,
    required this.createdAt,
    this.otherEmail = '',
    this.otherName,
    this.otherAvatarUrl,
  });

  String get displayName =>
      (otherName?.trim().isNotEmpty ?? false) ? otherName! : otherEmail;

  factory FriendRequest.fromMap(
    Map<String, dynamic> m, {
    required String otherKey, // 'sender' | 'receiver'
  }) {
    final u = m[otherKey] is Map ? m[otherKey] as Map : const {};
    return FriendRequest(
      id: m['id'] as String,
      senderId: (m['sender_id'] ?? '') as String,
      receiverId: (m['receiver_id'] ?? '') as String,
      status: (m['status'] ?? 'pending') as String,
      createdAt: DateTime.tryParse(m['created_at']?.toString() ?? '') ??
          DateTime.now(),
      otherEmail: (u['email'] ?? '') as String,
      otherName: u['name'] as String?,
      otherAvatarUrl: u['avatar_url'] as String?,
    );
  }
}
