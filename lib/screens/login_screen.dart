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
                  Container(
                    width: 120,
                    height: 120,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppTheme.heroGreenBg,
                      borderRadius: BorderRadius.circular(35),
                    ),
                    child: const CustomPaint(painter: _GroceryLogoPainter()),
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
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      const Expanded(child: Divider()),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Text('veya',
                            style:
                                TextStyle(color: scheme.onSurfaceVariant)),
                      ),
                      const Expanded(child: Divider()),
                    ],
                  ),
                  const SizedBox(height: 18),
                  OutlinedButton.icon(
                    onPressed: () =>
                        _snack('Google ile giriş yakında eklenecek.'),
                    icon: const Icon(Icons.g_mobiledata, size: 28),
                    label: const Text('Google ile devam et'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(double.infinity, 52),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
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

/// Giriş logosu — yeşil kese kâğıdı + üstünden taşan renkli ürünler.
class _GroceryLogoPainter extends CustomPainter {
  const _GroceryLogoPainter();

  static const _bagTop = Color(0xFF22C55E);
  static const _bagBottom = Color(0xFF15803D);
  static const _flap = Color(0xFF15803D);
  static const _tomato = Color(0xFFEF4444);
  static const _orange = Color(0xFFF59E0B);
  static const _carrot = Color(0xFFF97316);
  static const _greenA = Color(0xFF34D26A);
  static const _greenB = Color(0xFF4ADE80);

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final cx = w / 2;
    final s = w / 92; // ölçek
    final p = Paint()..isAntiAlias = true;

    void dot(double x, double y, double r, Color c) {
      p.color = c;
      canvas.drawCircle(Offset(x, y), r, p);
    }

    // Zemin gölgesi
    p.color = Colors.black.withValues(alpha: 0.06);
    canvas.drawOval(
      Rect.fromCenter(
          center: Offset(cx, h - 4 * s), width: 52 * s, height: 8 * s),
      p,
    );

    // Yeşillik (marul/brokoli)
    dot(cx - 4 * s, 18 * s, 10 * s, _greenA);
    dot(cx + 8 * s, 16 * s, 8 * s, _greenB);
    dot(cx - 16 * s, 20 * s, 7 * s, _greenB);

    // Domates
    dot(cx - 12 * s, 24 * s, 8 * s, _tomato);
    p.color = Colors.white.withValues(alpha: 0.5);
    canvas.drawCircle(Offset(cx - 15 * s, 21 * s), 2.2 * s, p);
    // Portakal
    dot(cx + 14 * s, 22 * s, 8 * s, _orange);
    p.color = Colors.white.withValues(alpha: 0.5);
    canvas.drawCircle(Offset(cx + 11 * s, 19 * s), 2.2 * s, p);

    // Havuç
    canvas.save();
    canvas.translate(cx + 22 * s, 16 * s);
    canvas.rotate(0.5);
    p.color = _carrot;
    canvas.drawPath(
      Path()
        ..moveTo(-5 * s, -8 * s)
        ..lineTo(5 * s, -8 * s)
        ..lineTo(0, 12 * s)
        ..close(),
      p,
    );
    p.color = _greenA;
    canvas.drawCircle(Offset(-2 * s, -9 * s), 2.6 * s, p);
    canvas.drawCircle(Offset(3 * s, -9 * s), 2.6 * s, p);
    canvas.restore();

    // Kese kâğıdının katlanmış kenarı
    p.color = _flap;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(cx - 33 * s, 30 * s, 66 * s, 12 * s),
        Radius.circular(6 * s),
      ),
      p,
    );

    // Kese gövdesi
    p.shader = const LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [_bagTop, _bagBottom],
    ).createShader(Rect.fromLTWH(cx - 30 * s, 36 * s, 60 * s, 50 * s));
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(cx - 30 * s, 36 * s, 60 * s, 50 * s),
        Radius.circular(12 * s),
      ),
      p,
    );
    p.shader = null;

    // Orta katlama çizgisi
    p.color = Colors.white.withValues(alpha: 0.16);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(cx - 1.5 * s, 40 * s, 3 * s, 42 * s),
        Radius.circular(2 * s),
      ),
      p,
    );
  }

  @override
  bool shouldRepaint(covariant _GroceryLogoPainter oldDelegate) => false;
}
