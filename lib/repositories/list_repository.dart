import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/list_item.dart';
import '../models/shopping_list.dart';

/// `shopping_lists` ve `list_items` tabloları için tek veri erişim noktası.
///
/// Amaç: Supabase sorgularını ekranlardan çıkarıp tek yerde toplamak. Her sorgu
/// burada hem RLS'e hem de açık `user_id` / `list_id` filtresine dayanır
/// (savunma derinliği). `client` dışarıdan verilebildiği için test edilebilir.
class ListRepository {
  ListRepository({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  String get _uid {
    final id = _client.auth.currentUser?.id;
    if (id == null) {
      throw StateError('Oturum yok: kullanıcı kimliği alınamadı.');
    }
    return id;
  }

  // --- shopping_lists --------------------------------------------------------

  /// Kullanıcının kendi oluşturduğu listeler (ürün sayısıyla birlikte),
  /// en yeni önce.
  Future<List<ShoppingList>> fetchOwnedLists() async {
    final rows = await _client
        .from('shopping_lists')
        .select('*, list_items(id)')
        .eq('user_id', _uid)
        .order('created_at', ascending: false);

    return rows
        .map<ShoppingList>((r) => ShoppingList.fromMap(r, isOwner: true))
        .toList();
  }

  /// Kullanıcıyla paylaşılmış listeler (sahibi başkası).
  Future<List<ShoppingList>> fetchSharedLists() async {
    final rows = await _client
        .from('shared_lists')
        .select(
            'shopping_lists(id, name, user_id, created_at, completion_rate, list_items(id))')
        .eq('user_id', _uid);

    return rows
        .where((r) => r['shopping_lists'] != null)
        .map<ShoppingList>((r) => ShoppingList.fromMap(
              Map<String, dynamic>.from(r['shopping_lists'] as Map),
              isOwner: false,
            ))
        .toList();
  }

  /// Sahip olunan + paylaşılan tüm listeler, oluşturulma tarihine göre azalan.
  Future<List<ShoppingList>> fetchAllVisibleLists() async {
    final owned = await fetchOwnedLists();
    final shared = await fetchSharedLists();
    final all = [...owned, ...shared]
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return all;
  }

  Future<ShoppingList> createList(String name) async {
    final row = await _client
        .from('shopping_lists')
        .insert({'name': name, 'user_id': _uid})
        .select()
        .single();
    return ShoppingList.fromMap(row, isOwner: true);
  }

  /// Listeyi siler. `list_items` ve `shared_lists` FK'de ON DELETE CASCADE
  /// olduğu için bağlı satırlar veritabanı seviyesinde birlikte silinir.
  Future<void> deleteList(String listId) async {
    await _client.from('shopping_lists').delete().eq('id', listId);
  }

  Future<void> updateCompletionRate(String listId, double rate) async {
    await _client
        .from('shopping_lists')
        .update({'completion_rate': rate}).eq('id', listId);
  }

  /// Kullanıcının görebildiği ürünlerde geçen benzersiz kategori adları
  /// (kategori keşfi için).
  Future<List<String>> fetchUsedCategories() async {
    final rows = await _client.from('list_items').select('category');
    return rows
        .map((r) => r['category'] as String?)
        .whereType<String>()
        .where((c) => c.isNotEmpty)
        .toSet()
        .toList();
  }

  // --- list_items ----------------------------------------------------------

  Future<List<ListItem>> fetchItems(String listId) async {
    final rows = await _client
        .from('list_items')
        .select()
        .eq('list_id', listId)
        .order('created_at', ascending: true);
    return rows.map<ListItem>(ListItem.fromMap).toList();
  }

  Future<void> addItems(String listId, List<ListItem> items) async {
    if (items.isEmpty) return;
    final payload = items
        .map((i) => i.copyWith().toInsert()..['list_id'] = listId)
        .toList();
    await _client.from('list_items').insert(payload);
  }

  Future<void> setItemCompleted(String itemId, bool completed) async {
    await _client
        .from('list_items')
        .update({'is_completed': completed}).eq('id', itemId);
  }

  /// Bir ürünün alanlarını günceller. Yalnızca verilen anahtarlar değişir.
  Future<void> updateItem(
    String itemId, {
    String? productName,
    int? quantity,
    String? category,
    String? market,
    String? imageUrl,
    List<String>? tags,
  }) async {
    final patch = <String, dynamic>{};
    if (productName != null) patch['product_name'] = productName;
    if (quantity != null) patch['quantity'] = quantity;
    if (category != null) patch['category'] = category;
    if (market != null) patch['market'] = market;
    if (imageUrl != null) patch['image_url'] = imageUrl;
    if (tags != null) patch['tags'] = tags;
    if (patch.isEmpty) return;
    await _client.from('list_items').update(patch).eq('id', itemId);
  }

  Future<void> deleteItem(String itemId) async {
    await _client.from('list_items').delete().eq('id', itemId);
  }

  // --- realtime -----------------------------------------------------------

  /// Kullanıcının listelerindeki değişiklikleri canlı yayınlar.
  Stream<List<ShoppingList>> watchOwnedLists() {
    return _client
        .from('shopping_lists')
        .stream(primaryKey: ['id'])
        .eq('user_id', _uid)
        .order('created_at', ascending: false)
        .map((rows) => rows
            .map<ShoppingList>((r) => ShoppingList.fromMap(r, isOwner: true))
            .toList());
  }

  /// Belirli bir listedeki ürünlerin canlı akışı.
  Stream<List<ListItem>> watchItems(String listId) {
    return _client
        .from('list_items')
        .stream(primaryKey: ['id'])
        .eq('list_id', listId)
        .order('created_at')
        .map((rows) => rows.map<ListItem>(ListItem.fromMap).toList());
  }
}
