import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:async';
import 'package:intl/intl.dart'; // For date formatting
import 'package:dropdown_button2/dropdown_button2.dart'; // For enhanced dropdowns

import '../repositories/list_repository.dart';
import '../repositories/sharing_repository.dart';

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
  late String currentUserId;
  String listOwnerEmail = '';
  List<Map<String, dynamic>> _items = [];
  List<String> _sharedEmails = [];
  bool _hideCompleted = false;
  bool _isChanged = false; // To track if changes need saving
  RealtimeChannel? _itemsChannel; // Items için mevcut kanal
  RealtimeChannel? _listCompletionChannel; // Yeni: Liste tamamlanma oranı için kanal
  // Timer? _debounce; // Debounce'ı test amaçlı kaldırdık

  // New state variables for filtering
  String? _selectedMarketFilter;
  String? _selectedCategoryFilter;
  List<String> _availableMarkets = ['Tümü']; // 'All' option
  // Önceden tanımlanmış kategori listesi
  final List<String> _predefinedCategories = [
    'Tümü', // 'All' option
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

  @override
  void initState() {
    super.initState();
    currentUserId = supabase.auth.currentSession!.user.id;
    _checkAccessAndInitialize();
  }

  Future<void> _checkAccessAndInitialize() async {
    final listId = widget.listData['id'];
    final hasAccess = await _checkUserHasAccess(listId, currentUserId);
    if (!hasAccess) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Bu listeye erişim hakkınız yok.')),
        );
        Navigator.pop(context); // Go back if no access
      }
      return;
    }

    // Liste Adını çek, eğer listData içinde yoksa (Popüler Kategoriler gibi durumlarda)
    if (widget.listData['name'] == null || widget.listData['name'].isEmpty) {
      final listInfoResponse = await supabase
          .from('shopping_lists')
          .select('name')
          .eq('id', widget.listData['id'])
          .maybeSingle();

      if (listInfoResponse != null && mounted) {
        setState(() {
          widget.listData['name'] = listInfoResponse['name']; // listData'yı güncelle
        });
      }
    }

    // Fetch owner information
    await _fetchListOwnerEmail(widget.listData['user_id'] as String);

    // Initialize items, shared users and realtime subscription
    await _fetchItems();
    await _fetchSharedUsers();
    _subscribeToRealtimeItems(); // Ürünler için realtime dinleyiciyi başlat
    _setupCompletionRateRealtimeListener(); // Yeni: Tamamlanma oranı için realtime dinleyiciyi başlat
  }

  Future<bool> _checkUserHasAccess(String listId, String userId) async {
    // 1) Is owner?
    final listRes = await supabase
        .from('shopping_lists')
        .select('user_id')
        .eq('id', listId)
        .maybeSingle();
    if (listRes != null && listRes['user_id'] == userId) return true;

    // 2) Is a shared user?
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
      setState(() {
        listOwnerEmail = res?['email'] ?? 'Bilinmiyor';
      });
    }
  }

  @override
  void dispose() {
    // _debounce?.cancel(); // Debounce kaldırıldığı için iptale gerek yok
    _itemsChannel?.unsubscribe(); 
    _listCompletionChannel?.unsubscribe(); 
    super.dispose();
  }

  // Ürünler (list_items) için gerçek zamanlı dinleyici
  void _subscribeToRealtimeItems() {
    _itemsChannel = supabase
        .channel('public:list_items_detail_page_items') // Benzersiz kanal adı
        .onPostgresChanges(
          event: PostgresChangeEvent.update, 
          schema: 'public',
          table: 'list_items',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq, 
            column: 'list_id', 
            value: widget.listData['id'], 
          ),
          callback: (payload) {
            debugPrint('list_detail Realtime: list_items UPDATE event received for list ID: ${widget.listData['id']}.');
            debugPrint('  New record: ${payload.newRecord}');
            _fetchItems(); // Değişiklik olduğunda öğeleri yeniden çek
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.insert, 
          schema: 'public',
          table: 'list_items',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'list_id',
            value: widget.listData['id'],
          ),
          callback: (payload) {
            debugPrint('list_detail Realtime: list_items INSERT event received for list ID: ${widget.listData['id']}.');
            debugPrint('  New record: ${payload.newRecord}');
            _fetchItems(); 
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.delete, 
          schema: 'public',
          table: 'list_items',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'list_id',
            value: widget.listData['id'],
          ),
          callback: (payload) {
            debugPrint('list_detail Realtime: list_items DELETE event received for list ID: ${widget.listData['id']}.');
            debugPrint('  Old record: ${payload.oldRecord}');
            _fetchItems(); 
          },
        )
        .subscribe();

        debugPrint('list_detail Realtime listener subscribed for list_items on list ID: ${widget.listData['id']}.');
  }

  // Yeni: Tamamlanma oranı (shopping_lists) için gerçek zamanlı dinleyici
  void _setupCompletionRateRealtimeListener() {
    _listCompletionChannel = supabase
        .channel('public:shopping_lists_detail_page_completion_rate') // Benzersiz kanal adı
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'shopping_lists',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'id', // Listenin ID'sini filtrele
            value: widget.listData['id'],
          ),
          callback: (payload) {
            debugPrint('list_detail Realtime: shopping_lists UPDATE event received for completion_rate on list ID: ${widget.listData['id']}.');
            debugPrint('  New record (completion_rate): ${payload.newRecord}');
            if (mounted) {
              setState(() {
                // Burada _items listesini doğrudan güncellemeyeceğiz, çünkü _itemsChannel zaten bunu yapacak.
                // Sadece UI'ın yeniden çizilmesi için setState'i tetiklemek yeterli.
                // _completionRate() getter'ı, her çizimde _items'ın güncel durumuna göre yeniden hesaplanacaktır.
                debugPrint('list_detail: Completion rate UI update triggered by shopping_lists event. New rate: ${(payload.newRecord['completion_rate'] as num?)?.toDouble() ?? 0.0}');
              });
            }
          },
        )
        .subscribe();
    debugPrint('list_detail Realtime listener subscribed for shopping_lists completion_rate on list ID: ${widget.listData['id']}.');
  }


  Future<void> _fetchItems() async {
    debugPrint('list_detail: _fetchItems() called for list ID: ${widget.listData['id']}.');
    try {
      final response = await supabase
          .from('list_items')
          .select('*') 
          .eq('list_id', widget.listData['id'])
          .order('created_at', ascending: true); 

      if (mounted) {
        setState(() {
          _items = List<Map<String, dynamic>>.from(response as List);
          debugPrint('list_detail: _items state updated. Now has ${_items.length} items.');

          // Populate available markets for filters (categories use predefined now)
          Set<String> markets = {'Tümü'};
          for (var item in _items) {
            if (item['market'] != null && (item['market'] as String).isNotEmpty) {
              markets.add(item['market'] as String);
            }
          }
          _availableMarkets = markets.toList();
          // _fetchItems çağrıldığında tamamlanma oranını da hemen güncelleyelim.
          // Bu, `list_items` tablosundaki bir değişiklikten sonra completion rate'in UI'da hemen güncellenmesini sağlar.
          // Zaten `_updateCompletionRate` çağrılıyor, ama bu setState'i tetikler ve UI'ı çizdirir.
          // Eğer _updateCompletionRate() hemen çağrılmazsa, UI'da değişim hemen görülmeyebilir.
          // Ancak dikkat: _updateCompletionRate() içindeki db çağrısı zaten Realtime eventini tetikleyecektir.
          // Buradaki setState sadece _items değiştiğinde UI'ın yenilenmesini sağlar.
          final newRate = _completionRate();
          debugPrint('list_detail: _fetchItems() completed, calculated completion rate: ${newRate * 100}%');
        });
      }
    } catch (e) {
      debugPrint('list_detail: Error fetching items: $e');
    }
  }

  Future<void> _fetchSharedUsers() async {
    debugPrint('list_detail: _fetchSharedUsers() called for list ID: ${widget.listData['id']}.');
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
          debugPrint('list_detail: Shared emails updated. Now has ${_sharedEmails.length} shared users.');
        });
      }
    } catch (e) {
      debugPrint('list_detail: Error fetching shared users: $e');
    }
  }

  /// Listedeki diğer katılımcılara bildirim yazar. İş sunucudaki
  /// `notify_list_participants` fonksiyonunda yapılır (erişim kontrolü +
  /// çağıran hariç herkese insert). Başarısızlık sessizce yutulur.
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


  Future<void> _toggleItemComplete(int index) async {
    final item = _items[index];
    final updatedStatus = !(item['is_completed'] ?? false);
    final String productName = item['product_name'] ?? 'bir ürün';
    
    // Optimistic update (UI'ı hemen güncelle)
    setState(() {
      _items[index]['is_completed'] = updatedStatus;
      _isChanged = true;
      debugPrint('list_detail: Optimistically updated item "$productName" to completed: $updatedStatus.');
    });

    try {
      await supabase
          .from('list_items')
          .update({'is_completed': updatedStatus})
          .eq('id', item['id']);
      debugPrint('list_detail: Database update successful for item "$productName".');
      
      // Tamamlama oranını güncelle - debounce kaldırıldı
      await _updateCompletionRate(); 

      // Bildirim gönder
      final String notificationMessage = updatedStatus ? '$productName tamamlandı.' : '$productName tamamlanmadı olarak işaretlendi.';
      await _notifyParticipants(notificationMessage);

    } catch (e) {
      // Hata durumunda eski durumu geri al
      if (mounted) {
        setState(() {
          _items[index]['is_completed'] = !updatedStatus; // Eskiye geri dön
          _isChanged = true; // Hata oluşsa bile değişiklik var say
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ürün durumu güncellenemedi: $e')),
        );
        debugPrint('list_detail: Error updating item "$productName". Reverting optimistic update. Error: $e');
      }
    }
  }

  Future<void> _updateCompletionRate() async {
    final rate = _completionRate();
    debugPrint('list_detail: Attempting to update completion_rate for list ID: ${widget.listData['id']} to $rate');
    try {
      final response = await supabase
          .from('shopping_lists')
          .update({'completion_rate': rate})
          .eq('id', widget.listData['id'])
          .select(); // Güncellenen kaydı döndürsün, hata ayıklama için
      debugPrint('list_detail: Completion rate update response: $response');
    } on PostgrestException catch (e) {
      debugPrint('list_detail: PostgrestException during completion rate update: ${e.message}');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Tamamlama oranı güncellenirken veritabanı hatası: ${e.message}')),
        );
      }
    } catch (e) {
      debugPrint('list_detail: Error during completion rate update: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Tamamlama oranı güncellenirken beklenmedik hata: $e')),
        );
      }
    }
  }

  Future<void> _deleteItem(int index) async {
    final itemId = _items[index]['id'];
    final String productName = _items[index]['product_name'] ?? 'bir ürün';

    // Optimistic deletion
    final originalItem = _items[index];
    setState(() {
      _items.removeAt(index);
      _isChanged = true;
      debugPrint('list_detail: Optimistically deleted item "$productName".');
    });

    try {
      await supabase.from('list_items').delete().eq('id', itemId);
      debugPrint('list_detail: Database delete successful for item "$productName".');
      await _updateCompletionRate(); // Silme sonrası oranı güncelle
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Ürün silindi!')),
        );
      }
      // Bildirim gönder
      await _notifyParticipants('$productName silindi.');

    } catch (e) {
      // Hata durumunda geri al
      if (mounted) {
        setState(() {
          _items.insert(index, originalItem); // Eski konuma geri ekle
          _isChanged = true; // Hata oluşsa bile değişiklik var say
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ürün silinemedi: $e')),
        );
        debugPrint('list_detail: Error deleting item "$productName". Reverting optimistic delete. Error: $e');
      }
    }
  }

  double _completionRate() {
    if (_items.isEmpty) {
      debugPrint('list_detail: _completionRate() called. Items list is empty. Returning 0.');
      return 0;
    }
    final completedCount =
        _items.where((item) => item['is_completed'] == true).length;
    final rate = completedCount / _items.length;
    debugPrint('list_detail: _completionRate() calculated: Completed $completedCount out of ${_items.length} items. Rate: $rate');
    return rate;
  }

  List<Map<String, dynamic>> get _visibleItems {
    Iterable<Map<String, dynamic>> filteredItems = _items;

    if (_hideCompleted) {
      filteredItems = filteredItems.where((item) => item['is_completed'] != true);
    }
    // Apply market filter
    if (_selectedMarketFilter != null && _selectedMarketFilter != 'Tümü') {
      filteredItems = filteredItems.where((item) =>
          (item['market'] as String? ?? '').toLowerCase() ==
          _selectedMarketFilter!.toLowerCase());
    }
    // Apply category filter
    if (_selectedCategoryFilter != null && _selectedCategoryFilter != 'Tümü') {
      filteredItems = filteredItems.where((item) =>
          (item['category'] as String? ?? '').toLowerCase() ==
          _selectedCategoryFilter!.toLowerCase());
    }
    return filteredItems.toList();
  }

  Future<void> _editItemDialog(int index) async {
    final item = _items[index];
    final nameCtrl =
        TextEditingController(text: (item['product_name'] ?? '') as String);
    final qtyCtrl =
        TextEditingController(text: '${item['quantity'] ?? 1}');
    final marketCtrl =
        TextEditingController(text: (item['market'] ?? '') as String);
    final tagsCtrl = TextEditingController(
        text: (item['tags'] is List)
            ? (item['tags'] as List).join(', ')
            : '');

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Ürünü düzenle'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(labelText: 'Ürün adı'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: qtyCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Miktar'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: marketCtrl,
                decoration:
                    const InputDecoration(labelText: 'Mağaza (opsiyonel)'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: tagsCtrl,
                decoration: const InputDecoration(
                    labelText: 'Etiketler (virgülle ayır)'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('İptal')),
          ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Kaydet')),
        ],
      ),
    );
    if (saved != true) return;

    final name = nameCtrl.text.trim();
    if (name.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Ürün adı boş olamaz.')),
        );
      }
      return;
    }

    try {
      await _listRepo.updateItem(
        item['id'] as String,
        productName: name,
        quantity: int.tryParse(qtyCtrl.text.trim()) ?? 1,
        market: marketCtrl.text.trim(),
        tags: tagsCtrl.text
            .split(',')
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .toList(),
      );
      await _fetchItems();
      await _notifyParticipants('"$name" güncellendi.');
    } catch (e) {
      debugPrint('Ürün güncellenemedi: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Ürün güncellenemedi.')),
        );
      }
    }
  }

  Future<void> _addNewItemDialog() async {
    final nameController = TextEditingController();
    final quantityController = TextEditingController(text: '1'); // Default quantity
    final marketController = TextEditingController();
    String? selectedCategoryInDialog; // New variable for category selection in dialog
    final tagsController = TextEditingController();

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Yeni Ürün Ekle', style: TextStyle(fontWeight: FontWeight.bold)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: InputDecoration(
                  labelText: 'Ürün Adı',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                ),
                autofocus: true, // Auto focus keyboard
              ),
              const SizedBox(height: 16),
              TextField(
                controller: quantityController,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: 'Miktar',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: marketController,
                decoration: InputDecoration(
                  labelText: 'Mağaza (Opsiyonel)',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
              const SizedBox(height: 16),
              // Kategori seçimi için DropdownButton2 kullanıldı
              DropdownButtonHideUnderline(
                child: DropdownButton2<String>(
                  isExpanded: true,
                  hint: Text(
                    'Kategori Seç (Opsiyonel)',
                    style: TextStyle(
                      fontSize: 14,
                      color: Theme.of(context).hintColor,
                    ),
                  ),
                  items: _predefinedCategories.where((cat) => cat != 'Tümü').map((category) => // 'Tümü' seçeneğini burada gösterme
                      DropdownMenuItem(value: category, child: Text(category))).toList(),
                  value: selectedCategoryInDialog,
                  onChanged: (value) {
                    setState(() { // AlertDialog'un setState'ini kullanarak güncelle
                      selectedCategoryInDialog = value;
                    });
                  },
                  buttonStyleData: ButtonStyleData(
                    padding: const EdgeInsets.only(left: 14, right: 14),
                    height: 40,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10), // Yuvarlak köşeler
                      border: Border.all(color: Colors.grey.shade400), // Kenarlık
                      color: Theme.of(context).colorScheme.surface,
                    ),
                  ),
                  menuItemStyleData: const MenuItemStyleData(
                    height: 40,
                  ),
                  dropdownStyleData: DropdownStyleData( // Dropdown menü stilini güncelle
                    maxHeight: 200,
                    width: 200,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      color: Theme.of(context).colorScheme.surface,
                    ),
                    offset: const Offset(0, 0),
                    scrollbarTheme: ScrollbarThemeData(
                      radius: const Radius.circular(40),
                      thickness: WidgetStateProperty.all(6),
                      thumbVisibility: WidgetStateProperty.all(true),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: tagsController,
                decoration: InputDecoration(
                  labelText: 'Etiketler (Virgülle Ayırın, Opsiyonel)',
                  hintText: 'örn: kahvaltılık, gluten-free',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('İptal', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () async {
              final name = nameController.text.trim();
              final quantity = int.tryParse(quantityController.text.trim()) ?? 1;
              final market = marketController.text.trim().isNotEmpty ? marketController.text.trim() : null;
              final category = selectedCategoryInDialog; // Diyalogdan seçilen kategori
              final tags = tagsController.text.trim().isNotEmpty
                  ? tagsController.text.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList()
                  : null;

              if (name.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Ürün adı boş olamaz!')),
                );
                return;
              }
              final newItem = {
                'list_id': widget.listData['id'],
                'product_name': name,
                'quantity': quantity,
                'market': market,
                'category': category,
                'tags': tags, // Store tags as a List of strings
                'is_completed': false,
                'created_at': DateTime.now().toIso8601String(),
              };
              try {
                final response = await supabase
                    .from('list_items')
                    .insert(newItem)
                    .select(); // Return the inserted item
                if (mounted) {
                  setState(() {
                    _items.add((response as List).first);
                    _isChanged = true;
                    // Market filtre seçeneklerini güncelle
                    if (market != null && !_availableMarkets.contains(market)) {
                      _availableMarkets.add(market);
                    }
                    // Kategoriler zaten sabit olduğu için _availableCategories'i güncellemeye gerek yok.
                  });
                  Navigator.pop(context);
                  await _updateCompletionRate(); // Update rate after new item added
                }
                // Bildirim gönder
                await _notifyParticipants('"$name" adlı yeni bir ürün eklendi.');
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Ürün eklenemedi: $e')),
                  );
                }
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).primaryColor,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('Ekle'),
          ),
        ],
      ),
    );
  }

  Future<void> _showShareDialog() async {
    final emailController = TextEditingController();
    final email = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Listeyi Paylaş',
            style: TextStyle(fontWeight: FontWeight.bold)),
        content: TextField(
          controller: emailController,
          autofocus: true,
          keyboardType: TextInputType.emailAddress,
          decoration: InputDecoration(
            labelText: 'Kullanıcının e-posta adresi',
            hintText: 'ornek@email.com',
            prefixIcon: const Icon(Icons.alternate_email),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('İptal', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, emailController.text.trim()),
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).primaryColor,
              foregroundColor: Colors.white,
            ),
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
        ShareOutcome.self =>
          ('Kendi listeni kendinle paylaşamazsın.', false),
        ShareOutcome.userNotFound =>
          ('Bu e-posta ile kayıtlı kullanıcı yok.', false),
        ShareOutcome.alreadyShared =>
          ('Bu liste zaten bu kullanıcıyla paylaşılmış.', false),
      };
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(text),
        backgroundColor: ok ? Colors.green : Colors.red.shade400,
      ));
      if (ok) await _fetchSharedUsers();
    } catch (e) {
      debugPrint('Paylaşım hatası: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Liste paylaşılırken bir hata oluştu.')),
        );
      }
    }
  }

  Future<void> _deleteList() async {
    // Add confirmation dialog
    final confirmDelete = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Listeyi Sil', style: TextStyle(fontWeight: FontWeight.bold)),
            content: const Text('Bu listeyi ve tüm ürünlerini kalıcı olarak silmek istediğinizden emin misiniz? Bu işlem geri alınamaz.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('İptal', style: TextStyle(color: Colors.grey)),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red, // Red for delete button
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                child: const Text('Sil'),
              ),
            ],
          ),
        ) ??
        false;

    if (!confirmDelete) return;

    try {
      // list_items + shared_lists, ON DELETE CASCADE ile bağlı: tek silme yeter.
      await _listRepo.deleteList(widget.listData['id'] as String);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Liste silindi.')),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      debugPrint('Liste silinirken hata: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Liste silinirken bir hata oluştu.')),
        );
      }
    }
  }

  Future<void> _showSaveChangesDialog() async {
    // Only show save dialog for lists owned by the current user
    final isOwner = widget.listData['user_id'] == currentUserId;

    if (!_isChanged || !isOwner) {
      if (!isOwner && _isChanged) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Paylaşılan listelerde ürün tamamlanma durumu otomatik kaydedilir. Diğer değişiklikler kaydedilemez.')),
        );
      } else if (!isOwner && !_isChanged) {
        // Nothing changed and not owner, no need to show notification.
      } else { // Owner and changed but not saved
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Kaydedilecek bir değişiklik bulunmuyor.')),
        );
      }
      return;
    }

    final shouldSave = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Değişiklikler Kaydedilsin mi?', style: TextStyle(fontWeight: FontWeight.bold)),
            content: const Text('Yaptığınız değişiklikleri kaydetmek ister misiniz?'),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Hayır', style: TextStyle(color: Colors.grey))),
              ElevatedButton(
                  onPressed: () => Navigator.pop(context, true),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).primaryColor,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  child: const Text('Evet')),
            ],
          ),
        ) ??
        false;
    if (shouldSave) {
      await _updateCompletionRate(); // Update completion rate
      if (mounted) {
        setState(() {
          _isChanged = false; // Reset changed status
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Değişiklikler kaydedildi!')),
        );
      }
    }
  }

  // ---------------------------------------------------------------------------
  // UI
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isOwner = widget.listData['user_id'] == currentUserId;
    final rate = _completionRate();
    final done = _items.where((i) => i['is_completed'] == true).length;

    final visible = _visibleItems;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.listData['name'] ?? 'Liste',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        actions: [
          if (isOwner)
            IconButton(
              icon: const Icon(Icons.person_add_alt_1_outlined),
              tooltip: 'Paylaş',
              onPressed: _showShareDialog,
            ),
          if (isOwner)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Listeyi Sil',
              onPressed: _deleteList,
            ),
          if (isOwner || _isChanged)
            IconButton(
              icon: Icon(_isChanged ? Icons.save : Icons.save_alt_outlined),
              tooltip: 'Kaydet',
              onPressed: _showSaveChangesDialog,
            ),
        ],
      ),
      floatingActionButton: isOwner
          ? FloatingActionButton.extended(
              heroTag: 'listDetailAddFab',
              onPressed: _addNewItemDialog,
              icon: const Icon(Icons.add),
              label: const Text('Ürün ekle'),
            )
          : null,
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
        children: [
          _progressCard(scheme, rate, done),
          if (_sharedEmails.isNotEmpty || !isOwner) ...[
            const SizedBox(height: 12),
            _sharedCard(scheme),
          ],
          const SizedBox(height: 16),
          _filterBar(scheme),
          const SizedBox(height: 12),
          if (visible.isEmpty)
            _emptyItems(scheme)
          else
            ...visible.map((item) => _itemTile(scheme, item, isOwner)),
        ],
      ),
    );
  }

  Widget _progressCard(ColorScheme scheme, double rate, int done) {
    final pct = (rate * 100).round();
    String created = '';
    try {
      created = DateFormat('dd MMMM yyyy', 'tr_TR')
          .format(DateTime.parse(widget.listData['created_at']));
    } catch (_) {}

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            scheme.primary,
            Color.lerp(scheme.primary, Colors.black, 0.3)!
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('%$pct',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 30,
                      fontWeight: FontWeight.bold)),
              const SizedBox(width: 12),
              Expanded(
                child: Text('$done / ${_items.length} ürün alındı',
                    style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.9),
                        fontSize: 13)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: rate,
              minHeight: 8,
              backgroundColor: Colors.white.withValues(alpha: 0.25),
              valueColor:
                  const AlwaysStoppedAnimation<Color>(Colors.white),
            ),
          ),
          if (created.isNotEmpty) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(Icons.calendar_today,
                    size: 13, color: Colors.white.withValues(alpha: 0.85)),
                const SizedBox(width: 6),
                Text(created,
                    style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.85),
                        fontSize: 12)),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _sharedCard(ColorScheme scheme) {
    final people = <String>[
      if (listOwnerEmail.isNotEmpty && listOwnerEmail != 'Bilinmiyor')
        listOwnerEmail,
      ..._sharedEmails,
    ];
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(14),
        border:
            Border.all(color: scheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          Icon(Icons.group_outlined, size: 18, color: scheme.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              people.isEmpty
                  ? 'Bu liste kimseyle paylaşılmadı.'
                  : people.join(', '),
              style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _filterBar(ColorScheme scheme) {
    final markets =
        _availableMarkets.where((m) => m != 'Tümü').toList();
    final categories = _items
        .map((i) => i['category'] as String?)
        .whereType<String>()
        .where((c) => c.isNotEmpty)
        .toSet()
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Ürünler (${_items.length})',
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: scheme.onSurface)),
            Row(
              children: [
                Text('Tamamlananları gizle',
                    style: TextStyle(
                        fontSize: 12, color: scheme.onSurfaceVariant)),
                Switch(
                  value: _hideCompleted,
                  onChanged: (v) => setState(() => _hideCompleted = v),
                ),
              ],
            ),
          ],
        ),
        if (markets.isNotEmpty || categories.isNotEmpty)
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final c in categories)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: FilterChip(
                      label: Text(c),
                      selected: _selectedCategoryFilter == c,
                      onSelected: (s) => setState(() =>
                          _selectedCategoryFilter = s ? c : null),
                    ),
                  ),
                for (final m in markets)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: FilterChip(
                      avatar: const Icon(Icons.storefront, size: 16),
                      label: Text(m),
                      selected: _selectedMarketFilter == m,
                      onSelected: (s) => setState(
                          () => _selectedMarketFilter = s ? m : null),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _emptyItems(ColorScheme scheme) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(16),
        border:
            Border.all(color: scheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Column(
        children: [
          Icon(Icons.shopping_cart_outlined,
              size: 44, color: scheme.primary),
          const SizedBox(height: 10),
          Text(
            _items.isEmpty
                ? 'Bu listede henüz ürün yok.'
                : 'Filtreye uyan ürün yok.',
            style: TextStyle(color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  Widget _itemTile(
      ColorScheme scheme, Map<String, dynamic> item, bool isOwner) {
    final realIndex = _items.indexOf(item);
    final completed = item['is_completed'] == true;
    final quantity = item['quantity'] ?? 1;
    final market = item['market'] as String?;
    final category = item['category'] as String?;
    final tags = (item['tags'] as List?)?.cast<String>() ?? const [];

    final meta = [
      'x$quantity',
      if (category != null && category.isNotEmpty) category,
      if (market != null && market.isNotEmpty) market,
    ].join(' • ');

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 5),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 6, 4, 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Checkbox(
              value: completed,
              onChanged: (isOwner || !completed)
                  ? (_) => _toggleItemComplete(realIndex)
                  : null,
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item['product_name'] ?? '',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      decoration:
                          completed ? TextDecoration.lineThrough : null,
                      color: completed
                          ? scheme.onSurfaceVariant
                          : scheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(meta,
                      style: TextStyle(
                          fontSize: 12, color: scheme.onSurfaceVariant)),
                  if (tags.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: tags
                            .map((t) => Chip(
                                  label: Text(t,
                                      style: const TextStyle(fontSize: 10)),
                                  visualDensity: VisualDensity.compact,
                                  materialTapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                  padding: EdgeInsets.zero,
                                ))
                            .toList(),
                      ),
                    ),
                ],
              ),
            ),
            if (isOwner) ...[
              IconButton(
                visualDensity: VisualDensity.compact,
                icon: Icon(Icons.edit_outlined,
                    size: 20, color: scheme.onSurfaceVariant),
                tooltip: 'Düzenle',
                onPressed: () => _editItemDialog(realIndex),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                icon: Icon(Icons.delete_outline,
                    size: 20, color: scheme.error),
                tooltip: 'Sil',
                onPressed: () => _deleteItem(realIndex),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
