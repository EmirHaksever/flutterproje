import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// FCM cihaz token'ını yönetir: izin ister, token'ı `device_tokens` tablosuna
/// yazar, yenilenince günceller, uygulama ön plandayken de bildirimi gösterir.
/// Yalnızca Android'de çalışır (web/iOS'ta no-op).
class PushService {
  PushService._();
  static final PushService instance = PushService._();

  bool _started = false;
  final _local = FlutterLocalNotificationsPlugin();
  static const _channel = AndroidNotificationChannel(
    'default_channel',
    'Bildirimler',
    description: 'Liste, paylaşım ve arkadaşlık bildirimleri',
    importance: Importance.high,
  );

  bool get _supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  Future<bool> _prefEnabled() async {
    final p = await SharedPreferences.getInstance();
    return p.getBool('notificationsEnabled') ?? true;
  }

  /// Kullanıcı giriş yaptıktan sonra çağrılır.
  Future<void> start() async {
    if (_started || !_supported) return;
    if (!await _prefEnabled()) return;
    _started = true;
    try {
      await FirebaseMessaging.instance.requestPermission();
      await _initLocal();
      await _syncToken();
      FirebaseMessaging.instance.onTokenRefresh.listen(_saveToken);
      FirebaseMessaging.onMessage.listen(_showForeground);
    } catch (e) {
      debugPrint('PushService.start hata: $e');
    }
  }

  Future<void> _initLocal() async {
    const init = InitializationSettings(
      android: AndroidInitializationSettings('@drawable/ic_notification'),
    );
    await _local.initialize(init);
    await _local
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(_channel);
  }

  /// Uygulama ön plandayken FCM bildirimini sistem tepsisinde göster.
  void _showForeground(RemoteMessage m) {
    final n = m.notification;
    if (n == null) return;
    _local.show(
      n.hashCode,
      n.title ?? 'Alışveriş Listem',
      n.body ?? '',
      NotificationDetails(
        android: AndroidNotificationDetails(
          _channel.id,
          _channel.name,
          channelDescription: _channel.description,
          importance: Importance.high,
          priority: Priority.high,
          icon: '@drawable/ic_notification',
        ),
      ),
    );
  }

  Future<void> _syncToken() async {
    final token = await FirebaseMessaging.instance.getToken();
    if (token != null) await _saveToken(token);
  }

  Future<void> _saveToken(String token) async {
    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (uid == null) return;
    try {
      await Supabase.instance.client.from('device_tokens').upsert({
        'token': token,
        'user_id': uid,
        'platform': 'android',
        'updated_at': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      debugPrint('device token kaydedilemedi: $e');
    }
  }

  /// Bu cihazın token'ını `device_tokens`'tan siler.
  Future<void> clearOnLogout() async {
    if (!_supported) return;
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null) {
        await Supabase.instance.client
            .from('device_tokens')
            .delete()
            .eq('token', token);
      }
    } catch (e) {
      debugPrint('device token silinemedi: $e');
    }
  }

  /// Ayarlar'daki "Bildirimleri Etkinleştir" anahtarı bunu çağırır.
  /// Kapalı = token silinir = push gelmez. Açık = yeniden kaydedilir.
  Future<void> setEnabled(bool enabled) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool('notificationsEnabled', enabled);
    if (!_supported) return;
    if (enabled) {
      _started = false;
      await start();
    } else {
      _started = false;
      await clearOnLogout();
    }
  }
}
