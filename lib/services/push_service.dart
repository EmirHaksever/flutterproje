import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// FCM cihaz token'ını yönetir: izin ister, token'ı `device_tokens` tablosuna
/// yazar, yenilenince günceller. Yalnızca Android'de çalışır (web/iOS'ta no-op).
class PushService {
  PushService._();
  static final PushService instance = PushService._();

  bool _started = false;

  bool get _supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// Kullanıcı giriş yaptıktan sonra çağrılır.
  Future<void> start() async {
    if (_started || !_supported) return;
    _started = true;
    try {
      await FirebaseMessaging.instance.requestPermission();
      await _syncToken();
      FirebaseMessaging.instance.onTokenRefresh.listen(_saveToken);
    } catch (e) {
      debugPrint('PushService.start hata: $e');
    }
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

  /// Çıkışta bu cihazın token'ını siler (bildirimler artık gelmesin).
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
}
