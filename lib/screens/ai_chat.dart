import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/gemini_service.dart';
import '../theme/app_theme.dart';

class AIChatPage extends StatefulWidget {
  const AIChatPage({super.key});

  @override
  State<AIChatPage> createState() => _AIChatPageState();
}

class _AIChatPageState extends State<AIChatPage>
    with SingleTickerProviderStateMixin {
  final TextEditingController _controller = TextEditingController();
  final GeminiService _geminiService = GeminiService();
  final supabase = Supabase.instance.client;
  final ScrollController _scrollController = ScrollController();

  List<Map<String, String>> messages = [];
  bool isLoading = true;
  String? _currentUserId;

  late AnimationController _animationController;
  late Animation<double> _sendButtonScaleAnimation;

  /// Hazır komutlar — DB üzerinde iş yapar.
  final Map<String, Map<String, dynamic>> suggestedPrompts = {
    'Stok Takibi': {'value': 'stok_takibi', 'icon': Icons.inventory_2_outlined},
    'Yemek Önerisi': {'value': 'yemek_tavsiyesi', 'icon': Icons.restaurant_menu},
    'Liste Önerisi': {'value': 'alisveris_listesi', 'icon': Icons.list_alt},
    'En Çok Alınanlar': {'value': 'en_cok_alinanlar', 'icon': Icons.trending_up},
  };

  /// Gemini'ye gönderilen geçmiş son 20 mesajla sınırlı (token/istek şişmesin).
  List<Map<String, String>> get _cappedHistory => messages.length > 20
      ? messages.sublist(messages.length - 20)
      : messages;

  @override
  void initState() {
    super.initState();
    _currentUserId = supabase.auth.currentUser?.id;
    if (_currentUserId == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.pushReplacementNamed(context, '/login');
      });
      return;
    }

    loadChatHistory();

    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _sendButtonScaleAnimation =
        Tween<double>(begin: 1.0, end: 1.2).animate(_animationController);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToBottom();
      if (messages.isEmpty && !isLoading) {
        setState(() => messages.add({
              'role': 'ai',
              'text':
                  'Merhaba! 👋 Bugün sana nasıl yardımcı olabilirim?',
            }));
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

  Future<void> loadChatHistory() async {
    if (_currentUserId == null) return;
    setState(() => isLoading = true);
    try {
      final response = await supabase
          .from('ai_chat_history')
          .select('*')
          .eq('user_id', _currentUserId!)
          .order('created_at', ascending: true);

      if (mounted) {
        setState(() {
          messages = response
              .map((e) => {
                    'role': e['role'] as String,
                    'text': e['message'] as String,
                  })
              .toList();
          isLoading = false;
        });
        _scrollToBottom();
      }
    } catch (e) {
      debugPrint('Sohbet geçmişi yüklenemedi: $e');
      if (mounted) setState(() => isLoading = false);
    }
  }

  Future<void> saveMessage(String role, String text) async {
    if (_currentUserId == null) return;
    try {
      await supabase.from('ai_chat_history').insert({
        'user_id': _currentUserId,
        'role': role,
        'message': text,
        'created_at': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      debugPrint('Mesaj kaydedilemedi: $e');
    }
  }

  Future<void> handlePrompt(String type) async {
    if (_currentUserId == null) return;

    final entry =
        suggestedPrompts.entries.firstWhere((e) => e.value['value'] == type);
    final userPromptText = entry.key;

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
        final list = (stock as List)
            .map((i) =>
                '${i['product_name']} (${i['quantity'] ?? 'Belirtilmemiş'})')
            .toList();
        systemResponse = list.isEmpty
            ? 'Stokta tamamlanmış ürün yok.'
            : 'Stoktaki tamamlanmış ürünler:\n${list.join('\n')}';
      } else if (type == 'yemek_tavsiyesi') {
        final stock = await supabase
            .from('list_items')
            .select('product_name, quantity')
            .eq('is_completed', true);
        final list = (stock as List)
            .map((i) =>
                '${i['product_name']} (${i['quantity'] ?? 'Belirtilmemiş'})')
            .toList();
        final prompt = list.isEmpty
            ? 'Stokta hiç tamamlanmış ürün yok. Yemek önerisi yapılamaz.'
            : 'Eldeki tamamlanmış ürünler: ${list.join(', ')}.\n'
                'Bu malzemelerle hangi yemekleri yapabilirim? Kısa ve öz öner.';
        systemResponse = await _geminiService.askGemini(prompt,
            currentChatHistory: _cappedHistory);
      } else if (type == 'alisveris_listesi' || type == 'en_cok_alinanlar') {
        final allItems =
            await supabase.from('list_items').select('product_name');
        final Map<String, int> frequency = {};
        for (var item in allItems) {
          final name = item['product_name'];
          if (name != null) frequency[name] = (frequency[name] ?? 0) + 1;
        }
        final sorted = frequency.entries.toList()
          ..sort((a, b) => b.value.compareTo(a.value));
        final top =
            sorted.take(5).map((e) => '${e.key} (${e.value} kez)').toList();
        systemResponse = top.isEmpty
            ? 'Alışveriş geçmişi yok.'
            : 'Sıklıkla alınan ürünler:\n${top.join('\n')}';
      }

      setState(() => messages.add({'role': 'ai', 'text': systemResponse}));
      _scrollToBottom();
      await saveMessage('ai', systemResponse);
    } catch (e) {
      _showError(e);
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  /// Hatayı geçici SnackBar ile gösterir; sohbet geçmişine KAYDETMEZ.
  void _showError(Object e) {
    if (!mounted) return;
    final msg = e.toString().replaceFirst('Exception: ', '');
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: Theme.of(context).colorScheme.error,
    ));
  }

  Future<void> sendMessage(String userMessage) async {
    if (userMessage.trim().isEmpty || isLoading) return;
    if (_currentUserId == null) return;

    _animationController.forward().then((_) => _animationController.reverse());

    final original = userMessage.trim();
    setState(() {
      messages.add({'role': 'user', 'text': original});
      isLoading = true;
    });
    _controller.clear();
    _scrollToBottom();
    await saveMessage('user', original);

    try {
      final stockResponse = await supabase
          .from('list_items')
          .select('product_name, quantity')
          .eq('is_completed', true);
      final list = (stockResponse as List)
          .map((i) =>
              '${i['product_name']} (${i['quantity'] ?? 'Belirtilmemiş'})')
          .toList();
      final stokMetni = list.isEmpty
          ? 'Stokta ürün yok.'
          : 'Mevcut stoktaki tamamlanmış ürünler: ${list.join(', ')}. ';

      final aiResponse = await _geminiService.askGemini(
        '$stokMetni\n\nKullanıcının sorusu: $original',
        currentChatHistory: _cappedHistory,
      );

      setState(() => messages.add({'role': 'ai', 'text': aiResponse}));
      _scrollToBottom();
      await saveMessage('ai', aiResponse);
    } catch (e) {
      _showError(e);
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  // ---------------------------------------------------------------------------
  // UI
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        titleSpacing: 0,
        title: Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: AppTheme.heroGreenBg,
              child: Icon(Icons.smart_toy_outlined,
                  color: scheme.primary, size: 20),
            ),
            const SizedBox(width: 10),
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('AI Asistan',
                    style: TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w800)),
                Text('Çevrimiçi',
                    style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: scheme.primary)),
              ],
            ),
          ],
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView.builder(
                controller: _scrollController,
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                itemCount: messages.length,
                itemBuilder: (context, index) => _bubble(messages[index]),
              ),
            ),
            if (isLoading)
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
                child: Row(
                  children: [
                    SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: scheme.primary),
                    ),
                    const SizedBox(width: 10),
                    Text('yazıyor…',
                        style: TextStyle(
                            fontSize: 12, color: scheme.onSurfaceVariant)),
                  ],
                ),
              ),
            _suggestionChips(scheme),
            _inputBar(scheme),
          ],
        ),
      ),
    );
  }

  Widget _bubble(Map<String, String> message) {
    final isUser = message['role'] == 'user';
    final scheme = Theme.of(context).colorScheme;
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.78),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        margin: const EdgeInsets.symmetric(vertical: 4),
        decoration: BoxDecoration(
          color: isUser ? scheme.primary : scheme.surface,
          borderRadius: BorderRadius.circular(17),
          border: isUser
              ? null
              : Border.all(color: scheme.outlineVariant),
        ),
        child: Text(
          message['text'] ?? '',
          style: TextStyle(
            color: isUser ? scheme.onPrimary : scheme.onSurface,
            fontSize: 13.5,
            height: 1.4,
          ),
        ),
      ),
    );
  }

  Widget _suggestionChips(ColorScheme scheme) {
    return SizedBox(
      height: 46,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: suggestedPrompts.entries.map((entry) {
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ActionChip(
              avatar: Icon(entry.value['icon'] as IconData,
                  size: 16, color: scheme.primary),
              label: Text(entry.key),
              labelStyle: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: scheme.onSurface),
              onPressed: isLoading
                  ? null
                  : () => handlePrompt(entry.value['value'] as String),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _inputBar(ColorScheme scheme) {
    return Container(
      color: scheme.surface,
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _controller,
              minLines: 1,
              maxLines: 4,
              textInputAction: TextInputAction.send,
              decoration: InputDecoration(
                hintText: 'Mesajını yaz…',
                filled: true,
                fillColor: scheme.surfaceContainerHighest,
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 18, vertical: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide.none,
                ),
              ),
              onSubmitted: (_) => sendMessage(_controller.text),
            ),
          ),
          const SizedBox(width: 8),
          ScaleTransition(
            scale: _sendButtonScaleAnimation,
            child: Material(
              color: scheme.primary,
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: isLoading ? null : () => sendMessage(_controller.text),
                child: SizedBox(
                  width: 46,
                  height: 46,
                  child: Icon(Icons.arrow_upward_rounded,
                      color: scheme.onPrimary),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
