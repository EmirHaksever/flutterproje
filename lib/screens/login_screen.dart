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

  static const Color _navy = Color(0xFF1F2D5A);

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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final headlineDark = isDark ? scheme.onSurface : _navy;
    final bg = isDark ? scheme.surface : const Color(0xFFF1F8F3);

    return Scaffold(
      backgroundColor: bg,
      body: Stack(
        children: [
          // Arka plan dekoru — yumuşak yeşil dalgalar
          Positioned(
            top: -120,
            right: -100,
            child: _blob(220, scheme.primary.withValues(alpha: isDark ? 0.10 : 0.12)),
          ),
          Positioned(
            bottom: -140,
            left: -110,
            child: _blob(260, scheme.primary.withValues(alpha: isDark ? 0.08 : 0.10)),
          ),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 28),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(height: 24),
                      const _GroceryArtwork(),
                      const SizedBox(height: 22),
                      _headline(headlineDark, scheme.primary),
                      const SizedBox(height: 10),
                      Text(
                        'Paylaşımlı listeler, akıllı öneriler ve '
                        'istatistiklerle her şey elinin altında.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 13.5,
                          height: 1.45,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 26),
                      _field(
                        controller: _emailController,
                        hint: 'E-posta adresiniz',
                        icon: Icons.mail_outline,
                        keyboardType: TextInputType.emailAddress,
                      ),
                      const SizedBox(height: 14),
                      _field(
                        controller: _passwordController,
                        hint: 'Şifreniz',
                        icon: Icons.lock_outline,
                        obscure: _obscurePassword,
                        onSubmitted: (_) => _isLoading ? null : _authUser(),
                        suffix: IconButton(
                          icon: Icon(
                            _obscurePassword
                                ? Icons.visibility_off_outlined
                                : Icons.visibility_outlined,
                            color: scheme.onSurfaceVariant,
                          ),
                          onPressed: () => setState(
                              () => _obscurePassword = !_obscurePassword),
                        ),
                      ),
                      if (_isLogin)
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton(
                            onPressed: _forgotPassword,
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 6),
                              minimumSize: Size.zero,
                              tapTargetSize:
                                  MaterialTapTargetSize.shrinkWrap,
                            ),
                            child: const Text('Şifremi Unuttum?'),
                          ),
                        )
                      else
                        const SizedBox(height: 18),
                      const SizedBox(height: 14),
                      SizedBox(
                        width: double.infinity,
                        height: 54,
                        child: FilledButton(
                          onPressed: _isLoading ? null : _authUser,
                          style: FilledButton.styleFrom(
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                            textStyle: const TextStyle(
                                fontSize: 16, fontWeight: FontWeight.w700),
                          ),
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
                            onTap: () =>
                                _snack('Google ile giriş yakında eklenecek.'),
                            child: const Text(
                              'G',
                              style: TextStyle(
                                fontSize: 21,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF4285F4),
                              ),
                            ),
                          ),
                          const SizedBox(width: 18),
                          _SocialButton(
                            onTap: () =>
                                _snack('Apple ile giriş yakında eklenecek.'),
                            child: Icon(Icons.apple,
                                size: 26, color: scheme.onSurface),
                          ),
                          const SizedBox(width: 18),
                          _SocialButton(
                            onTap: () => FocusScope.of(context).unfocus(),
                            child: Icon(Icons.mail_outline,
                                size: 23, color: scheme.primary),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            _isLogin
                                ? 'Hesabın yok mu? '
                                : 'Zaten hesabın var mı? ',
                            style:
                                TextStyle(color: scheme.onSurfaceVariant),
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
                                fontWeight: FontWeight.w800,
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
        ],
      ),
    );
  }

  Widget _blob(double size, Color color) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      );

  Widget _headline(Color darkColor, Color accent) {
    return RichText(
      textAlign: TextAlign.center,
      text: TextSpan(
        style: TextStyle(
          fontSize: 26,
          fontWeight: FontWeight.w800,
          height: 1.22,
          color: darkColor,
        ),
        children: [
          const TextSpan(text: 'Alışverişini kolaylaştır,\n'),
          TextSpan(text: 'zaman kazan!', style: TextStyle(color: accent)),
        ],
      ),
    );
  }

  Widget _field({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    bool obscure = false,
    TextInputType? keyboardType,
    Widget? suffix,
    void Function(String)? onSubmitted,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: TextField(
        controller: controller,
        obscureText: obscure,
        keyboardType: keyboardType,
        textInputAction:
            obscure ? TextInputAction.done : TextInputAction.next,
        onSubmitted: onSubmitted,
        decoration: InputDecoration(
          hintText: hint,
          prefixIcon: Icon(icon, color: scheme.onSurfaceVariant),
          suffixIcon: suffix,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: scheme.outlineVariant),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: scheme.outlineVariant),
          ),
        ),
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

