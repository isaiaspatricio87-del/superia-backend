import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

class ApiService {
  static const String baseUrl = 'https://superia-backend-1.onrender.com';

  static const Duration _authTimeout = Duration(seconds: 45);
  static const Duration _chatTimeout = Duration(seconds: 75);
  static const Duration _audioTimeout = Duration(seconds: 120);
  static const Duration _documentTimeout = Duration(seconds: 120);

  static Map<String, dynamic> _decodeJsonSafe(http.Response response) {
    if (response.body.trim().isEmpty) {
      return <String, dynamic>{};
    }

    try {
      final dynamic decoded = jsonDecode(response.body);

      if (decoded is Map<String, dynamic>) {
        return decoded;
      }

      if (decoded is Map) {
        return Map<String, dynamic>.from(decoded);
      }

      return <String, dynamic>{'data': decoded};
    } on FormatException {
      throw Exception(
        'El servidor devolvió una respuesta no válida '
        '(HTTP ${response.statusCode}).',
      );
    }
  }

  static String _extractErrorDetail(
    Map<String, dynamic> data,
    int statusCode,
    String fallback,
  ) {
    final dynamic detail = data['detail'] ?? data['error'] ?? data['message'];

    if (detail is String && detail.trim().isNotEmpty) {
      return detail.trim();
    }

    if (detail != null && detail.toString().trim().isNotEmpty) {
      return detail.toString();
    }

    return '$fallback (HTTP $statusCode).';
  }

  static Future> login({
    required String email,
    required String password,
  }) async {
    final response = await http
        .post(
          Uri.parse('$baseUrl/api/auth/login'),
          headers: const {'Content-Type': 'application/json'},
          body: jsonEncode({
            'email': email.trim(),
            'password': password,
          }),
        )
        .timeout(_authTimeout);

    final data = _decodeJsonSafe(response);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        _extractErrorDetail(
          data,
          response.statusCode,
          'Error al iniciar sesión.',
        ),
      );
    }

    return data;
  }

  static Future> register({
    required String name,
    required String email,
    required String password,
  }) async {
    final response = await http
        .post(
          Uri.parse('$baseUrl/api/auth/register'),
          headers: const {'Content-Type': 'application/json'},
          body: jsonEncode({
            'name': name.trim(),
            'email': email.trim(),
            'password': password,
          }),
        )
        .timeout(_authTimeout);

    final data = _decodeJsonSafe(response);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        _extractErrorDetail(
          data,
          response.statusCode,
          'Error al crear la cuenta.',
        ),
      );
    }

    return data;
  }

  static Future> googleQuickLogin({
    required String idToken,
  }) async {
    final cleanIdToken = idToken.trim();
    if (cleanIdToken.isEmpty) {
      throw Exception('Google no devolvió un ID token válido.');
    }

    final response = await http
        .post(
          Uri.parse('$baseUrl/api/auth/google'),
          headers: const {'Content-Type': 'application/json'},
          body: jsonEncode({'id_token': cleanIdToken}),
        )
        .timeout(_authTimeout);

    final data = _decodeJsonSafe(response);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        _extractErrorDetail(
          data,
          response.statusCode,
          'Error al iniciar sesión con Google.',
        ),
      );
    }

    return data;
  }

  static Future> sendMessage({
    required String authToken,
    required String message,
    required List<String> memories,
    required List<dynamic> history,
    Uint8List? image,
    String? imageMimeType,
    Uint8List? audioWav,
    // Cada documento debe tener: name, mime_type y base64.
    List> documents = const [],
  }) async {
    final body = <String, dynamic>{
      'message': message,
      'memories': memories,
      'history': history,
      if (image != null) 'image_base64': base64Encode(image),
      if (imageMimeType != null) 'image_mime_type': imageMimeType,
      if (audioWav != null) 'audio_base64': base64Encode(audioWav),
      if (audioWav != null) 'audio_mime_type': 'audio/wav',
      if (documents.isNotEmpty) 'documents': documents,
    };

    final Duration requestTimeout;

    if (audioWav != null) {
      requestTimeout = _audioTimeout;
    } else if (documents.isNotEmpty) {
      requestTimeout = _documentTimeout;
    } else {
      requestTimeout = _chatTimeout;
    }

    final response = await http
        .post(
          Uri.parse('$baseUrl/api/chat'),
          headers: {
            'Content-Type': 'application/json',
            if (authToken.trim().isNotEmpty)
              'Authorization': 'Bearer ${authToken.trim()}',
          },
          body: jsonEncode(body),
        )
        .timeout(requestTimeout);

    final data = _decodeJsonSafe(response);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        _extractErrorDetail(
          data,
          response.statusCode,
          'Error al comunicarse con el servidor.',
        ),
      );
    }

    final String reply = data['reply']?.toString() ??
        data['response']?.toString() ??
        data['message']?.toString() ??
        '';

    if (reply.trim().isEmpty) {
      throw Exception(
        'El servidor respondió, pero no devolvió texto. '
        'Revisa los logs del backend en Render.',
      );
    }

    Map<String, dynamic>? generatedFile;
    final dynamic rawFile = data['generated_file'];
    if (rawFile is Map<String, dynamic>) {
      generatedFile = rawFile;
    } else if (rawFile is Map) {
      generatedFile = Map<String, dynamic>.from(rawFile);
    }

    return <String, dynamic>{
      'reply': reply,
      'generated_file': generatedFile,
    };
  }
}