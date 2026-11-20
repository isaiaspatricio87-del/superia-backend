import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

class ApiService {
  // Cambia esta URL por la de tu servicio real en Render (sin / al final)
  static const String baseUrl = 'https://superia-backend-1.onrender.com';
  static const Duration _timeout = Duration(seconds: 15);

  static Future<dynamic> login({
    required String email,
    required String password,
  }) async {
    final res = await http
        .post(
          Uri.parse('$baseUrl/api/auth/login'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'email': email, 'password': password}),
        )
        .timeout(_timeout);

    final data = jsonDecode(res.body);
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception(data['detail'] ?? 'Error al iniciar sesión.');
    }
    return data;
  }

  static Future<dynamic> register({
    required String name,
    required String email,
    required String password,
  }) async {
    final res = await http
        .post(
          Uri.parse('$baseUrl/api/auth/register'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'name': name, 'email': email, 'password': password}),
        )
        .timeout(_timeout);

    final data = jsonDecode(res.body);
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception(data['detail'] ?? 'Error al crear cuenta.');
    }
    return data;
  }

  static Future<dynamic> googleQuickLogin({
    required String name,
    required String email,
  }) async {
    final res = await http
        .post(
          Uri.parse('$baseUrl/api/auth/google'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'name': name, 'email': email}),
        )
        .timeout(_timeout);

    final data = jsonDecode(res.body);
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception(data['detail'] ?? 'Error con cuenta de Google.');
    }
    return data;
  }

  static Future<String> sendMessage({
    required String authToken,
    required String message,
    required List<String> memories,
    required List<dynamic> history,
    Uint8List? image,
    String? imageMimeType,
    Uint8List? audioWav,
  }) async {
    final body = <String, dynamic>{
      'message': message,
      'memories': memories,
      'history': history,
      if (image != null) 'image_base64': base64Encode(image),
      if (imageMimeType != null) 'image_mime_type': imageMimeType,
      if (audioWav != null) 'audio_base64': base64Encode(audioWav),
      if (audioWav != null) 'audio_mime_type': 'audio/wav',
    };

    final requestTimeout =
        audioWav != null ? const Duration(seconds: 120) : const Duration(seconds: 60);

    final res = await http
        .post(
          Uri.parse('$baseUrl/api/chat'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $authToken',
          },
          body: jsonEncode(body),
        )
        .timeout(requestTimeout);

    final data = jsonDecode(res.body);
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception(data['detail'] ?? 'Error en el servidor.');
    }

    return data['reply']?.toString() ?? '';
  }
}