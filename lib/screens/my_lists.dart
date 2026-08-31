import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart'; // Tarih formatlama için
import 'dart:async'; // StreamSubscription için

import 'list_detail.dart';
import 'create_list.dart';
import 'ai_chat.dart';
import 'stats.dart'; // İstatistikler sayfası için import

class MyListsPage extends StatefulWidget {
  final MaterialColor customPrimarySwatch;

  const MyListsPage({super.key, required this.customPrimarySwatch});

  @override
  State<MyListsPage> createState() => _MyListsPageState();
}

class _MyListsPageState extends State<MyListsPage> {
  late final SupabaseClient supabase;
  List<Map<String, dynamic>> _lists = [];
  bool _isLoadingLists = true;
  bool _isDeleting = false;
  int _currentIndex = 1; // Bu sayfa ortada
  String? _userId;

  List<Map<String, dynamic>> _allAvailableCategories = [];

  RealtimeChannel? _shoppingListsChannel;
  RealtimeChannel? _sharedListsChannel;
  StreamSubscription<PostgresChangePayload>? _shoppingListsSubscription;
  StreamSubscription<PostgresChangePayload>? _sharedListsSubscription;

  // Kartlar için önceden tanımlanmış renk paleti
  final List<Color> _cardColors = [
    Colors.blue.shade50,
    Colors.green.shade50,
    Colors.orange.shade50,
    Colors.purple.shade50,
    Colors.red.shade50,
    Colors.teal.shade50,
    Colors.indigo.shade50,
    Colors.pink.shade50,
  ];

