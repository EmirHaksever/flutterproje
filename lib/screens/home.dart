import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'package:fl_chart/fl_chart.dart';
import 'dart:async'; // StreamSubscription için eklendi

// Diğer ekran importları (örneğin CreateListPage)
// import 'create_list.dart'; // create_list.dart olarak doğru dosya adı - KULLANILMADIĞI İÇİN KALDIRILDI
import 'category_detail_page.dart'; // Yeni: Kategori detay sayfası importu
import 'notifications_screen.dart';
import '../constants/categories.dart';

// WeeklyData modeli, doğrudan HomePage'deki grafik tarafından kullanıldığı için burada kalır.
class WeeklyData {
  final String day;
  final int itemCount;

  WeeklyData({required this.day, required int itemCount}) :
    itemCount = itemCount >= 0 ? itemCount : 0;
}

class HomePage extends StatefulWidget {
  final MaterialColor customPrimarySwatch; // Yeni: MaterialColor'ı al

  const HomePage({super.key, required this.customPrimarySwatch});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final supabase = Supabase.instance.client;

  String userName = '';
  List<dynamic> shoppingLists = []; // Tüm alışveriş listeleri
  List<dynamic> _filteredShoppingLists = []; // Arama için filtrelenmiş liste
  int totalItems = 0;
  int completedItems = 0;
  List<WeeklyData> weeklyData = [];
  List<Map<String, dynamic>> topProducts = [];
  List<String> suggestedToday = [];
  List<Map<String, dynamic>> _dynamicCategories = []; // Dinamik/Tercih edilen kategoriler için yeni liste
  List<Map<String, dynamic>> _allAvailableCategories = []; // Tüm mevcut kategoriler (yönetim için)

  final TextEditingController _searchController = TextEditingController();
  List<String> _currentSuggestions = []; // Arama önerileri için yeni liste
  bool _showSuggestions = false; // Önerileri göster/gizle durumu
  final FocusNode _searchFocusNode = FocusNode(); // Arama çubuğu odak takibi için

  // Realtime Subscriptions
  StreamSubscription<List<Map<String, dynamic>>>? _shoppingListSubscription;
  StreamSubscription<List<Map<String, dynamic>>>? _listItemSubscription;

