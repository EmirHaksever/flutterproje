import 'package:flutter/material.dart';

/// Uygulamanın varsayılan kategori kümesi.
///
/// Her giriş: `{ 'name': String, 'icon': IconData, 'colors': [Color, Color] }`.
/// `colors` bir degrade için başlangıç/bitiş renkleridir.
///
/// Daha önce bu liste main_navigation.dart, my_lists.dart ve home.dart içinde
/// ayrı ayrı (ve renkleri tutarsız biçimde) kopyalanmıştı; tek kaynak burası.
const List<Map<String, dynamic>> kDefaultCategories = [
  {
    'name': 'Market',
    'icon': Icons.local_grocery_store,
    'colors': [Color(0xFF56AB2F), Color(0xFFA8E063)],
  },
  {
    'name': 'Kıyafet',
    'icon': Icons.style,
    'colors': [Color(0xFFF7971E), Color(0xFFFFD200)],
  },
  {
    'name': 'Elektronik',
    'icon': Icons.devices_other,
    'colors': [Color(0xFF2193B0), Color(0xFF6DD5ED)],
  },
  {
    'name': 'Temizlik',
    'icon': Icons.cleaning_services,
    'colors': [Color(0xFF4CB8C4), Color(0xFF3CD3AD)],
  },
  {
    'name': 'Kırtasiye',
    'icon': Icons.school,
    'colors': [Color(0xFFFFCC33), Color(0xFFE2B00E)],
  },
  {
    'name': 'Evcil Hayvan',
    'icon': Icons.pets,
    'colors': [Color(0xFF536976), Color(0xFF292E49)],
  },
  {
    'name': 'Gıda',
    'icon': Icons.restaurant_menu,
    'colors': [Color(0xFFA8E063), Color(0xFF56AB2F)],
  },
  {
    'name': 'Bebek',
    'icon': Icons.child_care,
    'colors': [Color(0xFFFF9A9E), Color(0xFFFAD0C4)],
  },
];

/// Varsayılanlarda olmayan kategoriler için yedek görsel.
const IconData kFallbackCategoryIcon = Icons.category_outlined;
const List<Color> kFallbackCategoryColors = [Color(0xFF90A4AE), Color(0xFF607D8B)];

/// [kDefaultCategories] listesini, `list_items` içinde geçen ama varsayılanlarda
/// bulunmayan kategori adlarıyla birleştirir. Ad karşılaştırması harf-duyarsızdır.
List<Map<String, dynamic>> mergeDiscoveredCategories(Iterable<String> discovered) {
  final result = List<Map<String, dynamic>>.from(kDefaultCategories);
  for (final name in discovered) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) continue;
    final exists = result.any(
      (c) => (c['name'] as String).toLowerCase() == trimmed.toLowerCase(),
    );
    if (!exists) {
      result.add({
        'name': trimmed,
        'icon': kFallbackCategoryIcon,
        'colors': kFallbackCategoryColors,
      });
    }
  }
  return result;
}
