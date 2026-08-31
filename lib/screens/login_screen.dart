import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../theme/app_theme.dart';

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
    super.dispose();
  }

  // Yalnızca e-postayı hazır getirir. Şifre HİÇBİR ZAMAN saklanmaz —
  // Supabase oturumu zaten güvenli tutuluyor.
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

    try {
      final prefs = await SharedPreferences.getInstance();

      if (_isLogin) {
        final response = await Supabase.instance.client.auth.signInWithPassword(
          email: email,
          password: password,
        );

        if (response.session != null && mounted) {
          await prefs.setString('email', email);
          Navigator.pushReplacementNamed(context, '/home');
        }
      } else {
        final signUpResponse = await Supabase.instance.client.auth.signUp(
          email: email,
          password: password,
        );

        if (mounted) {
          if (signUpResponse.user != null) {
            if (signUpResponse.session == null) {
              _snack(
                'Kayıt başarılı! E-postanı kontrol edip hesabını onayla, '
                'sonra giriş yapabilirsin.',
              );
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
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const _LoginArtwork(),
                  const SizedBox(height: 24),
                  _headline(scheme),
                  const SizedBox(height: 10),
                  Text(
                    'Paylaşımlı listeler, akıllı öneriler ve istatistiklerle '
                    'her şey tek elde.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13.5,
                      height: 1.4,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 28),
                  TextField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      hintText: 'E-posta adresiniz',
                      prefixIcon: Icon(Icons.mail_outline),
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _passwordController,
                    obscureText: _obscurePassword,
                    onSubmitted: (_) => _isLoading ? null : _authUser(),
                    decoration: InputDecoration(
                      hintText: 'Şifreniz',
                      prefixIcon: const Icon(Icons.lock_outline),
                      suffixIcon: IconButton(
                        icon: Icon(_obscurePassword
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined),
                        onPressed: () => setState(
                            () => _obscurePassword = !_obscurePassword),
                      ),
                    ),
                  ),
                  if (_isLogin)
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: _forgotPassword,
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: const Text('Şifremi Unuttum?'),
                      ),
                    )
                  else
                    const SizedBox(height: 16),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    height: 52,
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
                  _orDivider(scheme),
                  const SizedBox(height: 18),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _SocialButton(
                        label: 'Google',
                        child: Text(
                          'G',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                            color: scheme.onSurface,
                          ),
                        ),
                        onTap: () => _snack(
                            'Google ile giriş yakında eklenecek.'),
                      ),
                      const SizedBox(width: 16),
                      _SocialButton(
                        label: 'Apple',
                        child: Icon(Icons.apple, size: 24, color: scheme.onSurface),
                        onTap: () =>
                            _snack('Apple ile giriş yakında eklenecek.'),
                      ),
                      const SizedBox(width: 16),
                      _SocialButton(
                        label: 'E-posta',
                        child: Icon(Icons.mail_outline,
                            size: 22, color: scheme.onSurface),
                        onTap: () => FocusScope.of(context).unfocus(),
                      ),
                    ],
                  ),
                  const SizedBox(height: 26),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        _isLogin ? 'Hesabın yok mu? ' : 'Zaten hesabın var mı? ',
                        style: TextStyle(color: scheme.onSurfaceVariant),
                      ),
                      GestureDetector(
                        onTap: () {
                          setState(() => _isLogin = !_isLogin);
                          _passwordController.clear();
                        },
                        child: Text(
                          _isLogin ? 'Kayıt Ol' : 'Giriş Yap',
                          style: TextStyle(
                            color: scheme.primary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _headline(ColorScheme scheme) {
    return RichText(
      textAlign: TextAlign.center,
      text: TextSpan(
        style: TextStyle(
          fontSize: 25,
          fontWeight: FontWeight.w800,
          height: 1.25,
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
    );
  }

  Widget _orDivider(ColorScheme scheme) {
    final line = Expanded(
      child: Divider(color: scheme.outlineVariant, thickness: 1),
    );
    return Row(
      children: [
        line,
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text('veya',
              style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13)),
        ),
        line,
      ],
    );
  }
}

/// Giriş ekranının üstündeki dekoratif "alışveriş" görseli.
/// (Harici görsel dosyası yok; sade bir kompozisyonla yaklaşıyoruz.)
class _LoginArtwork extends StatelessWidget {
  const _LoginArtwork();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: 150,
      height: 150,
      decoration: const BoxDecoration(
        color: AppTheme.heroGreenBg,
        shape: BoxShape.circle,
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Icon(Icons.shopping_basket_rounded, size: 76, color: scheme.primary),
          Positioned(
            top: 30,
            right: 34,
            child: _dot(const Color(0xFFEF5350), 14),
          ),
          Positioned(
            top: 40,
            left: 32,
            child: _dot(const Color(0xFFFFB300), 11),
          ),
          Positioned(
            bottom: 34,
            left: 40,
            child: _dot(const Color(0xFF66BB6A), 12),
          ),
        ],
      ),
    );
  }

  Widget _dot(Color color, double size) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      );
}

/// Dairesel, kenarlıklı sosyal giriş butonu.
class _SocialButton extends StatelessWidget {
  const _SocialButton({
    required this.child,
    required this.label,
    required this.onTap,
  });

  final Widget child;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      label: label,
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: scheme.outlineVariant),
          ),
          child: Center(child: child),
        ),
      ),
    );
  }
}
