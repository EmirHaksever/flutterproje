import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
// import 'package:image_picker/image_picker.dart'; // Kamera veya galeri için eklenebilir
// import 'package:path_provider/path_provider.dart'; // Resim yolu için
// import 'dart:io'; // File işlemleri için

class CreateListPage extends StatefulWidget {
  final String? initialFilterCategory; // Yeni: Başlangıç filtre kategorisi
  final List<Map<String, dynamic>> availableCategories; // Yeni: Tüm mevcut kategoriler
  final MaterialColor customPrimarySwatch; // Zorunlu parametre yapıldı

  const CreateListPage({
    super.key,
    this.initialFilterCategory,
    required this.availableCategories,
    required this.customPrimarySwatch, // Zorunlu parametre yapıldı
  });

  @override
  State<CreateListPage> createState() => _CreateListPageState();
}

class _CreateListPageState extends State<CreateListPage> {
  final TextEditingController _listNameController = TextEditingController();
  final TextEditingController _productNameController = TextEditingController();
  final TextEditingController _quantityController = TextEditingController(text: '1'); // Yeni: Adet sayısı için
  final TextEditingController _featuresController = TextEditingController(); // Yeni: Özellikler için
  final TextEditingController _newCategoryController = TextEditingController(); // Yeni kategori girişi için
  final TextEditingController _newMarketController = TextEditingController();   // Yeni market girişi için

  String? _selectedCategory; // Seçilen kategori Dropdown'dan gelir (veya "Yeni Kategori Ekle")
  String? _selectedMarket;   // Seçilen market Dropdown'dan gelir (veya "Yeni Mağaza Ekle")
  String? _filterCategory;   // Ürün listesini filtrelemek için kullanılan kategori

  bool _showNewCategoryInput = false; // Yeni kategori metin alanını göster/gizle
  bool _showNewMarketInput = false;   // Yeni market metin alanını göster/gizle

  List<Map<String, dynamic>> products = []; // Mevcut ürünler
  final supabase = Supabase.instance.client;

  // Mevcut marketler (şimdilik statik, ileride Supabase'den çekilebilir)
  final List<String> _availableMarkets = ['Migros', 'Carrefour', 'Şok', 'Bim', 'Yerel Market'];


  @override
  void initState() {
    super.initState();
    // Eğer bir başlangıç filtre kategorisi varsa, onu seçili hale getir
    if (widget.initialFilterCategory != null && widget.initialFilterCategory!.isNotEmpty) {
      _selectedCategory = widget.initialFilterCategory;
      _filterCategory = widget.initialFilterCategory; // Filtrelemek için de kullan
    }
    // İlk kategoriyi varsayılan olarak seç
    if (_selectedCategory == null && widget.availableCategories.isNotEmpty) {
      _selectedCategory = widget.availableCategories.first['name'].toString();
    }
  }

  @override
  void dispose() {
    _listNameController.dispose();
    _productNameController.dispose();
    _quantityController.dispose(); // Yeni controller dispose edildi
    _featuresController.dispose(); // Yeni controller dispose edildi
    _newCategoryController.dispose();
    _newMarketController.dispose();
    super.dispose();
  }

  void _addProduct() {
    if (_productNameController.text.isEmpty || _selectedCategory == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ürün adı ve kategori boş olamaz!')),
      );
      return;
    }

    final quantity = int.tryParse(_quantityController.text) ?? 1; // Adet sayısını al, varsayılan 1
    final features = _featuresController.text.trim().isNotEmpty
        ? _featuresController.text.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList()
        : <String>[]; // Özellikleri virgülle ayırarak al

