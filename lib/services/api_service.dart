import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

class ApiService {
  static const String baseUrl = 'https://TU-BACKEND.onrender.com';

  static Future> login({
    required String email,
    required String password,
  }) async {
    final res = await http.post(
      Uri.parse('$baseUrl/api/auth/login'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'email': email, 'password': password}),
    );

    final data = jsonDecode(res.body) as Map<String, dynamic>;
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception(data['detail'] ?? 'Error al iniciar sesión.');
    }
    return data;
  }

  static Future> register({
    required String name,
    required String email,
    required String password,
  }) async {
    final res = await http.post(
      Uri.parse('$baseUrl/api/auth/register'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'name': name, 'email': email, 'password': password}),
    );

    final data = jsonDecode(res.body) as Map<String, dynamic>;
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception(data['detail'] ?? 'Error al crear cuenta.');
    }
    return data;
  }

  static Future<String> sendMessage({
    required String authToken,
    required String message,
    required List<String> memories,
    required List> history,
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

    final res = await http.post(
      Uri.parse('$baseUrl/api/chat'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $authToken',
      },
      body: jsonEncode(body),
    );

    final data = jsonDecode(res.body) as Map<String, dynamic>;
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception(data['detail'] ?? 'Error en el servidor.');
    }

    return data['reply']?.toString() ?? '';
  }
}