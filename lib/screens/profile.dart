import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart'; // SharedPreferences için ekle
import 'package:flutter/services.dart'; // Clipboard için ekle

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  final supabase = Supabase.instance.client;
  User? _currentUser;
  String? _userEmail;
  String? _currentUserId; // Kullanıcı ID'si için değişken
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
      _currentUserId = _currentUser?.id; // Kullanıcı ID'sini al

      // Opsiyonel: Eğer public.users tablonuzda ek profil bilgileri varsa buradan çekebilirsiniz
      // final response = await supabase
      //     .from('users') // 'public.users' tablonuzun adını doğru yazdığınızdan emin olun
      //     .select('*')
      //     .eq('id', _currentUser!.id)
      //     .single();
      // if (mounted) {
      //   setState(() {
      //     // Örneğin: _userName = response['name'];
      //   });
      // }
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
                    backgroundColor: primaryColor.withOpacity(0.2),
                    child: Icon(
                      Icons.person_rounded,
                      size: 70,
                      color: primaryColor,
                    ),
                  ),
                  const SizedBox(height: 20),
                  // Kullanıcı Adı/E-posta
                  Text(
                    _userEmail ?? 'Misafir Kullanıcı',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey.shade800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  // Kullanıcı ID'si (Yeni)
                  if (_currentUserId != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16.0),
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.grey[200],
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Flexible(
                              child: Text(
                                'Kullanıcı ID: $_currentUserId',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.grey.shade700,
                                ),
                                // overflow: TextOverflow.ellipsis, // Taşmayı engelle - KALDITILDI
                              ),
                            ),
                            const SizedBox(width: 8),
                            IconButton(
                              icon: Icon(Icons.copy, size: 18, color: primaryColor),
                              tooltip: 'ID\'yi Kopyala',
                              onPressed: () {
                                // ID kopyalama işlevi için
                                Clipboard.setData(ClipboardData(text: _currentUserId!)); // ID'yi panoya kopyala
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Kullanıcı ID\'si kopyalandı!')),
                                );
                              },
                            ),
                          ],
                        ),
                      ),
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
