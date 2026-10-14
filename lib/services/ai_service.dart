import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as im;
import '../models/note_page.dart';

/// Optional online AI connector. No vendor/API key is embedded in the APK.
/// Only invoked after the user presses "Explain with AI" and has configured a URL.
class AiService {
  static Future<NoteInsight> explain(String endpoint, List<NotePage> pages) async {
    final uri = Uri.tryParse(endpoint.trim());
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) {
      throw const FormatException('Enter an HTTPS endpoint for your AI server.');
    }
    // Keep uploads small for speed, cost and reduced exposure of private notes.
    // The server can interpret diagrams in these images when image mode is enabled.
    final images = <String>[];
    for (final page in pages.take(3)) {
      final file = File(page.enhancedPath);
      final decoded = im.decodeImage(await file.readAsBytes());
      if (decoded == null) continue;
      final shrunk = decoded.width > 1100
          ? im.copyResize(decoded, width: 1100) : decoded;
      images.add(base64Encode(im.encodeJpg(shrunk, quality: 70)));
    }
    final allText = pages.map((p) => p.recognizedText).join('\n\n');
    final excerpt = allText.length > 12000 ? allText.substring(0, 12000) : allText;
    final response = await http.post(uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'ocr_text': excerpt,
        'images_base64': images,
      }),
    ).timeout(const Duration(seconds: 55));
    if (response.statusCode != 200) {
      throw HttpException('AI server error ${response.statusCode}.');
    }
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return NoteInsight(
      topic: (data['topic'] ?? 'Study notes').toString(),
      summary: (data['summary'] ?? '').toString(),
      explanations: (data['explanations'] as List<dynamic>? ?? []).map((e) => e.toString()).toList(),
      source: 'AI-assisted explanation (verify important facts)',
    );
  }
}
