import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/friend.dart';
import '../repositories/friends_repository.dart';
import '../theme/app_theme.dart';
import '../widgets/ui_kit.dart';

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

  Timer? _debounce;
  bool _loadError = false;
  bool _searching = false;
  List<({String id, String? name, String email, String? avatarUrl})> _results =
      [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _addCtrl.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    final q = value.trim();
    if (q.length < 2) {
      setState(() {
        _results = [];
        _searching = false;
      });
      return;
    }
    setState(() => _searching = true);
    _debounce = Timer(const Duration(milliseconds: 350), () async {
      try {
        final res = await _repo.searchUsers(q);
        if (mounted) {
          setState(() {
            _results = res;
            _searching = false;
          });
        }
      } catch (_) {
        if (mounted) setState(() => _searching = false);
      }
    });
  }

  Future<void> _sendTo(String email) async {
    try {
      await _repo.sendRequest(email);
      if (!mounted) return;
      _addCtrl.clear();
      setState(() => _results = []);
      FocusScope.of(context).unfocus();
      _snack('Arkadaşlık isteği gönderildi.', ok: true);
      _load();
    } catch (e) {
      _snack(_cleanError(e), error: true);
    }
  }

  String _maskEmail(String e) {
    final at = e.indexOf('@');
    if (at <= 1) return e;
    return '${e[0]}***${e.substring(at)}';
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
        _loadError = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadError = true;
      });
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

  /// "+" butonu: tam e-posta yazıldıysa doğrudan gönder (isimle bulunamayanlar
  /// için yedek yol).
  Future<void> _sendRequest() async {
    final text = _addCtrl.text.trim();
    if (!text.contains('@')) {
      _snack('İsimle aramak için yazmaya devam et ya da tam e-posta gir.',
          error: true);
      return;
    }
    await _sendTo(text);
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
        content: Text('${f.displayName} arkadaşlıktan çıkarılsın mı?'),
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
      await _repo.removeFriend(f.friendId);
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
                textInputAction: TextInputAction.search,
                onChanged: _onSearchChanged,
                onSubmitted: (_) => _sendRequest(),
                decoration: InputDecoration(
                  hintText: 'İsim veya e-posta ile arkadaş ara',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _addCtrl.text.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () {
                            _addCtrl.clear();
                            setState(() => _results = []);
                          },
                        ),
                ),
              ),
            ),
            if (_addCtrl.text.trim().length >= 2) _searchResults(scheme),
            TabBar(
              labelColor: scheme.primary,
              unselectedLabelColor: scheme.onSurfaceVariant,
              indicatorColor: scheme.primary,
              labelStyle: const TextStyle(fontWeight: FontWeight.w700),
              labelPadding: const EdgeInsets.symmetric(horizontal: 6),
              tabs: [
                Tab(
                  child: _tabLabel('Arkadaşlar', _friends.length, scheme),
                ),
                Tab(
                  child: _tabLabel('Gelen', _incoming.length, scheme),
                ),
                Tab(
                  child: _tabLabel('Gönderilen', _outgoing.length, scheme),
                ),
              ],
            ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _loadError
                      ? ErrorRetry(onRetry: _load)
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

  Widget _tabLabel(String text, int count, ColorScheme scheme) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(text),
        if (count > 0) ...[
          const SizedBox(width: 5),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(
              color: scheme.primary,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text('$count',
                style: TextStyle(
                    color: scheme.onPrimary,
                    fontSize: 10,
                    fontWeight: FontWeight.w700)),
          ),
        ],
      ],
    );
  }

  Widget _searchResults(ColorScheme scheme) {
    if (_searching) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 6),
        child: LinearProgressIndicator(minHeight: 2),
      );
    }
    if (_results.isEmpty) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 10),
        child: Text('Eşleşen kullanıcı yok.',
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
      );
    }
    return Container(
      constraints: const BoxConstraints(maxHeight: 230),
      margin: const EdgeInsets.only(bottom: 6),
      child: ListView.builder(
        shrinkWrap: true,
        padding: EdgeInsets.zero,
        itemCount: _results.length,
        itemBuilder: (context, i) {
          final r = _results[i];
          final name = (r.name?.trim().isNotEmpty ?? false)
              ? r.name!
              : r.email;
          return ListTile(
            dense: true,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 20, vertical: 0),
            leading: CircleAvatar(
              radius: 16,
              backgroundColor: AppTheme.heroGreenBg,
              backgroundImage:
                  (r.avatarUrl != null && r.avatarUrl!.isNotEmpty)
                      ? NetworkImage(r.avatarUrl!)
                      : null,
              child: (r.avatarUrl == null || r.avatarUrl!.isEmpty)
                  ? Text(
                      name.trim().isNotEmpty
                          ? name.trim()[0].toUpperCase()
                          : '?',
                      style: TextStyle(
                          fontWeight: FontWeight.w700, color: scheme.primary),
                    )
                  : null,
            ),
            title: Text(name,
                style: const TextStyle(
                    fontSize: 13.5, fontWeight: FontWeight.w600)),
            subtitle: Text(_maskEmail(r.email),
                style: TextStyle(
                    fontSize: 11, color: scheme.onSurfaceVariant)),
            trailing: TextButton(
              onPressed: () => _sendTo(r.email),
              child: const Text('Ekle'),
            ),
          );
        },
      ),
    );
  }

  Widget _friendsTab(ColorScheme scheme) {
    if (_friends.isEmpty) {
      return const EmptyState(
        icon: Icons.group_outlined,
        title: 'Henüz arkadaşın yok',
        message: 'Yukarıdaki arama kutusuna adını veya e-postasını yazarak '
            'arkadaş ekle. Listelerini paylaşabilirsin.',
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: _friends.length,
        itemBuilder: (context, i) {
          final f = _friends[i];
          final hasName =
              f.friendName != null && f.friendName!.trim().isNotEmpty;
          return _row(
            scheme,
            name: f.displayName,
            subtitle: hasName ? f.friendEmail : null,
            avatarUrl: f.avatarUrl,
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
      return EmptyState(
        icon: incoming ? Icons.inbox_outlined : Icons.send_outlined,
        title: incoming ? 'Gelen istek yok' : 'Gönderilmiş istek yok',
        message: incoming
            ? 'Biri sana arkadaşlık isteği gönderdiğinde burada görünür.'
            : 'Gönderdiğin istekler kabul edilene kadar burada bekler.',
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: list.length,
        itemBuilder: (context, i) {
          final r = list[i];
          final name =
              r.displayName.isEmpty ? 'Kullanıcı' : r.displayName;
          final hasName =
              r.otherName != null && r.otherName!.trim().isNotEmpty;
          return _row(
            scheme,
            name: name,
            subtitle: hasName ? r.otherEmail : null,
            avatarUrl: r.otherAvatarUrl,
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

  Widget _row(
    ColorScheme scheme, {
    required String name,
    String? subtitle,
    String? avatarUrl,
    required Widget trailing,
  }) {
    final letter = name.trim().isNotEmpty ? name.trim()[0].toUpperCase() : '?';
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
      leading: CircleAvatar(
        backgroundColor: AppTheme.heroGreenBg,
        backgroundImage: (avatarUrl != null && avatarUrl.isNotEmpty)
            ? NetworkImage(avatarUrl)
            : null,
        child: (avatarUrl == null || avatarUrl.isEmpty)
            ? Text(letter,
                style: TextStyle(
                    fontWeight: FontWeight.w700, color: scheme.primary))
            : null,
      ),
      title: Text(name,
          style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
          maxLines: 1,
          overflow: TextOverflow.ellipsis),
      subtitle: subtitle == null
          ? null
          : Text(subtitle,
              style: TextStyle(
                  fontSize: 11, color: scheme.onSurfaceVariant),
              maxLines: 1,
              overflow: TextOverflow.ellipsis),
      trailing: trailing,
    );
  }

}
