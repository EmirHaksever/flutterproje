import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../repositories/image_repository.dart';
import '../repositories/user_repository.dart';
import '../theme/app_theme.dart';
import 'friends_screen.dart';
import 'notifications_screen.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  final supabase = Supabase.instance.client;
  final UserRepository _userRepo = UserRepository();
  final ImageRepository _imageRepo = ImageRepository();
  final ImagePicker _picker = ImagePicker();

  String? _userEmail;
  String? _userName;
  String? _avatarUrl;
  int _listCount = 0;
  int _friendCount = 0;
  int _shareCount = 0;
  bool _isLoading = true;
  bool _uploadingAvatar = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      final uid = supabase.auth.currentUser?.id;
      _userEmail = supabase.auth.currentUser?.email;

      final profile = await _userRepo.fetchMyProfile();
      _userName = profile?['name'] as String?;
      _avatarUrl = profile?['avatar_url'] as String?;

      if (uid != null) {
        final lists = await supabase
            .from('shopping_lists')
            .select('id')
            .eq('user_id', uid)
            .count(CountOption.exact);
        _listCount = lists.count;

        try {
          final friends = await supabase
              .from('friends')
              .select('id')
              .eq('user_id', uid)
              .eq('status', 'accepted')
              .count(CountOption.exact);
          _friendCount = friends.count;
        } catch (_) {}

        final myListIds =
            (lists.data as List).map((e) => e['id']).toList();
        if (myListIds.isNotEmpty) {
          try {
            final shared = await supabase
                .from('shared_lists')
                .select('id')
                .filter('list_id', 'in', '(${myListIds.join(',')})')
                .count(CountOption.exact);
            _shareCount = shared.count;
          } catch (_) {}
        }
      }
      if (mounted) setState(() {});
    } catch (e) {
      debugPrint('Profil yüklenemedi: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _pickAndUploadAvatar() async {
    try {
      final picked = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 720,
        imageQuality: 80,
      );
      if (picked == null) return;
      final Uint8List bytes = await picked.readAsBytes();
      final ext = picked.name.contains('.')
          ? picked.name.split('.').last.toLowerCase()
          : 'jpg';

      setState(() => _uploadingAvatar = true);
      final url = await _imageRepo.uploadAvatar(bytes, extension: ext);
      await _userRepo.updateAvatarUrl(url);
      if (mounted) {
        setState(() {
          _avatarUrl = url;
          _uploadingAvatar = false;
        });
        _snack('Profil fotoğrafın güncellendi.');
      }
    } catch (e) {
      debugPrint('Avatar yüklenemedi: $e');
      if (mounted) {
        setState(() => _uploadingAvatar = false);
        _snack(
            'Fotoğraf yüklenemedi. (avatar migration\'ı uygulandı mı?)',
            error: true);
      }
    }
  }

  Future<void> _editName() async {
    final controller = TextEditingController(text: _userName ?? '');
    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Adını düzenle'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            labelText: 'Ad',
            prefixIcon: Icon(Icons.person_outline),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('İptal')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Kaydet'),
          ),
        ],
      ),
    );
    if (newName == null || newName.isEmpty || newName == _userName) return;
    try {
      await _userRepo.updateName(newName);
      if (mounted) {
        setState(() => _userName = newName);
        _snack('Adın güncellendi.');
      }
    } catch (_) {
      if (mounted) _snack('Ad güncellenemedi.', error: true);
    }
  }

  Future<void> _signOut() async {
    try {
      await supabase.auth.signOut();
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('email');
      if (mounted) {
        Navigator.pushNamedAndRemoveUntil(
            context, '/login', (route) => false);
      }
    } catch (e) {
      if (mounted) _snack('Çıkış yapılamadı.', error: true);
    }
  }

  void _showHelp() {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        final scheme = Theme.of(ctx).colorScheme;
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Yardım & Destek',
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: scheme.onSurface)),
              const SizedBox(height: 12),
              const _Faq(
                q: 'Bir listeyi nasıl paylaşırım?',
                a: 'Liste detayında sağ üstteki kişi-ekle simgesine dokun, '
                    'paylaşmak istediğin kişinin e-postasını gir.',
              ),
              const _Faq(
                q: 'Ürüne fotoğraf nasıl eklerim?',
                a: 'Ürün eklerken veya düzenlerken soldaki fotoğraf kutusuna '
                    'dokun ve galeriden bir görsel seç.',
              ),
              const _Faq(
                q: 'AI Asistan ne yapar?',
                a: 'Elindeki ürünlerle yemek önerir, sık aldıklarından liste '
                    'çıkarır, stok durumunu özetler.',
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Icon(Icons.mail_outline,
                      size: 18, color: scheme.onSurfaceVariant),
                  const SizedBox(width: 8),
                  Text('destek@alisverislistem.app',
                      style: TextStyle(color: scheme.onSurfaceVariant)),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  void _snack(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: error ? Theme.of(context).colorScheme.error : null,
    ));
  }

  void _push(Widget page) =>
      Navigator.push(context, MaterialPageRoute(builder: (_) => page));

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 30),
                children: [
                  Row(
                    children: [
                      IconButton(
                        padding: EdgeInsets.zero,
                        icon: const Icon(Icons.settings_outlined),
                        tooltip: 'Ayarlar',
                        onPressed: () =>
                            Navigator.pushNamed(context, '/settings'),
                      ),
                      const Spacer(),
                      IconButton(
                        padding: EdgeInsets.zero,
                        icon: const Icon(Icons.edit_outlined),
                        tooltip: 'Adı düzenle',
                        onPressed: _editName,
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  Center(child: _avatar(scheme)),
                  const SizedBox(height: 14),
                  Center(
                    child: Text(
                      (_userName?.trim().isNotEmpty ?? false)
                          ? _userName!
                          : 'İsimsiz',
                      style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          color: scheme.onSurface),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Center(
                    child: Text(_userEmail ?? 'Misafir',
                        style: TextStyle(
                            fontSize: 12,
                            color: scheme.onSurfaceVariant)),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      _stat('$_listCount', 'Liste'),
                      _stat('$_friendCount', 'Arkadaş'),
                      _stat('$_shareCount', 'Paylaşım'),
                    ],
                  ),
                  const SizedBox(height: 24),
                  _tile(scheme, Icons.people_outline, 'Arkadaşlar',
                      () => _push(const FriendsScreen())),
                  _tile(scheme, Icons.notifications_none, 'Bildirimler',
                      () => _push(const NotificationsScreen())),
                  _tile(scheme, Icons.settings_outlined, 'Ayarlar',
                      () => Navigator.pushNamed(context, '/settings')),
                  _tile(scheme, Icons.help_outline, 'Yardım & Destek',
                      _showHelp),
                  const SizedBox(height: 20),
                  SizedBox(
                    height: 50,
                    child: FilledButton.icon(
                      onPressed: _signOut,
                      icon: const Icon(Icons.logout),
                      label: const Text('Çıkış Yap'),
                      style: FilledButton.styleFrom(
                        backgroundColor: scheme.errorContainer,
                        foregroundColor: scheme.onErrorContainer,
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _avatar(ColorScheme scheme) {
    return GestureDetector(
      onTap: _uploadingAvatar ? null : _pickAndUploadAvatar,
      child: Stack(
        children: [
          CircleAvatar(
            radius: 48,
            backgroundColor: AppTheme.heroGreenBg,
            backgroundImage: (_avatarUrl != null && _avatarUrl!.isNotEmpty)
                ? NetworkImage(_avatarUrl!)
                : null,
            child: (_avatarUrl == null || _avatarUrl!.isEmpty)
                ? Icon(Icons.person, size: 52, color: scheme.primary)
                : null,
          ),
          Positioned(
            right: 0,
            bottom: 0,
            child: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: scheme.primary,
                shape: BoxShape.circle,
                border: Border.all(color: scheme.surface, width: 2),
              ),
              child: _uploadingAvatar
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : Icon(Icons.photo_camera_outlined,
                      size: 14, color: scheme.onPrimary),
            ),
          ),
        ],
      ),
    );
  }

  Widget _stat(String value, String label) {
    final scheme = Theme.of(context).colorScheme;
    return Expanded(
      child: Column(
        children: [
          Text(value,
              style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: scheme.onSurface)),
          const SizedBox(height: 2),
          Text(label,
              style: TextStyle(
                  fontSize: 11, color: scheme.onSurfaceVariant)),
        ],
      ),
    );
  }

  Widget _tile(ColorScheme scheme, IconData icon, String title,
      VoidCallback onTap) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      onTap: onTap,
      leading: Icon(icon, size: 22, color: scheme.onSurface),
      title: Text(title,
          style: const TextStyle(
              fontSize: 14, fontWeight: FontWeight.w600)),
      trailing:
          Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
    );
  }
}

class _Faq extends StatelessWidget {
  const _Faq({required this.q, required this.a});
  final String q;
  final String a;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        childrenPadding: const EdgeInsets.only(bottom: 10),
        title: Text(q,
            style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                color: scheme.onSurface)),
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Text(a,
                style: TextStyle(
                    fontSize: 12.5,
                    height: 1.4,
                    color: scheme.onSurfaceVariant)),
          ),
        ],
      ),
    );
  }
}
