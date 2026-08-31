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
                      color: Colors.white,
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
                      color: Colors.white,
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

  Widget buildSharedListInfoSection(MaterialColor themePrimaryColor) {
    final bool isOwner = widget.listData['user_id'] == currentUserId;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withValues(alpha: 0.1),
            spreadRadius: 1,
            blurRadius: 5,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.person_outline, size: 20, color: themePrimaryColor),
              const SizedBox(width: 8),
              const Text("Liste Sahibi:", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.black87)),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(left: 28.0),
            child: Text(
              listOwnerEmail,
              style: TextStyle(fontSize: 14, color: Colors.grey.shade700),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(Icons.group_outlined, size: 20, color: themePrimaryColor),
              const SizedBox(width: 8),
              const Text("Paylaşılan Kullanıcılar:", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.black87)),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(left: 28.0),
            child: _sharedEmails.isEmpty
                ? Text('Bu liste henüz kimseyle paylaşılmadı.', style: TextStyle(fontSize: 14, color: Colors.grey.shade700))
                : Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: _sharedEmails.map((email) => Chip(
                      label: Text(
                        email,
                        style: TextStyle(color: themePrimaryColor.shade700, fontSize: 12),
                        overflow: TextOverflow.ellipsis, // Added to prevent overflow
                      ),
                      backgroundColor: themePrimaryColor.shade50,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                      side: BorderSide(color: themePrimaryColor.shade200),
                    )).toList(),
                  ),
          ),
          if (!isOwner) // If not owner, show who shared this list
            Padding(
              padding: const EdgeInsets.only(top: 12.0),
              child: Row(
                children: [
                  const Icon(Icons.info_outline, size: 18, color: Colors.blueGrey),
                  const SizedBox(width: 5),
                  Text(
                    'Bu liste sizinle "$listOwnerEmail" tarafından paylaşıldı.',
                    style: TextStyle(fontSize: 13, color: Colors.blueGrey.shade700, fontStyle: FontStyle.italic),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // customPrimarySwatch'i burada kullanabiliriz
    final MaterialColor primaryColor = (Theme.of(context).primaryColor is MaterialColor)
        ? (Theme.of(context).primaryColor as MaterialColor)
        : Colors.teal;

    final bool isOwner = widget.listData['user_id'] == currentUserId;

    final createdAt = DateTime.tryParse(widget.listData['created_at'] ?? '');
    final String listMarketName = widget.listData['market'] ?? 'Bilinmiyor'; // Mağaza bilgisini al
    final String listCategoryName = widget.listData['category'] ?? 'Genel'; // Kategori bilgisini al

    // Tamamlanma oranını her build çağrısında yeniden hesapla (veya _listCompletionChannel'dan gelenle UI'ı tetikle)
    final double currentCompletionRate = _completionRate();
    debugPrint('list_detail: Current completion rate for UI: ${currentCompletionRate * 100}% at build time.');


    return Scaffold(
      backgroundColor: Colors.grey[50], // Daha açık arka plan
      appBar: AppBar( // Standart AppBar'a geri döndük
        title: Text(
          widget.listData['name'] ?? 'Liste Detayı',
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        backgroundColor: primaryColor, // Temanın ana rengini kullan
        elevation: 0, // AppBar'ın gölgesini kaldır
        centerTitle: true,
        actions: [
          if (isOwner) // Sadece sahip ise paylaşma ve silme butonlarını göster
            IconButton(
              icon: const Icon(Icons.share, color: Colors.white),
              tooltip: 'Listeyi Paylaş',
              onPressed: _showShareDialog,
            ),
          if (isOwner)
            IconButton(
              icon: const Icon(Icons.delete_forever, color: Colors.white),
              tooltip: 'Listeyi Sil',
              onPressed: _deleteList,
            ),
          // Paylaşılan listelerde değişiklik kaydetme butonu gizlendi
          if (isOwner || _isChanged) // Sadece sahibi ise veya paylaşılan listelerde completion değiştiyse kaydet
            IconButton(
              icon: Icon(_isChanged ? Icons.save : Icons.save_alt_outlined, color: Colors.white),
              tooltip: 'Değişiklikleri Kaydet',
              onPressed: _showSaveChangesDialog,
            ),
        ],
      ),
      body: SingleChildScrollView( // Wrapped with SingleChildScrollView to prevent bottom overflow
        padding: const EdgeInsets.symmetric(horizontal: 16), // Sadece yatay dolgu bırakıldı
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // İlk boşluk kaldırıldı çünkü AppBar'ın varsayılan boşluğu yeterli
            // const SizedBox(height: 16), // Bu boşluk kaldırıldı
            
            // Liste Genel Bilgileri Kartı
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: primaryColor.shade50, // Açık tonu
                borderRadius: BorderRadius.circular(15),
                boxShadow: [
                  BoxShadow(
                    color: Colors.grey.withValues(alpha: 0.1),
                    spreadRadius: 1,
                    blurRadius: 5,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.calendar_today, size: 18, color: primaryColor.shade700),
                      const SizedBox(width: 8),
                      Text(
                        'Oluşturulma Tarihi: ${createdAt != null ? DateFormat('dd MMMEEEE', 'tr_TR').format(createdAt) : 'Bilinmiyor'}',
                        style: TextStyle(fontSize: 14, color: Colors.grey.shade700),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(Icons.storefront, size: 18, color: primaryColor.shade700),
                      const SizedBox(width: 8),
                      Text(
                        'Liste Mağazası: $listMarketName', // Mağaza bilgisini göster
                        style: TextStyle(fontSize: 14, color: Colors.grey.shade700),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                   Row(
                    children: [
                      Icon(Icons.category, size: 18, color: primaryColor.shade700),
                      const SizedBox(width: 8),
                      Text(
                        'Liste Kategorisi: $listCategoryName', // Kategori bilgisini göster
                        style: TextStyle(fontSize: 14, color: Colors.grey.shade700),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Tamamlanma Oranı: %${(currentCompletionRate * 100).round()}', // Yeni değer
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.grey.shade800),
                  ),
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: LinearProgressIndicator(
                      value: currentCompletionRate, // Yeni değer
                      backgroundColor: Colors.grey[300],
                      color: primaryColor, // Ana renk
                      minHeight: 12,
                    ),
                  ),
                ],
              ),
            ),
            
            // Sahip ve Paylaşılanlar Bilgisi (ayrı bir kartta)
            buildSharedListInfoSection(primaryColor),

            const SizedBox(height: 16),
            // Tamamlananları Gizle Seçeneği
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(15),
                boxShadow: [
                  BoxShadow(
                    color: Colors.grey.withValues(alpha: 0.1),
                    spreadRadius: 1,
                    blurRadius: 5,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Tamamlanan Ürünleri Gizle',
                    style: TextStyle(fontSize: 16, color: Colors.grey.shade800),
                  ),
                  Switch.adaptive( // Platforma uygun switch
                    value: _hideCompleted,
                    onChanged: (v) => setState(() => _hideCompleted = v),
                    activeColor: primaryColor,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16), // Filtreleme alanı ile ürün başlığı arasına boşluk

            // Filtering Section for Items
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(15),
                boxShadow: [
                  BoxShadow(
                    color: Colors.grey.withValues(alpha: 0.1),
                    spreadRadius: 1,
                    blurRadius: 5,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Filtreleme Seçenekleri', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton2<String>(
                            isExpanded: true,
                            hint: Text(
                              'Mağazaya Göre Filtrele',
                              style: TextStyle(
                                fontSize: 14,
                                color: Theme.of(context).hintColor,
                              ),
                            ),
                            items: _availableMarkets.map((market) =>
                                DropdownMenuItem(value: market, child: Text(market))).toList(),
                            value: _selectedMarketFilter,
                            onChanged: (value) {
                              setState(() {
                                _selectedMarketFilter = value;
                              });
                            },
                            buttonStyleData: ButtonStyleData(
                              padding: const EdgeInsets.only(left: 14, right: 14),
                              height: 40,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(color: Colors.black26),
                                color: Colors.white,
                              ),
                            ),
                            menuItemStyleData: const MenuItemStyleData(
                              height: 40,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton2<String>(
                            isExpanded: true,
                            hint: Text(
                              'Kategoriye Göre Filtrele',
                              style: TextStyle(
                                fontSize: 14,
                                color: Theme.of(context).hintColor,
                              ),
                            ),
                            // Filtreleme için önceden tanımlı kategorileri kullan
                            items: _predefinedCategories.map((category) =>
                                DropdownMenuItem(value: category, child: Text(category))).toList(),
                            value: _selectedCategoryFilter,
                            onChanged: (value) {
                              setState(() {
                                _selectedCategoryFilter = value;
                              });
                            },
                            buttonStyleData: ButtonStyleData(
                              padding: const EdgeInsets.only(left: 14, right: 14),
                              height: 40,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(color: Colors.black26),
                                color: Colors.white,
                              ),
                            ),
                            menuItemStyleData: const MenuItemStyleData(
                              height: 40,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Products List Title
            Text(
              'Alışveriş Listesi Ürünleri',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.grey.shade800),
            ),
            const SizedBox(height: 12),

            ListView.builder(
              shrinkWrap: true, // Crucial for ListView inside SingleChildScrollView
              physics: const NeverScrollableScrollPhysics(), // Prevents nested scrolling
              itemCount: _visibleItems.length,
              itemBuilder: (context, index) {
                final item = _visibleItems[index];
                final realIndex = _items.indexOf(item); // Original index in _items
                final quantity = item['quantity'] ?? 1;
                final market = item['market'] as String?;
                final category = item['category'] as String?;
                final tags = item['tags'] as List?; // Tags are stored as a List

                return Card(
                  elevation: 2,
                  margin: const EdgeInsets.symmetric(vertical: 8),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16), // Added more padding
                    leading: Checkbox(
                      value: item['is_completed'],
                      onChanged: (isOwner || !item['is_completed']) // Sadece sahibi ise veya tamamlanmamışsa değiştirilebilir
                          ? (_) => _toggleItemComplete(realIndex)
                          : null, // Değiştirilemez ise null
                      activeColor: primaryColor,
                    ),
                    title: Text(
                      item['product_name'] ?? '',
                      style: TextStyle(
                        fontSize: 17, // Slightly larger font
                        fontWeight: FontWeight.w600, // Slightly bolder
                        decoration: item['is_completed'] ? TextDecoration.lineThrough : TextDecoration.none,
                        color: item['is_completed'] ? Colors.grey[500] : Colors.black87, // Faded for completed
                      ),
                    ),
                    subtitle: Padding(
                      padding: const EdgeInsets.only(top: 4.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Miktar: $quantity',
                            style: TextStyle(fontSize: 13, color: Colors.grey[700], fontWeight: FontWeight.w500),
                          ),
                          if (market != null && market.isNotEmpty)
                            Text(
                              'Mağaza: $market',
                              style: TextStyle(fontSize: 13, color: Colors.grey[700]),
                            ),
                          if (category != null && category.isNotEmpty)
                            Text(
                              'Kategori: $category',
                              style: TextStyle(fontSize: 13, color: Colors.grey[700]),
                            ),
                          if (tags != null && tags.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 6.0), // More space above tags
                              child: Wrap(
                                spacing: 6,
                                runSpacing: 4,
                                children: tags.map((tag) => Chip(
                                  label: Text(tag, style: TextStyle(fontSize: 10, color: primaryColor.shade800)),
                                  backgroundColor: primaryColor.shade100,
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 0), // Smaller padding
                                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                  side: BorderSide(color: primaryColor.shade300),
                                )).toList(),
                              ),
                            ),
                        ],
                      ),
                    ),
                    trailing: isOwner
                        ? Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: Icon(Icons.edit_outlined,
                                    color: Colors.grey.shade600),
                                tooltip: 'Düzenle',
                                onPressed: () => _editItemDialog(realIndex),
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete_rounded,
                                    color: Colors.red),
                                tooltip: 'Sil',
                                onPressed: () => _deleteItem(realIndex),
                              ),
                            ],
                          )
                        : null,
                  ),
                );
              },
            ),
            // The Elevated Button for adding new item.
            if (isOwner && _visibleItems.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 20.0),
                child: ElevatedButton.icon(
                  onPressed: _addNewItemDialog,
                  icon: const Icon(Icons.add),
                  label: const Text('Yeni Ürün Ekle'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primaryColor,
                    foregroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(50),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                    textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
              )
            else if (!isOwner && _visibleItems.isEmpty)
              const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}
