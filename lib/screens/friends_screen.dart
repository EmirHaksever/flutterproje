import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/friend.dart';
import '../repositories/friends_repository.dart';
import '../theme/app_theme.dart';

class FriendsScreen extends StatefulWidget {
  const FriendsScreen({super.key});

  @override
  State<FriendsScreen> createState() => _FriendsScreenState();
}

class _FriendsScreenState extends State<FriendsScreen> {
  final FriendsRepository _repo = FriendsRepository();
  final TextEditingController _addCtrl = TextEditingController();

  bool _loading = true;
  List<Friend> _friends = [];
  List<FriendRequest> _incoming = [];
  List<FriendRequest> _outgoing = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _addCtrl.dispose();
    super.dispose();
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
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
      _snack('Arkadaş verileri yüklenemedi.', error: true);
    }
  }

  void _snack(String msg, {bool error = false, bool ok = false}) {
    if (!mounted) return;
    final scheme = Theme.of(context).colorScheme;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: error
          ? scheme.error
          : ok
              ? scheme.primary
              : null,
    ));
  }

  Future<void> _sendRequest() async {
    final email = _addCtrl.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      _snack('Geçerli bir e-posta gir.', error: true);
      return;
    }
    try {
      await _repo.sendRequest(email);
      if (!mounted) return;
      _addCtrl.clear();
      FocusScope.of(context).unfocus();
      _snack('Arkadaşlık isteği gönderildi.', ok: true);
      _load();
    } catch (e) {
      _snack(_cleanError(e), error: true);
    }
  }

  Future<void> _respond(FriendRequest r, bool accept) async {
    try {
      await _repo.respond(r.id, accept: accept);
      _snack(accept ? 'Arkadaş eklendi.' : 'İstek reddedildi.', ok: accept);
      _load();
    } catch (e) {
      _snack(_cleanError(e), error: true);
    }
  }

  Future<void> _cancel(FriendRequest r) async {
    try {
      await _repo.cancelRequest(r.id);
      _load();
    } catch (_) {
      _snack('İstek geri çekilemedi.', error: true);
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
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: Theme.of(ctx).colorScheme.error),
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
    } catch (_) {
      _snack('İşlem başarısız.', error: true);
    }
  }

  static String _cleanError(Object e) {
    if (e is PostgrestException) return e.message;
    return 'Bir hata oluştu. Lütfen tekrar dene.';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        appBar: AppBar(title: const Text('Arkadaşlar')),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
              child: TextField(
                controller: _addCtrl,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _sendRequest(),
                decoration: InputDecoration(
                  hintText: 'E-posta ile arkadaş ekle',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: IconButton(
                    icon: Icon(Icons.add, color: scheme.primary),
                    onPressed: _sendRequest,
                  ),
                ),
              ),
            ),
            TabBar(
              labelColor: scheme.primary,
              unselectedLabelColor: scheme.onSurfaceVariant,
              indicatorColor: scheme.primary,
              labelStyle: const TextStyle(fontWeight: FontWeight.w700),
              tabs: [
                Tab(text: 'Arkadaşlarım (${_friends.length})'),
                Tab(text: 'Gelen (${_incoming.length})'),
                Tab(text: 'Gönderilen (${_outgoing.length})'),
              ],
            ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : TabBarView(
                      children: [
                        _friendsTab(scheme),
                        _requestsTab(scheme, _incoming, incoming: true),
                        _requestsTab(scheme, _outgoing, incoming: false),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _friendsTab(ColorScheme scheme) {
    if (_friends.isEmpty) {
      return _empty(scheme, Icons.group_outlined,
          'Henüz arkadaşın yok.\nYukarıdan e-posta ile ekleyebilirsin.');
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: _friends.length,
        itemBuilder: (context, i) {
          final f = _friends[i];
          return _row(
            scheme,
            f.friendEmail,
            trailing: PopupMenuButton<String>(
              icon: Icon(Icons.more_vert, color: scheme.onSurfaceVariant),
              onSelected: (v) {
                if (v == 'remove') _remove(f);
              },
              itemBuilder: (_) => const [
                PopupMenuItem(
                    value: 'remove', child: Text('Arkadaşlıktan çıkar')),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _requestsTab(
      ColorScheme scheme, List<FriendRequest> list, {required bool incoming}) {
    if (list.isEmpty) {
      return _empty(
        scheme,
        Icons.inbox_outlined,
        incoming ? 'Gelen istek yok.' : 'Gönderilmiş istek yok.',
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: list.length,
        itemBuilder: (context, i) {
          final r = list[i];
          final name = r.otherEmail.isEmpty ? 'Kullanıcı' : r.otherEmail;
          return _row(
            scheme,
            name,
            trailing: incoming
                ? Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextButton(
                        onPressed: () => _respond(r, true),
                        child: const Text('Kabul Et'),
                      ),
                      IconButton(
                        icon: Icon(Icons.close, color: scheme.onSurfaceVariant),
                        onPressed: () => _respond(r, false),
                      ),
                    ],
                  )
                : TextButton(
                    onPressed: () => _cancel(r),
                    child: const Text('Geri çek'),
                  ),
          );
        },
      ),
    );
  }

  Widget _row(ColorScheme scheme, String email, {required Widget trailing}) {
    final letter =
        email.isNotEmpty ? email[0].toUpperCase() : '?';
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
      leading: CircleAvatar(
        backgroundColor: AppTheme.heroGreenBg,
        child: Text(letter,
            style: TextStyle(
                fontWeight: FontWeight.w700, color: scheme.primary)),
      ),
      title: Text(email,
          style: const TextStyle(
              fontSize: 13.5, fontWeight: FontWeight.w600),
          maxLines: 1,
          overflow: TextOverflow.ellipsis),
      trailing: trailing,
    );
  }

  Widget _empty(ColorScheme scheme, IconData icon, String text) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 54, color: scheme.onSurfaceVariant),
            const SizedBox(height: 12),
            Text(text,
                textAlign: TextAlign.center,
                style: TextStyle(color: scheme.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }
}
