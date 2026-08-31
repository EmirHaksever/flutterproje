import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class CategoryDetailPage extends StatefulWidget {
  final String categoryName;
  final MaterialColor customPrimarySwatch;

  const CategoryDetailPage({
    super.key,
    required this.categoryName,
    required this.customPrimarySwatch,
  });

  @override
  State<CategoryDetailPage> createState() => _CategoryDetailPageState();
}

class _CategoryDetailPageState extends State<CategoryDetailPage> {
  final supabase = Supabase.instance.client;
  List<Map<String, dynamic>> _categoryItems = [];
  int _totalCategoryItems = 0;
  int _completedCategoryItems = 0;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchCategoryDetails();
  }

  Future<void> _fetchCategoryDetails() async {
    setState(() {
      _isLoading = true;
    });
    try {
      // Supabase sorgusu güncellendi:
      // 'list_items' tablosundan ürünleri çekerken, 'shopping_lists' tablosu ile
      // join yaparak (name) alanını da getiriyoruz.
      final response = await supabase
          .from('list_items')
          .select('*, shopping_lists(name)') // Burası güncellendi!
          .eq('category', widget.categoryName); // Sadece bu kategoriye ait olanları filtrele

      if (mounted) {
        int total = 0;
        int completed = 0;
        final List<Map<String, dynamic>> items = [];

        for (var item in response) {
          items.add(Map<String, dynamic>.from(item));
          total++;
          if (item['is_completed'] == true) {
            completed++;
          }
        }

        setState(() {
          _categoryItems = items;
          _totalCategoryItems = total;
          _completedCategoryItems = completed;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Kategori detayları çekilirken hata oluştu: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Kategori detayları yüklenirken bir hata oluştu: $e')),
        );
      }
    }
  }

  // Ürünün tamamlanma durumunu güncelleyen fonksiyon
  Future<void> _toggleItemCompletion(String itemId, bool currentStatus) async {
    try {
      await supabase
          .from('list_items')
          .update({'is_completed': !currentStatus})
          .eq('id', itemId);
      
      // Başarılı olursa listeyi yeniden çek
      _fetchCategoryDetails();
    } catch (e) {
      debugPrint('Ürün tamamlama durumu güncellenirken hata oluştu: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Durum güncellenirken hata oluştu: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final double completionRate = _totalCategoryItems > 0 ? _completedCategoryItems / _totalCategoryItems : 0.0;
    final Color primaryColor = widget.customPrimarySwatch;

    return Scaffold(
      backgroundColor: Colors.grey[50], // Arka plan rengi eklendi
      appBar: AppBar(
        title: Text('${widget.categoryName} Detayları'),
        backgroundColor: primaryColor,
        foregroundColor: Colors.white,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Toplam Ürün: $_totalCategoryItems',
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Tamamlanan Ürün: $_completedCategoryItems',
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Tamamlama Oranı: ${(completionRate * 100).toStringAsFixed(1)}%',
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 16),
                      LinearProgressIndicator(
                        value: completionRate,
                        backgroundColor: Colors.grey[300],
                        color: primaryColor, // Tema rengine uygun ton
                        minHeight: 10,
                        borderRadius: BorderRadius.circular(5),
                      ),
                    ],
                  ),
                ),
                const Divider(),
                Expanded(
                  child: _categoryItems.isEmpty
                      ? Center(child: Text('${widget.categoryName} kategorisinde hiç ürün bulunamadı.', style: const TextStyle(color: Colors.grey)))
                      : ListView.builder(
                          itemCount: _categoryItems.length,
                          itemBuilder: (context, index) {
                            final item = _categoryItems[index];
                            final productName = item['product_name'] ?? 'İsimsiz Ürün';
                            final isCompleted = item['is_completed'] ?? false;
                            
                            // Liste adını shopping_lists'tan çekiyoruz
                            // item['shopping_lists'] bir Map veya null olabilir, güvenli erişim
                            final listName = (item['shopping_lists'] as Map<String, dynamic>?)?['name'] as String? ?? 'Bilinmeyen Liste';

                            return Card(
                              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                              elevation: 2,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              child: CheckboxListTile(
                                title: Text(
                                  productName,
                                  style: TextStyle(
                                    decoration: isCompleted ? TextDecoration.lineThrough : TextDecoration.none,
                                    color: isCompleted ? Colors.grey : Colors.black,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                // BURADA LİSTE ADI GÖSTERİLİYOR
                                subtitle: Text(
                                  'Liste: $listName', // Listenin ID'si yerine adı gözükecek
                                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                                ),
                                value: isCompleted,
                                onChanged: (bool? newValue) {
                                  _toggleItemCompletion(item['id'], item['is_completed']);
                                },
                                activeColor: primaryColor, // Tema rengi
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }
}
