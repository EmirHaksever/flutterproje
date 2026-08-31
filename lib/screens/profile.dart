import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../repositories/user_repository.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  final supabase = Supabase.instance.client;
  final UserRepository _userRepo = UserRepository();
  User? _currentUser;
  String? _userEmail;
  String? _userName;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadUserProfile();
  }

  Future<void> _loadUserProfile() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
    });
    try {
      _currentUser = supabase.auth.currentUser;
      _userEmail = _currentUser?.email;
      _userName = await _userRepo.fetchMyName();
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Profil bilgileri yüklenirken hata oluştu: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _signOut() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
    });
    try {
      await supabase.auth.signOut();
      // Çıkışta "beni hatırla" tercihini temizle (şifre zaten hiç saklanmıyor)
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('email');
      await prefs.setBool('rememberMe', false);

      if (mounted) {
        // Çıkış başarılı, login ekranına yönlendir
        Navigator.pushNamedAndRemoveUntil(context, '/login', (route) => false);
      }
    } on AuthException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Çıkış yaparken hata oluştu: ${e.message}')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Beklenmedik bir hata oluştu: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
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
          ElevatedButton(
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
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Adın güncellendi.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Ad güncellenemedi.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final primaryColor = Theme.of(context).primaryColor;

    return Scaffold(
      backgroundColor: Colors.grey[50], // Açık gri arka plan
      appBar: AppBar(
        title: const Text(
          'Profilim',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        backgroundColor: primaryColor,
        elevation: 0,
        centerTitle: true,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const SizedBox(height: 20),
                  // Profil Avatarı
                  CircleAvatar(
                    radius: 60,
                    backgroundColor: primaryColor.withValues(alpha: 0.2),
                    child: Icon(
                      Icons.person_rounded,
                      size: 70,
                      color: primaryColor,
                    ),
                  ),
                  const SizedBox(height: 20),
                  // Ad + düzenle
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Flexible(
                        child: Text(
                          (_userName?.trim().isNotEmpty ?? false)
                              ? _userName!
                              : 'İsimsiz',
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: Colors.grey.shade800,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: Icon(Icons.edit_outlined,
                            size: 20, color: primaryColor),
                        tooltip: 'Adı düzenle',
                        onPressed: _editName,
                      ),
                    ],
                  ),
                  Text(
                    _userEmail ?? 'Misafir Kullanıcı',
                    style: TextStyle(fontSize: 15, color: Colors.grey.shade600),
                  ),
                  const SizedBox(height: 30),

                  // Profil Seçenekleri Kartları
                  buildProfileOptionCard(
                    context,
                    icon: Icons.settings,
                    title: 'Ayarlar',
                    onTap: () {
                      // Ayarlar sayfasına yönlendirme (MainNavigationPage'de halihazırda var)
                      Navigator.pushNamed(context, '/settings');
                    },
                    primaryColor: primaryColor,
                  ),
                  const SizedBox(height: 12),
                  buildProfileOptionCard(
                    context,
                    icon: Icons.help_outline,
                    title: 'Yardım & Destek',
                    onTap: () {
                      // Yardım sayfasına yönlendirme
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Yardım ve Destek Sayfası')),
                      );
                    },
                    primaryColor: primaryColor,
                  ),
                  const SizedBox(height: 12),
                  // Çıkış Yap Butonu
                  ElevatedButton.icon(
                    onPressed: _signOut,
                    icon: const Icon(Icons.logout),
                    label: const Text('Çıkış Yap'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red.shade600,
                      foregroundColor: Colors.white,
                      minimumSize: const Size.fromHeight(50),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                      textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      elevation: 5,
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget buildProfileOptionCard(
    BuildContext context, {
    required IconData icon,
    required String title,
    required VoidCallback onTap,
    required Color primaryColor,
  }) {
    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(15),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
          child: Row(
            children: [
              Icon(icon, size: 28, color: primaryColor),
              const SizedBox(width: 20),
              Text(
                title,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w500,
                  color: Colors.grey.shade800,
                ),
              ),
              const Spacer(),
              Icon(Icons.arrow_forward_ios, size: 20, color: Colors.grey.shade400),
            ],
          ),
        ),
      ),
    );
  }
}
