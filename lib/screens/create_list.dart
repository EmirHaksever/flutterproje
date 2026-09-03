import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../repositories/image_repository.dart';
import '../theme/app_theme.dart';
import '../widgets/ui_kit.dart';

class CreateListPage extends StatefulWidget {
  final String? initialFilterCategory;
  final List<Map<String, dynamic>> availableCategories;
  final MaterialColor customPrimarySwatch;

  const CreateListPage({
    super.key,
    this.initialFilterCategory,
    required this.availableCategories,
    required this.customPrimarySwatch,
  });

  @override
  State<CreateListPage> createState() => _CreateListPageState();
}

class _CreateListPageState extends State<CreateListPage> {
  final TextEditingController _listNameController = TextEditingController();
  final supabase = Supabase.instance.client;
  final ImagePicker _picker = ImagePicker();
  final ImageRepository _imageRepo = ImageRepository();

  final List<Map<String, dynamic>> products = [];
  bool _saving = false;

  static const Map<String, List<String>> _templates = {
    'Haftalık Market': ['Süt', 'Ekmek', 'Yumurta', 'Peynir', 'Domates'],
    'Aile Alışverişi': ['Süt', 'Ekmek', 'Makarna', 'Pirinç', 'Tavuk'],
    'Temizlik': [
      'Çamaşır Deterjanı',
      'Bulaşık Deterjanı',
      'Çöp Poşeti',
      'Kağıt Havlu'
    ],
    'Bebek': ['Bebek Bezi', 'Islak Mendil', 'Bebek Maması', 'Biberon'],
    'Kahvaltılık': ['Yumurta', 'Peynir', 'Zeytin', 'Bal', 'Tereyağı'],
  };

  @override
  void initState() {
    super.initState();
    if (widget.initialFilterCategory != null &&
        widget.initialFilterCategory!.isNotEmpty) {
      // Bir kategoriden gelindiyse ilk ürün o kategoride başlasın diye sakla.
      _pendingCategory = widget.initialFilterCategory;
    }
  }

  String? _pendingCategory;

  @override
  void dispose() {
    _listNameController.dispose();
    super.dispose();
  }

  void _applyTemplate(String key) {
    setState(() {
      if (_listNameController.text.trim().isEmpty) {
        _listNameController.text = key;
      }
      final existing =
          products.map((p) => (p['product_name'] as String).toLowerCase()).toSet();
      for (final name in _templates[key]!) {
        if (existing.contains(name.toLowerCase())) continue;
        products.add(_newProduct(name, _pendingCategory));
      }
    });
  }

  Map<String, dynamic> _newProduct(String name, String? category) => {
        'product_name': name,
        'category': category,
        'market': null,
        'quantity': 1,
        'tags': <String>[],
        'is_completed': false,
        'image_bytes': null,
        'image_ext': 'jpg',
        'image_url': null,
      };

