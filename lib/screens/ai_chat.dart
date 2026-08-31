import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/gemini_service.dart';

class AIChatPage extends StatefulWidget {
  const AIChatPage({super.key});

  @override
  State<AIChatPage> createState() => _AIChatPageState();
}

class _AIChatPageState extends State<AIChatPage> with SingleTickerProviderStateMixin {
  final TextEditingController _controller = TextEditingController();
  final GeminiService _geminiService = GeminiService();
  final supabase = Supabase.instance.client;

  List<Map<String, String>> messages = [];
  bool isLoading = true; 
  String? _currentUserId; // Mevcut kullanıcı ID'si

  final Map<String, Map<String, dynamic>> suggestedPrompts = {
    'Stok Takibi': {'value': 'stok_takibi', 'icon': Icons.inventory_outlined},
    'Yemek Tavsiyesi': {'value': 'yemek_tavsiyesi', 'icon': Icons.restaurant_menu},
    'Alışveriş Listesi Önerisi': {'value': 'alisveris_listesi', 'icon': Icons.list_alt},
    'En Çok Alınanlar': {'value': 'en_cok_alinanlar', 'icon': Icons.trending_up},
  };

  final ScrollController _scrollController = ScrollController();
  late AnimationController _animationController;
  late Animation<double> _sendButtonScaleAnimation;

