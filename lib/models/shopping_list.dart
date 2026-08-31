/// `shopping_lists` tablosundaki bir satırı temsil eder.
///
/// Daha önce ekranlar `Map<String, dynamic>` taşıyıp `list['name']` gibi
/// erişiyordu; yazım hatası ancak çalışma anında patlıyordu. Bu sınıf alanları
/// derleme anında kontrol edilebilir hale getirir.
class ShoppingList {
  final String id;
  final String userId;
  final String name;
  final DateTime createdAt;
  final double completionRate;

  /// Liste görünümü için istemcide hesaplanan yardımcı alanlar (DB'de yok).
  final bool isOwner;
  final int itemCount;

  const ShoppingList({
    required this.id,
    required this.userId,
    required this.name,
    required this.createdAt,
    this.completionRate = 0,
    this.isOwner = true,
    this.itemCount = 0,
  });

  factory ShoppingList.fromMap(
    Map<String, dynamic> map, {
    bool isOwner = true,
  }) {
    // `list_items(id)` gömülü seçildiğinde ürün sayısını buradan alırız.
    final embeddedItems = map['list_items'];
    final count = embeddedItems is List ? embeddedItems.length : 0;

    return ShoppingList(
      id: map['id'] as String,
      userId: (map['user_id'] ?? '') as String,
      name: (map['name'] ?? 'İsimsiz Liste') as String,
      createdAt:
          DateTime.tryParse(map['created_at']?.toString() ?? '') ?? DateTime.now(),
      completionRate: _toDouble(map['completion_rate']),
      isOwner: isOwner,
      itemCount: count,
    );
  }

  /// INSERT için gövde — sunucunun yönettiği alanlar (id, created_at) dışarıda.
  Map<String, dynamic> toInsert() => {
        'name': name,
        'user_id': userId,
      };

  ShoppingList copyWith({
    String? name,
    double? completionRate,
    bool? isOwner,
    int? itemCount,
  }) {
    return ShoppingList(
      id: id,
      userId: userId,
      name: name ?? this.name,
      createdAt: createdAt,
      completionRate: completionRate ?? this.completionRate,
      isOwner: isOwner ?? this.isOwner,
      itemCount: itemCount ?? this.itemCount,
    );
  }

  static double _toDouble(dynamic v) {
    if (v is double) return v;
    if (v is int) return v.toDouble();
    return double.tryParse(v?.toString() ?? '') ?? 0.0;
  }
}
