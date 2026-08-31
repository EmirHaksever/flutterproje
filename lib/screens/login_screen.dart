import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _isLoading = false;
  bool _isLogin = true;
  bool _obscurePassword = true;
  String _language = 'tr'; // Varsayılan dil Türkçe
  bool _rememberMe = false; // Yeni: Beni Hatırla durumu

  // Yeni eklenen vurgu rengi
  final Color _loginAccentColor = const Color(0xFF4DB6AC); // Material Teal 300

  @override
  void initState() {
    super.initState();
    _loadRememberMePreference(); // Beni Hatırla tercihini yükle
    // Navigasyon initState içinde doğrudan çağrılamaz; ilk kareden sonra çalıştır.
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkAutoLogin());
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  // "Beni Hatırla" tercihini ve (yalnızca) e-postayı yükle.
  // Şifre HİÇBİR ZAMAN saklanmaz — Supabase oturumu zaten güvenli tutuluyor.
  Future<void> _loadRememberMePreference() async {
    final prefs = await SharedPreferences.getInstance();

    // Eski sürümlerden kalmış olabilecek düz-metin şifreyi temizle (tek seferlik göç).
    await prefs.remove('password');

    if (!mounted) return;
    setState(() {
      _rememberMe = prefs.getBool('rememberMe') ?? false;
      if (_rememberMe) {
        _emailController.text = prefs.getString('email') ?? '';
      }
    });
  }

  // Otomatik giriş yalnızca geçerli bir Supabase oturumu varsa yapılır.
  // Supabase SDK oturumu güvenli depoda tutar ve access token'ı otomatik yeniler.
  void _checkAutoLogin() {
    final session = Supabase.instance.client.auth.currentSession;
    if (session != null && mounted) {
      debugPrint('Aktif Supabase oturumu var, ana sayfaya yönlendiriliyor.');
      Navigator.pushReplacementNamed(context, '/home');
    }
  }

  void _authUser() async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();

    try {
      final prefs = await SharedPreferences.getInstance();

      if (_isLogin) {
        final response = await Supabase.instance.client.auth.signInWithPassword(
          email: email,
          password: password,
        );

        if (response.session != null && mounted) {
          // "Beni Hatırla" yalnızca e-postayı bir sonraki açılışta hazır getirir.
          // Şifre asla saklanmaz; oturumu Supabase SDK güvenli şekilde yönetir.
          if (_rememberMe) {
            await prefs.setString('email', email);
            await prefs.setBool('rememberMe', true);
          } else {
            await prefs.remove('email');
            await prefs.setBool('rememberMe', false);
          }
          Navigator.pushReplacementNamed(context, '/home');
        }
      } else {
        // Kayıt olma
        final signUpResponse = await Supabase.instance.client.auth.signUp(
          email: email,
          password: password,
        );

        if (mounted) {
          if (signUpResponse.user != null) {
            if (signUpResponse.session == null) {
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Text(_language == 'tr'
                    ? 'Kayıt başarılı! Lütfen e-postanızı kontrol edin ve hesabınızı onaylayın. Onayladıktan sonra giriş yapabilirsiniz.'
                    : 'Registration successful! Please check your email to confirm your account. You can log in after confirmation.'),
                backgroundColor: _loginAccentColor,
                behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ));
            } else {
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Text(_language == 'tr'
                    ? 'Kayıt başarılı! Oturum açılıyor...'
                    : 'Registration successful! Logging in...'),
                backgroundColor: _loginAccentColor,
                behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ));
              Navigator.pushReplacementNamed(context, '/home');
            }
            setState(() {
              _isLogin = true;
            });
          } else {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text(_language == 'tr'
                  ? 'Kayıt olurken bir sorun oluştu. Lütfen bilgilerinizi kontrol edin ve tekrar deneyin.'
                  : 'An issue occurred during registration. Please check your details and try again.'),
              backgroundColor: Colors.red.shade400,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ));
          }
        }
      }
    } on AuthException catch (e) {
      if (!mounted) return;
      final errorMessage = _translateError(e.message);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(errorMessage),
        backgroundColor: Colors.red.shade400,
        behavior: SnackBarBehavior.floating, // Daha modern görünüm
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(_language == 'tr'
            ? 'Beklenmedik bir hata oluştu. Lütfen tekrar deneyin.'
            : 'An unexpected error occurred. Please try again.'),
        backgroundColor: Colors.red.shade400,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ));
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  String _translateError(String message) {
    final errors = {
      'Invalid login credentials': {
        'tr': 'Geçersiz e-posta veya şifre.',
        'en': 'Invalid email or password.'
      },
      'User already registered': {
        'tr': 'Bu e-posta ile zaten kayıt olunmuş.',
        'en': 'This email is already registered.'
      },
      'Email not confirmed': {
        'tr': 'E-posta adresiniz henüz onaylanmamış. Lütfen e-postanızı kontrol edin.',
        'en': 'Email address is not confirmed yet. Please check your email.'
      },
      'Password should be at least': {
        'tr': 'Şifre en az 6 karakter olmalıdır.',
        'en': 'Password must be at least 6 characters.'
      },
      'network-request-failed': {
        'tr': 'İnternet bağlantınızı kontrol edin.',
        'en': 'Check your internet connection.'
      },
      'Invalid email format': {
        'tr': 'Geçersiz e-posta formatı.',
        'en': 'Invalid email format.'
      },
      'Unable to connect to the server': { // Supabase bağlantı hatası için eklendi
        'tr': 'Sunucuya bağlanılamadı. İnternet bağlantınızı kontrol edin.',
        'en': 'Unable to connect to the server. Check your internet connection.'
      },
       'User already confirmed': { // Supabase'in "User already confirmed" hatası için eklendi
        'tr': 'Bu e-posta adresi zaten onaylanmış.',
        'en': 'This email address is already confirmed.'
      },
    };

    for (var key in errors.keys) {
      if (message.contains(key)) {
        return errors[key]?[_language] ?? message;
      }
    }

    return _language == 'tr' ? 'Bir hata oluştu: $message' : 'Error: $message';
  }

  // Degrade renkler güncellendi: Çok açık ve ferah yeşil-mavi tonları
  List<Color> _getBackgroundGradientColors() {
    return [
      const Color(0xFFF0FFF0), // Honeydew (Çok açık yeşil, beyaza yakın)
      const Color(0xFFE0FFFF), // Light Cyan (Açık cam göbeği/turkuaz, beyaza yakın)
    ];
  }

  @override
  Widget build(BuildContext context) {
    final isTurkish = _language == 'tr';
    final primaryColor = Theme.of(context).primaryColor; 

    return Scaffold(
      // Arka planı degrade ile kapla
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: _getBackgroundGradientColors(),
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Card( // Giriş formu için kart yapısı
                elevation: 10, // Hafif yükseltilmiş
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20), // Yuvarlak köşeler
                ),
                margin: const EdgeInsets.symmetric(horizontal: 20),
                child: Padding(
                  padding: const EdgeInsets.all(28),
                  child: Column(
                    mainAxisSize: MainAxisSize.min, // İçeriğe göre boyutlan
                    children: [
                      // Uygulamanızın Logosu veya Başlık
                      Icon(
                        Icons.shopping_basket_rounded, // Sepet ikonu
                        size: 80,
                        color: _loginAccentColor, // Vurgu rengi kullanıldı
                      ),
                      const SizedBox(height: 16),
                      Text(
                        _isLogin
                            ? (isTurkish ? 'Giriş Yap' : 'Login')
                            : (isTurkish ? 'Kayıt Ol' : 'Register'),
                        style: TextStyle(
                            fontSize: 32,
                            fontWeight: FontWeight.bold,
                            color: Colors.grey.shade800),
                      ),
                      const SizedBox(height: 30),

                      // E-posta Giriş Alanı
                      TextField(
                        controller: _emailController,
                        keyboardType: TextInputType.emailAddress,
                        decoration: InputDecoration(
                          labelText: isTurkish ? 'E-posta' : 'Email',
                          hintText: 'ornek@email.com',
                          prefixIcon: Icon(Icons.email_outlined, color: _loginAccentColor.withValues(alpha: 0.7)), // Vurgu rengi kullanıldı
                          filled: true,
                          fillColor: Colors.grey.shade100,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none, // Kenarlık çizgisi yok
                          ),
                          focusedBorder: OutlineInputBorder( // Odaklandığında kenarlık
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: _loginAccentColor, width: 2), // Vurgu rengi kullanıldı
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),

                      // Şifre Giriş Alanı
                      TextField(
                        controller: _passwordController,
                        obscureText: _obscurePassword,
                        decoration: InputDecoration(
                          labelText: isTurkish ? 'Şifre' : 'Password',
                          hintText: '••••••••',
                          prefixIcon: Icon(Icons.lock_outline, color: _loginAccentColor.withValues(alpha: 0.7)), // Vurgu rengi kullanıldı
                          filled: true,
                          fillColor: Colors.grey.shade100,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                          focusedBorder: OutlineInputBorder( // Odaklandığında kenarlık
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: _loginAccentColor, width: 2), // Vurgu rengi kullanıldı
                          ),
                          suffixIcon: IconButton(
                            icon: Icon(
                              _obscurePassword ? Icons.visibility_off : Icons.visibility,
                              color: Colors.grey.shade600,
                            ),
                            onPressed: () {
                              setState(() {
                                _obscurePassword = !_obscurePassword;
                              });
                            },
                          ),
                        ),
                      ),
                      const SizedBox(height: 10), // Boşluk eklendi

                      // Beni Hatırla Checkbox'ı
                      if (_isLogin) // Sadece giriş formunda göster
                        Align(
                          alignment: Alignment.centerLeft,
                          child: CheckboxListTile(
                            title: Text(
                              isTurkish ? 'Beni Hatırla' : 'Remember Me',
                              style: TextStyle(color: Colors.grey.shade700, fontSize: 14),
                            ),
                            value: _rememberMe,
                            onChanged: (bool? newValue) async {
                              setState(() {
                                _rememberMe = newValue ?? false;
                              });
                              final prefs = await SharedPreferences.getInstance();
                              await prefs.setBool('rememberMe', _rememberMe);
                              if (!_rememberMe) {
                                await prefs.remove('email');
                              }
                            },
                            controlAffinity: ListTileControlAffinity.leading, // Checkbox solda
                            contentPadding: EdgeInsets.zero, // İç boşlukları kaldır
                            activeColor: primaryColor, // Temanın ana rengini kullan
                          ),
                        ),
                      const SizedBox(height: 20), // Ek boşluk

                      // Giriş / Kayıt Butonu
                      _isLoading
                          ? CircularProgressIndicator(color: _loginAccentColor) // Vurgu rengi kullanıldı
                          : ElevatedButton(
                              onPressed: _authUser,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: _loginAccentColor, // Vurgu rengi kullanıldı
                                foregroundColor: Colors.white,
                                minimumSize: const Size.fromHeight(50), // Geniş buton
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(15), // Yuvarlak köşeler
                                ),
                                elevation: 5, // Hafif gölge
                              ),
                              child: Text(
                                _isLogin
                                    ? (isTurkish ? 'Giriş Yap' : 'Login')
                                    : (isTurkish ? 'Kayıt Ol' : 'Register'),
                                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                              ),
                            ),
                      const SizedBox(height: 20),

                      // Geçiş Butonu (Kayıt Ol / Giriş Yap)
                      TextButton(
                        onPressed: () {
                          setState(() => _isLogin = !_isLogin);
                          _emailController.clear();
                          _passwordController.clear();
                          _rememberMe = false; // Form değiştiğinde "beni hatırla" seçeneğini sıfırla
                        },
                        style: TextButton.styleFrom(
                          foregroundColor: _loginAccentColor.withValues(alpha: 0.8), // Vurgu rengi kullanıldı
                          textStyle: const TextStyle(fontSize: 16),
                        ),
                        child: Text(
                          _isLogin
                              ? (isTurkish
                                    ? 'Hesabın yok mu? Kayıt ol'
                                    : "Don't have an account? Register")
                              : (isTurkish
                                    ? 'Zaten hesabın var mı? Giriş yap'
                                    : 'Already have an account? Login'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
      appBar: AppBar(
        backgroundColor: Colors.transparent, // Şeffaf AppBar
        elevation: 0, // Gölge yok
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16.0),
            child: DropdownButton<String>(
              value: _language,
              underline: const SizedBox(),
              icon: Icon(Icons.language, color: Colors.grey.shade700), // İkon eklendi
              onChanged: (value) {
                setState(() => _language = value!);
              },
              items: const [
                DropdownMenuItem(value: 'tr', child: Text('🇹🇷 TR', style: TextStyle(color: Colors.black87))),
                DropdownMenuItem(value: 'en', child: Text('🇺🇸 EN', style: TextStyle(color: Colors.black87))),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
