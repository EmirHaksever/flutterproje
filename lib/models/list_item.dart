/// `list_items` tablosundaki bir satır (bir listedeki tek ürün).
class ListItem {
  final String id;
  final String listId;
  final String productName;
  final String? category;
  final int quantity;
  final bool isCompleted;
  final DateTime createdAt;
  final String? market;
  final String? imageUrl;
  final List<String> tags;
  final List<String> features;

  const ListItem({
    required this.id,
    required this.listId,
    required this.productName,
    this.category,
    this.quantity = 1,
    this.isCompleted = false,
    required this.createdAt,
    this.market,
    this.imageUrl,
    this.tags = const [],
    this.features = const [],
  });

  factory ListItem.fromMap(Map<String, dynamic> map) {
    return ListItem(
      id: map['id'] as String,
      listId: (map['list_id'] ?? '') as String,
      productName: (map['product_name'] ?? '') as String,
      category: map['category'] as String?,
      quantity: (map['quantity'] as num?)?.toInt() ?? 1,
      isCompleted: map['is_completed'] == true,
      createdAt:
          DateTime.tryParse(map['created_at']?.toString() ?? '') ?? DateTime.now(),
      market: map['market'] as String?,
      imageUrl: map['image_url'] as String?,
      tags: _toStringList(map['tags']),
      features: _toStringList(map['features']),
    );
  }

  /// INSERT için gövde. `id` ve `created_at` sunucuda oluşur.
  Map<String, dynamic> toInsert() => {
        'list_id': listId,
        'product_name': productName,
        'category': category,
        'quantity': quantity,
        'is_completed': isCompleted,
        'market': market,
        'image_url': imageUrl,
        'tags': tags,
        'features': features,
      };

  ListItem copyWith({
    String? productName,
    String? category,
    int? quantity,
    bool? isCompleted,
    String? market,
    String? imageUrl,
    List<String>? tags,
    List<String>? features,
  }) {
    return ListItem(
      id: id,
      listId: listId,
      productName: productName ?? this.productName,
      category: category ?? this.category,
      quantity: quantity ?? this.quantity,
      isCompleted: isCompleted ?? this.isCompleted,
      createdAt: createdAt,
      market: market ?? this.market,
      imageUrl: imageUrl ?? this.imageUrl,
      tags: tags ?? this.tags,
      features: features ?? this.features,
    );
  }

  static List<String> _toStringList(dynamic v) {
    if (v is List) return v.map((e) => e.toString()).toList();
    return const [];
  }
}