  @override
  void initState() {
    super.initState();
    _currentUserId = supabase.auth.currentUser?.id; // Kullanıcı ID'sini al
    if (_currentUserId == null) {
      // Kullanıcı oturum açmamışsa login sayfasına yönlendir
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.pushReplacementNamed(context, '/login');
      });
      return;
    }

    loadChatHistory(); // Sohbet geçmişini yükle
    // Not: Mesajlar zaten iyimser olarak ekrana ekleniyor ve DB'ye yazılıyor.
    // Realtime dinleyici, kendi yazdığımız mesajı bir kez daha ekleyip çift
    // baloncuğa yol açıyordu; tek kullanıcının kendi geçmişi olduğu için kaldırıldı.

    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _sendButtonScaleAnimation = Tween<double>(begin: 1.0, end: 1.2).animate(_animationController);

    // Mesaj geçmişi yüklendikten sonra hoş geldin mesajını kontrol et
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToBottom();
      // loadChatHistory tamamlandıktan sonra messages listesi hala boşsa hoş geldin mesajı ekle
      if (messages.isEmpty && !isLoading) {
        messages.add({'role': 'ai', 'text': 'Merhaba! Ben Yapay Zeka Asistanınız. Size nasıl yardımcı olabilirim?'});
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    _animationController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  // Mesajları Supabase'den çek
  Future<void> loadChatHistory() async {
    if (_currentUserId == null) return;

    setState(() {
      isLoading = true;
    });

    try {
      final response = await supabase
          .from('ai_chat_history') // Tablo adı
          .select('*')
          .eq('user_id', _currentUserId!) // Düzeltildi: Kullanıcı ID'si için 'user_id' sütunu kullanıldı
          .order('created_at', ascending: true); // En eski mesajdan en yeniye sırala

      if (mounted) {
        setState(() {
          messages = response.map((e) => {
            'role': e['role'] as String,
            'text': e['message'] as String, // message sütununu kullan
          }).toList();
          isLoading = false;
        });
        _scrollToBottom(); // Mesajlar yüklendikten sonra en alta kaydır
      }
    } catch (e) {
      debugPrint('Sohbet geçmişi yüklenemedi: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Sohbet geçmişi yüklenirken bir hata oluştu: $e')),
        );
        setState(() {
          isLoading = false;
        });
      }
    }
  }

  // Mesajı veritabanına kaydet
  Future<void> saveMessage(String role, String text) async {
    if (_currentUserId == null) return;
    try {
      await supabase.from('ai_chat_history').insert({
        // 'id' sütunu birincil anahtar olduğu için Supabase tarafından otomatik olarak atanır.
        // Buraya manuel olarak kullanıcı ID'si eklenmemelidir.
        'user_id': _currentUserId, // Düzeltildi: Kullanıcı ID'si için 'user_id' sütunu kullanıldı
        'role': role,
        'message': text, // message sütununu kullan
        'created_at': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      debugPrint('Mesaj kaydedilemedi: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Mesajınız kaydedilirken bir hata oluştu: $e')),
        );
      }
    }
  }

  Future<void> handlePrompt(String type) async {
    if (_currentUserId == null) return; // Kullanıcı yoksa işlem yapma

    final userPromptEntry = suggestedPrompts.entries.firstWhere((e) => e.value['value'] == type);
    final userPromptText = userPromptEntry.key;

    setState(() {
      messages.add({'role': 'user', 'text': userPromptText});
      isLoading = true;
    });
    _scrollToBottom();
    await saveMessage('user', userPromptText);

    String systemResponse = '';
    try {
      if (type == 'stok_takibi') {
        final stock = await supabase
            .from('list_items')
            .select('product_name, quantity')
            .eq('is_completed', true);

        final stokListesi = (stock as List).map((item) =>
            '${item['product_name']} (${item['quantity'] ?? 'Belirtilmemiş'})').toList();

        systemResponse = stokListesi.isEmpty
            ? 'Stokta tamamlanmış ürün yok.'
            : 'Stoktaki tamamlanmış ürünler:\n${stokListesi.join('\n')}';
      } else if (type == 'yemek_tavsiyesi') {
        final stock = await supabase
            .from('list_items')
            .select('product_name, quantity')
            .eq('is_completed', true);

        final stokListesi = (stock as List).map((item) =>
            '${item['product_name']} (${item['quantity'] ?? 'Belirtilmemiş'})').toList();

        final prompt = stokListesi.isEmpty
            ? 'Stokta hiç tamamlanmış ürün yok. Yemek önerisi yapılamaz.'
            : 'Eldeki tamamlanmış ürünler: ${stokListesi.join(', ')}.\nBu malzemelerle hangi yemekleri yapabilirim? Kısa ve öz önerilerde bulun.';

        // Gemini API çağrısı
        systemResponse = await _geminiService.askGemini(prompt, currentChatHistory: messages);
      } else if (type == 'alisveris_listesi' || type == 'en_cok_alinanlar') {
        final allItems = await supabase.from('list_items').select('product_name');
        final Map<String, int> frequency = {};

        for (var item in allItems) {
          final name = item['product_name'];
          if (name != null) {
            frequency[name] = (frequency[name] ?? 0) + 1;
          }
        }

        final sorted = frequency.entries.toList()
          ..sort((a, b) => b.value.compareTo(a.value));
        final topItems = sorted.take(5).map((e) => '${e.key} (${e.value} kez)').toList();

        systemResponse = topItems.isEmpty
            ? 'Alışveriş geçmişi yok.'
            : 'Sıklıkla alınan ürünler:\n${topItems.join('\n')}';
      }

      setState(() {
        messages.add({'role': 'ai', 'text': systemResponse});
      });
      _scrollToBottom();
      await saveMessage('ai', systemResponse);
    } catch (e) {
      _showError(e);
    } finally {
      setState(() => isLoading = false);
    }
  }

  /// Hatayı geçici bir SnackBar ile gösterir; sohbet geçmişine KAYDETMEZ.
  void _showError(Object e) {
    if (!mounted) return;
    final msg = e.toString().replaceFirst('Exception: ', '');
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.red.shade400),
    );
  }

  Future<void> sendMessage(String userMessage) async {
    if (userMessage.trim().isEmpty || isLoading) return;
    if (_currentUserId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Kullanıcı oturumu bulunamadı. Lütfen tekrar giriş yapın.')),
      );
      return;
    }

    _animationController.forward().then((_) => _animationController.reverse());

    final originalUserMessage = userMessage;
    setState(() {
      messages.add({'role': 'user', 'text': originalUserMessage});
      isLoading = true;
    });
    _controller.clear();
    _scrollToBottom();
    await saveMessage('user', originalUserMessage);

    try {
      final stockResponse = await supabase
          .from('list_items')
          .select('product_name, quantity')
          .eq('is_completed', true);

      final stokListesi = (stockResponse as List).map((item) =>
          '${item['product_name']} (${item['quantity'] ?? 'Belirtilmemiş'})').toList();

      final stokMetni = stokListesi.isEmpty
          ? 'Stokta ürün yok.'
          : 'Mevcut stoktaki tamamlanmış ürünler: ${stokListesi.join(', ')}. ';

      final aiResponse = await _geminiService.askGemini(
        '$stokMetni\n\nKullanıcının sorusu: $originalUserMessage',
        currentChatHistory: messages,
      );

      setState(() {
        messages.add({'role': 'ai', 'text': aiResponse});
      });
      _scrollToBottom();
      await saveMessage('ai', aiResponse);
    } catch (e) {
      _showError(e);
    } finally {
      setState(() {
        isLoading = false;
      });
    }
  }

  Widget buildMessage(Map<String, String> message) {
    final isUser = message['role'] == 'user';
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
        decoration: BoxDecoration(
          color: isUser ? const Color(0xFF6A1B9A).withValues(alpha: 0.9) : const Color(0xFFE8EAF6), // Mor tonları / Açık gri-mavi
          borderRadius: BorderRadius.circular(20), // Daha yuvarlak baloncuklar
          boxShadow: [
            BoxShadow(
              color: (isUser ? const Color(0xFF6A1B9A) : Colors.grey).withValues(alpha: 0.2),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Text(
          message['text'] ?? '',
          style: TextStyle(
            color: isUser ? Colors.white : Colors.blueGrey.shade800, // Daha belirgin metin rengi
            fontSize: 16, // Font boyutu artırıldı
          ),
        ),
      ),
    );
  }

  Widget buildSuggestedPromptButtons() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10.0),
      color: Colors.white,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16.0),
        child: Row(
          children: suggestedPrompts.entries.map((entry) {
            return Padding(
              padding: const EdgeInsets.only(right: 12.0),
              child: ActionChip(
                avatar: Icon(entry.value['icon'] as IconData, color: const Color(0xFF6A1B9A), size: 22), // Mor ikon
                label: Text(entry.key),
                onPressed: isLoading ? null : () => handlePrompt(entry.value['value'] as String),
                backgroundColor: Colors.white,
                side: BorderSide(color: const Color(0xFF6A1B9A).withValues(alpha: 0.4), width: 1.0), // Mor kenarlık
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                labelStyle: const TextStyle(color: Color(0xFF6A1B9A), fontWeight: FontWeight.w600, fontSize: 14),
                elevation: 4,
                shadowColor: Colors.black.withValues(alpha: 0.15),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF8E24AA), Color(0xFF4A148C)], // Mor tonları
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        title: const Text('AI Asistanı', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 22)), // Daha büyük başlık
        iconTheme: const IconThemeData(color: Colors.white),
        elevation: 0,
        centerTitle: true, // Başlık ortalandı
      ),
      backgroundColor: const Color(0xFFF0F2F5), // Daha açık, yumuşak gri arka plan
      body: SafeArea(
        child: Column(
          children: [
            // Önerilen İstem Butonları
            buildSuggestedPromptButtons(),
            // Sohbet Geçmişi
            Expanded(
              child: ListView.builder(
                controller: _scrollController,
                padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
                itemCount: messages.length,
                itemBuilder: (context, index) => buildMessage(messages[index]),
              ),
            ),
            // Yüklenme Göstergesi
            if (isLoading)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                child: LinearProgressIndicator(
                  backgroundColor: const Color(0xFFE8EAF6), // Açık gri-mavi
                  valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF6A1B9A)), // Mor tonu
                  borderRadius: BorderRadius.circular(10),
                  minHeight: 8,
                ),
              ),
            // Metin Giriş Alanı ve Gönderme Butonu
            Container(
              color: Colors.white,
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      decoration: InputDecoration(
                        hintText: 'Mesajınızı yazın...',
                        hintStyle: TextStyle(color: Colors.grey.shade600),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(30.0), // Daha da yuvarlak
                          borderSide: BorderSide.none,
                        ),
                        filled: true,
                        fillColor: const Color(0xFFF0F2F5), // Arka plan rengiyle uyumlu
                        contentPadding: const EdgeInsets.symmetric(horizontal: 22.0, vertical: 14.0), // Padding artırıldı
                      ),
                      onSubmitted: (value) => sendMessage(_controller.text),
                    ),
                  ),
                  const SizedBox(width: 10), // Daha fazla boşluk
                  ScaleTransition(
                    scale: _sendButtonScaleAnimation,
                    child: FloatingActionButton(
                      heroTag: 'aiChatSendFab',
                      onPressed: isLoading ? null : () => sendMessage(_controller.text),
                      mini: false, // Daha büyük bir FAB
                      backgroundColor: const Color(0xFF8E24AA), // Mor tonu
                      elevation: 5, // Daha belirgin gölge
                      shape: const CircleBorder(), // Tamamen dairesel buton
                      child: isLoading
                          ? const SizedBox(
                              width: 24, // Boyut ayarlandı
                              height: 24,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5, // Kalınlık ayarlandı
                                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                              ),
                            )
                          : const Icon(Icons.send_rounded, color: Colors.white, size: 28), // Daha büyük ikon
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
