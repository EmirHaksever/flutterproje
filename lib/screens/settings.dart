import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../controllers/settings_controller.dart';

class SettingsPage extends StatefulWidget {
  final void Function()? toggleTheme;
  final void Function(Locale)? changeLocale;

  const SettingsPage({super.key, this.toggleTheme, this.changeLocale});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final _settings = SettingsController.instance;
  bool _notifEnabled = true;

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((p) {
      if (mounted) {
        setState(() =>
            _notifEnabled = p.getBool('notificationsEnabled') ?? true);
      }
    });
  }

  String get _themeLabel => switch (_settings.themeMode) {
        ThemeMode.light => 'Açık',
        ThemeMode.dark => 'Koyu',
        ThemeMode.system => 'Sistem',
      };

  String get _langLabel =>
      _settings.locale.languageCode == 'en' ? 'English' : 'Türkçe';

  void _snack(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: error ? Theme.of(context).colorScheme.error : null,
    ));
  }

  Future<void> _pickTheme() async {
    final scheme = Theme.of(context).colorScheme;
    await showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final e in const {
            ThemeMode.system: ('Sistem', Icons.brightness_auto_outlined),
            ThemeMode.light: ('Açık', Icons.light_mode_outlined),
            ThemeMode.dark: ('Koyu', Icons.dark_mode_outlined),
          }.entries)
            ListTile(
              leading: Icon(e.value.$2),
              title: Text(e.value.$1),
              trailing: _settings.themeMode == e.key
                  ? Icon(Icons.check, color: scheme.primary)
                  : null,
              onTap: () {
                _settings.setThemeMode(e.key);
                setState(() {});
                Navigator.pop(ctx);
              },
            ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Future<void> _pickLanguage() async {
    final scheme = Theme.of(context).colorScheme;
    await showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final e in const {'tr': 'Türkçe', 'en': 'English'}.entries)
            ListTile(
              title: Text(e.value),
              trailing: _settings.locale.languageCode == e.key
                  ? Icon(Icons.check, color: scheme.primary)
                  : null,
              onTap: () {
                _settings.setLocale(Locale(e.key));
                widget.changeLocale?.call(Locale(e.key));
                setState(() {});
                Navigator.pop(ctx);
              },
            ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Future<void> _changePassword() async {
    final pw1 = TextEditingController();
    final pw2 = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Şifre Değiştir'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: pw1,
              obscureText: true,
              decoration: const InputDecoration(hintText: 'Yeni şifre'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: pw2,
              obscureText: true,
              decoration:
                  const InputDecoration(hintText: 'Yeni şifre (tekrar)'),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('İptal')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Kaydet')),
        ],
      ),
    );
    if (ok != true) return;
    final p1 = pw1.text.trim();
    if (p1.length < 6) {
      _snack('Şifre en az 6 karakter olmalı.', error: true);
      return;
    }
    if (p1 != pw2.text.trim()) {
      _snack('Şifreler eşleşmiyor.', error: true);
      return;
    }
    try {
      await Supabase.instance.client.auth
          .updateUser(UserAttributes(password: p1));
      _snack('Şifren güncellendi.');
    } catch (e) {
      debugPrint('Şifre güncellenemedi: $e');
      _snack('Şifre güncellenemedi. Yeniden giriş yapman gerekebilir.',
          error: true);
    }
  }

  Future<void> _sendPasswordReset() async {
    final email = Supabase.instance.client.auth.currentUser?.email;
    if (email == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Şifre Sıfırlama'),
        content: Text('$email adresine sıfırlama bağlantısı gönderilsin mi?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('İptal')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Gönder')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await Supabase.instance.client.auth.resetPasswordForEmail(email);
      _snack('Sıfırlama bağlantısı e-postana gönderildi.');
    } catch (_) {
      _snack('Bağlantı gönderilemedi.', error: true);
    }
  }

  Future<void> _setNotif(bool v) async {
    setState(() => _notifEnabled = v);
    final p = await SharedPreferences.getInstance();
    await p.setBool('notificationsEnabled', v);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(title: const Text('Ayarlar')),
      body: ListenableBuilder(
        listenable: _settings,
        builder: (context, _) => ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 30),
          children: [
            _sectionTitle('Görünüm'),
            _tile(Icons.brightness_6_outlined, 'Tema',
                value: _themeLabel, onTap: _pickTheme),
            _tile(Icons.language_outlined, 'Dil',
                value: _langLabel, onTap: _pickLanguage),
            const SizedBox(height: 20),
            _sectionTitle('Hesap'),
            _tile(Icons.lock_outline, 'Şifre Değiştir',
                onTap: _changePassword),
            _tile(Icons.vpn_key_outlined, 'Şifre Sıfırlama',
                onTap: _sendPasswordReset),
            const SizedBox(height: 20),
            _sectionTitle('Bildirimler'),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _notifEnabled,
              onChanged: _setNotif,
              title: const Text('Bildirimleri Etkinleştir',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
            ),
            const SizedBox(height: 20),
            _tile(Icons.info_outline, 'Uygulama Hakkında',
                value: 'v1.0.0',
                onTap: () => showAboutDialog(
                      context: context,
                      applicationName: 'Alışveriş Listem',
                      applicationVersion: '1.0.0',
                      applicationLegalese:
                          'Paylaşımlı alışveriş listesi + yapay zekâ asistanı.',
                    )),
          ],
        ),
      ),
    );
  }

  Widget _sectionTitle(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4, top: 4),
      child: Text(text,
          style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: Theme.of(context).colorScheme.onSurface)),
    );
  }

  Widget _tile(IconData icon, String title,
      {String? value, required VoidCallback onTap}) {
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      onTap: onTap,
      leading: Icon(icon, color: scheme.onSurface),
      title: Text(title,
          style: const TextStyle(
              fontSize: 14, fontWeight: FontWeight.w600)),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (value != null)
            Text(value,
                style: TextStyle(
                    fontSize: 12, color: scheme.onSurfaceVariant)),
          const SizedBox(width: 4),
          Icon(Icons.chevron_right, size: 20, color: scheme.onSurfaceVariant),
        ],
      ),
    );
  }
}