/// Renkli "market sepeti" illüstrasyonu — CustomPaint ile çizildi.
class _GroceryArtwork extends StatelessWidget {
  const _GroceryArtwork();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      width: 220,
      height: 176,
      child: CustomPaint(painter: _GroceryPainter()),
    );
  }
}

class _GroceryPainter extends CustomPainter {
  const _GroceryPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final p = Paint()..isAntiAlias = true;

    // Zemin gölgesi
    p.color = Colors.black.withValues(alpha: 0.08);
    canvas.drawOval(
      Rect.fromCenter(center: Offset(w / 2, h - 14), width: 150, height: 26),
      p,
    );

    // Arka yapraklar (sepetin ağzından çıkan yeşillik)
    void leaf(double cx, double cy, double r, Color c) {
      p.color = c;
      canvas.drawCircle(Offset(cx, cy), r, p);
    }

    leaf(w / 2 - 14, 44, 20, const Color(0xFF66BB6A));
    leaf(w / 2 + 10, 40, 17, const Color(0xFF81C784));
    leaf(w / 2 + 2, 30, 13, const Color(0xFF4CAF50));

    // Meyveler (rim üstünde)
    p.color = const Color(0xFFEF5350); // domates/elma
    canvas.drawCircle(Offset(w / 2 - 34, 58), 16, p);
    p.color = const Color(0xFFFFB300); // portakal
    canvas.drawCircle(Offset(w / 2 + 34, 56), 15, p);
    p.color = const Color(0xFFFFD54F); // limon
    canvas.drawCircle(Offset(w / 2 + 8, 62), 12, p);

    // Havuç
    final carrotPath = Path()
      ..moveTo(w / 2 + 46, 44)
      ..lineTo(w / 2 + 58, 50)
      ..lineTo(w / 2 + 44, 74)
      ..close();
    p.color = const Color(0xFFFB8C00);
    canvas.drawPath(carrotPath, p);
    p.color = const Color(0xFF66BB6A);
    canvas.drawCircle(Offset(w / 2 + 50, 42), 5, p);

    // Sepet ağzı (rim)
    final rimRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(w / 2 - 62, 66, 124, 20),
      const Radius.circular(10),
    );
    p.color = const Color(0xFF2E7D32);
    canvas.drawRRect(rimRect, p);

    // Sepet gövdesi (yukarı doğru genişleyen)
    final body = Path()
      ..moveTo(w / 2 - 58, 80)
      ..lineTo(w / 2 + 58, 80)
      ..lineTo(w / 2 + 44, 150)
      ..lineTo(w / 2 - 44, 150)
      ..close();
    p.shader = const LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [Color(0xFF43A047), Color(0xFF2E7D32)],
    ).createShader(Rect.fromLTWH(w / 2 - 58, 80, 116, 70));
    canvas.drawPath(body, p);
    p.shader = null;

    // Sepet dikey çizgileri
    p.color = Colors.white.withValues(alpha: 0.18);
    p.strokeWidth = 4;
    p.style = PaintingStyle.stroke;
    for (final dx in [-28.0, 0.0, 28.0]) {
      canvas.drawLine(
        Offset(w / 2 + dx, 86),
        Offset(w / 2 + dx * 0.78, 148),
        p,
      );
    }
    p.style = PaintingStyle.fill;

    // Dekoratif küçük yapraklar / noktalar
    p.color = const Color(0xFF81C784);
    canvas.drawCircle(const Offset(28, 40), 6, p);
    canvas.drawCircle(Offset(w - 26, 90), 5, p);
    p.color = const Color(0xFFFFCC80);
    canvas.drawCircle(Offset(w - 34, 34), 4, p);
    canvas.drawCircle(const Offset(34, 104), 4, p);
  }

  @override
  bool shouldRepaint(covariant _GroceryPainter oldDelegate) => false;
}

/// Beyaz, gölgeli, dairesel sosyal giriş butonu.
class _SocialButton extends StatelessWidget {
  const _SocialButton({required this.child, required this.onTap});

  final Widget child;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: Container(
        width: 54,
        height: 54,
        decoration: BoxDecoration(
          color: scheme.surface,
          shape: BoxShape.circle,
          border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.6)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 14,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Center(child: child),
      ),
    );
  }
}
