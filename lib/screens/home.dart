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


  // ---------------------------------------------------------------------------
  // UI
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Stack(
        children: [
          RefreshIndicator(
            onRefresh: _initializeDataAndListeners,
            child: ListView(
              physics: _showSuggestions
                  ? const NeverScrollableScrollPhysics()
                  : const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.only(bottom: 96),
              children: [
                _buildHeader(scheme),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildQuickStats(scheme),
                      const SizedBox(height: 28),
                      _buildRecentListsSection(scheme),
                      if (suggestedToday.isNotEmpty) ...[
                        const SizedBox(height: 28),
                        _buildSuggestionsSection(scheme),
                      ],
                      const SizedBox(height: 28),
                      _buildCategoriesSection(scheme),
                      if (weeklyData.any((d) => d.itemCount > 0)) ...[
                        const SizedBox(height: 28),
                        _buildWeeklyChartSection(scheme),
                      ],
                      if (topProducts.isNotEmpty) ...[
                        const SizedBox(height: 28),
                        _buildTopProductsSection(scheme),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (_showSuggestions) _buildSuggestionsOverlay(scheme),
        ],
      ),
    );
  }

  // --- Header ---------------------------------------------------------------

  Widget _buildHeader(ColorScheme scheme) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(
          16, MediaQuery.of(context).padding.top + 12, 16, 22),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: getGreetingCardGradientColors(),
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius:
            const BorderRadius.vertical(bottom: Radius.circular(28)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.menu_rounded, color: Colors.white),
                onPressed: () => Scaffold.of(context).openDrawer(),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(getGreeting(),
                        style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.85),
                            fontSize: 13)),
                    Text(
                      userName.isEmpty ? 'Merhaba!' : userName,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.notifications_none_rounded,
                    color: Colors.white),
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const NotificationsScreen()),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(14),
            ),
            child: TextField(
              controller: _searchController,
              focusNode: _searchFocusNode,
              style: const TextStyle(color: Colors.white),
              cursorColor: Colors.white,
              decoration: InputDecoration(
                isDense: true,
                hintText: 'Liste veya ürün ara…',
                hintStyle:
                    TextStyle(color: Colors.white.withValues(alpha: 0.8)),
                prefixIcon:
                    const Icon(Icons.search_rounded, color: Colors.white),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                filled: false,
                contentPadding:
                    const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
              ),
              onSubmitted: _onSearchSubmitted,
            ),
          ),
        ],
      ),
    );
  }

  // --- Quick stats -------------------------------------------------------

  Widget _buildQuickStats(ColorScheme scheme) {
    final completion =
        totalItems == 0 ? 0 : (completedItems / totalItems * 100).round();
    return Row(
      children: [
        Expanded(
            child: _statCard(scheme, Icons.receipt_long_outlined,
                '${shoppingLists.length}', 'Liste')),
        const SizedBox(width: 12),
        Expanded(
            child: _statCard(
                scheme, Icons.shopping_bag_outlined, '$totalItems', 'Ürün')),
        const SizedBox(width: 12),
        Expanded(
            child: _statCard(scheme, Icons.check_circle_outline,
                '%$completion', 'Tamam')),
      ],
    );
  }

  Widget _statCard(
      ColorScheme scheme, IconData icon, String value, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(14),
        border:
            Border.all(color: scheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Column(
        children: [
          Icon(icon, color: scheme.primary, size: 22),
          const SizedBox(height: 6),
          Text(value,
              style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: scheme.onSurface)),
          Text(label,
              style:
                  TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
        ],
      ),
    );
  }

  Widget _sectionHeader(ColorScheme scheme, String title, {Widget? action}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(title,
              style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: scheme.onSurface)),
          if (action != null) action,
        ],
      ),
    );
  }

  // --- Recent lists ---------------------------------------------------

  Widget _buildRecentListsSection(ColorScheme scheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader(scheme, 'Listelerim'),
        if (_filteredShoppingLists.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: scheme.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                  color: scheme.outlineVariant.withValues(alpha: 0.5)),
            ),
            child: Column(
              children: [
                Icon(Icons.playlist_add_rounded,
                    size: 40, color: scheme.primary),
                const SizedBox(height: 8),
                Text('Henüz listen yok.',
                    style: TextStyle(color: scheme.onSurfaceVariant)),
              ],
            ),
          )
        else
          SizedBox(
            height: 132,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _filteredShoppingLists.length,
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: (context, i) =>
                  _recentListCard(scheme, _filteredShoppingLists[i]),
            ),
          ),
      ],
    );
  }

  Widget _recentListCard(ColorScheme scheme, Map<String, dynamic> list) {
    final items = (list['list_items'] as List?) ?? const [];
    final itemCount = items.length;
    final names = items
        .take(2)
        .map((e) => (e['product_name'] ?? '').toString())
        .where((s) => s.isNotEmpty)
        .join(', ');
    String date = '';
    try {
      date = DateFormat('dd MMM', 'tr_TR')
          .format(DateTime.parse(list['created_at']));
    } catch (_) {}

    return InkWell(
      onTap: () => Navigator.pushNamed(context, '/listDetail', arguments: {
        'id': list['id'],
        'name': list['name'],
        'user_id': list['user_id'],
      }),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: 200,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
              color: scheme.outlineVariant.withValues(alpha: 0.5)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: scheme.primaryContainer,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(Icons.list_alt_rounded,
                  color: scheme.onPrimaryContainer, size: 20),
            ),
            const SizedBox(height: 10),
            Text(list['name'] ?? 'İsimsiz',
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                    color: scheme.onSurface),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
            const SizedBox(height: 2),
            Text('$itemCount ürün${date.isEmpty ? '' : ' • $date'}',
                style:
                    TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
            if (names.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(names,
                    style: TextStyle(
                        fontSize: 11,
                        color: scheme.onSurfaceVariant
                            .withValues(alpha: 0.8)),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
              ),
          ],
        ),
      ),
    );
  }

  // --- AI suggestions ------------------------------------------------

  Widget _buildSuggestionsSection(ColorScheme scheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader(scheme, 'Önerilen ürünler'),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: suggestedToday.map((name) {
            return ActionChip(
              avatar:
                  Icon(Icons.add_rounded, size: 18, color: scheme.primary),
              label: Text(name),
              onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                    content: Text('"$name" için bir listeye ekleyin.')),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  // --- Categories ---------------------------------------------------

  Widget _buildCategoriesSection(ColorScheme scheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader(scheme, 'Kategoriler',
            action: TextButton(
              onPressed: _showCategoryManagementSheet,
              child: const Text('Düzenle'),
            )),
        if (_dynamicCategories.isEmpty)
          Text('Ürün ekledikçe kategoriler burada görünür.',
              style: TextStyle(color: scheme.onSurfaceVariant))
        else
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children:
                _dynamicCategories.map((cat) => _categoryTile(scheme, cat)).toList(),
          ),
      ],
    );
  }

  Widget _categoryTile(ColorScheme scheme, Map<String, dynamic> cat) {
    final colors = (cat['colors'] as List?)?.cast<Color>() ??
        const [Color(0xFF90A4AE), Color(0xFF607D8B)];
    final count = (cat['count'] as int?) ?? 0;
    final width = (MediaQuery.of(context).size.width - 32 - 24) / 3;
    return InkWell(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => CategoryDetailPage(
            categoryName: cat['name'] as String,
            customPrimarySwatch: widget.customPrimarySwatch,
          ),
        ),
      ),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: width,
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
              color: scheme.outlineVariant.withValues(alpha: 0.5)),
        ),
        child: Column(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: colors),
                shape: BoxShape.circle,
              ),
              child: Icon(
                  cat['icon'] as IconData? ?? Icons.category_outlined,
                  color: Colors.white,
                  size: 22),
            ),
            const SizedBox(height: 8),
            Text(cat['name'] as String,
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: scheme.onSurface),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
            if (count > 0)
              Text('$count ürün',
                  style: TextStyle(
                      fontSize: 10, color: scheme.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }

  // --- Weekly chart -----------------------------------------------

  Widget _buildWeeklyChartSection(ColorScheme scheme) {
    final maxCount =
        weeklyData.map((e) => e.itemCount).fold<int>(0, (a, b) => a > b ? a : b);
    final maxY = (maxCount == 0 ? 5 : maxCount * 1.2).toDouble();

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(16),
        border:
            Border.all(color: scheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Haftalık Aktivite',
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: scheme.onSurface)),
          const SizedBox(height: 16),
          SizedBox(
            height: 180,
            child: BarChart(
              BarChartData(
                alignment: BarChartAlignment.spaceAround,
                barTouchData: BarTouchData(enabled: false),
                maxY: maxY,
                titlesData: FlTitlesData(
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 28,
                        getTitlesWidget: (v, m) => Text(
                            v.toInt().toString(),
                            style: TextStyle(
                                color: scheme.onSurfaceVariant,
                                fontSize: 10))),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      getTitlesWidget: (v, m) {
                        final i = v.toInt();
                        if (i < 0 || i >= weeklyData.length) {
                          return const SizedBox();
                        }
                        return Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(weeklyData[i].day,
                              style: TextStyle(
                                  color: scheme.onSurfaceVariant,
                                  fontSize: 10)),
                        );
                      },
                    ),
                  ),
                  topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                ),
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  getDrawingHorizontalLine: (v) => FlLine(
                      color: scheme.outlineVariant.withValues(alpha: 0.4),
                      strokeWidth: 1),
                ),
                borderData: FlBorderData(show: false),
                barGroups: List.generate(weeklyData.length, (i) {
                  return BarChartGroupData(x: i, barRods: [
                    BarChartRodData(
                      toY: weeklyData[i].itemCount.toDouble(),
                      color: scheme.primary,
                      width: 16,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ]);
                }),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // --- Top products ---------------------------------------------

  Widget _buildTopProductsSection(ColorScheme scheme) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(16),
        border:
            Border.all(color: scheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Sıkça Alınanlar',
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: scheme.onSurface)),
          const SizedBox(height: 8),
          ...topProducts.take(4).map((p) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: scheme.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(Icons.shopping_bag_outlined,
                        color: scheme.primary, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(p['product_name'].toString(),
                        style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: scheme.onSurface),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                  ),
                  Text('${p['count']}x',
                      style: TextStyle(
                          color: scheme.onSurfaceVariant,
                          fontWeight: FontWeight.w600)),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  // --- Search suggestions overlay -----------------------------

  Widget _buildSuggestionsOverlay(ColorScheme scheme) {
    return Positioned(
      top: MediaQuery.of(context).padding.top + 132,
      left: 16,
      right: 16,
      child: Material(
        elevation: 6,
        color: scheme.surface,
        borderRadius: BorderRadius.circular(14),
        child: ConstrainedBox(
          constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.35),
          child: ListView.builder(
            padding: EdgeInsets.zero,
            shrinkWrap: true,
            itemCount: _currentSuggestions.length,
            itemBuilder: (context, i) {
              final s = _currentSuggestions[i];
              final isAi = s.startsWith('AI');
              return ListTile(
                dense: true,
                leading: Icon(
                    isAi
                        ? Icons.psychology_outlined
                        : Icons.north_west_rounded,
                    size: 18,
                    color: isAi ? scheme.primary : scheme.onSurfaceVariant),
                title: Text(s,
                    style: TextStyle(
                        color: isAi ? scheme.primary : scheme.onSurface,
                        fontWeight:
                            isAi ? FontWeight.bold : FontWeight.normal)),
                onTap: () {
                  _searchController.text = s;
                  _onSearchSubmitted(s);
                },
              );
            },
          ),
        ),
      ),
    );
  }
}
