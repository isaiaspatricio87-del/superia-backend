import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

class ApiService {
  static const String _backendChatUrl =
      'https://superia-backend-1.onrender.com/api/chat';

  static Future<String> sendMessage({
    required String message,
    required List<String> memories,
    List<Map<String, String>> history = const [],
    Uint8List? audioWav,
    Uint8List? image,
    String? imageMimeType,
  }) async {
    final payload = <String, dynamic>{
      'message': message,
      'memories': memories,
      'history': history,
    };

    if (audioWav != null) {
      payload['audio_base64'] = base64Encode(audioWav);
      payload['audio_mime_type'] = 'audio/wav';
    }

    if (image != null) {
      payload['image_base64'] = base64Encode(image);
      payload['image_mime_type'] = imageMimeType ?? 'image/jpeg';
    }

    try {
      final response = await http
          .post(
            Uri.parse(_backendChatUrl),
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 90));

      dynamic body;
      try {
        body = jsonDecode(response.body);
      } catch (_) {
        body = null;
      }

      if (response.statusCode < 200 || response.statusCode >= 300) {
        final detail = body is Map ? body['detail'] : null;
        throw Exception(
          detail?.toString() ?? 'Error HTTP ${response.statusCode}',
        );
      }

      if (body is! Map || !body.containsKey('reply')) {
        throw Exception('El servidor devolvió una respuesta inválida.');
      }

      return body['reply'].toString();
    } catch (error) {
      final text = error.toString().replaceFirst('Exception: ', '');

      if (text.contains('Failed to fetch') ||
          text.contains('XMLHttpRequest')) {
        throw Exception('Falló la conexión con Render. Revisa el backend.');
      }

      throw Exception(text);
    }
  }
}
