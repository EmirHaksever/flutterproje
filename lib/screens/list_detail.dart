import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../repositories/image_repository.dart';
import '../repositories/list_repository.dart';
import '../repositories/sharing_repository.dart';
import '../widgets/ui_kit.dart';

class ListDetailPage extends StatefulWidget {
  final Map<String, dynamic> listData;

  const ListDetailPage({super.key, required this.listData});

  @override
  State<ListDetailPage> createState() => _ListDetailPageState();
}

class _ListDetailPageState extends State<ListDetailPage> {
  final supabase = Supabase.instance.client;
  final ListRepository _listRepo = ListRepository();
  final SharingRepository _sharingRepo = SharingRepository();
  final ImageRepository _imageRepo = ImageRepository();
  final ImagePicker _picker = ImagePicker();

  late String currentUserId;
  String listOwnerEmail = '';
  List<Map<String, dynamic>> _items = [];
  List<String> _sharedEmails = [];
  bool _hideCompleted = false;
  RealtimeChannel? _itemsChannel;
  RealtimeChannel? _listCompletionChannel;

  String? _selectedCategoryFilter; // null = Tümü

  static const List<String> _predefinedCategories = [
    'Gıda',
    'İçecek',
    'Temizlik',
    'Kişisel Bakım',
    'Ev Eşyaları',
    'Atıştırmalık',
    'Meyve & Sebze',
    'Et & Balık',
    'Süt Ürünleri',
    'Bakliyat & Tahıl',
    'Fırın & Pasta',
    'Dondurulmuş Ürünler',
    'Evcil Hayvan Ürünleri',
    'Elektronik',
    'Kırtasiye',
    'Diğer',
  ];

  bool get _isOwner => widget.listData['user_id'] == currentUserId;

  @override
  void initState() {
    super.initState();
    currentUserId = supabase.auth.currentSession!.user.id;
    _checkAccessAndInitialize();
  }

  @override
  void dispose() {
    _itemsChannel?.unsubscribe();
    _listCompletionChannel?.unsubscribe();
    super.dispose();
  }

  Future<void> _checkAccessAndInitialize() async {
    final listId = widget.listData['id'];
    final hasAccess = await _checkUserHasAccess(listId, currentUserId);
    if (!hasAccess) {
      if (mounted) {
        _snack('Bu listeye erişim hakkın yok.');
        Navigator.pop(context);
      }
      return;
    }

    if (widget.listData['name'] == null ||
        (widget.listData['name'] as String).isEmpty) {
      final info = await supabase
          .from('shopping_lists')
          .select('name')
          .eq('id', widget.listData['id'])
          .maybeSingle();
      if (info != null && mounted) {
        setState(() => widget.listData['name'] = info['name']);
      }
    }

    await _fetchListOwnerEmail(widget.listData['user_id'] as String);
    await _fetchItems();
    await _fetchSharedUsers();
    _subscribeToRealtimeItems();
    _setupCompletionRateRealtimeListener();
  }

  Future<bool> _checkUserHasAccess(String listId, String userId) async {
    final listRes = await supabase
        .from('shopping_lists')
        .select('user_id')
        .eq('id', listId)
        .maybeSingle();
    if (listRes != null && listRes['user_id'] == userId) return true;

    final sharedRes = await supabase
        .from('shared_lists')
        .select()
        .eq('list_id', listId)
        .eq('user_id', userId);
    return (sharedRes as List).isNotEmpty;
  }

  Future<void> _fetchListOwnerEmail(String ownerId) async {
    final res = await supabase
        .from('users')
        .select('email')
        .eq('id', ownerId)
        .maybeSingle();
    if (mounted) {
      setState(() => listOwnerEmail = res?['email'] ?? 'Bilinmiyor');
    }
  }

