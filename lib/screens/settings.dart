import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../controllers/settings_controller.dart';

class SettingsPage extends StatefulWidget {
  // main.dart hâlâ bu geri-çağrıları veriyor (SettingsController'a yönleniyorlar).
  final void Function()? toggleTheme;
  final void Function(Locale)? changeLocale;

  const SettingsPage({super.key, this.toggleTheme, this.changeLocale});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final _settings = SettingsController.instance;

  Future<void> _sendPasswordReset() async {
    final email = Supabase.instance.client.auth.currentUser?.email;
    if (email == null) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Şifre sıfırlama'),
        content: Text(
            '$email adresine bir şifre sıfırlama bağlantısı gönderilsin mi?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('İptal')),
          ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Gönder')),
        ],
      ),
    );
    if (ok != true) return;

    try {
      await Supabase.instance.client.auth.resetPasswordForEmail(email);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Sıfırlama bağlantısı e-postana gönderildi.')),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Bağlantı gönderilemedi.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Ayarlar')),
      body: ListenableBuilder(
        listenable: _settings,
        builder: (context, _) {
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const _SectionTitle('Görünüm'),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Tema',
                          style: TextStyle(fontWeight: FontWeight.w600)),
                      const SizedBox(height: 12),
                      SegmentedButton<ThemeMode>(
                        segments: const [
                          ButtonSegment(
                              value: ThemeMode.light,
                              icon: Icon(Icons.light_mode_outlined),
                              label: Text('Açık')),
                          ButtonSegment(
                              value: ThemeMode.system,
                              icon: Icon(Icons.brightness_auto_outlined),
                              label: Text('Sistem')),
                          ButtonSegment(
                              value: ThemeMode.dark,
                              icon: Icon(Icons.dark_mode_outlined),
                              label: Text('Koyu')),
                        ],
                        selected: {_settings.themeMode},
                        onSelectionChanged: (s) =>
                            _settings.setThemeMode(s.first),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.language),
                  title: const Text('Dil'),
                  trailing: DropdownButton<String>(
                    value: _settings.locale.languageCode,
                    underline: const SizedBox(),
                    onChanged: (v) {
                      if (v != null) _settings.setLocale(Locale(v));
                    },
                    items: const [
                      DropdownMenuItem(value: 'tr', child: Text('Türkçe')),
                      DropdownMenuItem(value: 'en', child: Text('English')),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const _SectionTitle('Hesap'),
              Card(
                child: ListTile(
                  leading: Icon(Icons.lock_reset, color: scheme.primary),
                  title: const Text('Şifreyi Sıfırla'),
                  subtitle:
                      const Text('E-postana sıfırlama bağlantısı gönderir'),
                  onTap: _sendPasswordReset,
                ),
              ),
              const SizedBox(height: 16),
              const _SectionTitle('Hakkında'),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.info_outline),
                  title: const Text('Alışveriş Listem'),
                  subtitle: const Text('Sürüm 1.0.0'),
                  onTap: () => showAboutDialog(
                    context: context,
                    applicationName: 'Alışveriş Listem',
                    applicationVersion: '1.0.0',
                    applicationLegalese:
                        'Paylaşımlı alışveriş listesi + yapay zekâ asistanı.',
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }
}
