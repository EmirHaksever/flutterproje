/// `friends` tablosu — kabul edilmiş bir arkadaşlık (tek yön; karşı yön ayrı satır).
class Friend {
  final String id;
  final String userId;
  final String friendEmail;
  final String status; // 'pending' | 'accepted'
  final DateTime addedAt;

  const Friend({
    required this.id,
    required this.userId,
    required this.friendEmail,
    required this.status,
    required this.addedAt,
  });

  factory Friend.fromMap(Map<String, dynamic> m) => Friend(
        id: m['id'] as String,
        userId: (m['user_id'] ?? '') as String,
        friendEmail: (m['friend_email'] ?? '') as String,
        status: (m['status'] ?? 'pending') as String,
        addedAt: DateTime.tryParse(m['added_at']?.toString() ?? '') ??
            DateTime.now(),
      );
}

/// `friend_requests` tablosu — bekleyen/işlenmiş bir arkadaşlık isteği.
/// [otherEmail] istemcide doldurulur (istekle birlikte çekilen users(email)).
class FriendRequest {
  final String id;
  final String senderId;
  final String receiverId;
  final String status; // 'pending' | 'accepted' | 'rejected'
  final DateTime createdAt;
  final String otherEmail;

  const FriendRequest({
    required this.id,
    required this.senderId,
    required this.receiverId,
    required this.status,
    required this.createdAt,
    this.otherEmail = '',
  });

  factory FriendRequest.fromMap(
    Map<String, dynamic> m, {
    String otherEmail = '',
  }) =>
      FriendRequest(
        id: m['id'] as String,
        senderId: (m['sender_id'] ?? '') as String,
        receiverId: (m['receiver_id'] ?? '') as String,
        status: (m['status'] ?? 'pending') as String,
        createdAt: DateTime.tryParse(m['created_at']?.toString() ?? '') ??
            DateTime.now(),
        otherEmail: otherEmail,
      );
}