  void _subscribeToRealtimeItems() {
    _itemsChannel = supabase
        .channel('public:list_items_detail_page_items')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'list_items',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'list_id',
            value: widget.listData['id'],
          ),
          callback: (_) => _fetchItems(),
        )
        .subscribe();
  }

  void _setupCompletionRateRealtimeListener() {
    _listCompletionChannel = supabase
        .channel('public:shopping_lists_detail_page_completion_rate')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'shopping_lists',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'id',
            value: widget.listData['id'],
          ),
          callback: (_) {
            if (mounted) setState(() {});
          },
        )
        .subscribe();
  }

  Future<void> _fetchItems() async {
    try {
      final response = await supabase
          .from('list_items')
          .select('*')
          .eq('list_id', widget.listData['id'])
          .order('created_at', ascending: true);
      if (mounted) {
        setState(() =>
            _items = List<Map<String, dynamic>>.from(response as List));
      }
    } catch (e) {
      debugPrint('list_detail: ürünler çekilemedi: $e');
    }
  }

  Future<void> _fetchSharedUsers() async {
    try {
      final response = await supabase
          .from('shared_lists')
          .select('user_id, users(email)')
          .eq('list_id', widget.listData['id']);
      if (mounted) {
        setState(() {
          _sharedEmails = (response as List)
              .map((e) => e['users']?['email'] as String?)
              .whereType<String>()
              .toList();
        });
      }
    } catch (e) {
      debugPrint('list_detail: paylaşılan kullanıcılar çekilemedi: $e');
    }
  }

  Future<void> _notifyParticipants(String changeMessage) async {
    final listName = widget.listData['name'] ?? 'Alışveriş Listesi';
    try {
      await supabase.rpc('notify_list_participants', params: {
        'p_list_id': widget.listData['id'],
        'p_message': '"$listName" listende $changeMessage',
      });
    } catch (e) {
      debugPrint('Bildirim gönderilemedi: $e');
    }
  }

  Future<void> _toggleItemComplete(Map<String, dynamic> item) async {
    final index = _items.indexOf(item);
    if (index == -1) return;
    final newStatus = !(item['is_completed'] ?? false);
    final name = item['product_name'] ?? 'bir ürün';

    HapticFeedback.selectionClick();
    setState(() => _items[index]['is_completed'] = newStatus);
    try {
      await supabase
          .from('list_items')
          .update({'is_completed': newStatus}).eq('id', item['id']);
      await _updateCompletionRate();
      await _notifyParticipants(
          newStatus ? '$name tamamlandı.' : '$name tekrar alınacak.');
    } catch (e) {
      if (mounted) {
        setState(() => _items[index]['is_completed'] = !newStatus);
        _snack('Ürün durumu güncellenemedi.');
      }
    }
  }

  Future<void> _updateCompletionRate() async {
    try {
      await supabase
          .from('shopping_lists')
          .update({'completion_rate': _completionRate()}).eq(
              'id', widget.listData['id']);
    } catch (e) {
      debugPrint('list_detail: tamamlanma oranı güncellenemedi: $e');
    }
  }

  Future<void> _deleteItem(Map<String, dynamic> item) async {
    final index = _items.indexOf(item);
    if (index == -1) return;
    final name = item['product_name'] ?? 'bir ürün';
    final original = Map<String, dynamic>.from(item);

    HapticFeedback.mediumImpact();
    setState(() => _items.removeAt(index));
    try {
      await supabase.from('list_items').delete().eq('id', item['id']);
      await _updateCompletionRate();
      await _notifyParticipants('$name silindi.');
      if (mounted) _snack('Ürün silindi.');
    } catch (e) {
      if (mounted) {
        setState(() => _items.insert(index, original));
        _snack('Ürün silinemedi.');
      }
    }
  }

  /// Tamamlandı işaretli tüm ürünleri listeden siler (onay ister).
  Future<void> _clearCompleted() async {
    final done = _items.where((i) => i['is_completed'] == true).toList();
    if (done.isEmpty) {
      _snack('Tamamlanmış ürün yok.');
      return;
    }
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Tamamlananları Temizle'),
        content: Text(
            '${done.length} tamamlanmış ürün listeden silinsin mi? '
            'Bu işlem geri alınamaz.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('İptal')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Temizle'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    final ids = done.map((i) => i['id']).toList();
    HapticFeedback.mediumImpact();
    setState(() => _items.removeWhere((i) => i['is_completed'] == true));
    try {
      await supabase.from('list_items').delete().inFilter('id', ids);
      await _updateCompletionRate();
      await _notifyParticipants(
          '${done.length} tamamlanmış ürün temizlendi.');
      if (mounted) _snack('${done.length} ürün temizlendi.');
      await _fetchItems();
    } catch (e) {
      debugPrint('Tamamlananlar temizlenemedi: $e');
      if (mounted) _snack('Temizlenirken bir hata oluştu.', error: true);
      await _fetchItems();
    }
  }

  double _completionRate() {
    if (_items.isEmpty) return 0;
    final done = _items.where((i) => i['is_completed'] == true).length;
    return done / _items.length;
  }

  List<Map<String, dynamic>> get _visibleItems {
    Iterable<Map<String, dynamic>> items = _items;
    if (_hideCompleted) {
      items = items.where((i) => i['is_completed'] != true);
    }
    if (_selectedCategoryFilter != null) {
      items = items.where((i) =>
          (i['category'] as String? ?? '').toLowerCase() ==
          _selectedCategoryFilter!.toLowerCase());
    }
    return items.toList();
  }

  void _snack(String msg, {bool error = false}) {
    if (!mounted) return;
    final scheme = Theme.of(context).colorScheme;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: error ? scheme.error : null,
    ));
  }

  Future<(Uint8List, String)?> _pickImage() async {
    try {
      final picked = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1024,
        imageQuality: 78,
      );
      if (picked == null) return null;
      final bytes = await picked.readAsBytes();
      final ext = picked.name.contains('.')
          ? picked.name.split('.').last.toLowerCase()
          : 'jpg';
      return (bytes, ext);
    } catch (e) {
      debugPrint('Resim seçilemedi: $e');
      if (mounted) _snack('Resim seçilemedi.', error: true);
      return null;
    }
  }

  // --- Ürün ekle / düzenle (alttan açılan sayfa) --------------------------

  Future<void> _itemSheet({Map<String, dynamic>? existing}) async {
    final editing = existing != null;
    final nameCtrl = TextEditingController(
        text: editing ? (existing['product_name'] ?? '') as String : '');
    final marketCtrl = TextEditingController(
        text: editing ? (existing['market'] ?? '') as String : '');
    final tagsCtrl = TextEditingController(
        text: editing && existing['tags'] is List
            ? (existing['tags'] as List).join(', ')
            : '');
    String? category = editing ? existing['category'] as String? : null;
    int qty = editing ? (existing['quantity'] as int? ?? 1) : 1;
    String? currentImageUrl =
        editing ? existing['image_url'] as String? : null;
    Uint8List? newBytes;
    String newExt = 'jpg';

    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        final scheme = Theme.of(ctx).colorScheme;
        return Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
          ),
          child: StatefulBuilder(
            builder: (ctx, setSheet) => SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(editing ? 'Ürünü Düzenle' : 'Ürün Ekle',
                      style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: scheme.onSurface)),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      GestureDetector(
                        onTap: () async {
                          final picked = await _pickImage();
                          if (picked != null) {
                            setSheet(() {
                              newBytes = picked.$1;
                              newExt = picked.$2;
                            });
                          }
                        },
                        child: _sheetThumb(scheme, newBytes, currentImageUrl),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: nameCtrl,
                          autofocus: !editing,
                          textCapitalization: TextCapitalization.sentences,
                          decoration: const InputDecoration(
                              hintText: 'Ürün adı (örn: Süt 1 L)'),
                        ),
                      ),
                    ],
                  ),
                  if (newBytes != null || currentImageUrl != null)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: () => setSheet(() {
                          newBytes = null;
                          currentImageUrl = null;
                        }),
                        icon: const Icon(Icons.close, size: 16),
                        label: const Text('Fotoğrafı kaldır'),
                      ),
                    ),
                  const SizedBox(height: 14),
                  Text('Kategori',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: scheme.onSurfaceVariant)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _predefinedCategories.map((c) {
                      final sel = category == c;
                      return ChoiceChip(
                        label: Text(c),
                        selected: sel,
                        onSelected: (_) =>
                            setSheet(() => category = sel ? null : c),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: marketCtrl,
                    decoration:
                        const InputDecoration(hintText: 'Mağaza (opsiyonel)'),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: tagsCtrl,
                    decoration: const InputDecoration(
                      hintText: 'Etiketler — virgülle ayır (ör: organik, büyük)',
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Text('Adet',
                          style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: scheme.onSurface)),
                      const Spacer(),
                      _QtyStepper(
                        value: qty,
                        onChanged: (v) => setSheet(() => qty = v),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: FilledButton(
                      onPressed: () {
                        if (nameCtrl.text.trim().isEmpty) return;
                        Navigator.pop(ctx, true);
                      },
                      child: Text(editing ? 'Kaydet' : 'Ekle'),
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ),
        );
      },
    );
    if (saved != true) return;

    final name = nameCtrl.text.trim();
    final market = marketCtrl.text.trim();
    final tags = tagsCtrl.text
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();

    // Fotoğraf yükleme
    String? imageUrl = currentImageUrl;
    if (newBytes != null) {
      try {
        imageUrl = await _imageRepo.uploadProductImage(newBytes!,
            extension: newExt);
      } catch (e) {
        debugPrint('Ürün resmi yüklenemedi: $e');
      }
    }

    try {
      if (editing) {
        await _listRepo.updateItem(
          existing['id'] as String,
          productName: name,
          quantity: qty,
          category: category ?? '',
          market: market,
          imageUrl: imageUrl ?? '',
          tags: tags,
        );
        await _notifyParticipants('"$name" güncellendi.');
      } else {
        await supabase.from('list_items').insert({
          'list_id': widget.listData['id'],
          'product_name': name,
          'quantity': qty,
          'market': market.isEmpty ? null : market,
          'category': category,
          'image_url': imageUrl,
          'tags': tags,
          'is_completed': false,
        });
        await _updateCompletionRate();
        await _notifyParticipants('yeni ürün "$name" eklendi.');
      }
      await _fetchItems();
    } catch (e) {
      debugPrint('Ürün kaydedilemedi: $e');
      if (mounted) _snack('Ürün kaydedilemedi.', error: true);
    }
  }

  Widget _sheetThumb(
      ColorScheme scheme, Uint8List? bytes, String? url) {
    if (bytes != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Image.memory(bytes, width: 56, height: 56, fit: BoxFit.cover),
      );
    }
    if (url != null && url.isNotEmpty) {
      return ProductThumb(imageUrl: url, size: 56);
    }
    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        color: scheme.primary.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(Icons.add_a_photo_outlined, color: scheme.primary),
    );
  }

  Future<void> _showShareDialog() async {
    final emailController = TextEditingController();
    final email = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Listeyi Paylaş'),
        content: TextField(
          controller: emailController,
          autofocus: true,
          keyboardType: TextInputType.emailAddress,
          decoration: const InputDecoration(
            hintText: 'ornek@email.com',
            prefixIcon: Icon(Icons.alternate_email),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('İptal')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, emailController.text.trim()),
            child: const Text('Paylaş'),
          ),
        ],
      ),
    );
    if (email == null || email.isEmpty) return;

    try {
      final outcome = await _sharingRepo.shareByEmail(
          listId: widget.listData['id'] as String, email: email);
      if (!mounted) return;
      final (text, ok) = switch (outcome) {
        ShareOutcome.success => ('Liste paylaşıldı.', true),
        ShareOutcome.invalidEmail => ('Geçerli bir e-posta girin.', false),
        ShareOutcome.self => ('Kendi listeni kendinle paylaşamazsın.', false),
        ShareOutcome.userNotFound =>
          ('Bu e-posta ile kayıtlı kullanıcı yok.', false),
        ShareOutcome.alreadyShared =>
          ('Bu liste zaten bu kullanıcıyla paylaşılmış.', false),
      };
      _snack(text, error: !ok);
      if (ok) await _fetchSharedUsers();
    } catch (e) {
      debugPrint('Paylaşım hatası: $e');
      if (mounted) _snack('Liste paylaşılırken bir hata oluştu.', error: true);
    }
  }

  Future<void> _deleteList() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Listeyi Sil'),
        content: const Text(
            'Bu listeyi ve tüm ürünlerini kalıcı olarak silmek istiyor musun? '
            'Bu işlem geri alınamaz.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('İptal')),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: Theme.of(ctx).colorScheme.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Sil'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    try {
      await _listRepo.deleteList(widget.listData['id'] as String);
      if (mounted) {
        _snack('Liste silindi.');
        Navigator.pop(context);
      }
    } catch (e) {
      debugPrint('Liste silinirken hata: $e');
      if (mounted) _snack('Liste silinirken bir hata oluştu.', error: true);
    }
  }

  // ---------------------------------------------------------------------------
  // UI
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final rate = _completionRate();
    final done = _items.where((i) => i['is_completed'] == true).length;
    final visible = _visibleItems;
    final categories = _items
        .map((i) => i['category'] as String?)
        .whereType<String>()
        .where((c) => c.isNotEmpty)
        .toSet()
        .toList();

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(widget.listData['name'] ?? 'Liste'),
        actions: [
          if (_isOwner)
            IconButton(
              icon: const Icon(Icons.person_add_alt_1_outlined),
              tooltip: 'Paylaş',
              onPressed: _showShareDialog,
            ),
          if (_isOwner)
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_horiz),
              onSelected: (v) {
                if (v == 'delete') _deleteList();
                if (v == 'clearDone') _clearCompleted();
              },
              itemBuilder: (_) => [
                const PopupMenuItem(
                  value: 'clearDone',
                  child: Text('Tamamlananları temizle'),
                ),
                const PopupMenuItem(
                  value: 'delete',
                  child: Text('Listeyi Sil'),
                ),
              ],
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'listDetailAddFab',
        onPressed: () => _itemSheet(),
        icon: const Icon(Icons.add),
        label: const Text('Ürün Ekle'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('$done / ${_items.length} ürün',
                          style: TextStyle(
                              color: scheme.primary,
                              fontWeight: FontWeight.w700)),
                      const SizedBox(height: 8),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: LinearProgressIndicator(
                          value: rate,
                          minHeight: 7,
                          backgroundColor: scheme.primary.withValues(alpha: .12),
                          color: scheme.primary,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                PercentRing(value: rate),
              ],
            ),
          ),
          if (_sharedEmails.isNotEmpty || !_isOwner)
            _sharedStrip(scheme),
          const SizedBox(height: 8),
          _filterRow(scheme, categories),
          Expanded(
            child: visible.isEmpty
                ? _emptyItems(scheme)
                : ListView(
                    padding: const EdgeInsets.fromLTRB(20, 6, 20, 100),
                    children: _groupedItemWidgets(scheme, visible),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _sharedStrip(ColorScheme scheme) {
    final people = <String>[
      if (listOwnerEmail.isNotEmpty && listOwnerEmail != 'Bilinmiyor')
        listOwnerEmail,
      ..._sharedEmails,
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
      child: Row(
        children: [
          Icon(Icons.group_outlined, size: 16, color: scheme.onSurfaceVariant),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              people.isEmpty ? 'Bu liste paylaşılmadı.' : people.join(', '),
              style:
                  TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _filterRow(ColorScheme scheme, List<String> categories) {
    return SizedBox(
      height: 44,
      child: Row(
        children: [
          Expanded(
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              children: [
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: const Text('Tümü'),
                    selected: _selectedCategoryFilter == null,
                    onSelected: (_) =>
                        setState(() => _selectedCategoryFilter = null),
                  ),
                ),
                for (final c in categories)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(c),
                      selected: _selectedCategoryFilter == c,
                      onSelected: (s) => setState(
                          () => _selectedCategoryFilter = s ? c : null),
                    ),
                  ),
              ],
            ),
          ),
          IconButton(
            tooltip: _hideCompleted
                ? 'Tamamlananları göster'
                : 'Tamamlananları gizle',
            icon: Icon(
              _hideCompleted ? Icons.filter_list_off : Icons.filter_list,
              color: _hideCompleted ? scheme.primary : scheme.onSurfaceVariant,
            ),
            onPressed: () =>
                setState(() => _hideCompleted = !_hideCompleted),
          ),
          const SizedBox(width: 8),
        ],
      ),
    );
  }

  List<Widget> _groupedItemWidgets(
      ColorScheme scheme, List<Map<String, dynamic>> visible) {
    // Kategoriye göre grupla; kategorisizler "Diğer" altında.
    final groups = <String, List<Map<String, dynamic>>>{};
    for (final item in visible) {
      final cat = (item['category'] as String?)?.trim();
      final key = (cat == null || cat.isEmpty) ? 'Diğer' : cat;
      groups.putIfAbsent(key, () => []).add(item);
    }

    final widgets = <Widget>[];
    groups.forEach((cat, items) {
      widgets.add(Padding(
        padding: const EdgeInsets.fromLTRB(2, 10, 0, 8),
        child: Text(cat,
            style: TextStyle(
                fontWeight: FontWeight.w800, color: scheme.onSurface)),
      ));
      for (final item in items) {
        widgets.add(_itemTile(scheme, item));
      }
    });
    return widgets;
  }

  Widget _itemTile(ColorScheme scheme, Map<String, dynamic> item) {
    final completed = item['is_completed'] == true;
    final qty = item['quantity'] ?? 1;
    final market = item['market'] as String?;
    final category = item['category'] as String?;
    final tags = (item['tags'] as List?)?.cast<String>() ?? const [];
    final meta = [
      if (qty != 1) 'x$qty',
      if (market != null && market.isNotEmpty) market,
      if (tags.isNotEmpty) tags.join(', '),
    ].join(' • ');

    final tile = Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: ListTile(
        onTap: _isOwner ? () => _itemSheet(existing: item) : null,
        contentPadding: const EdgeInsets.fromLTRB(12, 4, 6, 4),
        leading: ProductThumb(
          imageUrl: item['image_url'] as String?,
          emoji: category != null && category.isNotEmpty
              ? categoryEmoji(category)
              : null,
          size: 44,
        ),
        title: Text(
          item['product_name'] ?? '',
          style: TextStyle(
            fontWeight: FontWeight.w600,
            decoration: completed ? TextDecoration.lineThrough : null,
            color:
                completed ? scheme.onSurfaceVariant : scheme.onSurface,
          ),
        ),
        subtitle: meta.isEmpty
            ? null
            : Text(meta,
                style: TextStyle(
                    fontSize: 11.5, color: scheme.onSurfaceVariant)),
        trailing: Checkbox(
          value: completed,
          activeColor: scheme.primary,
          onChanged: (_) => _toggleItemComplete(item),
        ),
      ),
    );

    if (!_isOwner) return tile;
    return Dismissible(
      key: ValueKey(item['id']),
      // Sağa kaydır → tamamlandı işaretle/kaldır, sola kaydır → sil.
      background: Container(
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.only(left: 24, bottom: 8),
        decoration: BoxDecoration(
          color: scheme.primary.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(15),
        ),
        margin: const EdgeInsets.only(bottom: 8),
        child: Icon(
          completed ? Icons.remove_done_rounded : Icons.check_circle_rounded,
          color: scheme.primary,
        ),
      ),
      secondaryBackground: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24, bottom: 8),
        decoration: BoxDecoration(
          color: scheme.error.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(15),
        ),
        margin: const EdgeInsets.only(bottom: 8),
        child: Icon(Icons.delete_outline, color: scheme.error),
      ),
      confirmDismiss: (direction) async {
        if (direction == DismissDirection.startToEnd) {
          await _toggleItemComplete(item);
        } else {
          await _deleteItem(item);
        }
        return false; // listeyi _fetchItems / setState tazeliyor
      },
      child: tile,
    );
  }

  Widget _emptyItems(ColorScheme scheme) {
    if (_items.isEmpty) {
      return EmptyState(
        icon: Icons.shopping_cart_outlined,
        title: 'Liste boş',
        message: _isOwner
            ? 'Sağ alttaki "Ürün Ekle" ile ilk ürünü ekle.'
            : 'Liste sahibi ürün ekleyince burada görünür.',
      );
    }
    return const EmptyState(
      icon: Icons.filter_alt_off_rounded,
      title: 'Filtreye uyan ürün yok',
      message: 'Kategori filtresini ya da "tamamlananları gizle" '
          'seçeneğini değiştir.',
      compact: true,
    );
  }
}

/// − sayı + adet seçici (create_list ile aynı görünüm).
class _QtyStepper extends StatelessWidget {
  const _QtyStepper({required this.value, required this.onChanged});

  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          visualDensity: VisualDensity.compact,
          icon: Icon(Icons.remove, color: scheme.onSurfaceVariant),
          onPressed: value > 1 ? () => onChanged(value - 1) : null,
        ),
        SizedBox(
          width: 24,
          child: Text('$value',
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w700)),
        ),
        IconButton(
          visualDensity: VisualDensity.compact,
          icon: Icon(Icons.add, color: scheme.primary),
          onPressed: () => onChanged(value + 1),
        ),
      ],
    );
  }
}