  @override
  void initState() {
    super.initState();
    supabase = Supabase.instance.client;
    _userId = supabase.auth.currentUser?.id;
    if (_userId == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.pushReplacementNamed(context, '/login');
      });
      return;
    }

    _fetchLists();
    _fetchAllAvailableCategories();
    _setupRealtimeListenersForLists();
  }

  @override
  void dispose() {
    _shoppingListsSubscription?.cancel();
    _shoppingListsChannel?.unsubscribe();
    _sharedListsSubscription?.cancel();
    _sharedListsChannel?.unsubscribe();
    super.dispose();
  }

  Future<void> _fetchAllAvailableCategories() async {
    try {
      List<Map<String, dynamic>> defaultDefinedCategories = [
        {
          'name': 'Market',
          'icon': Icons.local_grocery_store,
          'colors': [const Color(0xFF56AB2F), const Color(0xFFA8E063)],
        },
        {
          'name': 'Kıyafet',
          'icon': Icons.style,
          'colors': [const Color(0xFFF7971E), const Color(0xFFFF5F6D)],
        },
        {
          'name': 'Elektronik',
          'icon': Icons.power,
          'colors': [const Color(0xFFAA076B), const Color(0xFF61045F)],
        },
        {
          'name': 'Temizlik',
          'icon': Icons.cleaning_services,
          'colors': [const Color(0xFF4CB8C4), const Color(0xFF3CD3AD)],
        },
        {
          'name': 'Kırtasiye',
          'icon': Icons.school,
          'colors': [const Color(0xFFFFCC33), const Color(0xFFE2B00E)],
        },
        {
          'name': 'Evcil Hayvan',
          'icon': Icons.pets,
          'colors': [const Color(0xFF536976), const Color(0xFF292E49)],
        },
        {
          'name': 'Gıda',
          'icon': Icons.restaurant_menu,
          'colors': [const Color(0xFFA8E063), const Color(0xFF56AB2F)],
        },
        {
          'name': 'Bebek',
          'icon': Icons.child_care,
          'colors': [const Color(0xFFF7971E), const Color(0xFFFF5F6D)],
        },
      ];

      final response = await supabase
          .from('list_items')
          .select('category');

      Set<String> uniqueListItemCategories = {};
      for (var item in response) {
        final categoryName = item['category'] as String?;
        if (categoryName != null && categoryName.isNotEmpty) {
          uniqueListItemCategories.add(categoryName);
        }
      }

      List<Map<String, dynamic>> tempAllAvailableCategories = [];
      tempAllAvailableCategories.addAll(defaultDefinedCategories);

      for (String categoryName in uniqueListItemCategories) {
        if (!tempAllAvailableCategories.any((cat) => cat['name'].toLowerCase() == categoryName.toLowerCase())) {
          tempAllAvailableCategories.add({
            'name': categoryName,
            'icon': Icons.category_outlined,
            'colors': [Colors.blueGrey.shade300, Colors.blueGrey.shade500],
          });
        }
      }

      if (mounted) {
        setState(() {
          _allAvailableCategories = tempAllAvailableCategories;
        });
      }
    } catch (e) {
      debugPrint('Tüm mevcut kategoriler çekilemedi: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Kategoriler yüklenirken hata oluştu: $e')),
        );
      }
    }
  }

  Future<void> _fetchLists() async {
    if (_userId == null) {
      debugPrint('User ID is null, cannot fetch lists.');
      if (mounted) {
        setState(() {
          _isLoadingLists = false;
        });
      }
      return;
    }

    setState(() {
      _isLoadingLists = true;
    });

    debugPrint('Fetching lists for user ID: $_userId');

    try {
      // Kendi oluşturduğun listeler
      final myListsResponse = await supabase
          .from('shopping_lists')
          .select('*, list_items(id)')
          .eq('user_id', _userId!)
          .order('created_at', ascending: false);

      final myLists = List<Map<String, dynamic>>.from(myListsResponse);
      debugPrint('My lists fetched: ${myLists.length} lists');

      // Paylaşılan listeler
      final sharedListsResponse = await supabase
          .from('shared_lists')
          .select('list_id, user_id, shared_by_user_id, created_at, shopping_lists(id, name, user_id, created_at, completion_rate, list_items(id))')
          .eq('user_id', _userId!);

      final sharedLists = sharedListsResponse
          .where((e) => e['shopping_lists'] != null)
          .map<Map<String, dynamic>>((e) {
              final Map<String, dynamic> shoppingList = Map<String, dynamic>.from(e['shopping_lists']);
              if (e['shopping_lists']['list_items'] is List) {
                  shoppingList['list_items'] = e['shopping_lists']['list_items'] as List<dynamic>;
              } else {
                  shoppingList['list_items'] = [];
              }
              shoppingList['shared_by_user_id'] = e['shared_by_user_id'];
              return shoppingList;
          })
          .toList();

      debugPrint('Shared lists fetched: ${sharedLists.length} lists');

      // Ayrım için flag ekle
      final myListsWithFlag = myLists.map((e) => {...e, 'isOwner': true}).toList();
      final sharedListsWithFlag = sharedLists.map((e) => {...e, 'isOwner': false}).toList();

      // Tüm listeleri birleştir ve sırala
      final allLists = [...myListsWithFlag, ...sharedListsWithFlag];
      allLists.sort((a, b) {
        final aDate = DateTime.tryParse(a['created_at'] ?? '') ?? DateTime.now();
        final bDate = DateTime.tryParse(b['created_at'] ?? '') ?? DateTime.now();
        return bDate.compareTo(aDate);
      });

      if (mounted) {
        setState(() {
          _lists = allLists;
          _isLoadingLists = false;
        });
        debugPrint('Total combined lists updated: ${_lists.length}');
      }

    } catch (e) {
      debugPrint('Error fetching lists: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Listeler yüklenirken bir hata oluştu: $e')),
        );
        setState(() {
          _isLoadingLists = false;
        });
      }
    }
  }

  void _setupRealtimeListenersForLists() {
    if (_userId == null) {
      debugPrint('Cannot setup realtime listeners, user ID is null.');
      return;
    }

    _shoppingListsChannel = supabase
        .channel('public:shopping_lists_channel')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'shopping_lists',
          callback: (payload) {
            debugPrint('Realtime: shopping_lists UPDATE - New Record: ${payload.newRecord}');
            if (mounted) {
              setState(() {
                final String updatedListId = payload.newRecord['id'];
                final double newCompletionRate = (payload.newRecord['completion_rate'] as num?)?.toDouble() ?? 0.0;
                final String? updatedListName = payload.newRecord['name'];

                final index = _lists.indexWhere((list) => list['id'] == updatedListId);
                if (index != -1) {
                  _lists[index]['completion_rate'] = newCompletionRate;
                  debugPrint('List "${updatedListName}" completion rate updated in UI to: $newCompletionRate');
                } else {
                  debugPrint('Updated list not found in current view. Re-fetching all lists.');
                  _fetchLists();
                }
              });
            }
          },
        )
        .subscribe();

    _sharedListsChannel = supabase
        .channel('public:shared_lists_channel')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'shared_lists',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'user_id',
            value: _userId!,
          ),
          callback: (payload) {
            debugPrint('Realtime: shared_lists CHANGE - Event Type: ${payload.eventType}');
            if (mounted) {
              _fetchLists();
            }
          },
        )
        .subscribe();

    debugPrint('Realtime listeners set up for shopping_lists and shared_lists.');
  }

  Future<void> _deleteList(String listId) async {
    if (_isDeleting) return;

    final bool confirmDelete = await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Listeyi Sil', style: TextStyle(fontWeight: FontWeight.bold)),
        content: const Text('Bu listeyi ve tüm ürünlerini kalıcı olarak silmek istediğinizden emin misiniz? Bu işlem geri alınamaz.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('İptal', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Sil'),
          ),
        ],
      ),
    ) ?? false;

    if (!confirmDelete) return;

    setState(() {
      _isDeleting = true;
    });

    try {
      // list_items ve shared_lists, shopping_lists'e ON DELETE CASCADE ile bağlı;
      // ana satırı silmek bağlı satırları veritabanı seviyesinde atomik olarak siler.
      await supabase
          .from('shopping_lists')
          .delete()
          .eq('id', listId);

      await _fetchLists();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Liste başarıyla silindi!')),
        );
      }
    } catch (e) {
      debugPrint('Liste silinemedi: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Liste silinemedi: $e')),
        );
      }
    } finally {
      setState(() {
        _isDeleting = false;
      });
    }
  }

  void _showShareDialog(String listId, String listName) {
    final emailController = TextEditingController();
    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: Text('"$listName" listesini paylaş'),
          content: TextField(
            controller: emailController,
            keyboardType: TextInputType.emailAddress,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Kullanıcının e-posta adresi',
              hintText: 'ornek@email.com',
              prefixIcon: Icon(Icons.alternate_email),
            ),
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('İptal', style: TextStyle(color: Colors.grey)),
              onPressed: () => Navigator.of(dialogContext).pop(),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: widget.customPrimarySwatch,
                foregroundColor: Colors.white,
              ),
              child: const Text('Paylaş'),
              onPressed: () {
                final email = emailController.text.trim().toLowerCase();
                if (email.isEmpty || !email.contains('@')) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Geçerli bir e-posta adresi girin.')),
                  );
                  return;
                }
                Navigator.of(dialogContext).pop();
                _shareListByEmail(listId, email);
              },
            ),
          ],
        );
      },
    );
  }

  Future<void> _shareListByEmail(String listId, String email) async {
    final currentUserEmail =
        supabase.auth.currentUser?.email?.toLowerCase();
    if (email == currentUserEmail) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Kendi listenizi kendinizle paylaşamazsınız.')),
        );
      }
      return;
    }

    try {
      // 1) E-postadan hedef kullanıcıyı bul
      final targetUser = await supabase
          .from('users')
          .select('id')
          .eq('email', email)
          .maybeSingle();

      if (targetUser == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Bu e-posta ile kayıtlı bir kullanıcı bulunamadı.')),
          );
        }
        return;
      }

      final String sharedUserId = targetUser['id'] as String;

      // 2) Zaten paylaşılmış mı?
      final existingShare = await supabase
          .from('shared_lists')
          .select('id')
          .eq('list_id', listId)
          .eq('user_id', sharedUserId)
          .maybeSingle();

      if (existingShare != null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Bu liste zaten bu kullanıcıyla paylaşılmış.')),
          );
        }
        return;
      }

      // 3) Paylaş (RLS: yalnızca listenin sahibi ekleyebilir)
      await supabase.from('shared_lists').insert({
        'list_id': listId,
        'user_id': sharedUserId,
        'user_email': email,
        'role': 'editor',
        'shared_by_user_id': _userId,
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Liste başarıyla paylaşıldı!'),
            backgroundColor: Colors.green,
          ),
        );
        await _fetchLists();
      }
    } on PostgrestException catch (e) {
      debugPrint('Paylaşım hatası (PostgrestException): ${e.message}');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Liste paylaşılırken hata oluştu: ${e.message}')),
        );
      }
    } catch (e) {
      debugPrint('Paylaşım hatası: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Liste paylaşılırken beklenmedik bir hata oluştu: $e')),
        );
      }
    }
  }

  void _onTabTapped(int index) {
    if (index == _currentIndex) return;

    setState(() => _currentIndex = index);

    final MaterialColor safePrimarySwatch = widget.customPrimarySwatch;

    if (index == 0) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => CreateListPage(
            availableCategories: _allAvailableCategories,
            customPrimarySwatch: safePrimarySwatch,
          ),
        ),
      );
    } else if (index == 2) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const AIChatPage()),
      );
    } else if (index == 3) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => StatsPage(customPrimarySwatch: safePrimarySwatch)),
      );
    }
  }

  // Helper function to get a consistent color for each list based on its ID
  Color _getCardColor(String listId) {
    // Simple hash to get a consistent color from the palette
    final int hash = listId.hashCode;
    return _cardColors[hash % _cardColors.length];
  }

  @override
  Widget build(BuildContext context) {
    final MaterialColor globalPrimaryColor = widget.customPrimarySwatch;

    return Scaffold(
      backgroundColor: Colors.grey[50], // Very light grey background
      appBar: AppBar(
        title: const Text('Listelerim', style: TextStyle(color: Colors.black87, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white, // White AppBar
        elevation: 0, // No shadow
        centerTitle: false, // Title aligned to left
      ),
      body: Column(
        children: [
          if (_isDeleting || _isLoadingLists)
            LinearProgressIndicator(minHeight: 4, color: globalPrimaryColor.shade700),
          Expanded(
            child: _isLoadingLists
                ? Center(child: CircularProgressIndicator(color: globalPrimaryColor))
                : _lists.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(20.0),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.assignment_turned_in_outlined, size: 80, color: Colors.grey[400]),
                              const SizedBox(height: 20),
                              Text(
                                'Henüz hiç listeniz yok.',
                                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.grey[700]),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 10),
                              Text(
                                'Yeni bir alışveriş listesi oluşturarak başlayın veya sizinle paylaşılan listeleri bekleyin!',
                                style: TextStyle(fontSize: 16, color: Colors.grey[600]),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 30),
                              ElevatedButton.icon(
                                onPressed: () {
                                  _onTabTapped(0);
                                },
                                icon: const Icon(Icons.add_circle_outline),
                                label: const Text('Yeni Liste Oluştur'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: globalPrimaryColor,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                                  textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                    : ListView.builder( // Reverted to ListView.builder
                        padding: const EdgeInsets.all(16.0),
                        itemCount: _lists.length,
                        itemBuilder: (context, index) {
                          final list = _lists[index];
                          final createdAt = DateTime.tryParse(list['created_at'] ?? '') ?? DateTime.now();
                          final itemCount = (list['list_items'] is List) ? (list['list_items'] as List<dynamic>).length : 0;
                          final isOwner = list['isOwner'] ?? false;
                          
                          double completionRate;
                          final dynamic rawCompletionRate = list['completion_rate'];

                          if (rawCompletionRate == null) {
                            completionRate = 0.0;
                          } else if (rawCompletionRate is int) {
                            completionRate = rawCompletionRate.toDouble();
                          } else if (rawCompletionRate is double) {
                            completionRate = rawCompletionRate;
                          } else {
                            try {
                              completionRate = double.tryParse(rawCompletionRate.toString()) ?? 0.0;
                            } catch (e) {
                              debugPrint('Unexpected type for completion_rate: ${rawCompletionRate.runtimeType}, value: $rawCompletionRate. Error: $e');
                              completionRate = 0.0;
                            }
                          }

                          // Get dynamic card color
                          final cardBackgroundColor = _getCardColor(list['id']);

                          return Card(
                            margin: const EdgeInsets.symmetric(vertical: 8.0),
                            elevation: 4, // Subtle shadow
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(15), // Rounded corners
                            ),
                            color: cardBackgroundColor, // Dynamic card background color
                            child: InkWell(
                              borderRadius: BorderRadius.circular(15),
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => ListDetailPage(listData: list),
                                  ),
                                );
                              },
                              child: Padding(
                                padding: const EdgeInsets.all(16.0),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Expanded(
                                          child: Text(
                                            list['name'] ?? 'İsimsiz Liste',
                                            style: TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 18,
                                              color: Colors.grey.shade800, // Darker text for readability on light card
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        if (!isOwner)
                                          Tooltip(
                                            message: 'Bu liste sizinle paylaşıldı.',
                                            child: Icon(Icons.people_alt_outlined, color: globalPrimaryColor.shade600, size: 20),
                                          ),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      '${itemCount} Ürün',
                                      style: TextStyle(
                                        fontSize: 14,
                                        color: Colors.grey.shade700,
                                      ),
                                    ),
                                    Text(
                                      'Oluşturulma: ${DateFormat('dd MMMM yyyy', 'tr_TR').format(createdAt)}',
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: Colors.grey.shade600,
                                      ),
                                    ),
                                    const SizedBox(height: 12),
                                    LinearProgressIndicator(
                                      value: completionRate,
                                      backgroundColor: Colors.grey[300],
                                      color: globalPrimaryColor, // Use primary theme color for progress
                                      minHeight: 8,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    const SizedBox(height: 6),
                                    Align(
                                      alignment: Alignment.centerRight,
                                      child: Text(
                                        '${(completionRate * 100).round()}% tamamlandı',
                                        style: TextStyle(
                                          fontSize: 13,
                                          color: Colors.grey.shade700,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                    if (isOwner)
                                      Padding(
                                        padding: const EdgeInsets.only(top: 12.0),
                                        child: Row(
                                          mainAxisAlignment: MainAxisAlignment.end,
                                          children: [
                                            IconButton(
                                              icon: Icon(Icons.share, color: globalPrimaryColor.shade600, size: 22),
                                              tooltip: 'Listeyi Paylaş',
                                              onPressed: () => _showShareDialog(list['id'], list['name'] ?? 'Liste'),
                                            ),
                                            IconButton(
                                              icon: const Icon(Icons.delete_forever, color: Colors.red, size: 22),
                                              tooltip: 'Listeyi Sil',
                                              onPressed: () => _deleteList(list['id']),
                                            ),
                                          ],
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _onTabTapped(0),
        icon: const Icon(Icons.add_shopping_cart_rounded, color: Colors.white),
        label: const Text('Yeni Liste Oluştur', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        backgroundColor: globalPrimaryColor.shade700,
        elevation: 8,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      bottomNavigationBar: BottomAppBar(
        shape: const CircularNotchedRectangle(),
        notchMargin: 8.0,
        color: Colors.white,
        elevation: 10,
        child: Row(
        ),
      ),
    );
  }

  // Alt gezinme çubuğu öğesi için yardımcı widget
  Widget _buildNavItem(IconData icon, String label, int index, MaterialColor primaryColor) {
    final bool isSelected = _currentIndex == index;
    return Expanded(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _onTabTapped(index),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  color: isSelected ? primaryColor.shade700 : Colors.grey.shade600,
                  size: 26,
                ),
                Text(
                  label,
                  style: TextStyle(
                    color: isSelected ? primaryColor.shade700 : Colors.grey.shade600,
                    fontSize: 11,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
