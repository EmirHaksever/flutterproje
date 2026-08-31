import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/friend.dart';
import '../repositories/friends_repository.dart';

class FriendsScreen extends StatefulWidget {
  const FriendsScreen({super.key});

  @override
  State<FriendsScreen> createState() => _FriendsScreenState();
}

class _FriendsScreenState extends State<FriendsScreen> {
  final FriendsRepository _repo = FriendsRepository();

  bool _loading = true;
  List<Friend> _friends = [];
  List<FriendRequest> _incoming = [];
  List<FriendRequest> _outgoing = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        _repo.fetchFriends(),
        _repo.fetchIncomingRequests(),
        _repo.fetchOutgoingRequests(),
      ]);
      if (!mounted) return;
      setState(() {
        _friends = results[0] as List<Friend>;
        _incoming = results[1] as List<FriendRequest>;
        _outgoing = results[2] as List<FriendRequest>;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      _snack('Arkadaş verileri yüklenemedi.');
    }
  }

  void _snack(String msg, {Color? color}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: color),
    );
  }

  Future<void> _addFriendDialog() async {
    final controller = TextEditingController();
    final email = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Arkadaş ekle'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.emailAddress,
          decoration: const InputDecoration(
            labelText: 'E-posta adresi',
            hintText: 'arkadas@email.com',
            prefixIcon: Icon(Icons.alternate_email),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('İptal'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('İstek gönder'),
          ),
        ],
      ),
    );
    if (email == null || email.isEmpty) return;

    try {
      await _repo.sendRequest(email);
      _snack('Arkadaşlık isteği gönderildi.', color: Colors.green);
      _load();
    } catch (e) {
      _snack(_cleanError(e), color: Colors.red.shade400);
    }
  }

  Future<void> _respond(FriendRequest r, bool accept) async {
    try {
      await _repo.respond(r.id, accept: accept);
      _snack(accept ? 'Arkadaş eklendi.' : 'İstek reddedildi.',
          color: accept ? Colors.green : null);
      _load();
    } catch (e) {
      _snack(_cleanError(e), color: Colors.red.shade400);
    }
  }

  Future<void> _cancel(FriendRequest r) async {
    try {
      await _repo.cancelRequest(r.id);
      _load();
    } catch (e) {
      _snack('İstek geri çekilemedi.', color: Colors.red.shade400);
    }
  }

  Future<void> _remove(Friend f) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Arkadaşlıktan çıkar'),
        content: Text('${f.friendEmail} arkadaşlıktan çıkarılsın mı?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('İptal')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Çıkar'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _repo.removeFriend(f.friendEmail);
      _load();
    } catch (e) {
      _snack('İşlem başarısız.', color: Colors.red.shade400);
    }
  }

  static String _cleanError(Object e) {
    // RPC içindeki `raise exception` mesajı PostgrestException.message'a düşer.
    if (e is PostgrestException) return e.message;
    return 'Bir hata oluştu. Lütfen tekrar deneyin.';
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).primaryColor;
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Arkadaşlar'),
          backgroundColor: primary,
          foregroundColor: Colors.white,
          bottom: TabBar(
            indicatorColor: Colors.white,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            tabs: [
              Tab(text: 'Arkadaşlar (${_friends.length})'),
              Tab(text: 'Gelen (${_incoming.length})'),
              Tab(text: 'Giden (${_outgoing.length})'),
            ],
          ),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : TabBarView(
                children: [
                  _FriendsTab(friends: _friends, onRemove: _remove),
                  _RequestsTab(
                    requests: _incoming,
                    emptyText: 'Gelen istek yok.',
                    trailingBuilder: (r) => Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.check_circle,
                              color: Colors.green),
                          tooltip: 'Kabul et',
                          onPressed: () => _respond(r, true),
                        ),
                        IconButton(
                          icon:
                              const Icon(Icons.cancel, color: Colors.redAccent),
                          tooltip: 'Reddet',
                          onPressed: () => _respond(r, false),
                        ),
                      ],
                    ),
                  ),
                  _RequestsTab(
                    requests: _outgoing,
                    emptyText: 'Gönderilmiş istek yok.',
                    trailingBuilder: (r) => TextButton(
                      onPressed: () => _cancel(r),
                      child: const Text('Geri çek'),
                    ),
                  ),
                ],
              ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: _addFriendDialog,
          icon: const Icon(Icons.person_add),
          label: const Text('Arkadaş ekle'),
          backgroundColor: primary,
          foregroundColor: Colors.white,
        ),
      ),
    );
  }
}

class _FriendsTab extends StatelessWidget {
  const _FriendsTab({required this.friends, required this.onRemove});

  final List<Friend> friends;
  final void Function(Friend) onRemove;

  @override
  Widget build(BuildContext context) {
    if (friends.isEmpty) {
      return const _EmptyHint(
          icon: Icons.group_outlined, text: 'Henüz arkadaşın yok.');
    }
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: friends.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, i) {
        final f = friends[i];
        return ListTile(
          leading: CircleAvatar(child: Text(_initial(f.friendEmail))),
          title: Text(f.friendEmail),
          trailing: IconButton(
            icon: const Icon(Icons.person_remove_outlined, color: Colors.grey),
            tooltip: 'Çıkar',
            onPressed: () => onRemove(f),
          ),
        );
      },
    );
  }
}

class _RequestsTab extends StatelessWidget {
  const _RequestsTab({
    required this.requests,
    required this.emptyText,
    required this.trailingBuilder,
  });

  final List<FriendRequest> requests;
  final String emptyText;
  final Widget Function(FriendRequest) trailingBuilder;

  @override
  Widget build(BuildContext context) {
    if (requests.isEmpty) {
      return _EmptyHint(icon: Icons.inbox_outlined, text: emptyText);
    }
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: requests.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, i) {
        final r = requests[i];
        return ListTile(
          leading: CircleAvatar(child: Text(_initial(r.otherEmail))),
          title: Text(r.otherEmail.isEmpty ? 'Kullanıcı' : r.otherEmail),
          trailing: trailingBuilder(r),
        );
      },
    );
  }
}

class _EmptyHint extends StatelessWidget {
  const _EmptyHint({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon,
              size: 64,
              color: Theme.of(context).colorScheme.onSurfaceVariant),
          const SizedBox(height: 12),
          Text(text,
              style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontSize: 16)),
        ],
      ),
    );
  }
}

String _initial(String email) =>
    email.isNotEmpty ? email[0].toUpperCase() : '?';
