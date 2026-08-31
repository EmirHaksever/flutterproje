import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';

class GeminiService {
  // API anahtarı .env dosyasından okunur (koda gömülmez). main() içinde
  // dotenv.load() çağrıldığı için burada hazır olur.
  final String apiKey = dotenv.env['GEMINI_API_KEY'] ?? '';

  // Model adı .env'den değiştirilebilir (GEMINI_MODEL). Google modelleri zaman
  // zaman emekliye ayırdığı için sabit yazmıyoruz; varsayılan "her zaman güncel
  // flash" takma adı.
  static final String _model =
      dotenv.env['GEMINI_MODEL']?.trim().isNotEmpty == true
          ? dotenv.env['GEMINI_MODEL']!.trim()
          : 'gemini-flash-latest';
  final String apiUrl =
      'https://generativelanguage.googleapis.com/v1beta/models/$_model:generateContent';

  /// Sends a prompt to the Gemini API and includes previous chat history for context.
  ///
  /// [prompt]: The current message from the user.
  /// [currentChatHistory]: An optional list of previous messages in the chat,
  ///   formatted as `{'role': 'user'/'ai', 'text': 'message content'}`.
  Future<String> askGemini(String prompt, {List<Map<String, String>>? currentChatHistory}) async {
    if (apiKey.isEmpty) {
      throw Exception(
          'GEMINI_API_KEY tanımlı değil. Proje kökündeki .env dosyasına '
          'GEMINI_API_KEY=... satırını ekleyin.');
    }

    // This list will hold the formatted chat history to send to the Gemini API.
    List<Map<String, dynamic>> contents = [];

    // If there's existing chat history, add it to the contents list.
    if (currentChatHistory != null) {
      for (var msg in currentChatHistory) {
        // Map your app's 'ai' role to Gemini's 'model' role
        final role = msg['role'] == 'user' ? 'user' : 'model';
        contents.add({
          "role": role,
          "parts": [
            {"text": msg['text']}
          ]
        });
      }
    }

    // Add the current user's prompt to the contents list.
    contents.add({
      "role": "user",
      "parts": [
        {"text": prompt}
      ]
    });

    final uri = Uri.parse('$apiUrl?key=$apiKey');

    final http.Response response;
    try {
      response = await http
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              "contents": contents,
              "generationConfig": {
                "temperature": 0.7,
                "topP": 0.95,
                "topK": 40,
                "maxOutputTokens": 1024,
              },
            }),
          )
          .timeout(const Duration(seconds: 30));
    } on Exception {
      throw Exception(
          'Yapay zekâ servisine ulaşılamadı. İnternet bağlantını kontrol edip tekrar dene.');
    }

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      // Check for 'candidates' and their structure carefully
      if (data['candidates'] != null && data['candidates'].isNotEmpty &&
          data['candidates'][0]['content'] != null &&
          data['candidates'][0]['content']['parts'] != null &&
          data['candidates'][0]['content']['parts'].isNotEmpty) {
        return data['candidates'][0]['content']['parts'][0]['text'] ?? 'Yanıt alınamadı.';
      } else {
        return 'Yapay zekadan beklenen formatta bir yanıt alınamadı.';
      }
    } else {
      throw Exception(
          'Gemini API hatası: ${response.statusCode} - ${response.body}');
    }
  }
}
