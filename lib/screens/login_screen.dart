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
  final _nameController = TextEditingController();

  bool _isLoading = false;
  bool _isLogin = true;
  bool _obscurePassword = true;

  @override
  void initState() {
    super.initState();
    _loadRememberedEmail();
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkAutoLogin());
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  // Yalnızca e-postayı hazır getirir. Şifre HİÇBİR ZAMAN saklanmaz.
  Future<void> _loadRememberedEmail() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('password'); // eski sürüm temizliği
    if (!mounted) return;
    setState(() => _emailController.text = prefs.getString('email') ?? '');
  }

  void _checkAutoLogin() {
    final session = Supabase.instance.client.auth.currentSession;
    if (session != null && mounted) {
      Navigator.pushReplacementNamed(context, '/home');
    }
  }

  void _authUser() async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();
    final name = _nameController.text.trim();

    if (!_isLogin && name.isEmpty) {
      _snack('Adını gir (arkadaşların seni isimle bulabilsin).', error: true);
      setState(() => _isLoading = false);
      return;
    }

    try {
      final prefs = await SharedPreferences.getInstance();

      if (_isLogin) {
        final response = await Supabase.instance.client.auth.signInWithPassword(
          email: email,
          password: password,
        );
        if (response.session != null) {
          await prefs.setString('email', email);
          if (!mounted) return;
          Navigator.pushReplacementNamed(context, '/home');
        }
      } else {
        final signUpResponse = await Supabase.instance.client.auth.signUp(
          email: email,
          password: password,
          data: {'name': name},
        );
        if (mounted) {
          if (signUpResponse.user != null) {
            // Oturum varsa adı users tablosuna da yaz (trigger + yedek).
            if (signUpResponse.session != null) {
              try {
                await Supabase.instance.client
                    .from('users')
                    .update({'name': name}).eq('id', signUpResponse.user!.id);
              } catch (_) {}
            }
            if (!mounted) return;
            if (signUpResponse.session == null) {
              _snack('Kayıt başarılı! E-postanı kontrol edip hesabını onayla, '
                  'sonra giriş yapabilirsin.');
            } else {
              _snack('Kayıt başarılı! Oturum açılıyor...');
              Navigator.pushReplacementNamed(context, '/home');
            }
            setState(() => _isLogin = true);
          } else {
            _snack('Kayıt sırasında bir sorun oluştu. Bilgilerini kontrol et.',
                error: true);
          }
        }
      }
    } on AuthException catch (e) {
      if (!mounted) return;
      _snack(_translateError(e.message), error: true);
    } catch (e) {
      if (!mounted) return;
      _snack('Beklenmedik bir hata oluştu. Lütfen tekrar dene.', error: true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _forgotPassword() async {
    final email = _emailController.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      _snack('Önce e-posta adresini yaz, sonra sıfırlama bağlantısı gönderelim.',
          error: true);
      return;
    }
    try {
      await Supabase.instance.client.auth.resetPasswordForEmail(email);
      _snack('Şifre sıfırlama bağlantısı $email adresine gönderildi.');
    } catch (_) {
      _snack('Bağlantı gönderilemedi. Lütfen tekrar dene.', error: true);
    }
  }

  void _snack(String msg, {bool error = false}) {
    if (!mounted) return;
    final scheme = Theme.of(context).colorScheme;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: error ? scheme.error : scheme.primary,
    ));
  }

  String _translateError(String message) {
    final errors = {
      'Invalid login credentials': 'Geçersiz e-posta veya şifre.',
      'User already registered': 'Bu e-posta ile zaten kayıt olunmuş.',
      'Email not confirmed':
          'E-posta adresin henüz onaylanmamış. Lütfen e-postanı kontrol et.',
      'Password should be at least': 'Şifre en az 6 karakter olmalı.',
      'network-request-failed': 'İnternet bağlantını kontrol et.',
      'Invalid email format': 'Geçersiz e-posta formatı.',
      'Unable to connect to the server':
          'Sunucuya bağlanılamadı. İnternet bağlantını kontrol et.',
      'User already confirmed': 'Bu e-posta adresi zaten onaylanmış.',
    };
    for (final key in errors.keys) {
      if (message.contains(key)) return errors[key]!;
    }
    return 'Bir hata oluştu: $message';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                children: [
                  const SizedBox(height: 32),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(28),
                    child: Image.asset(
                      'assets/icon/app_icon.png',
                      width: 108,
                      height: 108,
                      fit: BoxFit.cover,
                    ),
                  ),
                  const SizedBox(height: 24),
                  RichText(
                    textAlign: TextAlign.center,
                    text: TextSpan(
                      style: TextStyle(
                        fontSize: 25,
                        fontWeight: FontWeight.w800,
                        height: 1.2,
                        color: scheme.onSurface,
                      ),
                      children: [
                        const TextSpan(text: 'Alışverişini kolaylaştır,\n'),
                        TextSpan(
                          text: 'zaman kazan!',
                          style: TextStyle(color: scheme.primary),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Paylaşımlı listeler, akıllı öneriler\n'
                    've alışveriş istatistikleri.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: scheme.onSurfaceVariant,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 35),
                  if (!_isLogin) ...[
                    TextField(
                      controller: _nameController,
                      textCapitalization: TextCapitalization.words,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.person_outline),
                        hintText: 'Ad Soyad',
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  TextField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.email_outlined),
                      hintText: 'E-posta adresiniz',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _passwordController,
                    obscureText: _obscurePassword,
                    onSubmitted: (_) => _isLoading ? null : _authUser(),
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.lock_outline),
                      suffixIcon: IconButton(
                        icon: Icon(_obscurePassword
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined),
                        onPressed: () => setState(
                            () => _obscurePassword = !_obscurePassword),
                      ),
                      hintText: 'Şifreniz',
                    ),
                  ),
                  if (_isLogin)
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: _forgotPassword,
                        child: const Text('Şifremi Unuttum?'),
                      ),
                    )
                  else
                    const SizedBox(height: 8),
                  const SizedBox(height: 5),
                  SizedBox(
                    height: 52,
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _isLoading ? null : _authUser,
                      child: _isLoading
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.4,
                                color: Colors.white,
                              ),
                            )
                          : Text(_isLogin ? 'Giriş Yap' : 'Kayıt Ol'),
                    ),
                  ),
                  const SizedBox(height: 22),
                  GestureDetector(
                    onTap: () {
                      setState(() => _isLogin = !_isLogin);
                      _passwordController.clear();
                    },
                    child: Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: _isLogin
                                ? 'Hesabın yok mu? '
                                : 'Zaten hesabın var mı? ',
                            style:
                                TextStyle(color: scheme.onSurfaceVariant),
                          ),
                          TextSpan(
                            text: _isLogin ? 'Kayıt Ol' : 'Giriş Yap',
                            style: TextStyle(
                              color: scheme.primary,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
