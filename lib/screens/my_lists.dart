import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'dart:async';

import 'list_detail.dart';
import 'create_list.dart';
import '../constants/categories.dart';
import '../models/shopping_list.dart';
import '../repositories/list_repository.dart';
import '../repositories/sharing_repository.dart';

class MyListsPage extends StatefulWidget {
  final MaterialColor customPrimarySwatch;

  const MyListsPage({super.key, required this.customPrimarySwatch});

  @override
  State<MyListsPage> createState() => _MyListsPageState();
}

class _MyListsPageState extends State<MyListsPage> {
  final SupabaseClient _supabase = Supabase.instance.client;
  final ListRepository _listRepo = ListRepository();
  final SharingRepository _sharingRepo = SharingRepository();

  List<ShoppingList> _lists = [];
  bool _isLoadingLists = true;
  bool _isDeleting = false;
  String? _userId;

  List<Map<String, dynamic>> _allAvailableCategories = [];

  RealtimeChannel? _shoppingListsChannel;
  RealtimeChannel? _sharedListsChannel;

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
    _userId = _supabase.auth.currentUser?.id;
    if (_userId == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.pushReplacementNamed(context, '/login');
      });
      return;
    }

    _fetchLists();
    _fetchAllAvailableCategories();
    _setupRealtimeListeners();
  }

  @override
  void dispose() {
    _shoppingListsChannel?.unsubscribe();
    _sharedListsChannel?.unsubscribe();
    super.dispose();
  }

  Future<void> _fetchAllAvailableCategories() async {
    try {
      final discovered = await _listRepo.fetchUsedCategories();
      if (mounted) {
        setState(() {
          _allAvailableCategories = mergeDiscoveredCategories(discovered);
        });
      }
    } catch (e) {
      debugPrint('Kategoriler çekilemedi: $e');
    }
  }

  Future<void> _fetchLists() async {
    if (_userId == null) return;
    setState(() => _isLoadingLists = true);

    try {
      final lists = await _listRepo.fetchAllVisibleLists();
      if (mounted) {
        setState(() {
          _lists = lists;
          _isLoadingLists = false;
        });
      }
    } catch (e) {
      debugPrint('Listeler yüklenemedi: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Listeler yüklenirken bir hata oluştu.')),
        );
        setState(() => _isLoadingLists = false);
      }
    }
  }

  void _setupRealtimeListeners() {
    final uid = _userId;
    if (uid == null) return;

    // shopping_lists UPDATE: tamamlanma oranını yerinde güncelle, bulunamazsa
    // tüm listeyi tazele.
    _shoppingListsChannel = _supabase
        .channel('public:my_lists_shopping_lists')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'shopping_lists',
          callback: (payload) {
            if (!mounted) return;
            final id = payload.newRecord['id'] as String?;
            final rate =
                (payload.newRecord['completion_rate'] as num?)?.toDouble();
            if (id == null) return;
            final index = _lists.indexWhere((l) => l.id == id);
            if (index != -1 && rate != null) {
              setState(() {
                _lists[index] = _lists[index].copyWith(completionRate: rate);
              });
            } else {
              _fetchLists();
            }
          },
        )
        .subscribe();

    // shared_lists: bu kullanıcıyla ilgili herhangi bir değişiklikte tazele.
    _sharedListsChannel = _supabase
        .channel('public:my_lists_shared_lists')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'shared_lists',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'user_id',
            value: uid,
          ),
          callback: (_) {
            if (mounted) _fetchLists();
          },
        )
        .subscribe();
  }

  Future<void> _deleteList(String listId) async {
    if (_isDeleting) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Listeyi Sil',
            style: TextStyle(fontWeight: FontWeight.bold)),
        content: const Text(
            'Bu listeyi ve tüm ürünlerini kalıcı olarak silmek istediğinizden emin misiniz? Bu işlem geri alınamaz.'),
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
    );
    if (confirm != true) return;

    setState(() => _isDeleting = true);
    try {
      await _listRepo.deleteList(listId);
      await _fetchLists();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Liste silindi.')),
        );
      }
    } catch (e) {
      debugPrint('Liste silinemedi: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Liste silinemedi.')),
        );
      }
    } finally {
      if (mounted) setState(() => _isDeleting = false);
    }
  }

  void _showShareDialog(String listId, String listName) {
    final emailController = TextEditingController();
    showDialog(
      context: context,
      builder: (dialogContext) {
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
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('İptal', style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: widget.customPrimarySwatch,
                foregroundColor: Colors.white,
              ),
              onPressed: () {
                final email = emailController.text.trim();
                Navigator.of(dialogContext).pop();
                _shareList(listId, email);
              },
              child: const Text('Paylaş'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _shareList(String listId, String email) async {
    try {
      final outcome =
          await _sharingRepo.shareByEmail(listId: listId, email: email);
      if (!mounted) return;

      final (text, color) = switch (outcome) {
        ShareOutcome.success => ('Liste paylaşıldı.', Colors.green),
        ShareOutcome.invalidEmail =>
          ('Geçerli bir e-posta adresi girin.', Colors.red.shade400),
        ShareOutcome.self => (
            'Kendi listenizi kendinizle paylaşamazsınız.',
            Colors.red.shade400
          ),
        ShareOutcome.userNotFound => (
            'Bu e-posta ile kayıtlı bir kullanıcı bulunamadı.',
            Colors.red.shade400
          ),
        ShareOutcome.alreadyShared => (
            'Bu liste zaten bu kullanıcıyla paylaşılmış.',
            Colors.orange.shade700
          ),
      };

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(text), backgroundColor: color),
      );
      if (outcome == ShareOutcome.success) _fetchLists();
    } catch (e) {
      debugPrint('Paylaşım hatası: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Liste paylaşılırken bir hata oluştu.')),
        );
      }
    }
  }

  void _openCreateList() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => CreateListPage(
          availableCategories: _allAvailableCategories,
          customPrimarySwatch: widget.customPrimarySwatch,
        ),
      ),
    );
  }

  Color _getCardColor(String listId) {
    return _cardColors[listId.hashCode % _cardColors.length];
  }

  @override
  Widget build(BuildContext context) {
    final MaterialColor primary = widget.customPrimarySwatch;

    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: const Text('Listelerim',
            style:
                TextStyle(color: Colors.black87, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: false,
      ),
      body: Column(
        children: [
          if (_isDeleting || _isLoadingLists)
            LinearProgressIndicator(minHeight: 4, color: primary.shade700),
          Expanded(
            child: _isLoadingLists
                ? Center(child: CircularProgressIndicator(color: primary))
                : _lists.isEmpty
                    ? _EmptyState(primary: primary, onCreate: _openCreateList)
                    : ListView.builder(
                        padding: const EdgeInsets.all(16.0),
                        itemCount: _lists.length,
                        itemBuilder: (context, index) {
                          final list = _lists[index];
                          return _ListCard(
                            list: list,
                            primary: primary,
                            background: _getCardColor(list.id),
                            onOpen: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) =>
                                    ListDetailPage(listData: list.toMap()),
                              ),
                            ),
                            onShare: () => _showShareDialog(list.id, list.name),
                            onDelete: () => _deleteList(list.id),
                          );
                        },
                      ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openCreateList,
        icon: const Icon(Icons.add_shopping_cart_rounded, color: Colors.white),
        label: const Text('Yeni Liste Oluştur',
            style:
                TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        backgroundColor: primary.shade700,
        elevation: 8,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.primary, required this.onCreate});

  final MaterialColor primary;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.assignment_turned_in_outlined,
                size: 80, color: Colors.grey[400]),
            const SizedBox(height: 20),
            Text('Henüz hiç listeniz yok.',
                style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey[700]),
                textAlign: TextAlign.center),
            const SizedBox(height: 10),
            Text(
              'Yeni bir alışveriş listesi oluşturarak başlayın veya sizinle paylaşılan listeleri bekleyin!',
              style: TextStyle(fontSize: 16, color: Colors.grey[600]),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 30),
            ElevatedButton.icon(
              onPressed: onCreate,
              icon: const Icon(Icons.add_circle_outline),
              label: const Text('Yeni Liste Oluştur'),
              style: ElevatedButton.styleFrom(
                backgroundColor: primary,
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                shape:
                    RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                textStyle: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ListCard extends StatelessWidget {
  const _ListCard({
    required this.list,
    required this.primary,
    required this.background,
    required this.onOpen,
    required this.onShare,
    required this.onDelete,
  });

  final ShoppingList list;
  final MaterialColor primary;
  final Color background;
  final VoidCallback onOpen;
  final VoidCallback onShare;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final rate = list.completionRate.clamp(0.0, 1.0);
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8.0),
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      color: background,
      child: InkWell(
        borderRadius: BorderRadius.circular(15),
        onTap: onOpen,
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
                      list.name,
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                          color: Colors.grey.shade800),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (!list.isOwner)
                    Tooltip(
                      message: 'Bu liste sizinle paylaşıldı.',
                      child: Icon(Icons.people_alt_outlined,
                          color: primary.shade600, size: 20),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Text('${list.itemCount} Ürün',
                  style: TextStyle(fontSize: 14, color: Colors.grey.shade700)),
              Text(
                'Oluşturulma: ${DateFormat('dd MMMM yyyy', 'tr_TR').format(list.createdAt)}',
                style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
              ),
              const SizedBox(height: 12),
              LinearProgressIndicator(
                value: rate,
                backgroundColor: Colors.grey[300],
                color: primary,
                minHeight: 8,
                borderRadius: BorderRadius.circular(4),
              ),
              const SizedBox(height: 6),
              Align(
                alignment: Alignment.centerRight,
                child: Text(
                  '${(rate * 100).round()}% tamamlandı',
                  style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey.shade700,
                      fontWeight: FontWeight.bold),
                ),
              ),
              if (list.isOwner)
                Padding(
                  padding: const EdgeInsets.only(top: 12.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      IconButton(
                        icon: Icon(Icons.share,
                            color: primary.shade600, size: 22),
                        tooltip: 'Listeyi Paylaş',
                        onPressed: onShare,
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_forever,
                            color: Colors.red, size: 22),
                        tooltip: 'Listeyi Sil',
                        onPressed: onDelete,
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
