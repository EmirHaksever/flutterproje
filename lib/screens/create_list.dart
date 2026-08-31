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
  _CreateListPageState createState() => _CreateListPageState();
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
    // Ensure globalPrimaryColor is a MaterialColor to use shades
    final MaterialColor globalPrimaryColor = widget.customPrimarySwatch;

    // Filtrelenmiş ürün listesi
    List<Map<String, dynamic>> _filteredProducts = products.where((product) {
      if (_filterCategory == null || _filterCategory == 'Tümü') {
        return true; // Kategori filtresi yoksa tümünü göster
      }
      return product['category'] == _filterCategory;
    }).toList();


    return Scaffold(
      appBar: AppBar(
        title: Text(
          _listNameController.text.isEmpty ? 'Yeni Liste Oluştur' : _listNameController.text,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: globalPrimaryColor, // Tema rengini kullan
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.save),
            onPressed: _saveList,
            tooltip: 'Listeyi Kaydet',
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            // Liste Adı Girişi
            TextField(
              controller: _listNameController,
              decoration: InputDecoration(
                labelText: 'Liste Adı',
                hintText: 'Örn: Haftalık Market Listesi',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                prefixIcon: Icon(Icons.list_alt, color: globalPrimaryColor),
              ),
              onChanged: (value) {
                setState(() {}); // AppBar başlığını güncellemek için
              },
            ),
            const SizedBox(height: 20),

            // Ürün Ekleme Formu
            _buildProductInputForm(globalPrimaryColor),
            const SizedBox(height: 20),

            // Kategori Filtreleme Dropdown'ı (Şimdi sadece mevcut kategorileri kullanıyor)
            _buildCategoryFilterDropdown(globalPrimaryColor),
            const SizedBox(height: 20),

            // Ürün Listesi
            Expanded(
              child: _buildProductList(_filteredProducts, globalPrimaryColor),
            ),
          ],
        ),
      ),
    );
  }

  // Ürün Ekleme Formunu oluşturan yardımcı metod
  Widget _buildProductInputForm(MaterialColor globalPrimaryColor) {
    return Column(
      children: [
        TextField(
          controller: _productNameController,
          decoration: InputDecoration(
            labelText: 'Ürün Adı',
            hintText: 'Örn: Süt, Ekmek',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            prefixIcon: Icon(Icons.shopping_basket, color: globalPrimaryColor),
          ),
          onSubmitted: (_) => _addProduct(), // Enter'a basınca ekle
        ),
        const SizedBox(height: 15),
        TextField( // Yeni: Adet sayısı girişi
          controller: _quantityController,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            labelText: 'Adet Sayısı (Opsiyonel)',
            hintText: 'Örn: 2, 500gr',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            prefixIcon: Icon(Icons.numbers, color: globalPrimaryColor),
          ),
        ),
        const SizedBox(height: 15),
        TextField( // Yeni: Özellikler girişi
          controller: _featuresController,
          decoration: InputDecoration(
            labelText: 'Özellikler (Opsiyonel, Virgülle Ayırın)',
            hintText: 'Örn: organik, glutensiz, büyük boy',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            prefixIcon: Icon(Icons.label_outline, color: globalPrimaryColor),
            suffixIcon: IconButton( // Add button moved here for product, quantity, features
              icon: Icon(Icons.add_circle, color: globalPrimaryColor, size: 30),
              onPressed: _addProduct,
            ),
          ),
          onSubmitted: (_) => _addProduct(), // Enter'a basınca ekle
        ),
        const SizedBox(height: 15),
        // Kategori Seçimi (Dropdown)
        DropdownButtonFormField<String>(
          value: _selectedCategory,
          hint: const Text('Kategori Seç'),
          decoration: InputDecoration(
            labelText: 'Kategori',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            prefixIcon: Icon(Icons.category, color: globalPrimaryColor),
          ),
          // availableCategories'den direkt çekiyoruz
          items: [
            ...widget.availableCategories.map((cat) => DropdownMenuItem(value: cat['name'].toString(), child: Text(cat['name'].toString()))),
            DropdownMenuItem(value: 'Yeni Kategori Ekle', child: Row(
              children: [
                Icon(Icons.add, color: globalPrimaryColor),
                const SizedBox(width: 8),
                const Text('Yeni Kategori Ekle'),
              ],
            )),
          ],
          onChanged: (value) {
            setState(() {
              if (value == 'Yeni Kategori Ekle') {
                _showNewCategoryInput = true;
                _selectedCategory = null; // Dropdown'ı sıfırla
              } else {
                _selectedCategory = value;
                _showNewCategoryInput = false;
              }
            });
          },
        ),
        if (_showNewCategoryInput) ...[
          const SizedBox(height: 15),
          TextField(
            controller: _newCategoryController,
            decoration: InputDecoration(
              labelText: 'Yeni Kategori Adı',
              hintText: 'Örn: Hobi Malzemeleri',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              prefixIcon: Icon(Icons.add_box, color: globalPrimaryColor),
              suffixIcon: IconButton(
                icon: Icon(Icons.check_circle, color: globalPrimaryColor),
                onPressed: () {
                  if (_newCategoryController.text.isNotEmpty) {
                    setState(() {
                      final newCategoryName = _newCategoryController.text;
                      // widget.availableCategories listesini de güncellememiz gerekir ki dropdown'da gözüksün.
                      // Ancak widget'tan gelen liste immutable olabilir.
                      // Bunun yerine bu durumda ana uygulama tarafında bir mekanizma olması daha sağlıklı olur
                      // veya sadece bu oturum için _availableTags'e ekleyip dropdown'da göstermeliyiz.
                      // Mevcut durumda _availableTags kaldırıldığı için, bu yeni kategorinin sadece seçili kalmasını sağlarız.
                      _selectedCategory = newCategoryName;
                      _showNewCategoryInput = false;
                      _newCategoryController.clear();
                      
                      // Eğer yeni kategori gerçekten kalıcı olarak eklensin isteniyorsa,
                      // buraya Supabase'e kategori ekleme veya HomePage'deki availableCategories listesini güncelleme mantığı eklenmeli.
                      // Şimdilik sadece bu dropdown için geçici olarak seçili kalıyor.
                    });
                  }
                },
              ),
            ),
          ),
        ],
        const SizedBox(height: 15),
        // Market Seçimi (Dropdown)
        DropdownButtonFormField<String>(
          value: _selectedMarket,
          hint: const Text('Market Seç (Opsiyonel)'),
          decoration: InputDecoration(
            labelText: 'Market',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            prefixIcon: Icon(Icons.store, color: globalPrimaryColor),
          ),
          items: [
            ..._availableMarkets.map((market) => DropdownMenuItem(value: market, child: Text(market))),
            DropdownMenuItem(value: 'Yeni Mağaza Ekle', child: Row(
              children: [
                Icon(Icons.add, color: globalPrimaryColor),
                const SizedBox(width: 8),
                const Text('Yeni Mağaza Ekle'),
              ],
            )),
          ],
          onChanged: (value) {
            setState(() {
              if (value == 'Yeni Mağaza Ekle') {
                _showNewMarketInput = true;
                _selectedMarket = null; // Dropdown'ı sıfırla
              } else {
                _selectedMarket = value;
                _showNewMarketInput = false;
              }
            });
          },
        ),
        if (_showNewMarketInput) ...[
          const SizedBox(height: 15),
          TextField(
            controller: _newMarketController,
            decoration: InputDecoration(
              labelText: 'Yeni Mağaza Adı',
              hintText: 'Örn: Yerel Bakkal',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              prefixIcon: Icon(Icons.add_box, color: globalPrimaryColor),
              suffixIcon: IconButton(
                icon: Icon(Icons.check_circle, color: globalPrimaryColor),
                onPressed: () {
                  if (_newMarketController.text.isNotEmpty) {
                    setState(() {
                      _availableMarkets.add(_newMarketController.text);
                      _selectedMarket = _newMarketController.text;
                      _showNewMarketInput = false;
                      _newMarketController.clear();
                    });
                  }
                },
              ),
            ),
          ),
        ],
      ],
    );
  }

  // Kategori filtreleme dropdown'ı oluşturan yardımcı metod
  Widget _buildCategoryFilterDropdown(MaterialColor globalPrimaryColor) {
    return DropdownButtonFormField<String>(
      value: _filterCategory,
      hint: const Text('Kategoriye Göre Filtrele'),
      decoration: InputDecoration(
        labelText: 'Listeyi Filtrele',
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        prefixIcon: Icon(Icons.filter_list, color: globalPrimaryColor),
      ),
      items: [
        const DropdownMenuItem(value: 'Tümü', child: Text('Tümü')),
        // Filtreleme için widget'tan gelen kategorileri kullan
        ...widget.availableCategories.map((cat) => DropdownMenuItem(value: cat['name'].toString(), child: Text(cat['name'].toString()))),
      ],
      onChanged: (value) {
        setState(() {
          _filterCategory = value;
        });
      },
    );
  }

  // Ürün listesini oluşturan yardımcı metod
  Widget _buildProductList(List<Map<String, dynamic>> displayProducts, MaterialColor primaryMaterialColor) {
    return ListView.builder(
      itemCount: displayProducts.length,
      itemBuilder: (context, index) {
        final product = displayProducts[index];
        final realIndex = products.indexOf(product);
        final quantity = product['quantity'] ?? 1; // Adet sayısını al
        final features = product['features'] as List<String>? ?? []; // Özellikleri al

        return Card(
          margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 0),
          elevation: 3,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
          child: ListTile(
            title: CheckboxListTile(
              controlAffinity: ListTileControlAffinity.leading,
              value: product['is_completed'],
              onChanged: (bool? newValue) {
                setState(() {
                  products[realIndex]['is_completed'] = newValue!;
                });
              },
              title: Text(
                product['product_name'],
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 16,
                  decoration: product['is_completed'] ? TextDecoration.lineThrough : TextDecoration.none,
                  color: product['is_completed'] ? Colors.grey : Colors.black87,
                ),
              ),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (product['category'] != null)
                    Text('Kategori: ${product['category']}', style: TextStyle(color: Colors.grey.shade700, fontSize: 13)),
                  if (product['market'] != null)
                    Text('Mağaza: ${product['market']}', style: TextStyle(color: Colors.grey.shade700, fontSize: 13)),
                  Text('Adet: $quantity', style: TextStyle(color: Colors.grey.shade700, fontSize: 13)), // Adet sayısı gösterimi
                  if (features.isNotEmpty) // Özellikler varsa göster
                    Padding(
                      padding: const EdgeInsets.only(top: 8.0),
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        children: features.map((feature) {
                          return Chip(
                            label: Text(feature, style: TextStyle(color: primaryMaterialColor.shade700)),
                            backgroundColor: primaryMaterialColor.shade50,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                            side: BorderSide(color: primaryMaterialColor.shade200),
                          );
                        }).toList(),
                      ),
                    ),
                ],
              ),
            ),
            trailing: IconButton(
              icon: const Icon(Icons.delete_rounded, color: Colors.red),
              onPressed: () => _removeProduct(realIndex),
              tooltip: 'Ürünü Sil',
            ),
          ),
        );
      },
    );
  }
}