    setState(() {
      products.add({
        'product_name': _productNameController.text,
        'category': _selectedCategory,
        'market': _selectedMarket,
        'quantity': quantity, // Adet sayısı eklendi
        'features': features, // Özellikler eklendi
        'is_completed': false, // Varsayılan olarak tamamlanmamış
      });
      _productNameController.clear();
      _quantityController.text = '1'; // Adet sayısını sıfırla
      _featuresController.clear(); // Özellikleri temizle
    });
  }

  void _removeProduct(int index) {
    setState(() {
      products.removeAt(index);
    });
  }

  Future<void> _saveList() async {
    if (_listNameController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Liste adı boş olamaz!')),
      );
      return;
    }
    if (products.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Listede ürün bulunmuyor!')),
      );
      return;
    }

    try {
      final userId = supabase.auth.currentUser!.id;
      // Yeni alışveriş listesi oluştur
      final newShoppingList = await supabase.from('shopping_lists').insert({
        'name': _listNameController.text,
        'user_id': userId,
      }).select().single();

      final listId = newShoppingList['id'];

      // Ürünleri list_items tablosuna ekle
      final itemsToInsert = products.map((product) {
        return {
          'product_name': product['product_name'],
          'category': product['category'],
          'market': product['market'],
          'quantity': product['quantity'], // Adet sayısı eklendi
          'features': product['features'], // Özellikler eklendi (List<String> olarak kaydedilecek)
          'is_completed': product['is_completed'],
          'list_id': listId,
        };
      }).toList();

      await supabase.from('list_items').insert(itemsToInsert);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Liste başarıyla kaydedildi!')),
        );
        Navigator.pop(context); // Mevcut CreateListPage'i kapat
        Navigator.pushReplacementNamed(context, '/home'); // Ana sayfaya dön
      }
    } catch (e) {
      debugPrint('Liste kaydedilirken hata oluştu: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Liste kaydedilirken bir hata oluştu: $e')),
        );
      }
    }
  }


  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    final filtered = products.where((p) {
      if (_filterCategory == null || _filterCategory == 'Tümü') return true;
      return p['category'] == _filterCategory;
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Yeni Liste'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
        children: [
          TextField(
            controller: _listNameController,
            decoration: const InputDecoration(
              labelText: 'Liste adı',
              hintText: 'Örn: Haftalık Market',
              prefixIcon: Icon(Icons.drive_file_rename_outline),
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 20),
          _sectionLabel(scheme, 'Ürün ekle'),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: _buildAddForm(scheme),
            ),
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _sectionLabel(scheme, 'Ürünler (${products.length})'),
              if (widget.availableCategories.isNotEmpty)
                _filterChip(scheme),
            ],
          ),
          const SizedBox(height: 8),
          if (filtered.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Text('Henüz ürün eklenmedi.',
                    style: TextStyle(color: scheme.onSurfaceVariant)),
              ),
            )
          else
            ...filtered.map((p) => _productCard(scheme, p)),
        ],
      ),
      bottomNavigationBar: Padding(
        padding: EdgeInsets.fromLTRB(
            16, 8, 16, 8 + MediaQuery.of(context).padding.bottom),
        child: FilledButton.icon(
          onPressed: _saveList,
          icon: const Icon(Icons.check_rounded),
          label: const Text('Listeyi Kaydet'),
          style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(50)),
        ),
      ),
    );
  }

  Widget _sectionLabel(ColorScheme scheme, String text) {
    return Text(text,
        style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.5,
            color: scheme.primary));
  }

  Widget _buildAddForm(ColorScheme scheme) {
    final catItems = [
      ...widget.availableCategories.map((c) => DropdownMenuItem(
          value: c['name'].toString(), child: Text(c['name'].toString()))),
      const DropdownMenuItem(
          value: 'Yeni Kategori Ekle', child: Text('+ Yeni kategori')),
    ];
    final marketItems = [
      ..._availableMarkets.map(
          (m) => DropdownMenuItem(value: m, child: Text(m))),
      const DropdownMenuItem(
          value: 'Yeni Mağaza Ekle', child: Text('+ Yeni mağaza')),
    ];

    return Column(
      children: [
        TextField(
          controller: _productNameController,
          decoration: const InputDecoration(
            labelText: 'Ürün adı',
            hintText: 'Örn: Süt',
            prefixIcon: Icon(Icons.shopping_basket_outlined),
          ),
          onSubmitted: (_) => _addProduct(),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _quantityController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Adet',
                  prefixIcon: Icon(Icons.tag),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: _featuresController,
                decoration: const InputDecoration(
                  labelText: 'Etiketler',
                  hintText: 'organik, büyük',
                ),
                onSubmitted: (_) => _addProduct(),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          initialValue: _selectedCategory,
          isExpanded: true,
          decoration: const InputDecoration(
            labelText: 'Kategori',
            prefixIcon: Icon(Icons.category_outlined),
          ),
          items: catItems,
          onChanged: (v) => setState(() {
            if (v == 'Yeni Kategori Ekle') {
              _showNewCategoryInput = true;
              _selectedCategory = null;
            } else {
              _selectedCategory = v;
              _showNewCategoryInput = false;
            }
          }),
        ),
        if (_showNewCategoryInput) ...[
          const SizedBox(height: 12),
          TextField(
            controller: _newCategoryController,
            decoration: InputDecoration(
              labelText: 'Yeni kategori adı',
              suffixIcon: IconButton(
                icon: Icon(Icons.check_circle, color: scheme.primary),
                onPressed: () {
                  if (_newCategoryController.text.trim().isNotEmpty) {
                    setState(() {
                      _selectedCategory = _newCategoryController.text.trim();
                      _showNewCategoryInput = false;
                      _newCategoryController.clear();
                    });
                  }
                },
              ),
            ),
          ),
        ],
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          initialValue: _selectedMarket,
          isExpanded: true,
          decoration: const InputDecoration(
            labelText: 'Mağaza (opsiyonel)',
            prefixIcon: Icon(Icons.storefront_outlined),
          ),
          items: marketItems,
          onChanged: (v) => setState(() {
            if (v == 'Yeni Mağaza Ekle') {
              _showNewMarketInput = true;
              _selectedMarket = null;
            } else {
              _selectedMarket = v;
              _showNewMarketInput = false;
            }
          }),
        ),
        if (_showNewMarketInput) ...[
          const SizedBox(height: 12),
          TextField(
            controller: _newMarketController,
            decoration: InputDecoration(
              labelText: 'Yeni mağaza adı',
              suffixIcon: IconButton(
                icon: Icon(Icons.check_circle, color: scheme.primary),
                onPressed: () {
                  if (_newMarketController.text.trim().isNotEmpty) {
                    setState(() {
                      _availableMarkets.add(_newMarketController.text.trim());
                      _selectedMarket = _newMarketController.text.trim();
                      _showNewMarketInput = false;
                      _newMarketController.clear();
                    });
                  }
                },
              ),
            ),
          ),
        ],
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: _addProduct,
            icon: const Icon(Icons.add_rounded),
            label: const Text('Ürünü listeye ekle'),
          ),
        ),
      ],
    );
  }

  Widget _filterChip(ColorScheme scheme) {
    return DropdownButtonHideUnderline(
      child: DropdownButton<String>(
        value: _filterCategory ?? 'Tümü',
        icon: const Icon(Icons.filter_list_rounded),
        style: TextStyle(color: scheme.onSurface, fontSize: 13),
        borderRadius: BorderRadius.circular(12),
        items: [
          const DropdownMenuItem(value: 'Tümü', child: Text('Tümü')),
          ...widget.availableCategories.map((c) => DropdownMenuItem(
              value: c['name'].toString(),
              child: Text(c['name'].toString()))),
        ],
        onChanged: (v) => setState(() => _filterCategory = v),
      ),
    );
  }

  Widget _productCard(ColorScheme scheme, Map<String, dynamic> p) {
    final realIndex = products.indexOf(p);
    final done = p['is_completed'] == true;
    final features = (p['features'] as List?)?.cast<String>() ?? const [];

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 4, 8, 4),
        child: Row(
          children: [
            Checkbox(
              value: done,
              onChanged: (v) =>
                  setState(() => products[realIndex]['is_completed'] = v),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    p['product_name'] ?? '',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                      decoration: done ? TextDecoration.lineThrough : null,
                      color: done
                          ? scheme.onSurfaceVariant
                          : scheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    [
                      if (p['category'] != null) p['category'],
                      if (p['market'] != null) p['market'],
                      'x${p['quantity'] ?? 1}',
                    ].join(' • '),
                    style: TextStyle(
                        fontSize: 12, color: scheme.onSurfaceVariant),
                  ),
                  if (features.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: features
                            .map((f) => Chip(
                                  label: Text(f,
                                      style: const TextStyle(fontSize: 11)),
                                  visualDensity: VisualDensity.compact,
                                  materialTapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                ))
                            .toList(),
                      ),
                    ),
                ],
              ),
            ),
            IconButton(
              icon: Icon(Icons.delete_outline, color: scheme.error),
              tooltip: 'Sil',
              onPressed: () => _removeProduct(realIndex),
            ),
          ],
        ),
      ),
    );
  }
}
