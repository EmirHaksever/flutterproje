import 'package:flutter/material.dart';

class SettingsPage extends StatefulWidget {
  final void Function() toggleTheme;
  final void Function(Locale) changeLocale;

  const SettingsPage({
    super.key,
    required this.toggleTheme,
    required this.changeLocale,
  });

  @override
  _SettingsPageState createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool _isDarkMode = false;
  String _selectedLanguage = 'Türkçe';
  bool _isPushNotificationsEnabled = true;

  void _toggleDarkMode(bool value) {
    setState(() {
      _isDarkMode = value;
    });
    widget.toggleTheme();
  }

  void _changeLanguage(String? value) {
    if (value == null) return;
    setState(() {
      _selectedLanguage = value;
    });

    if (value == 'Türkçe') {
      widget.changeLocale(const Locale('tr', 'TR'));
    } else if (value == 'English') {
      widget.changeLocale(const Locale('en', 'US'));
    }
  }

  void _togglePushNotifications(bool value) {
    setState(() {
      _isPushNotificationsEnabled = value;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Ayarlar")),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ListTile(
              title: const Text("Tema"),
              subtitle: Text(_isDarkMode ? "Karanlık Mod" : "Aydınlık Mod"),
              trailing: Switch(
                value: _isDarkMode,
                onChanged: _toggleDarkMode,
              ),
            ),
            const Divider(),
            ListTile(
              title: const Text("Dil Seçimi"),
              subtitle: Text(_selectedLanguage),
              trailing: DropdownButton<String>(
                value: _selectedLanguage,
                onChanged: _changeLanguage,
                items: const [
                  DropdownMenuItem(value: 'Türkçe', child: Text('Türkçe')),
                  DropdownMenuItem(value: 'English', child: Text('English')),
                ],
              ),
            ),
            const Divider(),
            ListTile(
              title: const Text("Bildirimler"),
              subtitle:
                  Text(_isPushNotificationsEnabled ? "Açık" : "Kapalı"),
              trailing: Switch(
                value: _isPushNotificationsEnabled,
                onChanged: _togglePushNotifications,
              ),
            ),
            const Divider(),
            ListTile(
              title: const Text("Gizlilik ve Güvenlik"),
              subtitle: const Text("Şifre sıfırlama ve güvenlik ayarları"),
              onTap: () {},
            ),
            const Divider(),
            ListTile(
              title: const Text("Hakkında"),
              subtitle: const Text("Uygulama hakkında bilgi"),
              onTap: () {},
            ),
          ],
        ),
      ),
    );
  }
}