  Future<(Uint8List, String)?> _pickImage() async {
    try {
      final picked = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1024,
        imageQuality: 78,
      );
      if (picked == null) return null;
      final bytes = await picked.readAsBytes();
      final ext = picked.name.contains('.')
          ? picked.name.split('.').last.toLowerCase()
          : 'jpg';
      return (bytes, ext);
    } catch (e) {
      debugPrint('Resim seçilemedi: $e');
      if (mounted) _snack('Resim seçilemedi.');
      return null;
    }
  }

  void _removeProduct(int index) {
    setState(() => products.removeAt(index));
  }

  void _changeQty(int index, int delta) {
    setState(() {
      final q = (products[index]['quantity'] as int? ?? 1) + delta;
      products[index]['quantity'] = q < 1 ? 1 : q;
    });
  }

  Future<void> _addProductSheet() async {
    final nameCtrl = TextEditingController();
    final marketCtrl = TextEditingController();
    final tagsCtrl = TextEditingController();
    String? category = _pendingCategory;
    int qty = 1;
    Uint8List? photoBytes;
    String photoExt = 'jpg';

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        final scheme = Theme.of(ctx).colorScheme;
        return Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
          ),
          child: StatefulBuilder(
            builder: (ctx, setSheet) => Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Ürün Ekle',
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: scheme.onSurface)),
                const SizedBox(height: 14),
                Row(
                  children: [
                    GestureDetector(
                      onTap: () async {
                        final picked = await _pickImage();
                        if (picked != null) {
                          setSheet(() {
                            photoBytes = picked.$1;
                            photoExt = picked.$2;
                          });
                        }
                      },
                      child: photoBytes == null
                          ? Container(
                              width: 56,
                              height: 56,
                              decoration: BoxDecoration(
                                color: AppTheme.heroGreenBg,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Icon(Icons.add_a_photo_outlined,
                                  color: scheme.primary),
                            )
                          : ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: Image.memory(photoBytes!,
                                  width: 56, height: 56, fit: BoxFit.cover),
                            ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: nameCtrl,
                        autofocus: true,
                        textCapitalization: TextCapitalization.sentences,
                        decoration: const InputDecoration(
                          hintText: 'Ürün adı (örn: Süt 1 L)',
                        ),
                      ),
                    ),
                  ],
                ),
                if (widget.availableCategories.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  Text('Kategori',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: scheme.onSurfaceVariant)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: widget.availableCategories.map((c) {
                      final name = c['name'].toString();
                      final sel = category == name;
                      return ChoiceChip(
                        label: Text(name),
                        selected: sel,
                        onSelected: (_) =>
                            setSheet(() => category = sel ? null : name),
                      );
                    }).toList(),
                  ),
                ],
                const SizedBox(height: 12),
                TextField(
                  controller: marketCtrl,
                  decoration:
                      const InputDecoration(hintText: 'Mağaza (opsiyonel)'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: tagsCtrl,
                  decoration: const InputDecoration(
                    hintText: 'Etiketler — virgülle ayır (opsiyonel)',
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Text('Adet',
                        style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: scheme.onSurface)),
                    const Spacer(),
                    _QtyStepper(
                      value: qty,
                      onChanged: (v) => setSheet(() => qty = v),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: FilledButton(
                    onPressed: () {
                      final name = nameCtrl.text.trim();
                      if (name.isEmpty) return;
                      setState(() {
                        final p = _newProduct(name, category);
                        p['quantity'] = qty;
                        p['market'] = marketCtrl.text.trim().isEmpty
                            ? null
                            : marketCtrl.text.trim();
                        p['tags'] = tagsCtrl.text
                            .split(',')
                            .map((e) => e.trim())
                            .where((e) => e.isNotEmpty)
                            .toList();
                        p['image_bytes'] = photoBytes;
                        p['image_ext'] = photoExt;
                        products.add(p);
                      });
                      Navigator.pop(ctx);
                    },
                    child: const Text('Ekle'),
                  ),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _saveList() async {
    if (_saving) return;
    final name = _listNameController.text.trim();
    if (name.isEmpty) {
      _snack('Liste adı boş olamaz.');
      return;
    }
    if (products.isEmpty) {
      _snack('En az bir ürün ekle.');
      return;
    }

    setState(() => _saving = true);
    try {
      // Önce eklenen fotoğrafları yükle (biri patlarsa o ürün resimsiz gider).
      for (final p in products) {
        final bytes = p['image_bytes'] as Uint8List?;
        if (bytes == null || p['image_url'] != null) continue;
        try {
          p['image_url'] = await _imageRepo.uploadProductImage(
            bytes,
            extension: (p['image_ext'] as String?) ?? 'jpg',
          );
        } catch (e) {
          debugPrint('Ürün resmi yüklenemedi: $e');
        }
      }

      final userId = supabase.auth.currentUser!.id;
      final newList = await supabase
          .from('shopping_lists')
          .insert({'name': name, 'user_id': userId})
          .select()
          .single();
      final listId = newList['id'];

      final items = products
          .map((p) => {
                'product_name': p['product_name'],
                'category': p['category'],
                'market': p['market'],
                'quantity': p['quantity'],
                'tags': p['tags'],
                'image_url': p['image_url'],
                'is_completed': false,
                'list_id': listId,
              })
          .toList();
      await supabase.from('list_items').insert(items);

      if (mounted) {
        _snack('Liste oluşturuldu.');
        Navigator.pop(context);
      }
    } catch (e) {
      debugPrint('Liste kaydedilemedi: $e');
      if (mounted) _snack('Liste kaydedilirken bir hata oluştu.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(title: const Text('Yeni Liste Oluştur')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 30),
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFDFF6E4), Color(0xFFF7FCF8)],
              ),
              borderRadius: BorderRadius.circular(24),
            ),
            child: Column(
              children: [
                Icon(Icons.playlist_add_rounded,
                    size: 52, color: scheme.primary),
                const SizedBox(height: 8),
                Text('Yeni listeni oluştur',
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: scheme.onSurface)),
                const SizedBox(height: 4),
                Text('Liste adını ver ve ürünlerini ekle.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 12, color: scheme.onSurfaceVariant)),
              ],
            ),
          ),
          const SizedBox(height: 24),
          _label(scheme, 'Liste Adı'),
          const SizedBox(height: 8),
          TextField(
            controller: _listNameController,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(hintText: 'Örn: Haftalık Market'),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 22),
          _label(scheme, 'Hızlı Şablonlar'),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _templates.keys
                .map((k) => ActionChip(
                      label: Text(k),
                      onPressed: () => _applyTemplate(k),
                    ))
                .toList(),
          ),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _label(scheme, 'Ürünler'),
              Text('${products.length} ürün',
                  style: TextStyle(
                      fontSize: 12, color: scheme.onSurfaceVariant)),
            ],
          ),
          const SizedBox(height: 10),
          if (products.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text('Henüz ürün eklenmedi.',
                  style: TextStyle(color: scheme.onSurfaceVariant)),
            )
          else
            ...List.generate(products.length, (i) => _productRow(scheme, i)),
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: _addProductSheet,
              icon: const Icon(Icons.add),
              label: const Text('Ürün Ekle'),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 52,
            width: double.infinity,
            child: FilledButton(
              onPressed: _saving ? null : _saveList,
              child: _saving
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                          strokeWidth: 2.4, color: Colors.white),
                    )
                  : const Text('Listeyi Oluştur'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _label(ColorScheme scheme, String text) => Text(
        text,
        style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: scheme.onSurface),
      );

  Widget _productRow(ColorScheme scheme, int i) {
    final p = products[i];
    final category = p['category'] as String?;
    final bytes = p['image_bytes'] as Uint8List?;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(12, 8, 6, 8),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        children: [
          if (bytes != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Image.memory(bytes, width: 38, height: 38, fit: BoxFit.cover),
            )
          else
            ProductThumb(
              emoji: category != null && category.isNotEmpty
                  ? categoryEmoji(category)
                  : null,
              size: 38,
              radius: 10,
            ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(p['product_name'] as String,
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 13),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
                if (category != null && category.isNotEmpty)
                  Text(category,
                      style: TextStyle(
                          fontSize: 11, color: scheme.onSurfaceVariant)),
              ],
            ),
          ),
          _QtyStepper(
            value: p['quantity'] as int? ?? 1,
            onChanged: (v) =>
                _changeQty(i, v - (p['quantity'] as int? ?? 1)),
            dense: true,
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: Icon(Icons.close, size: 18, color: scheme.onSurfaceVariant),
            onPressed: () => _removeProduct(i),
          ),
        ],
      ),
    );
  }
}

/// − sayı + adet seçici.
class _QtyStepper extends StatelessWidget {
  const _QtyStepper({
    required this.value,
    required this.onChanged,
    this.dense = false,
  });

  final int value;
  final ValueChanged<int> onChanged;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final s = dense ? 18.0 : 22.0;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          visualDensity: VisualDensity.compact,
          icon: Icon(Icons.remove, size: s, color: scheme.onSurfaceVariant),
          onPressed: value > 1 ? () => onChanged(value - 1) : null,
        ),
        SizedBox(
          width: 20,
          child: Text('$value',
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w700)),
        ),
        IconButton(
          visualDensity: VisualDensity.compact,
          icon: Icon(Icons.add, size: s, color: scheme.primary),
          onPressed: () => onChanged(value + 1),
        ),
      ],
    );
  }
}
