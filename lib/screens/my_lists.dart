import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:async';

import 'list_detail.dart';
import 'create_list.dart';
import '../constants/categories.dart';
import '../models/shopping_list.dart';
import '../repositories/list_repository.dart';
import '../widgets/ui_kit.dart';

class MyListsPage extends StatefulWidget {
  final MaterialColor customPrimarySwatch;

  const MyListsPage({super.key, required this.customPrimarySwatch});

  @override
  State<MyListsPage> createState() => _MyListsPageState();
}

class _MyListsPageState extends State<MyListsPage> {
  final SupabaseClient _supabase = Supabase.instance.client;
  final ListRepository _listRepo = ListRepository();

  List<ShoppingList> _lists = [];
  bool _isLoadingLists = true;
  String? _userId;

  List<Map<String, dynamic>> _allAvailableCategories = [];

  RealtimeChannel? _shoppingListsChannel;
  RealtimeChannel? _sharedListsChannel;

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
    if (mounted) setState(() => _isLoadingLists = true);
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
          const SnackBar(
              content: Text('Listeler yüklenirken bir hata oluştu.')),
        );
        setState(() => _isLoadingLists = false);
      }
    }
  }

  void _setupRealtimeListeners() {
    final uid = _userId;
    if (uid == null) return;

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

  void _openList(ShoppingList list) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ListDetailPage(listData: list.toMap()),
      ),
    ).then((_) => _fetchLists());
  }

  int _doneCount(ShoppingList l) =>
      (l.completionRate.clamp(0.0, 1.0) * l.itemCount).round();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final canPop = ModalRoute.of(context)?.canPop ?? false;
    final owned = _lists.where((l) => l.isOwner).toList();
    final shared = _lists.where((l) => !l.isOwner).toList();

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        bottom: false,
        child: DefaultTabController(
          length: 2,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 14, 20, 6),
                child: Row(
                  children: [
                    if (canPop)
                      IconButton(
                        icon: const Icon(Icons.arrow_back),
                        onPressed: () => Navigator.pop(context),
                      )
                    else
                      const SizedBox(width: 8),
                    Text('Listelerim',
                        style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w800,
                            color: scheme.onSurface)),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: TabBar(
                  isScrollable: true,
                  tabAlignment: TabAlignment.start,
                  labelColor: scheme.primary,
                  unselectedLabelColor: scheme.onSurfaceVariant,
                  indicatorColor: scheme.primary,
                  labelStyle: const TextStyle(fontWeight: FontWeight.w700),
                  tabs: const [
                    Tab(text: 'Kendi Listelerim'),
                    Tab(text: 'Paylaşılanlar'),
                  ],
                ),
              ),
              if (_isLoadingLists)
                LinearProgressIndicator(minHeight: 3, color: scheme.primary),
              Expanded(
                child: TabBarView(
                  children: [
                    _listTab(
                      lists: owned,
                      emptyIcon: Icons.playlist_add_rounded,
                      emptyTitle: 'Henüz listen yok',
                      emptyMessage:
                          'İlk alışveriş listeni oluştur, ürünleri ekle, '
                          'işaretleyerek takip et.',
                      showCreateButton: true,
                    ),
                    _listTab(
                      lists: shared,
                      emptyIcon: Icons.group_outlined,
                      emptyTitle: 'Paylaşılan liste yok',
                      emptyMessage:
                          'Bir arkadaşın seninle liste paylaştığında '
                          'burada görünür.',
                      showCreateButton: false,
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

  Widget _listTab({
    required List<ShoppingList> lists,
    required IconData emptyIcon,
    required String emptyTitle,
    required String emptyMessage,
    required bool showCreateButton,
  }) {
    return RefreshIndicator(
      onRefresh: _fetchLists,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 30),
        children: [
          if (lists.isEmpty && !_isLoadingLists)
            EmptyState(
              icon: emptyIcon,
              title: emptyTitle,
              message: emptyMessage,
              actionLabel: showCreateButton ? 'İlk Listeni Oluştur' : null,
              onAction: showCreateButton ? _openCreateList : null,
            ),
          ...lists.map(
            (l) => ListCard(
              title: l.name,
              done: _doneCount(l),
              total: l.itemCount,
              onTap: () => _openList(l),
            ),
          ),
          if (showCreateButton && lists.isNotEmpty) ...[
            const SizedBox(height: 4),
            SizedBox(
              height: 52,
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _openCreateList,
                icon: const Icon(Icons.add),
                label: const Text('Yeni Liste Oluştur'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
