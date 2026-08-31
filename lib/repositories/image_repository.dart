import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

/// Supabase Storage'a ürün fotoğrafı yükler / siler.
///
/// Dosyalar `product-images/<uid>/<zaman>.<uzantı>` yoluna konur; bucket
/// herkese açık okunur, yazma yalnızca kullanıcının kendi klasörüne.
class ImageRepository {
  ImageRepository({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;
  static const _bucket = 'product-images';

  Future<String> uploadProductImage(
    Uint8List bytes, {
    String extension = 'jpg',
  }) async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) throw StateError('Oturum yok.');

    final ext = extension.replaceAll('.', '').toLowerCase();
    final path = '$uid/${DateTime.now().millisecondsSinceEpoch}.$ext';
    final contentType = switch (ext) {
      'png' => 'image/png',
      'webp' => 'image/webp',
      'gif' => 'image/gif',
      _ => 'image/jpeg',
    };

    await _client.storage.from(_bucket).uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(contentType: contentType, upsert: false),
        );
    return _client.storage.from(_bucket).getPublicUrl(path);
  }

  /// Genel URL'den dosya yolunu çıkarıp siler (hatayı yutar).
  Future<void> deleteByUrl(String publicUrl) async {
    try {
      const marker = '/$_bucket/';
      final idx = publicUrl.indexOf(marker);
      if (idx == -1) return;
      final path = publicUrl.substring(idx + marker.length);
      await _client.storage.from(_bucket).remove([path]);
    } catch (_) {
      // sessiz geç
    }
  }
}
