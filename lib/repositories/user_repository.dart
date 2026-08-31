import 'package:supabase_flutter/supabase_flutter.dart';

/// `public.users` tablosu (uygulama profili: ad, tercih edilen kategoriler).
class UserRepository {
  UserRepository({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  String get _uid {
    final id = _client.auth.currentUser?.id;
    if (id == null) throw StateError('Oturum yok.');
    return id;
  }

  /// Giriş yapan kullanıcının profil satırı (yoksa null).
  Future<Map<String, dynamic>?> fetchMyProfile() async {
    return _client.from('users').select().eq('id', _uid).maybeSingle();
  }

  Future<String?> fetchMyName() async {
    final row = await _client
        .from('users')
        .select('name')
        .eq('id', _uid)
        .maybeSingle();
    return row?['name'] as String?;
  }

  Future<void> updateName(String name) async {
    await _client.from('users').update({'name': name.trim()}).eq('id', _uid);
  }

  Future<void> updatePreferredCategories(List<String> categories) async {
    await _client
        .from('users')
        .update({'preferred_categories': categories}).eq('id', _uid);
  }
}