  @override
  void initState() {
    super.initState();
    Intl.defaultLocale = 'tr_TR';
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeDataAndListeners(); // Verileri çek ve dinleyicileri başlat
    });

    // Arama çubuğundaki metin değişimlerini dinle ve önerileri güncelle
    _searchController.addListener(_updateSuggestions);
    // Odak değişimlerini dinle, odak kalktığında önerileri gizle
    _searchFocusNode.addListener(() {
      if (!_searchFocusNode.hasFocus) {
        Future.delayed(const Duration(milliseconds: 100), () {
          if (mounted) {
            setState(() {
              _showSuggestions = false;
            });
          }
        });
      } else {
        _updateSuggestions(); // Odaklandığında tekrar önerileri göster (eğer metin varsa)
      }
    });
  }

  // Tüm başlangıç verilerini çeken ve dinleyicileri başlatan ana fonksiyon
  Future<void> _initializeDataAndListeners() async {
    await fetchUserInfo();
    await fetchWeeklyData();
    await fetchTopProducts();
    // Kategorileri en son çekiyoruz çünkü hem varsayılanları hem de dinamik verileri kullanacak.
    await fetchDynamicCategories();

    _setupRealtimeListeners(); // Yeni: Realtime dinleyicileri kur
  }

  // Supabase Realtime dinleyicilerini kurar
  void _setupRealtimeListeners() {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return;

    // Alışveriş listesi değişikliklerini dinle
    _shoppingListSubscription = supabase
        .from('shopping_lists')
        .stream(primaryKey: ['id']) // primaryKey kullanarak dinleme
        .eq('user_id', userId) // Sadece kullanıcının listelerini dinle
        .order('created_at', ascending: false)
        .listen((data) {
      debugPrint('Realtime: shopping_lists değişti');
      if (mounted) {
        setState(() {
          shoppingLists = data;
          _filteredShoppingLists = data; // Filtrelenmiş listeyi de güncelle
        });
        fetchStatistics(); // İstatistikleri güncelle
      }
    });

    // Liste öğesi değişikliklerini dinle
    _listItemSubscription = supabase
        .from('list_items')
        .stream(primaryKey: ['id']) // primaryKey kullanarak dinleme
        .listen((data) { // Tüm list_items değişikliklerini dinle, daha sonra liste ID'sine göre filtreleyebiliriz
      debugPrint('Realtime: list_items değişti');
      if (mounted) {
        // İstatistikler, sıkça alınanlar, öneriler ve kategoriler bu değişikliklerden etkilenebilir
        fetchStatistics();
        fetchTopProducts();
        fetchSuggestions();
        fetchDynamicCategories(); // Kategori verileri de etkilenebilir
        // Ayrıca, ana alışveriş listesini (shoppingLists) de güncellemek gerekebilir
        // Ancak bu daha karmaşık olabilir, çünkü list_items'daki değişiklikler
        // doğrudan shopping_lists'ı etkilemez, dolaylı yoldan etkiler.
        // Şimdilik üstteki fetch'ler çoğu zaman yeterli olacaktır.
        fetchUserInfo(); // shoppingLists'i de güncellemek için userInfo'yu tekrar çekebiliriz
      }
    });
  }


  @override
  void dispose() {
    _searchController.removeListener(_updateSuggestions);
    _searchController.dispose();
    _searchFocusNode.removeListener(() {});
    _searchFocusNode.dispose();

    _shoppingListSubscription?.cancel(); // Dinleyicileri temizle
    _listItemSubscription?.cancel();     // Dinleyicileri temizle

    super.dispose();
  }

  // Arama çubuğuna yazıldıkça önerileri güncelleyen fonksiyon
  void _updateSuggestions() {
    final query = _searchController.text.toLowerCase();
    List<String> newSuggestions = [];

    if (query.isEmpty) {
      setState(() {
        _currentSuggestions = [];
        _showSuggestions = false;
        _filteredShoppingLists = shoppingLists; // Arama boşsa tüm listeleri göster
      });
      return;
    }

    final allSearchableItems = <String>{};
    for (var list in shoppingLists) {
      allSearchableItems.add(list['name'].toLowerCase());
    }
    for (var product in topProducts) {
      allSearchableItems.add(product['product_name'].toLowerCase());
    }
    for (var category in _dynamicCategories) { // Kategorileri de arama önerilerine dahil et
      allSearchableItems.add(category['name'].toLowerCase());
    }


    final matchedLocalSuggestions = allSearchableItems
        .where((item) => item.contains(query))
        .toList();

    newSuggestions.addAll(matchedLocalSuggestions.take(4));

    if (query.length > 2) {
      newSuggestions.add('AI\'ya sor: "$query"');
    }

    setState(() {
      _currentSuggestions = newSuggestions;
      _showSuggestions = _currentSuggestions.isNotEmpty;
    });
  }

  // Arama çubuğundaki enter tuşuna basıldığında veya arama ikonu tıklandığında
  void _onSearchSubmitted(String query) {
    if (query.isEmpty) {
      setState(() {
        _filteredShoppingLists = shoppingLists; // Arama boşsa tüm listeleri göster
      });
    } else if (query.startsWith('AI\'ya sor: "') && query.endsWith('"')) {
      final aiQuery = query.substring(12, query.length - 1);
      Navigator.pushNamed(context, '/aiChat', arguments: aiQuery);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('"$query" ile listeler aranıyor...')),
      );
      setState(() {
        _filteredShoppingLists = shoppingLists.where((list) {
          final listName = list['name'].toLowerCase();
          return listName.contains(query.toLowerCase());
        }).toList();
      });
    }
    setState(() {
      _currentSuggestions = [];
      _showSuggestions = false;
    });
    FocusScope.of(context).unfocus();
  }

  // Dinamik kategorileri Supabase'den çek ve kullanıcı tercihlerini dahil et
  Future<void> fetchDynamicCategories() async {
    try {
      // Ürünleri çek: kategori başına adet + tamamlanan adet sayımı için
      final allListItemsResponse = await supabase
          .from('list_items')
          .select('category, is_completed');

      final Map<String, int> categoryCounts = {};
      final Map<String, int> completedCategoryCounts = {};
      final Set<String> uniqueListItemCategories = {};

      for (var item in allListItemsResponse) {
        final categoryName = item['category'] as String?;
        if (categoryName != null && categoryName.isNotEmpty) {
          categoryCounts[categoryName] = (categoryCounts[categoryName] ?? 0) + 1;
          uniqueListItemCategories.add(categoryName);
          if (item['is_completed'] == true) {
            completedCategoryCounts[categoryName] =
                (completedCategoryCounts[categoryName] ?? 0) + 1;
          }
        }
      }

      // Varsayılan kategoriler + list_items'ta geçen ekstra kategoriler
      final tempAllAvailableCategories =
          mergeDiscoveredCategories(uniqueListItemCategories);
      setState(() {
        _allAvailableCategories = tempAllAvailableCategories;
      });


      final userId = supabase.auth.currentUser?.id;
      List<String> preferredCategoryNames = [];

      // Kullanıcının tercih edilen kategorilerini çek
      if (userId != null) {
        final userResponse = await supabase
            .from('users')
            .select('preferred_categories')
            .eq('id', userId)
            .maybeSingle();

        if (userResponse != null && userResponse['preferred_categories'] != null) {
          preferredCategoryNames = List<String>.from(userResponse['preferred_categories']);
        }
      }

      // Görüntülenecek kategorileri oluştur
      List<Map<String, dynamic>> categoriesToDisplay = [];

      // Eğer kullanıcının tercih ettiği kategoriler varsa, bunları önceliklendir
      if (preferredCategoryNames.isNotEmpty) {
        for (String pName in preferredCategoryNames) {
          final matchedCategory = _allAvailableCategories.firstWhere(
            (cat) => cat['name'].toLowerCase() == pName.toLowerCase(),
            orElse: () => { // Eşleşme bulunamazsa varsayılan bir yapı oluştur
              'name': pName,
              'icon': Icons.category_outlined,
              'colors': [Colors.blueGrey.shade300, Colors.blueGrey.shade500],
            },
          );
          categoriesToDisplay.add({
            ...matchedCategory, // Mevcut icon ve renkleri koru
            'count': categoryCounts[matchedCategory['name']] ?? 0, // Ürün sayısını ekle
            'completed_count': completedCategoryCounts[matchedCategory['name']] ?? 0, // Completed ürün sayısını ekle
          });
        }
      } else {
        // Eğer tercih yoksa, dinamik olarak _allAvailableCategories içinden en çok ürüne sahip olanlardan ilk 6'yı göster
        final List<Map<String, dynamic>> tempDynamicCategoriesForDefault = [];
        // Sadece _allAvailableCategories içindeki kategorileri dikkate alarak ürün sayılarını ekle
        for(var catData in _allAvailableCategories){
          tempDynamicCategoriesForDefault.add({
            'name': catData['name'],
            'icon': catData['icon'],
            'colors': catData['colors'],
            'count': categoryCounts[catData['name']] ?? 0,
            'completed_count': completedCategoryCounts[catData['name']] ?? 0, // Add completed count here too
          });
        }
        
        // Ürün sayısına göre sırala ve ilk 6'yı al
        tempDynamicCategoriesForDefault.sort((a, b) => (b['count'] as int).compareTo(a['count'] as int));
        categoriesToDisplay = tempDynamicCategoriesForDefault.take(6).toList();
      }
      
      setState(() {
        _dynamicCategories = categoriesToDisplay;
      });

    } catch (e) {
      debugPrint('Dinamik kategoriler çekilemedi: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Kategoriler yüklenirken bir hata oluştu: $e')),
        );
      }
    }
  }

  // Popüler kategorileri yönetmek için modal alt sayfa
  void _showCategoryManagementSheet() {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Kategorileri yönetmek için giriş yapmalısınız.')),
      );
      return;
    }

    // Modalı açtığımızda kullanıcının mevcut tercihlerini kopyala
    // Bu liste, modal içindeki geçici durumu tutacak.
    List<String> selectedCategoriesInModal = _dynamicCategories.map((e) => e['name'] as String).toList();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true, // Tam ekran boyutu için
      builder: (BuildContext bc) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter modalSetState) {
            // globalPrimarySwatch'i widget'tan al
            final MaterialColor globalPrimarySwatch = widget.customPrimarySwatch;
            final Color globalPrimaryColor = globalPrimarySwatch; // Ana renk, MaterialColor'ın kendisidir

            return Container(
              height: MediaQuery.of(context).size.height * 0.8, // Ekranın %80'i kadar
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(25)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 5,
                      margin: const EdgeInsets.only(bottom: 15),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                  Text(
                    'Popüler Kategorileri Yönet',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey.shade800,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Ana sayfada göstermek istediğiniz kategorileri seçin. En fazla 6 kategori seçebilirsiniz.',
                    style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
                  ),
                  const SizedBox(height: 20),
                  Expanded(
                    child: ListView.builder(
                      itemCount: _allAvailableCategories.length, // Yönetilebilir kategoriler artık tüm benzersizleri içeriyor
                      itemBuilder: (context, index) {
                        final category = _allAvailableCategories[index];
                        // Modaldaki geçici listeyi kontrol et
                        final isSelected = selectedCategoriesInModal.contains(category['name']);
                        
                        // Kategori kartlarının renklerini belirlerken ana tema rengine göre ayarlıyoruz
                        List<Color> categoryModalColors;
                        if (category['name'] == 'Elektronik') { 
                           categoryModalColors = [globalPrimarySwatch.shade300, globalPrimaryColor];
                        } else if (category['name'] == 'Bebek') { 
                           categoryModalColors = [globalPrimarySwatch.shade50, globalPrimarySwatch.shade200];
                        } else if (category['name'] == 'Kıyafet') { 
                           categoryModalColors = [globalPrimarySwatch.shade100, globalPrimarySwatch.shade300];
                        } else {
                          categoryModalColors = category['colors'] as List<Color>;
                        }

                        return CheckboxListTile(
                          title: Text(category['name']),
                          secondary: Icon(category['icon'] as IconData, color: categoryModalColors[0]), // Renk güncellendi
                          value: isSelected,
                          onChanged: (bool? newValue) {
                            modalSetState(() { // Modalı güncelle
                              if (newValue == true) {
                                if (selectedCategoriesInModal.length < 6) { // Max 6 kategori seçilebilir
                                  selectedCategoriesInModal.add(category['name'] as String);
                                } else {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('En fazla 6 kategori seçebilirsiniz.')),
                                  );
                                }
                              } else {
                                selectedCategoriesInModal.remove(category['name'] as String);
                              }
                            });
                          },
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () async {
                        // Seçimleri Supabase'e kaydet
                        try {
                          await supabase
                              .from('users')
                              .update({'preferred_categories': selectedCategoriesInModal})
                              .eq('id', userId);
                          
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Kategori tercihleri kaydedildi!')),
                            );
                            Navigator.pop(context); // Modalı kapat
                            await fetchDynamicCategories(); // Ana sayfayı güncelleyerek yeni tercihleri göster
                          }
                        } catch (e) {
                          debugPrint('Kategori tercihleri kaydedilemedi: $e');
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Kategori tercihleri kaydedilirken hata oluştu: $e')),
                            );
                          }
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: globalPrimaryColor, // Uygulamanın ana rengini kullan
                        padding: const EdgeInsets.symmetric(vertical: 15),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(15),
                        ),
                      ),
                      child: const Text(
                        'Kaydet',
                        style: TextStyle(fontSize: 18, color: Colors.white, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }


  // Günün saatine göre selam metni
  String getGreeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return "Günaydın";
    if (hour < 18) return "İyi Günler";
    return "İyi Akşamlar";
  }

  // Karşılama kartı degradesi — tema ana renginden türetilir (koyu modda da uyumlu).
  List<Color> getGreetingCardGradientColors() {
    final primary = Theme.of(context).colorScheme.primary;
    return [primary, Color.lerp(primary, Colors.black, 0.28)!];
  }

  // Yazılara hafif gölge ekleyen TextShadow listesi
  List<Shadow> _getTextShadows() {
    return [
      Shadow(
        offset: const Offset(1.0, 1.0),
        blurRadius: 3.0,
        color: Colors.black.withValues(alpha: 0.4),
      ),
    ];
  }

  String getTurkishDayName(int weekday) {
    const days = ['Pzt', 'Sal', 'Çar', 'Per', 'Cum', 'Cmt', 'Paz'];
    return days[weekday - 1];
  }

  Future<void> fetchUserInfo() async {
    final session = supabase.auth.currentSession;
    if (session == null) {
      if (mounted) Navigator.pushReplacementNamed(context, '/login');
      return;
    }
    final userId = session.user.id;
    final userResponse = await supabase
        .from('users')
        .select('name')
        .eq('id', userId)
        .maybeSingle();
    
    // BURASI GÜNCELLENDİ: list_items içindeki product_name'leri de çekiyoruz.
    final listResponse = await supabase
        .from('shopping_lists')
        .select('*, list_items(product_name)') // product_name'leri de çek!
        .eq('user_id', userId)
        .order('created_at', ascending: false);

    setState(() {
      userName = userResponse?['name'] ?? 'Kullanıcı';
      shoppingLists = listResponse;
      _filteredShoppingLists = listResponse; // Başlangıçta filtrelenmiş liste tüm listeleri içerir
    });

    await fetchStatistics();
  }

  Future<void> fetchStatistics() async {
    if (shoppingLists.isEmpty) {
      setState(() {
        totalItems = 0;
        completedItems = 0;
      });
      return;
    }
    final listIds = shoppingLists.map((e) => e['id']).toList();
    if (listIds.isEmpty) {
       setState(() {
        totalItems = 0;
        completedItems = 0;
      });
      return;
    }

    final response = await supabase
        .from('list_items')
        .select('is_completed')
        .filter('list_id', 'in', '(${listIds.join(',')})');

    final completed =
        response.where((item) => item['is_completed'] == true).length;

    setState(() {
      totalItems = response.length;
      completedItems = completed;
    });
  }

  Future<void> fetchWeeklyData() async {
    final oneWeekAgo = DateTime.now().subtract(const Duration(days: 7));
    final response = await supabase
        .from('list_items')
        .select('created_at')
        .gte('created_at', oneWeekAgo.toIso8601String());

    final dailyCounts = {
      'Pzt': 0, 'Sal': 0, 'Çar': 0, 'Per': 0,
      'Cum': 0, 'Cmt': 0, 'Paz': 0
    };

    for (var item in response) {
      final date = DateTime.parse(item['created_at']);
      final weekday = getTurkishDayName(date.weekday);
      dailyCounts[weekday] = dailyCounts[weekday]! + 1;
    }

    final orderedDays = ['Pzt', 'Sal', 'Çar', 'Per', 'Cum', 'Cmt', 'Paz'];
    setState(() {
      weeklyData = orderedDays
          .map((day) => WeeklyData(day: day, itemCount: dailyCounts[day]!))
          .toList();
    });
  }

  Future<void> fetchTopProducts() async {
    final response =
        await supabase.from('list_items').select('product_name').limit(200);
    final productCount = <String, int>{};
    for (var item in response) {
      final name = item['product_name'];
      if (name != null) productCount[name] = (productCount[name] ?? 0) + 1;
    }
    final sorted = productCount.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    setState(() {
      topProducts =
          sorted.take(6).map((e) => {'product_name': e.key, 'count': e.value}).toList();
    });
  }

  Future<void> fetchSuggestions() async {
    final recentItems = await supabase
        .from('list_items')
        .select('product_name, is_completed, created_at')
        .order('created_at', ascending: false)
        .limit(50);
    final productCounts = <String, int>{};
    for (var item in recentItems) {
      if (item['is_completed'] == false && item['product_name'] != null) {
        final product = item['product_name'];
        productCounts[product] = (productCounts[product] ?? 0) + 1;
      }
    }
    final sorted = productCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    setState(() {
      suggestedToday = sorted.take(3).map((e) => e.key).toList();
    });
  }

  Widget _buildUnifiedCard({
    required Widget child,
    EdgeInsetsGeometry? padding,
    Color? color,
    double borderRadius = 16,
    EdgeInsetsGeometry? margin,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: margin ?? const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: color ?? scheme.surface,
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Padding(
        padding: padding ?? const EdgeInsets.all(20),
        child: child,
      ),
    );
  }

  Widget _buildSectionTitle(String text,
      {IconData? icon, Color? iconColor, double fontSize = 20}) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: Row(
        children: [
          if (icon != null)
            Icon(icon, color: iconColor ?? scheme.primary, size: 26),
          if (icon != null) const SizedBox(width: 10),
          Text(
            text,
            style: TextStyle(
              fontSize: fontSize,
              fontWeight: FontWeight.bold,
              color: scheme.onSurface,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVisualCategoryCard({
    required IconData icon,
    required String title,
    required List<Color> gradientColors,
    VoidCallback? onTap,
    required int itemCount, // New: Total items in this category
    required int completedCount, // New: Completed items in this category
  }) {
    final double completionRate = itemCount > 0 ? completedCount / itemCount : 0.0;
    
    return InkWell(
      onTap: onTap, // Kategoriye tıklama işlevi
      borderRadius: BorderRadius.circular(15),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(15),
          gradient: LinearGradient(
            colors: gradientColors,
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          boxShadow: [
            BoxShadow(
              color: gradientColors[0].withValues(alpha: 0.3),
              spreadRadius: 1,
              blurRadius: 5,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 40, color: Colors.white),
            const SizedBox(height: 6),
            Text(
              title,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
              textAlign: TextAlign.center,
              maxLines: 1, // Limit title to one line
              overflow: TextOverflow.ellipsis,
            ),
            if (itemCount > 0) ...[ // Show stats only if there are items
              const SizedBox(height: 4),
              Text(
                '$itemCount Ürün',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.8),
                  fontSize: 11,
                ),
              ),
              SizedBox(
                width: double.infinity,
                child: LinearProgressIndicator(
                  value: completionRate,
                  backgroundColor: Colors.white.withValues(alpha: 0.3),
                  valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
                  minHeight: 4,
                ),
              ),
              Text(
                '${(completionRate * 100).round()}% Tamamlandı',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.8),
                  fontSize: 10,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildAISuggestionCard(String productName) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      width: 130,
      margin: const EdgeInsets.only(right: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(Icons.lightbulb_outline, size: 34, color: scheme.primary),
          const SizedBox(height: 8),
          Text(
            productName,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 13,
              color: scheme.onSurface,
            ),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 10),
          FilledButton.tonal(
            onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('"$productName" listene eklendi!')),
            ),
            style: FilledButton.styleFrom(
              minimumSize: const Size(0, 32),
              padding: const EdgeInsets.symmetric(horizontal: 16),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: const Text('Ekle', style: TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
  }

  Widget _buildProductListItem(String productName, int count, Color accentColor) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: accentColor.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(12),
            ),
            child:
                Icon(Icons.shopping_bag_outlined, color: accentColor, size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  productName,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                    color: scheme.onSurface,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text('$count kez alındı',
                    style: TextStyle(
                        color: scheme.onSurfaceVariant, fontSize: 12)),
              ],
            ),
          ),
          Icon(Icons.chevron_right, size: 20, color: scheme.onSurfaceVariant),
        ],
      ),
    );
  }

  Widget _buildStatItem(String title, String value, IconData icon, Color color) {
    final scheme = Theme.of(context).colorScheme;
    return Expanded(
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, size: 26, color: color),
          ),
          const SizedBox(height: 10),
          Text(value,
              style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: scheme.onSurface)),
          const SizedBox(height: 4),
          Text(title,
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
              textAlign: TextAlign.center),
        ],
      ),
    );
  }

  // BURASI GÜNCELLENDİ: list_items'tan ürün adlarını gösteriyoruz
  Widget _buildRecentListItemCard(Map<String, dynamic> list) {
    // Toplam ürün sayısını hesapla
    final itemCount = (list['list_items'] as List<dynamic>?)?.length ?? 0;
    
    // İlk iki ürünün adını al
    final List<String> productNames = (list['list_items'] as List<dynamic>?)
        ?.take(2)
        .map((item) => item['product_name'] as String? ?? '')
        .where((name) => name.isNotEmpty)
        .toList() ?? [];

    final date = DateFormat('dd MMM', 'tr_TR')
        .format(DateTime.parse(list['created_at']));
    final scheme = Theme.of(context).colorScheme;

    return InkWell(
      onTap: () => Navigator.pushNamed(
        context,
        '/listDetail',
        arguments: {
          'id': list['id'],
          'name': list['name'],
          'user_id': list['user_id'],
        },
      ),
      borderRadius: BorderRadius.circular(14),
      child: Container(
        width: 190,
        padding: const EdgeInsets.all(14),
        margin: const EdgeInsets.only(right: 12),
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: BorderRadius.circular(14),
          border:
              Border.all(color: scheme.outlineVariant.withValues(alpha: 0.5)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.assignment_outlined, color: scheme.primary, size: 26),
            const SizedBox(height: 8),
            Text(
              list['name'] ?? 'İsimsiz',
              style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                  color: scheme.onSurface),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 4),
            Text('$itemCount ürün • $date',
                style:
                    TextStyle(color: scheme.onSurfaceVariant, fontSize: 12)),
            if (productNames.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                productNames.join(', '),
                style: TextStyle(
                    color: scheme.onSurfaceVariant.withValues(alpha: 0.8),
                    fontSize: 11),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Get the global primary swatch from widget
    final MaterialColor globalPrimarySwatch = widget.customPrimarySwatch;
    final Color globalPrimaryColor = globalPrimarySwatch;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: Stack(
          children: [
            GestureDetector(
              onTap: () {
                if (_showSuggestions) {
                  setState(() {
                    _showSuggestions = false;
                    _searchFocusNode.unfocus();
                  });
                }
              },
              child: SingleChildScrollView(
                // BURASI GÜNCELLENDİ: Ana kaydırılabilir alana daha fazla üst padding eklendi
                padding: const EdgeInsets.only(top: 0), // İlk Container kendi padding'ini yönetecek
                physics: _showSuggestions ? const NeverScrollableScrollPhysics() : const AlwaysScrollableScrollPhysics(),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 1. Dinamik Karşılama Alanı ve Arama Çubuğu
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.only(top: 25, bottom: 25, left: 20, right: 20),
                      margin: const EdgeInsets.only(bottom: 20), // Aşağıya da boşluk eklendi
                      decoration: BoxDecoration(
                        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(30)),
                        gradient: LinearGradient(
                          colors: getGreetingCardGradientColors(),
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.08),
                            spreadRadius: 0,
                            blurRadius: 15,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              // Menüyü açmak için IconButton (MainNavigationPage'in Drawer'ını açacak)
                              IconButton(
                                icon: Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.2),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: const Icon(Icons.menu_rounded, color: Colors.white, size: 24),
                                ),
                                onPressed: () {
                                  Scaffold.of(context).openDrawer();
                                },
                              ),
                              Row(
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.notifications_none, color: Colors.white, size: 28),
                                    onPressed: () {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) => const NotificationsScreen(),
                                        ),
                                      );
                                    },
                                  ),
                                  const SizedBox(width: 8),
                                  CircleAvatar(
                                    radius: 20,
                                    backgroundColor: Colors.white.withValues(alpha: 0.3),
                                    child: const Icon(Icons.person, color: Colors.white, size: 24),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          const SizedBox(height: 25),
                          Text(
                            '${getGreeting()}, $userName!',
                            style: TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                              shadows: _getTextShadows(),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Bugün ne alacaksın? Hadi planla!',
                            style: TextStyle(
                              fontSize: 16,
                              color: Colors.white,
                              shadows: _getTextShadows(),
                            ),
                          ),
                          const SizedBox(height: 25),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.4),
                              borderRadius: BorderRadius.circular(25),
                            ),
                            child: TextField(
                              controller: _searchController,
                              focusNode: _searchFocusNode,
                              style: const TextStyle(color: Colors.white),
                              decoration: InputDecoration(
                                hintText: 'Ne arıyorsunuz?',
                                hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 16),
                                border: InputBorder.none,
                                icon: IconButton(
                                  icon: const Icon(Icons.camera_alt, color: Colors.white, size: 24),
                                  onPressed: () {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(content: Text('Kamera özelliği ile ürün barkodu okuyabilir veya resim çekebilirsiniz!')),
                                    );
                                  },
                                ),
                                suffixIcon: IconButton(
                                  icon: const Icon(Icons.search, color: Colors.white, size: 24),
                                  onPressed: () => _onSearchSubmitted(_searchController.text),
                                ),
                              ),
                              onSubmitted: _onSearchSubmitted,
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Sayfanın geri kalanı için padding (artık bu alan dışarıda değil, ilk konteynerden sonra başlayacak)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 15.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 20),

                          // 2. Bugünün Önerileri (Akıllı AI) Bölümü
                          _buildSectionTitle('Bugünün Önerileri ✨'),
                          SizedBox(
                            height: 172,
                            child: suggestedToday.isEmpty
                                ? Center(
                                    child: Text(
                                        'Hiç öneri yok. Daha fazla ürün ekledikçe öneriler gelecek.',
                                        style: TextStyle(
                                            color: Theme.of(context)
                                                .colorScheme
                                                .onSurfaceVariant)))
                                : ListView.builder(
                                    scrollDirection: Axis.horizontal,
                                    itemCount: suggestedToday.length,
                                    itemBuilder: (context, index) =>
                                        _buildAISuggestionCard(
                                            suggestedToday[index]),
                                  ),
                          ),

                          const SizedBox(height: 30),

                          // 3. Popüler Kategoriler Bölümü (Dinamikleştirildi ve Yönetilebilir!)
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              _buildSectionTitle('Popüler Kategoriler 🛍️', iconColor: const Color(0xFF6DD5ED)),
                              TextButton.icon(
                                onPressed: _showCategoryManagementSheet,
                                icon: const Icon(Icons.edit, size: 20, color: Colors.grey),
                                label: const Text('Düzenle', style: TextStyle(color: Colors.grey, fontSize: 14)),
                              ),
                            ],
                          ),
                          _dynamicCategories.isEmpty
                            ? const Center(child: Padding(
                                padding: EdgeInsets.all(8.0),
                                child: Text('Henüz kategorize edilmiş ürün bulunmamaktadır veya tercih edilen kategori yok.', style: TextStyle(color: Colors.grey)),
                              ))
                            : GridView.count(
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                crossAxisCount: 3,
                                crossAxisSpacing: 15,
                                mainAxisSpacing: 15,
                                children: _dynamicCategories.map((category) {
                                  List<Color> cardColors = category['colors'] as List<Color>;
                                  
                                  // Elektronik, Bebek, Kıyafet kategorilerinin renklerini yeni tema rengine göre ayarlıyoruz
                                  if (category['name'] == 'Elektronik') { 
                                    cardColors = [widget.customPrimarySwatch.shade300, globalPrimaryColor]; 
                                  } else if (category['name'] == 'Bebek') { 
                                    cardColors = [widget.customPrimarySwatch.shade50, widget.customPrimarySwatch.shade200];
                                  } else if (category['name'] == 'Kıyafet') { 
                                      cardColors = [widget.customPrimarySwatch.shade100, widget.customPrimarySwatch.shade300]; 
                                  }
                                  
                                  return _buildVisualCategoryCard(
                                    icon: category['icon'] as IconData,
                                    title: category['name'] as String,
                                    gradientColors: cardColors, // Güncellenmiş renkler
                                    itemCount: category['count'] as int, // Pass item count
                                    completedCount: category['completed_count'] as int, // Pass completed count
                                    onTap: () {
                                      // Kategoriye tıklandığında CategoryDetailPage'e yönlendir ve filtrele
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (context) => CategoryDetailPage(
                                            categoryName: category['name'] as String,
                                            customPrimarySwatch: widget.customPrimarySwatch, // MaterialColor'ı gönder
                                          ),
                                        ),
                                      );
                                    },
                                  );
                                }).toList(),
                              ),

                          const SizedBox(height: 30),

                          // 4. İstatistikler ve Sıkça Satın Alınanlar Birleşik Kartı
                          _buildUnifiedCard(
                            padding: const EdgeInsets.all(25),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Sıkça Satın Alınanlar
                                _buildSectionTitle('Sıkça Satın Alınanlar 🔥', fontSize: 20, iconColor: const Color(0xFFFD4444)),
                                const SizedBox(height: 10),
                                if (topProducts.isEmpty)
                                  const Text('Henüz sık alınan ürün yok.', style: TextStyle(color: Colors.grey))
                                else
                                  Column(
                                    children: topProducts.take(3).map((product) {
                                      return _buildProductListItem(
                                        product['product_name'],
                                        product['count'],
                                        globalPrimaryColor, // Vurgu rengi kullanıldı
                                      );
                                    }).toList(),
                                  ),
                                const Divider(height: 30),

                                // Alışveriş İstatistikleri
                                _buildSectionTitle('Alışveriş İstatistikleri 📊', fontSize: 20, iconColor: globalPrimaryColor), 
                                const SizedBox(height: 10),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                                  children: [
                                    _buildStatItem(
                                      'Toplam Ürün',
                                      totalItems.toString(),
                                      Icons.format_list_numbered,
                                      globalPrimaryColor, 
                                    ),
                                    _buildStatItem(
                                      'Tamamlandı',
                                      '${(totalItems == 0 ? 0 : completedItems / totalItems * 100).toStringAsFixed(1)}%',
                                      Icons.check_circle,
                                      widget.customPrimarySwatch.shade600, // widget.customPrimarySwatch kullanıldı
                                    ),
                                  ],
                                ),
                                if (totalItems > 0) ...[
                                  const SizedBox(height: 15),
                                  LinearProgressIndicator(
                                    value: completedItems / totalItems,
                                    backgroundColor: Theme.of(context)
                                        .colorScheme
                                        .surfaceContainerHighest,
                                    borderRadius: BorderRadius.circular(10),
                                    minHeight: 12,
                                  ),
                                ],
                                if (totalItems == 0)
                                  const Padding(
                                    padding: EdgeInsets.only(top: 15.0),
                                    child: Text('Henüz hiç ürün eklenmemiş.', style: TextStyle(color: Colors.grey)),
                                  ),
                              ],
                            ),
                          ),

                          const SizedBox(height: 30),

                          // 5. Haftalık Aktivite Grafiği Bölümü
                          _buildUnifiedCard(
                            padding: const EdgeInsets.all(25),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _buildSectionTitle('Haftalık Aktivite Trendi 📈', iconColor: globalPrimaryColor), 
                                const SizedBox(height: 15),
                                SizedBox(
                                  height: 200,
                                  child: BarChart(
                                    BarChartData(
                                      alignment: BarChartAlignment.spaceAround,
                                      barTouchData: BarTouchData(enabled: false),
                                      titlesData: FlTitlesData(
                                        show: true,
                                        leftTitles: AxisTitles(
                                          sideTitles: SideTitles(
                                            showTitles: true,
                                            reservedSize: 30,
                                            getTitlesWidget: (value, meta) {
                                              return Text(value.toInt().toString(), style: TextStyle(color: Colors.grey.shade600, fontSize: 11));
                                            },
                                          ),
                                        ),
                                        bottomTitles: AxisTitles(
                                          sideTitles: SideTitles(
                                            showTitles: true,
                                            getTitlesWidget: (value, meta) {
                                              final index = value.toInt();
                                              if (index >= 0 && index < weeklyData.length) {
                                                return Padding(
                                                  padding: const EdgeInsets.only(top: 8.0),
                                                  child: Text(weeklyData[index].day, style: TextStyle(color: Colors.grey.shade600, fontSize: 11)),
                                                );
                                              }
                                              return const Text('');
                                            },
                                          ),
                                        ),
                                        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                                        rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                                      ),
                                      gridData: FlGridData(
                                        show: true,
                                        drawVerticalLine: false,
                                        getDrawingHorizontalLine: (value) => FlLine(
                                          color: Colors.grey.shade100,
                                        ),
                                      ),
                                      borderData: FlBorderData(show: false),
                                      barGroups: List.generate(weeklyData.length, (index) {
                                        return BarChartGroupData(
                                          x: index,
                                          barRods: [
                                            BarChartRodData(
                                              toY: weeklyData[index].itemCount.toDouble(),
                                              color: globalPrimaryColor, // Bar rengi globalPrimaryColor
                                              width: 18,
                                              borderRadius: BorderRadius.circular(5),
                                              backDrawRodData: BackgroundBarChartRodData(
                                                show: true,
                                                toY: weeklyData.isNotEmpty ? weeklyData.map((e) => e.itemCount).reduce((a, b) => a > b ? a : b).toDouble() * 1.2 : 5,
                                                color: Colors.grey.shade100,
                                              ),
                                            ),
                                          ],
                                        );
                                      }),
                                      maxY: weeklyData.isNotEmpty ? weeklyData.map((e) => e.itemCount).reduce((a, b) => a > b ? a : b).toDouble() * 1.2 : 5,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),

                          const SizedBox(height: 30),

                          // 6. Son Listelerim Bölümü (Arama tarafından filtrelenir)
                          _buildSectionTitle('Son Listelerim 📋'),
                          SizedBox(
                            height: 150,
                            child: _filteredShoppingLists.isEmpty
                                ? Center(
                                    child: Text(
                                        'Kaydedilmiş liste yok veya arama sonucu bulunamadı.',
                                        style: TextStyle(
                                            color: Theme.of(context)
                                                .colorScheme
                                                .onSurfaceVariant)))
                                : ListView.builder(
                                    scrollDirection: Axis.horizontal,
                                    itemCount: _filteredShoppingLists.length,
                                    itemBuilder: (context, index) =>
                                        _buildRecentListItemCard(
                                            _filteredShoppingLists[index]),
                                  ),
                          ),

                          const SizedBox(height: 80),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // Arama önerileri katmanı
            if (_showSuggestions)
              Positioned(
                top: 240, // Arama çubuğunun hemen altına gelecek şekilde ayarlandı
                left: 20,
                right: 20,
                child: Material(
                  elevation: 8,
                  color: Theme.of(context).colorScheme.surface,
                  borderRadius: BorderRadius.circular(15),
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(15),
                    ),
                    constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.3), // Maksimum yükseklik
                    child: ListView.builder(
                      padding: EdgeInsets.zero,
                      shrinkWrap: true,
                      itemCount: _currentSuggestions.length,
                      itemBuilder: (context, index) {
                        final suggestion = _currentSuggestions[index];
                        final isAIQuery = suggestion.startsWith('AI\'ya sor: ');
                        return ListTile(
                          title: Text(
                            suggestion,
                            style: TextStyle(
                              color: isAIQuery
                                  ? Theme.of(context).colorScheme.primary
                                  : Theme.of(context).colorScheme.onSurface,
                              fontWeight: isAIQuery
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                            ),
                          ),
                          trailing: Icon(
                            isAIQuery ? Icons.psychology_outlined : Icons.north_west, // AI için farklı ikon
                            size: 18,
                            color: isAIQuery ? globalPrimaryColor : Colors.grey, // AI için primaryColor
                          ),
                          onTap: () {
                            setState(() {
                              _searchController.text = suggestion;
                              _searchController.selection = TextSelection.fromPosition(TextPosition(offset: _searchController.text.length));
                              _showSuggestions = false;
                            });
                            _onSearchSubmitted(suggestion); // Öneri seçildiğinde arama işlemini tetikle
                          },
                        );
                      },
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
