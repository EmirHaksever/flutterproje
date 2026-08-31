/// `notifications` tablosundaki bir satır.
class AppNotification {
  final String id;
  final String userId;
  final String message;
  final bool isRead;
  final DateTime createdAt;

  const AppNotification({
    required this.id,
    required this.userId,
    required this.message,
    required this.isRead,
    required this.createdAt,
  });

  factory AppNotification.fromMap(Map<String, dynamic> m) => AppNotification(
        id: m['id'] as String,
        userId: (m['user_id'] ?? '') as String,
        message: (m['message'] ?? '') as String,
        isRead: m['is_read'] == true,
        createdAt: DateTime.tryParse(m['created_at']?.toString() ?? '') ??
            DateTime.now(),
      );
}
