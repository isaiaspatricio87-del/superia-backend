import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:google_sign_in_web/web_only.dart' as web;
import 'package:image_picker/image_picker.dart';
import 'package:record/record.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web/web.dart' as html_web;

import 'services/api_service.dart';
import 'services/voice_player.dart';

const Color bg = Color(0xFF05091B);
const Color panel = Color(0xE608122B);
const Color cyan = Color(0xFF19C7FF);
const Color blue = Color(0xFF3475FF);
const Color muted = Color(0xFFAAC0E0);

@JS('registerSuperiaPasteListener')
external void _registerSuperiaPasteListener(JSFunction callback);

@JS()
@anonymous
extension type _PastePayload._(JSObject _) implements JSObject {
  external String? get type;
  external String? get name;
  external String? get mimeType;
  external String? get base64;
  external String? get text;
}

void main() => runApp(const SuperIAApp());

class PendingAttachment {
  const PendingAttachment({
    required this.name,
    required this.bytes,
    required this.mimeType,
    this.isImage = true,
    this.extractedText,
  });

  final String name;
  final Uint8List bytes;
  final String mimeType;
  final bool isImage;
  final String? extractedText;
}

class GeneratedDownloadFile {
  const GeneratedDownloadFile({
    required this.filename,
    required this.mimeType,
    required this.base64Data,
  });

  final String filename;
  final String mimeType;
  final String base64Data;

  Map<String, dynamic> toJson() => {
        'filename': filename,
        'mime_type': mimeType,
        'base64': base64Data,
      };

  factory GeneratedDownloadFile.fromJson(Map<String, dynamic> json) =>
      GeneratedDownloadFile(
        filename: json['filename']?.toString() ?? 'documento_superia.pdf',
        mimeType: json['mime_type']?.toString() ?? 'application/pdf',
        base64Data: json['base64']?.toString() ?? '',
      );
}

class StoredSentImage {
  const StoredSentImage({
    required this.id,
    required this.name,
    required this.mimeType,
    required this.imageBase64,
    required this.sentAt,
    this.caption = '',
  });

  final String id;
  final String name;
  final String mimeType;
  final String imageBase64;
  final DateTime sentAt;
  final String caption;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'mimeType': mimeType,
        'imageBase64': imageBase64,
        'sentAt': sentAt.toIso8601String(),
        'caption': caption,
      };

  factory StoredSentImage.fromJson(Map<String, dynamic> json) =>
      StoredSentImage(
        id: json['id']?.toString() ??
            DateTime.now().microsecondsSinceEpoch.toString(),
        name: json['name']?.toString() ?? 'Imagen.jpg',
        mimeType: json['mimeType']?.toString() ?? 'image/jpeg',
        imageBase64: json['imageBase64']?.toString() ?? '',
        sentAt:
            DateTime.tryParse(json['sentAt']?.toString() ?? '') ?? DateTime.now(),
        caption: json['caption']?.toString() ?? '',
      );
}

class StoredAccount {
  const StoredAccount({
    required this.token,
    required this.name,
    required this.email,
    this.avatarBase64,
  });

  final String token;
  final String name;
  final String email;
  final String? avatarBase64;

  StoredAccount copyWith({
    String? token,
    String? name,
    String? email,
    String? avatarBase64,
  }) =>
      StoredAccount(
        token: token ?? this.token,
        name: name ?? this.name,
        email: email ?? this.email,
        avatarBase64: avatarBase64 ?? this.avatarBase64,
      );

  Map<String, dynamic> toJson() => {
        'token': token,
        'name': name,
        'email': email,
        'avatarBase64': avatarBase64,
      };

  factory StoredAccount.fromJson(Map<String, dynamic> json) => StoredAccount(
        token: json['token']?.toString() ?? '',
        name: json['name']?.toString() ?? '',
        email: json['email']?.toString() ?? '',
        avatarBase64: json['avatarBase64']?.toString(),
      );
}

class SuperIAApp extends StatelessWidget {
  const SuperIAApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'isaias titan',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: bg,
        colorScheme: ColorScheme.fromSeed(
          seedColor: cyan,
          brightness: Brightness.dark,
          surface: const Color(0xFF08132A),
        ),
        useMaterial3: true,
        snackBarTheme: const SnackBarThemeData(
          backgroundColor: Color(0xFF0A244D),
          contentTextStyle: TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
          behavior: SnackBarBehavior.floating,
        ),
      ),
      home: const AuthGate(),
    );
  }
}

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  bool _checking = true;
  String? _token;
  String _userName = '';
  String _userEmail = '';
  List<StoredAccount> _savedAccounts = [];

  @override
  void initState() {
    super.initState();
    _restoreSession();
  }

  List<StoredAccount> _decodeAccounts(String? raw) {
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List;
      return list
          .map(
            (e) => StoredAccount.fromJson(Map<String, dynamic>.from(e as Map)),
          )
          .where((a) => a.email.isNotEmpty)
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> _persistAccounts(
    SharedPreferences prefs,
    List<StoredAccount> accounts,
  ) async {
    await prefs.setString(
      'savedAccounts',
      jsonEncode(accounts.map((a) => a.toJson()).toList()),
    );
  }

  Future<void> _restoreSession() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('authToken');
    final name = prefs.getString('userName') ?? '';
    final email = prefs.getString('userEmail') ?? '';
    final accounts = _decodeAccounts(prefs.getString('savedAccounts'));

    if (token != null &&
        token.isNotEmpty &&
        email.isNotEmpty &&
        !accounts.any((a) => a.email.toLowerCase() == email.toLowerCase())) {
      accounts.insert(
        0,
        StoredAccount(token: token, name: name, email: email),
      );
      await _persistAccounts(prefs, accounts);
    }

    if (mounted) {
      setState(() {
        _token = (token != null && token.isNotEmpty) ? token : null;
        _userName = name;
        _userEmail = email;
        _savedAccounts = accounts;
        _checking = false;
      });
    }
  }

  Future<void> _onAuthenticated({
    required String token,
    required String name,
    required String email,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('authToken', token);
    await prefs.setString('userName', name);
    await prefs.setString('userEmail', email);
    await prefs.setString('lastUserName', name);
    await prefs.setString('lastUserEmail', email);

    final accounts = _decodeAccounts(prefs.getString('savedAccounts'));
    final existingIdx = accounts.indexWhere(
      (a) => a.email.toLowerCase() == email.toLowerCase(),
    );
    final preservedAvatar =
        existingIdx != -1 ? accounts[existingIdx].avatarBase64 : null;
    if (existingIdx != -1) {
      accounts.removeAt(existingIdx);
    }
    accounts.insert(
      0,
      StoredAccount(
        token: token,
        name: name,
        email: email,
        avatarBase64: preservedAvatar,
      ),
    );
    await _persistAccounts(prefs, accounts);

    if (mounted) {
      setState(() {
        _token = token;
        _userName = name;
        _userEmail = email;
        _savedAccounts = accounts;
      });
    }
  }

  Future<void> _switchAccount(StoredAccount target) async {
    if (target.token.isEmpty) {
      await _addAnotherAccount();
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('authToken', target.token);
    await prefs.setString('userName', target.name);
    await prefs.setString('userEmail', target.email);
    await prefs.setString('lastUserName', target.name);
    await prefs.setString('lastUserEmail', target.email);

    if (mounted) {
      setState(() {
        _token = target.token;
        _userName = target.name;
        _userEmail = target.email;
      });
    }
  }

  Future<void> _updateCurrentProfile({
    required String newName,
    String? avatarBase64,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('userName', newName);
    await prefs.setString('lastUserName', newName);

    final accounts = _decodeAccounts(prefs.getString('savedAccounts'));
    final idx = accounts.indexWhere(
      (a) => a.email.toLowerCase() == _userEmail.toLowerCase(),
    );
    if (idx != -1) {
      accounts[idx] = accounts[idx].copyWith(
        name: newName,
        avatarBase64: avatarBase64 ?? accounts[idx].avatarBase64,
      );
      await _persistAccounts(prefs, accounts);
    }

    if (mounted) {
      setState(() {
        _userName = newName;
        _savedAccounts = accounts;
      });
    }
  }

  Future<void> _addAnotherAccount() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('authToken');
    await prefs.remove('userName');
    await prefs.remove('userEmail');

    if (mounted) {
      setState(() {
        _token = null;
        _userName = '';
        _userEmail = '';
      });
    }
  }

  Future<void> _logoutAllAccounts() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('authToken');
    await prefs.remove('userName');
    await prefs.remove('userEmail');
    await prefs.remove('lastUserName');
    await prefs.remove('lastUserEmail');
    await prefs.remove('savedAccounts');

    if (mounted) {
      setState(() {
        _token = null;
        _userName = '';
        _userEmail = '';
        _savedAccounts = [];
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_checking) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_token == null) {
      return LoginScreen(onSuccess: _onAuthenticated);
    }

    return SuperIAHome(
      key: ValueKey(_userEmail),
      authToken: _token!,
      userName: _userName,
      userEmail: _userEmail,
      savedAccounts: _savedAccounts,
      onSwitchAccount: _switchAccount,
      onAddAnotherAccount: _addAnotherAccount,
      onUpdateProfile: _updateCurrentProfile,
      onLogoutAll: _logoutAllAccounts,
    );
  }
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, required this.onSuccess});

  final Future<void> Function({
    required String token,
    required String name,
    required String email,
  }) onSuccess;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  static Future<void>? _sharedGoogleInit;
  static const String _credentialsKey = 'registeredCredentials';

  bool _showEmailForm = false;
  bool _isRegister = false;
  bool _submitting = false;
  bool _obscurePassword = true;
  bool _googleReady = false;

  String _lastAccountName = '';
  String _lastAccountEmail = '';

  StreamSubscription<GoogleSignInAuthenticationEvent>? _googleSub;

  final TextEditingController _nameCtrl = TextEditingController();
  final TextEditingController _emailCtrl = TextEditingController();
  final TextEditingController _passwordCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadLastAccount();
    _initGoogleSignIn();
  }

  Future<void> _saveRegisteredCredential({
    required String name,
    required String email,
    required String password,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_credentialsKey);
    Map<String, dynamic> map = {};
    if (raw != null && raw.isNotEmpty) {
      try {
        map = Map<String, dynamic>.from(jsonDecode(raw) as Map);
      } catch (_) {
        map = {};
      }
    }
    map[email.trim().toLowerCase()] = {
      'name': name.trim(),
      'password': password,
    };
    await prefs.setString(_credentialsKey, jsonEncode(map));
  }

  Future<Map<String, String>?> _getRegisteredCredential(String email) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_credentialsKey);
    if (raw == null || raw.isEmpty) return null;
    try {
      final map = Map<String, dynamic>.from(jsonDecode(raw) as Map);
      final entry = map[email.trim().toLowerCase()];
      if (entry is Map) {
        return {
          'name': entry['name']?.toString() ?? '',
          'password': entry['password']?.toString() ?? '',
        };
      }
    } catch (_) {}
    return null;
  }

  Future<void> _initGoogleSignIn() async {
    try {
      final signIn = GoogleSignIn.instance;
      _sharedGoogleInit ??= signIn.initialize();
      await _sharedGoogleInit;

      _googleSub = signIn.authenticationEvents.listen(
        (event) {
          if (event is GoogleSignInAuthenticationEventSignIn) {
            _handleGoogleAccount(event.user);
          }
        },
        onError: (err) {
          _showError('Error al seleccionar cuenta de Google: $err');
        },
      );

      if (mounted) {
        setState(() => _googleReady = true);
      }
    } catch (e) {
      final clean = e.toString().replaceFirst('Exception: ', '');
      if (clean.contains('ClientID not set') ||
          clean.contains('google-signin-client_id')) {
        _showError('Falta pegar tu Client ID de Google en web/index.html.');
      } else {
        _showError('No se pudo inicializar Google Sign-In: $clean');
      }
    }
  }

  Future<void> _handleGoogleAccount(GoogleSignInAccount account) async {
    if (_submitting) return;
    setState(() => _submitting = true);

    try {
      final email = account.email;
      final name = (account.displayName != null &&
              account.displayName!.trim().isNotEmpty)
          ? account.displayName!.trim()
          : email.split('@').first;

      final auth = account.authentication;
      final idToken = auth.idToken ?? '';
      if (idToken.isEmpty) {
        throw Exception('Google no entregó el idToken de autenticación.');
      }

      final result = await ApiService.googleQuickLogin(idToken: idToken);
      final token = result['token']?.toString() ?? '';
      final userMap = Map<String, dynamic>.from(
        (result['user'] as Map?) ?? const {},
      );

      if (token.isEmpty) {
        throw Exception('No se recibió token de sesión.');
      }

      await widget.onSuccess(
        token: token,
        name: userMap['name']?.toString() ?? name,
        email: userMap['email']?.toString() ?? email,
      );
    } catch (e) {
      final clean = e.toString().replaceFirst('Exception: ', '');
      _showError(
        clean.contains('TimeoutException')
            ? 'El servidor tardó demasiado en responder.'
            : clean,
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _loadLastAccount() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    final lastEmail = prefs.getString('lastUserEmail') ?? '';
    final lastName = prefs.getString('lastUserName') ?? '';
    setState(() {
      _lastAccountName = lastName;
      _lastAccountEmail = lastEmail;
      if (_emailCtrl.text.isEmpty && lastEmail.isNotEmpty) {
        _emailCtrl.text = lastEmail;
      }
    });
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            msg,
            style: const TextStyle(color: Colors.white),
          ),
        ),
      );
  }

  Future<void> _continueWithSavedAccount() async {
    if (_lastAccountEmail.isEmpty) return;
    final savedCred = await _getRegisteredCredential(_lastAccountEmail);
    if (savedCred == null || (savedCred['password'] ?? '').isEmpty) {
      setState(() {
        _showEmailForm = true;
        _isRegister = false;
        _emailCtrl.text = _lastAccountEmail;
      });
      _showError('Inicia sesión con tu contraseña o con Google para continuar.');
      return;
    }

    setState(() => _submitting = true);
    try {
      final result = await ApiService.login(
        email: _lastAccountEmail,
        password: savedCred['password']!,
      );
      final token = result['token']?.toString() ?? '';
      final userMap = Map<String, dynamic>.from(
        (result['user'] as Map?) ?? const {},
      );
      if (token.isEmpty) {
        throw Exception('No se recibió token de sesión.');
      }
      await widget.onSuccess(
        token: token,
        name: userMap['name']?.toString() ?? _lastAccountName,
        email: userMap['email']?.toString() ?? _lastAccountEmail,
      );
    } catch (e) {
      final clean = e.toString().replaceFirst('Exception: ', '');
      _showError(
        clean.contains('TimeoutException')
            ? 'El servidor tardó demasiado en responder.'
            : clean,
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _submit() async {
    final name = _nameCtrl.text.trim();
    final email = _emailCtrl.text.trim();
    final password = _passwordCtrl.text;

    if (_isRegister && name.length < 2) {
      _showError('Escribe tu nombre para crear tu cuenta.');
      return;
    }
    if (email.isEmpty || !email.contains('@')) {
      _showError('Escribe un correo electrónico válido.');
      return;
    }
    if (password.length < 6) {
      _showError('La contraseña debe tener al menos 6 caracteres.');
      return;
    }

    setState(() => _submitting = true);

    try {
      Map<String, dynamic> result;

      if (_isRegister) {
        await _saveRegisteredCredential(
          name: name,
          email: email,
          password: password,
        );
        result = await ApiService.register(
          name: name,
          email: email,
          password: password,
        );
      } else {
        final savedCred = await _getRegisteredCredential(email);
        try {
          result = await ApiService.login(
            email: email,
            password: password,
          );
          await _saveRegisteredCredential(
            name: (result['user'] is Map &&
                    (result['user']['name']?.toString().isNotEmpty ?? false))
                ? result['user']['name'].toString()
                : (savedCred?['name']?.isNotEmpty == true
                    ? savedCred!['name']!
                    : email.split('@').first),
            email: email,
            password: password,
          );
        } catch (_) {
          if (savedCred != null && savedCred['password'] == password) {
            final resolvedSavedName = savedCred['name']!.isNotEmpty
                ? savedCred['name']!
                : email.split('@').first;
            result = await ApiService.register(
              name: resolvedSavedName,
              email: email,
              password: password,
            );
          } else if (savedCred != null && savedCred['password'] != password) {
            throw Exception('La contraseña no coincide con la registrada.');
          } else {
            rethrow;
          }
        }
      }

      final token = result['token']?.toString() ?? '';
      final userMap = Map<String, dynamic>.from(
        (result['user'] as Map?) ?? const {},
      );
      final savedCredAfter = await _getRegisteredCredential(email);
      final resolvedName =
          (userMap['name']?.toString().trim().isNotEmpty == true)
              ? userMap['name'].toString().trim()
              : (name.isNotEmpty
                  ? name
                  : (savedCredAfter?['name']?.isNotEmpty == true
                      ? savedCredAfter!['name']!
                      : email.split('@').first));
      final resolvedEmail = userMap['email']?.toString() ?? email;

      if (token.isEmpty) {
        throw Exception('No se recibió token de sesión.');
      }

      await widget.onSuccess(
        token: token,
        name: resolvedName,
        email: resolvedEmail,
      );
    } catch (e) {
      final clean = e.toString().replaceFirst('Exception: ', '');
      if (clean.contains('TimeoutException')) {
        _showError(
          'El servidor tardó demasiado en responder. Revisa tu URL de Render.',
        );
      } else if (clean.contains('Failed to fetch') ||
          clean.contains('XMLHttpRequest')) {
        _showError(
          'No se pudo conectar con el servidor. Verifica la URL en api_service.dart.',
        );
      } else {
        _showError(clean);
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  String _initialsFrom(String name, String email) {
    final source = name.trim().isNotEmpty ? name.trim() : email.trim();
    if (source.isEmpty) return 'IA';
    final parts = source.split(RegExp(r'\s+'));
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return source.substring(0, source.length >= 2 ? 2 : 1).toUpperCase();
  }

  @override
  void dispose() {
    _googleSub?.cancel();
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: Image.asset(
              'assets/images/goku.jpg',
              fit: BoxFit.cover,
              alignment: const Alignment(0.45, -0.15),
            ),
          ),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [
                    bg.withOpacity(.95),
                    bg.withOpacity(.85),
                    bg.withOpacity(.65),
                  ],
                ),
              ),
            ),
          ),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: panel,
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: blue.withOpacity(.55)),
                      boxShadow: [
                        BoxShadow(
                          color: cyan.withOpacity(.14),
                          blurRadius: 24,
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.all_inclusive, size: 52, color: cyan),
                        const SizedBox(height: 8),
                        const Text(
                          'isaias titan',
                          style: TextStyle(
                            fontSize: 30,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _showEmailForm
                              ? (_isRegister
                                  ? 'Crea tu cuenta para entrar'
                                  : 'Inicia sesión con tu correo')
                              : 'Elige cómo quieres entrar',
                          style: const TextStyle(color: muted, fontSize: 13),
                        ),
                        const SizedBox(height: 24),
                        if (!_showEmailForm) ...[
                          if (_lastAccountEmail.isNotEmpty) ...[
                            SizedBox(
                              width: double.infinity,
                              height: 58,
                              child: ElevatedButton(
                                onPressed: _submitting
                                    ? null
                                    : _continueWithSavedAccount,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF0E1D3D),
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(30),
                                    side: BorderSide(
                                      color: cyan.withOpacity(.65),
                                    ),
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    CircleAvatar(
                                      radius: 18,
                                      backgroundColor: const Color(0xFF0A8F82),
                                      child: Text(
                                        _initialsFrom(
                                          _lastAccountName,
                                          _lastAccountEmail,
                                        ),
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 13,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          const Text(
                                            'Continuar con esta cuenta',
                                            style: TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 14,
                                            ),
                                          ),
                                          Text(
                                            _lastAccountEmail,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              color: muted,
                                              fontSize: 12,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 14),
                          ],
                          if (kIsWeb)
                            Center(
                              child: _googleReady
                                  ? web.renderButton(
                                      configuration:
                                          web.GSIButtonConfiguration(
                                        shape: web.GSIButtonShape.pill,
                                        size: web.GSIButtonSize.large,
                                        text: web.GSIButtonText.continueWith,
                                      ),
                                    )
                                  : const SizedBox(
                                      height: 44,
                                      child: Center(
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2.2,
                                        ),
                                      ),
                                    ),
                            ),
                          const SizedBox(height: 14),
                          SizedBox(
                            width: double.infinity,
                            height: 50,
                            child: OutlinedButton(
                              onPressed: _submitting
                                  ? null
                                  : () => setState(() {
                                        _showEmailForm = true;
                                        _isRegister = false;
                                      }),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.white,
                                side: BorderSide(color: blue.withOpacity(.7)),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(30),
                                ),
                              ),
                              child: const Text(
                                'Inicia sesión de otra forma',
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 15,
                                ),
                              ),
                            ),
                          ),
                        ] else ...[
                          if (_isRegister) ...[
                            TextField(
                              controller: _nameCtrl,
                              textInputAction: TextInputAction.next,
                              decoration: const InputDecoration(
                                labelText: 'Nombre',
                                prefixIcon:
                                    Icon(Icons.person_outline, color: cyan),
                              ),
                            ),
                            const SizedBox(height: 12),
                          ],
                          TextField(
                            controller: _emailCtrl,
                            keyboardType: TextInputType.emailAddress,
                            textInputAction: TextInputAction.next,
                            decoration: const InputDecoration(
                              labelText: 'Correo electrónico',
                              prefixIcon:
                                  Icon(Icons.email_outlined, color: cyan),
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _passwordCtrl,
                            obscureText: _obscurePassword,
                            textInputAction: TextInputAction.done,
                            onSubmitted: (_) => _submitting ? null : _submit(),
                            decoration: InputDecoration(
                              labelText: 'Contraseña',
                              prefixIcon:
                                  const Icon(Icons.lock_outline, color: cyan),
                              suffixIcon: IconButton(
                                onPressed: () => setState(
                                  () => _obscurePassword = !_obscurePassword,
                                ),
                                icon: Icon(
                                  _obscurePassword
                                      ? Icons.visibility_off
                                      : Icons.visibility,
                                  color: muted,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 20),
                          SizedBox(
                            width: double.infinity,
                            height: 46,
                            child: FilledButton(
                              onPressed: _submitting ? null : _submit,
                              style: FilledButton.styleFrom(
                                backgroundColor: blue,
                                foregroundColor: Colors.white,
                              ),
                              child: _submitting
                                  ? const SizedBox(
                                      width: 22,
                                      height: 22,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2.4,
                                        color: Colors.white,
                                      ),
                                    )
                                  : Text(
                                      _isRegister
                                          ? 'Crear cuenta y entrar'
                                          : 'Iniciar sesión',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 15,
                                      ),
                                    ),
                            ),
                          ),
                          const SizedBox(height: 10),
                          TextButton(
                            onPressed: _submitting
                                ? null
                                : () => setState(
                                    () => _isRegister = !_isRegister),
                            child: Text(
                              _isRegister
                                  ? '¿Ya tienes cuenta? Inicia sesión'
                                  : '¿No tienes cuenta? Regístrate aquí',
                              style: const TextStyle(color: cyan),
                            ),
                          ),
                          TextButton.icon(
                            onPressed: _submitting
                                ? null
                                : () => setState(() => _showEmailForm = false),
                            icon: const Icon(Icons.arrow_back,
                                size: 18, color: muted),
                            label: const Text(
                              'Volver a opciones de acceso',
                              style: TextStyle(color: muted),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class ChatItem {
  const ChatItem({
    required this.user,
    required this.text,
    required this.time,
    this.imageBase64,
    this.imageName,
    this.imagesBase64 = const [],
    this.imageNames = const [],
    this.documentNames = const [],
    this.generatedFile,
    this.isVoice = false,
    this.voiceDurationSeconds = 0,
    this.audioBase64,
  });

  final bool user;
  final String text;
  final DateTime time;
  final String? imageBase64;
  final String? imageName;
  final List<String> imagesBase64;
  final List<String> imageNames;
  final List<String> documentNames;
  final GeneratedDownloadFile? generatedFile;
  final bool isVoice;
  final int voiceDurationSeconds;
  final String? audioBase64;

  List<String> get allImagesBase64 {
    if (imagesBase64.isNotEmpty) return imagesBase64;
    if (imageBase64 != null && imageBase64!.isNotEmpty) return [imageBase64!];
    return const [];
  }

  List<String> get allImageNames {
    if (imageNames.isNotEmpty) return imageNames;
    if (imageName != null && imageName!.isNotEmpty) return [imageName!];
    return const [];
  }

  Map<String, dynamic> toJson() => {
        'user': user,
        'text': text,
        'time': time.toIso8601String(),
        'imageBase64': imageBase64,
        'imageName': imageName,
        'imagesBase64': imagesBase64,
        'imageNames': imageNames,
        'documentNames': documentNames,
        'generatedFile': generatedFile?.toJson(),
        'isVoice': isVoice,
        'voiceDurationSeconds': voiceDurationSeconds,
        'audioBase64': audioBase64,
      };

  factory ChatItem.fromJson(Map<String, dynamic> json) {
    final rawImgs = (json['imagesBase64'] as List?)
            ?.map((e) => e.toString())
            .where((e) => e.isNotEmpty)
            .toList() ??
        const <String>[];
    final rawNames = (json['imageNames'] as List?)
            ?.map((e) => e.toString())
            .where((e) => e.isNotEmpty)
            .toList() ??
        const <String>[];
    final rawDocs = (json['documentNames'] as List?)
            ?.map((e) => e.toString())
            .where((e) => e.isNotEmpty)
            .toList() ??
        const <String>[];

    GeneratedDownloadFile? parsedFile;
    if (json['generatedFile'] is Map) {
      parsedFile = GeneratedDownloadFile.fromJson(
        Map<String, dynamic>.from(json['generatedFile'] as Map),
      );
    }

    return ChatItem(
      user: json['user'] == true,
      text: json['text']?.toString() ?? '',
      time:
          DateTime.tryParse(json['time']?.toString() ?? '') ?? DateTime.now(),
      imageBase64: json['imageBase64']?.toString(),
      imageName: json['imageName']?.toString(),
      imagesBase64: rawImgs,
      imageNames: rawNames,
      documentNames: rawDocs,
      generatedFile: parsedFile,
      isVoice: json['isVoice'] == true,
      voiceDurationSeconds:
          (json['voiceDurationSeconds'] as num?)?.toInt() ?? 0,
      audioBase64: json['audioBase64']?.toString(),
    );
  }
}

class WhatsAppVoiceBubble extends StatefulWidget {
  const WhatsAppVoiceBubble({
    super.key,
    required this.durationSeconds,
    this.audioBase64,
  });

  final int durationSeconds;
  final String? audioBase64;

  @override
  State<WhatsAppVoiceBubble> createState() => _WhatsAppVoiceBubbleState();
}

class _WhatsAppVoiceBubbleState extends State<WhatsAppVoiceBubble> {
  final VoiceAudioPlayer _player = VoiceAudioPlayer();
  Timer? _playTimer;
  bool _playing = false;
  bool _started = false;
  int _elapsedSeconds = 0;

  int get _totalSeconds =>
      widget.durationSeconds <= 0 ? 1 : widget.durationSeconds;

  String _fmt(int sec) {
    final m = sec ~/ 60;
    final s = sec % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  void _onAudioFinished() {
    _playTimer?.cancel();
    if (!mounted) return;
    setState(() {
      _playing = false;
      _started = false;
      _elapsedSeconds = _totalSeconds;
    });
  }

  Future<void> _togglePlay() async {
    if (_playing) {
      _playTimer?.cancel();
      await _player.pause();
      if (mounted) setState(() => _playing = false);
      return;
    }

    final b64 = widget.audioBase64;
    if (b64 == null || b64.isEmpty) return;

    final restart = !_started || _elapsedSeconds >= _totalSeconds;
    setState(() {
      if (restart) {
        _elapsedSeconds = 0;
      }
      _playing = true;
      _started = true;
    });

    try {
      if (restart) {
        await _player.playBase64Wav(b64, onEnded: _onAudioFinished);
      } else {
        await _player.resume(onEnded: _onAudioFinished);
      }
    } catch (_) {
      _onAudioFinished();
      return;
    }

    _playTimer?.cancel();
    _playTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted || !_playing) {
        timer.cancel();
        return;
      }
      setState(() {
        if (_elapsedSeconds < _totalSeconds) {
          _elapsedSeconds++;
        }
      });
    });
  }

  @override
  void dispose() {
    _playTimer?.cancel();
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final progress = (_elapsedSeconds / _totalSeconds).clamp(0.0, 1.0);
    final hasAudio =
        widget.audioBase64 != null && widget.audioBase64!.isNotEmpty;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        InkWell(
          onTap: hasAudio ? _togglePlay : null,
          borderRadius: BorderRadius.circular(20),
          child: Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: hasAudio ? cyan : cyan.withOpacity(0.35),
              shape: BoxShape.circle,
            ),
            child: Icon(
              _playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
              color: const Color(0xFF040B1C),
              size: 22,
            ),
          ),
        ),
        const SizedBox(width: 10),
        SizedBox(
          width: 120,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 5,
                  backgroundColor: Colors.white24,
                  valueColor: const AlwaysStoppedAnimation<Color>(cyan),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _playing
                    ? '${_fmt(_elapsedSeconds)} / ${_fmt(_totalSeconds)}'
                    : _fmt(_totalSeconds),
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 6),
        const Icon(Icons.mic, color: cyan, size: 18),
      ],
    );
  }
}

class SavedConversation {
  SavedConversation({
    required this.id,
    required this.title,
    required this.updatedAt,
    required this.messages,
  });

  final String id;
  final String title;
  final DateTime updatedAt;
  final List<ChatItem> messages;

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'updatedAt': updatedAt.toIso8601String(),
        'messages': messages.map((m) => m.toJson()).toList(),
      };

  factory SavedConversation.fromJson(Map<String, dynamic> json) {
    final rawMsgs = (json['messages'] as List?) ?? const [];
    return SavedConversation(
      id: json['id']?.toString() ??
          DateTime.now().microsecondsSinceEpoch.toString(),
      title: json['title']?.toString() ?? 'Conversación',
      updatedAt: DateTime.tryParse(json['updatedAt']?.toString() ?? '') ??
          DateTime.now(),
      messages: rawMsgs
          .map(
            (item) => ChatItem.fromJson(Map<String, dynamic>.from(item as Map)),
          )
          .toList(),
    );
  }
}

class AssistantCommand {
  const AssistantCommand(
    this.icon,
    this.title,
    this.description,
    this.command,
  );

  final String icon;
  final String title;
  final String description;
  final String command;
}

class SuperIAHome extends StatefulWidget {
  const SuperIAHome({
    super.key,
    required this.authToken,
    required this.userName,
    required this.userEmail,
    required this.savedAccounts,
    required this.onSwitchAccount,
    required this.onAddAnotherAccount,
    required this.onUpdateProfile,
    required this.onLogoutAll,
  });

  final String authToken;
  final String userName;
  final String userEmail;
  final List<StoredAccount> savedAccounts;
  final Future<void> Function(StoredAccount account) onSwitchAccount;
  final Future<void> Function() onAddAnotherAccount;
  final Future<void> Function({
    required String newName,
    String? avatarBase64,
  }) onUpdateProfile;
  final Future<void> Function() onLogoutAll;

  @override
  State<SuperIAHome> createState() => _SuperIAHomeState();
}

class _SuperIAHomeState extends State<SuperIAHome> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  int _page = 0;
  bool _sidebarOpen = true;
  bool _searchingChats = false;
  String _searchQuery = '';
  String _assistantName = 'Son Goku';

  bool _speakReplies = false;
  bool _loading = false;
  bool _ready = false;
  bool _recording = false;
  int _recordingSeconds = 0;

  StreamSubscription? _currentRequestSubscription;

  List<SavedConversation> _conversations = [];
  String _activeConversationId = '';
  List<ChatItem> _messages = [];
  List<String> _memories = [];
  List<StoredSentImage> _sentImages = [];

  final List<PendingAttachment> _attachments = [];

  final TextEditingController _input = TextEditingController();
  final FocusNode _inputFocus = FocusNode();
  final TextEditingController _searchCtrl = TextEditingController();
  final TextEditingController _memoryInput = TextEditingController();
  final TextEditingController _nameInput = TextEditingController();
  final ScrollController _scroll = ScrollController();

  final AudioRecorder _recorder = AudioRecorder();
  final ImagePicker _picker = ImagePicker();
  final FlutterTts _tts = FlutterTts();

  StreamSubscription<Uint8List>? _recordingSubscription;
  final List<Uint8List> _recordedPcmChunks = [];
  Timer? _recordingTimer;

  JSFunction? _jsPasteCallback;

  String get _conversationsKey =>
      'conversations_${widget.userEmail.toLowerCase()}';
  String get _chatKey => 'chat_${widget.userEmail.toLowerCase()}';
  String get _memoryKey => 'memories_${widget.userEmail.toLowerCase()}';
  String get _sentImagesKey => 'sent_images_${widget.userEmail.toLowerCase()}';

  StoredAccount? get _currentStoredAccount {
    for (final acc in widget.savedAccounts) {
      if (acc.email.toLowerCase() == widget.userEmail.toLowerCase()) {
        return acc;
      }
    }
    return null;
  }

  String get _heroWelcomeTitle {
    final name = widget.userName.trim();
    if (name.isEmpty) return '¿En qué te ayudo hoy?';
    return '¿Qué tenemos en la agenda hoy, $name?';
  }

  static const List<AssistantCommand> _commands = [
    AssistantCommand('⏰', 'Hora y fecha', 'Muestra fecha y hora.', '/hora'),
    AssistantCommand(
      '🧠',
      'Guardar memoria',
      'Escribe una nota para guardarla.',
      '/recordar',
    ),
    AssistantCommand('📚', 'Ver memoria', 'Muestra tus notas.', '/memoria'),
    AssistantCommand(
      '🧹',
      'Limpiar chat',
      'Borra los mensajes del chat.',
      '/limpiar',
    ),
    AssistantCommand('💡', 'Ayuda', 'Muestra los comandos.', '/ayuda'),
  ];

  @override
  void initState() {
    super.initState();
    _loadLocal();
    if (kIsWeb) {
      _initWebPasteListener();
    }
  }

  String _withIdentityInstruction(String prompt) {
    final identityRule =
        '[Instrucción de identidad: Tu nombre es "$_assistantName". '
        'No te llames SuperIA ni Isaias Titan; si te preguntan cómo te llamas o cuál es tu nombre, responde claramente que te llamas "$_assistantName".]';
    if (prompt.trim().isEmpty) {
      return '$identityRule El usuario envió una nota de voz o un documento.';
    }
    return '$identityRule

$prompt';
  }

  void _initWebPasteListener() {
    try {
      void onPaste(JSAny? rawPayload) {
        if (!mounted || _loading || _recording || rawPayload == null) return;
        final payload = rawPayload as _PastePayload;
        final kind = payload.type;

        if (kind == 'image') {
          final b64 = payload.base64 ?? '';
          if (b64.isEmpty) return;
          try {
            final bytes = base64Decode(b64);
            final name = (payload.name != null && payload.name!.isNotEmpty)
                ? payload.name!
                : 'Captura_CtrlV.png';
            final mime =
                (payload.mimeType != null && payload.mimeType!.isNotEmpty)
                    ? payload.mimeType!
                    : 'image/png';
            _handlePastedImageBytes(
              bytes: bytes,
              name: name,
              mimeType: mime,
            );
          } catch (_) {
            _toast('No pude procesar la captura pegada.');
          }
        } else if (kind == 'text') {
          final text = payload.text ?? '';
          if (text.isNotEmpty) {
            _handlePastedText(text);
          }
        }
      }

      _jsPasteCallback = onPaste.toJS;
      _registerSuperiaPasteListener(_jsPasteCallback!);
    } catch (_) {
      try {
        globalContext.setProperty('superiaPasteCallback'.toJS, null);
      } catch (_) {}
    }
  }

  void _handlePastedImageBytes({
    required Uint8List bytes,
    required String name,
    required String mimeType,
  }) {
    if (!mounted || _loading || _recording) return;
    setState(() {
      _attachments.add(
        PendingAttachment(
          name: name,
          bytes: bytes,
          mimeType: mimeType,
          isImage: true,
        ),
      );
      _page = 0;
    });
    _toast('Captura pegada con Ctrl + V.');
  }

  void _handlePastedText(String pastedText) {
    if (!mounted || _loading || _recording || pastedText.isEmpty) return;
    final current = _input.text;
    final separator =
        (current.isNotEmpty && !current.endsWith(' ') && !current.endsWith('
'))
            ? ' '
            : '';
    final updated = '$current$separator$pastedText';
    setState(() {
      _page = 0;
      _input.value = TextEditingValue(
        text: updated,
        selection: TextSelection.collapsed(offset: updated.length),
      );
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _inputFocus.requestFocus();
    });
  }

  String _initialsFrom(String name, String email) {
    final source = name.trim().isNotEmpty ? name.trim() : email.trim();
    if (source.isEmpty) return 'IA';
    final parts = source.split(RegExp(r'\s+'));
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return source.substring(0, source.length >= 2 ? 2 : 1).toUpperCase();
  }

  Widget _buildUserAvatar({
    required String name,
    required String email,
    String? avatarBase64,
    double radius = 17,
    Color fallbackColor = const Color(0xFF0A8F82),
  }) {
    if (avatarBase64 != null && avatarBase64.isNotEmpty) {
      try {
        return CircleAvatar(
          radius: radius,
          backgroundImage: MemoryImage(base64Decode(avatarBase64)),
        );
      } catch (_) {}
    }

    return CircleAvatar(
      radius: radius,
      backgroundColor: fallbackColor,
      child: Text(
        _initialsFrom(name, email),
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
          fontSize: radius * 0.72,
        ),
      ),
    );
  }

  String _buildConversationTitle(List<ChatItem> msgs, String? fallbackText) {
    for (final m in msgs) {
      if (m.user && m.text.trim().isNotEmpty && !m.isVoice) {
        final clean = m.text.trim().replaceAll(RegExp(r'\s+'), ' ');
        return clean.length > 34 ? '${clean.substring(0, 34)}…' : clean;
      }
      if (m.user && m.documentNames.isNotEmpty) {
        return m.documentNames.first;
      }
    }
    if (fallbackText != null && fallbackText.trim().isNotEmpty) {
      final clean = fallbackText.trim().replaceAll(RegExp(r'\s+'), ' ');
      return clean.length > 34 ? '${clean.substring(0, 34)}…' : clean;
    }
    return 'Nueva conversación';
  }

  void _syncActiveConversationToList({String? hintTitle}) {
    if (_activeConversationId.isEmpty) {
      _activeConversationId =
          DateTime.now().microsecondsSinceEpoch.toString();
    }

    final existingIdx =
        _conversations.indexWhere((c) => c.id == _activeConversationId);

    if (_messages.isEmpty) {
      if (existingIdx != -1) {
        _conversations.removeAt(existingIdx);
      }
      return;
    }

    final existingTitle =
        existingIdx != -1 ? _conversations[existingIdx].title : null;
    final computedTitle =
        (existingTitle != null && existingTitle != 'Nueva conversación')
            ? existingTitle
            : _buildConversationTitle(_messages, hintTitle);

    final updated = SavedConversation(
      id: _activeConversationId,
      title: computedTitle,
      updatedAt: DateTime.now(),
      messages: List<ChatItem>.from(_messages),
    );

    if (existingIdx != -1) {
      _conversations[existingIdx] = updated;
    } else {
      _conversations.insert(0, updated);
    }

    _conversations.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  }

  Future<void> _loadLocal() async {
    final prefs = await SharedPreferences.getInstance();

    List<ChatItem> legacyMessages = [];
    try {
      final decodedLegacy =
          jsonDecode(prefs.getString(_chatKey) ?? '[]') as List;
      legacyMessages = decodedLegacy
          .map(
            (item) => ChatItem.fromJson(
              Map<String, dynamic>.from(item as Map),
            ),
          )
          .toList();
    } catch (_) {
      legacyMessages = [];
    }

    try {
      final decodedConv =
          jsonDecode(prefs.getString(_conversationsKey) ?? '[]') as List;
      _conversations = decodedConv
          .map(
            (item) => SavedConversation.fromJson(
              Map<String, dynamic>.from(item as Map),
            ),
          )
          .toList();
    } catch (_) {
      _conversations = [];
    }

    try {
      final decodedImgs =
          jsonDecode(prefs.getString(_sentImagesKey) ?? '[]') as List;
      _sentImages = decodedImgs
          .map(
            (item) => StoredSentImage.fromJson(
              Map<String, dynamic>.from(item as Map),
            ),
          )
          .where((img) => img.imageBase64.isNotEmpty)
          .toList();
    } catch (_) {
      _sentImages = [];
    }

    if (_conversations.isEmpty && legacyMessages.isNotEmpty) {
      final initialConv = SavedConversation(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        title: _buildConversationTitle(legacyMessages, null),
        updatedAt: DateTime.now(),
        messages: legacyMessages,
      );
      _conversations = [initialConv];
      _activeConversationId = initialConv.id;
      _messages = List<ChatItem>.from(initialConv.messages);
    } else if (_conversations.isNotEmpty) {
      _conversations.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      _activeConversationId = _conversations.first.id;
      _messages = List<ChatItem>.from(_conversations.first.messages);
    } else {
      _activeConversationId =
          DateTime.now().microsecondsSinceEpoch.toString();
      _messages = [];
    }

    _memories = prefs.getStringList(_memoryKey) ?? [];
    _assistantName = prefs.getString('assistantName') ?? 'Son Goku';
    _speakReplies = prefs.getBool('speakReplies') ?? false;
    _nameInput.text = _assistantName;

    if (mounted) setState(() => _ready = true);
  }

  Future<void> _save({String? hintTitle}) async {
    _syncActiveConversationToList(hintTitle: hintTitle);
    final prefs = await SharedPreferences.getInstance();

    await prefs.setString(
      _conversationsKey,
      jsonEncode(_conversations.map((c) => c.toJson()).toList()),
    );
    await prefs.setString(
      _chatKey,
      jsonEncode(_messages.map((item) => item.toJson()).toList()),
    );
    await prefs.setString(
      _sentImagesKey,
      jsonEncode(_sentImages.map((img) => img.toJson()).toList()),
    );
    await prefs.setStringList(_memoryKey, _memories);
    await prefs.setString('assistantName', _assistantName);
    await prefs.setBool('speakReplies', _speakReplies);
  }

  Future<void> _recordSentImages(
    List<PendingAttachment> imageItems,
    String caption,
  ) async {
    if (imageItems.isEmpty) return;
    final now = DateTime.now();
    final created = <StoredSentImage>[];
    for (int i = 0; i < imageItems.length; i++) {
      final item = imageItems[i];
      created.add(
        StoredSentImage(
          id: '${now.microsecondsSinceEpoch}_$i',
          name: item.name,
          mimeType: item.mimeType,
          imageBase64: base64Encode(item.bytes),
          sentAt: now,
          caption: caption,
        ),
      );
    }
    setState(() {
      _sentImages.insertAll(0, created);
      if (_sentImages.length > 80) {
        _sentImages.removeRange(80, _sentImages.length);
      }
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _sentImagesKey,
      jsonEncode(_sentImages.map((img) => img.toJson()).toList()),
    );
  }

  Future<void> _deleteSentImage(String id) async {
    setState(() {
      _sentImages.removeWhere((img) => img.id == id);
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _sentImagesKey,
      jsonEncode(_sentImages.map((img) => img.toJson()).toList()),
    );
    _toast('Imagen eliminada de la galería.');
  }

  void _attachStoredImageToChat(StoredSentImage stored) {
    try {
      final bytes = base64Decode(stored.imageBase64);
      setState(() {
        _attachments.add(
          PendingAttachment(
            name: stored.name,
            bytes: bytes,
            mimeType: stored.mimeType,
            isImage: true,
          ),
        );
        _page = 0;
      });
      _toast('Imagen añadida al chat.');
    } catch (_) {
      _toast('No pude cargar esta imagen.');
    }
  }

  void _openImagePreviewDialog(StoredSentImage stored) {
    showDialog(
      context: context,
      builder: (dialogCtx) => Dialog(
        backgroundColor: const Color(0xFF08132A),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: blue.withOpacity(0.55)),
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520, maxHeight: 620),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        stored.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(dialogCtx),
                      icon: const Icon(Icons.close, color: muted),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Flexible(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: Image.memory(
                      base64Decode(stored.imageBase64),
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
                if (stored.caption.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      stored.caption,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: muted, fontSize: 12.5),
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton.icon(
                      onPressed: () async {
                        Navigator.pop(dialogCtx);
                        await _deleteSentImage(stored.id);
                      },
                      icon: const Icon(
                        Icons.delete_outline,
                        color: Colors.redAccent,
                        size: 18,
                      ),
                      label: const Text(
                        'Eliminar',
                        style: TextStyle(color: Colors.redAccent),
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton.icon(
                      onPressed: () {
                        Navigator.pop(dialogCtx);
                        _attachStoredImageToChat(stored);
                      },
                      icon: const Icon(Icons.send_rounded, size: 17),
                      label: const Text('Enviar al chat'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _downloadGeneratedFile(GeneratedDownloadFile file) {
    if (file.base64Data.isEmpty) {
      _toast('El archivo generado no contiene datos descargables.');
      return;
    }

    if (kIsWeb) {
      try {
        final bytes = base64Decode(file.base64Data);
        final jsBytes = bytes.toJS;
        final parts = <JSAny>[jsBytes].toJS;
        final blob = html_web.Blob(
          parts,
          html_web.BlobPropertyBag(type: file.mimeType),
        );
        final url = html_web.URL.createObjectURL(blob);
        final anchor =
            html_web.document.createElement('a') as html_web.HTMLAnchorElement
              ..href = url
              ..download = file.filename
              ..style.display = 'none';
        html_web.document.body?.append(anchor);
        anchor.click();
        anchor.remove();
        html_web.URL.revokeObjectURL(url);
        _toast('Descargando ${file.filename}...');
      } catch (e) {
        _toast('No pude descargar ${file.filename}: $e');
      }
    } else {
      _toast('Descarga disponible en navegador Web (${file.filename}).');
    }
  }

  Future<void> _startNewConversation() async {
    if (_messages.isNotEmpty) {
      await _save();
    }
    setState(() {
      _activeConversationId =
          DateTime.now().microsecondsSinceEpoch.toString();
      _messages = [];
      _attachments.clear();
      _page = 0;
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_chatKey, '[]');
  }

  Future<void> _openConversation(SavedConversation conv) async {
    if (_messages.isNotEmpty && _activeConversationId != conv.id) {
      await _save();
    }
    setState(() {
      _activeConversationId = conv.id;
      _messages = List<ChatItem>.from(conv.messages);
      _page = 0;
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _chatKey,
      jsonEncode(_messages.map((item) => item.toJson()).toList()),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      }
    });
  }

  Future<void> _deleteConversation(String id) async {
    setState(() {
      _conversations.removeWhere((c) => c.id == id);
      if (_activeConversationId == id) {
        if (_conversations.isNotEmpty) {
          _activeConversationId = _conversations.first.id;
          _messages = List<ChatItem>.from(_conversations.first.messages);
        } else {
          _activeConversationId =
              DateTime.now().microsecondsSinceEpoch.toString();
          _messages = [];
        }
      }
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _conversationsKey,
      jsonEncode(_conversations.map((c) => c.toJson()).toList()),
    );
    await prefs.setString(
      _chatKey,
      jsonEncode(_messages.map((item) => item.toJson()).toList()),
    );
    _toast('Conversación eliminada.');
  }

  void _toast(String text) {
    if (!mounted) return;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            text,
            style: const TextStyle(color: Colors.white),
          ),
          duration: const Duration(seconds: 3),
        ),
      );
  }

  Future<void> _copyMessageText(String text) async {
    if (text.trim().isEmpty) return;
    await Clipboard.setData(ClipboardData(text: text));
    _toast('Texto copiado al portapapeles.');
  }

  void _setPage(int page) {
    setState(() => _page = page);
  }

  Future<void> _openEditProfileDialog() async {
    final nameCtrl = TextEditingController(
      text: widget.userName.isNotEmpty
          ? widget.userName
          : widget.userEmail.split('@').first,
    );
    String? newAvatarB64 = _currentStoredAccount?.avatarBase64;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          return AlertDialog(
            backgroundColor: const Color(0xFF0A1733),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: BorderSide(color: blue.withOpacity(0.5)),
            ),
            title: const Text('Editar perfil'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                GestureDetector(
                  onTap: () async {
                    try {
                      final file = await _picker.pickImage(
                        source: ImageSource.gallery,
                        imageQuality: 75,
                        maxWidth: 400,
                      );
                      if (file != null) {
                        final bytes = await file.readAsBytes();
                        setDialogState(() {
                          newAvatarB64 = base64Encode(bytes);
                        });
                      }
                    } catch (_) {}
                  },
                  child: Stack(
                    children: [
                      _buildUserAvatar(
                        name: nameCtrl.text,
                        email: widget.userEmail,
                        avatarBase64: newAvatarB64,
                        radius: 36,
                      ),
                      Positioned(
                        right: 0,
                        bottom: 0,
                        child: Container(
                          padding: const EdgeInsets.all(5),
                          decoration: const BoxDecoration(
                            color: blue,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.camera_alt,
                            size: 14,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Nombre del perfil',
                    prefixIcon: Icon(Icons.person_outline, color: cyan),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogCtx, false),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogCtx, true),
                child: const Text('Guardar'),
              ),
            ],
          );
        },
      ),
    );

    if (confirmed == true && nameCtrl.text.trim().isNotEmpty) {
      await widget.onUpdateProfile(
        newName: nameCtrl.text.trim(),
        avatarBase64: newAvatarB64,
      );
      _toast('Perfil actualizado.');
    }
    nameCtrl.dispose();
  }

  void _openProfileSwitcherModal() {
    final activeName = widget.userName.isNotEmpty
        ? widget.userName
        : widget.userEmail.split('@').first;
    final currentAvatar = _currentStoredAccount?.avatarBase64;
    final otherAccounts = widget.savedAccounts
        .where((a) => a.email.toLowerCase() != widget.userEmail.toLowerCase())
        .toList();

    showDialog(
      context: context,
      barrierColor: Colors.black54,
      builder: (dialogCtx) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.all(16),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFF0A1630),
                borderRadius: BorderRadius.circular(26),
                border: Border.all(color: blue.withOpacity(0.55)),
                boxShadow: [
                  BoxShadow(
                    color: cyan.withOpacity(0.18),
                    blurRadius: 28,
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      IconButton(
                        tooltip: 'Cerrar',
                        onPressed: () => Navigator.pop(dialogCtx),
                        icon: const Icon(Icons.close, color: muted),
                        visualDensity: VisualDensity.compact,
                      ),
                    ],
                  ),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0F2147),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: cyan.withOpacity(0.35)),
                    ),
                    child: Row(
                      children: [
                        GestureDetector(
                          onTap: () {
                            Navigator.pop(dialogCtx);
                            _openEditProfileDialog();
                          },
                          child: Stack(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(2.5),
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(color: cyan, width: 2),
                                ),
                                child: _buildUserAvatar(
                                  name: activeName,
                                  email: widget.userEmail,
                                  avatarBase64: currentAvatar,
                                  radius: 26,
                                ),
                              ),
                              Positioned(
                                right: 0,
                                bottom: 0,
                                child: Container(
                                  padding: const EdgeInsets.all(4),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF08132A),
                                    shape: BoxShape.circle,
                                    border: Border.all(color: cyan, width: 1),
                                  ),
                                  child: const Icon(
                                    Icons.edit,
                                    size: 11,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                activeName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                widget.userEmail,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: muted,
                                  fontSize: 12,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: cyan.withOpacity(0.16),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: cyan.withOpacity(0.55),
                                  ),
                                ),
                                child: const Text(
                                  'Activo',
                                  style: TextStyle(
                                    color: cyan,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (otherAccounts.isNotEmpty) ...[
                    for (int i = 0; i < otherAccounts.length; i++)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Material(
                          color: const Color(0xFF0E1D3D),
                          borderRadius: BorderRadius.circular(16),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(16),
                            onTap: () async {
                              Navigator.pop(dialogCtx);
                              await widget.onSwitchAccount(otherAccounts[i]);
                            },
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 11,
                              ),
                              child: Row(
                                children: [
                                  _buildUserAvatar(
                                    name: otherAccounts[i].name,
                                    email: otherAccounts[i].email,
                                    avatarBase64: otherAccounts[i].avatarBase64,
                                    radius: 18,
                                    fallbackColor: i.isEven
                                        ? const Color(0xFFD95B16)
                                        : const Color(0xFF2563EB),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          otherAccounts[i].name.isNotEmpty
                                              ? otherAccounts[i].name
                                              : otherAccounts[i]
                                                  .email
                                                  .split('@')
                                                  .first,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w600,
                                            fontSize: 14,
                                          ),
                                        ),
                                        Text(
                                          otherAccounts[i].email,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            color: muted,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                  Material(
                    color: const Color(0xFF0E1D3D),
                    borderRadius: BorderRadius.circular(16),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: () async {
                        Navigator.pop(dialogCtx);
                        await widget.onAddAnotherAccount();
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 13,
                        ),
                        child: Row(
                          children: [
                            CircleAvatar(
                              radius: 16,
                              backgroundColor: blue.withOpacity(0.25),
                              child: const Icon(
                                Icons.add,
                                color: cyan,
                                size: 20,
                              ),
                            ),
                            const SizedBox(width: 12),
                            const Text(
                              'Añadir otra cuenta',
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Material(
                    color: const Color(0xFF0E1D3D),
                    borderRadius: BorderRadius.circular(16),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: () async {
                        Navigator.pop(dialogCtx);
                        await widget.onLogoutAll();
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 13,
                        ),
                        child: Row(
                          children: [
                            CircleAvatar(
                              radius: 16,
                              backgroundColor:
                                  Colors.redAccent.withOpacity(0.18),
                              child: const Icon(
                                Icons.logout,
                                color: Colors.redAccent,
                                size: 18,
                              ),
                            ),
                            const SizedBox(width: 12),
                            const Text(
                              'Cerrar sesión en todas las cuentas',
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () {
                        Navigator.pop(dialogCtx);
                        _openEditProfileDialog();
                      },
                      icon: const Icon(
                        Icons.manage_accounts_outlined,
                        color: cyan,
                        size: 19,
                      ),
                      label: const Text(
                        'Gestionar tu perfil de isaias titan',
                        style: TextStyle(color: Colors.white),
                      ),
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: blue.withOpacity(0.55)),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(24),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _addMessage(
    bool isUser,
    String text, {
    String? imageBase64,
    String? imageName,
    List<String> imagesBase64 = const [],
    List<String> imageNames = const [],
    List<String> documentNames = const [],
    GeneratedDownloadFile? generatedFile,
    bool isVoice = false,
    int voiceDurationSeconds = 0,
    String? audioBase64,
    String? hintTitle,
  }) async {
    setState(() {
      _messages.add(
        ChatItem(
          user: isUser,
          text: text,
          time: DateTime.now(),
          imageBase64: imageBase64,
          imageName: imageName,
          imagesBase64: imagesBase64,
          imageNames: imageNames,
          documentNames: documentNames,
          generatedFile: generatedFile,
          isVoice: isVoice,
          voiceDurationSeconds: voiceDurationSeconds,
          audioBase64: audioBase64,
        ),
      );
    });

    await _save(hintTitle: hintTitle);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  List<dynamic> _conversationHistory() {
    final previous =
        _messages.where((item) => item.text.trim().isNotEmpty).toList();

    final recent = previous.length > 14
        ? previous.sublist(previous.length - 14)
        : previous;

    return recent
        .map(
          (item) => <String, String>{
            'role': item.user ? 'user' : 'model',
            'text': item.text,
          },
        )
        .toList();
  }

  Future<String?> _runCommand(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return null;

    final parts = trimmed.split(RegExp(r'\s+'));
    final command = parts.first.toLowerCase();
    final argument = parts.length > 1 ? parts.skip(1).join(' ') : '';

    switch (command) {
      case '/hora':
        final now = DateTime.now();
        final time = TimeOfDay.fromDateTime(now).format(context);
        final date = MaterialLocalizations.of(context).formatMediumDate(now);
        return 'Ahora son las $time del $date.';

      case '/recordar':
        if (argument.isEmpty) {
          return 'Escribe qué quieres recordar. Ejemplo: /recordar Me gusta el café.';
        }
        setState(() => _memories.add(argument));
        await _save();
        return 'Listo, guardé en este dispositivo: “$argument”.';

      case '/memoria':
        if (_memories.isEmpty) return 'Aún no hay notas guardadas.';
        return 'Esto es lo que recuerdo:
• ${_memories.join('
• ')}';

      case '/limpiar':
        setState(() {
          _messages.clear();
        });
        await _save();
        return 'Chat limpio. Tus notas y conversaciones guardadas siguen disponibles.';

      case '/ayuda':
        return 'Comandos: /hora, /recordar [nota], /memoria, /limpiar y /ayuda.';

      default:
        return null;
    }
  }

  void _handleSendOrStop() {
    if (_loading) {
      _currentRequestSubscription?.cancel();
      setState(() {
        _loading = false;
        _currentRequestSubscription = null;
      });
      _toast('Investigación o proceso detenido.');
      return;
    }

    if (_recording) return;
    _sendText();
  }

  Future<void> _sendText() async {
    final text = _input.text.trim();
    if (text.isEmpty && _attachments.isEmpty) return;
    if (_loading) return;

    final history = _conversationHistory();
    final batch = List<PendingAttachment>.from(_attachments);
    final imageItems = batch.where((a) => a.isImage).toList();
    final docItems = batch.where((a) => !a.isImage).toList();

    final imagesB64 =
        imageItems.map((img) => base64Encode(img.bytes)).toList();
    final docNames = docItems.map((d) => d.name).toList();

    final documentsPayload = docItems
        .map(
          (doc) => <String, String>{
            'name': doc.name,
            'mime_type': doc.mimeType,
            'base64': base64Encode(doc.bytes),
          },
        )
        .toList();

    final buffer = StringBuffer();
    if (imageItems.isNotEmpty) {
      if (text.isNotEmpty) {
        buffer.writeln(
          '$text

Describe detalladamente lo que aparece en ${imageItems.length > 1 ? 'estas imágenes' : 'esta imagen'} y responde a mi mensaje.',
        );
      } else {
        buffer.writeln(
          'Describe y analiza detalladamente ${imageItems.length > 1 ? 'estas imágenes' : 'esta imagen'}.',
        );
      }
    } else if (text.isNotEmpty) {
      buffer.writeln(text);
    } else {
      buffer.writeln(
        'Analiza, investiga y resuelve el contenido de estos documentos con datos reales.',
      );
    }

    final promptForBackend = _withIdentityInstruction(buffer.toString().trim());

    _input.clear();
    setState(() {
      _attachments.clear();
      _loading = true;
    });

    if (imageItems.isNotEmpty) {
      await _recordSentImages(imageItems, text);
    }

    try {
      await _addMessage(
        true,
        text,
        imageBase64: imagesB64.isNotEmpty ? imagesB64.first : null,
        imagesBase64: imagesB64,
        documentNames: docNames,
        hintTitle: text.isNotEmpty
            ? text
            : (batch.isNotEmpty ? batch.first.name : null),
      );

      final commandReply = batch.isEmpty ? await _runCommand(text) : null;
      final String reply;
      GeneratedDownloadFile? downloadedFile;

      if (commandReply != null) {
        reply = commandReply;
      } else {
        final completer = Completer<Map<String, dynamic>>();

        _currentRequestSubscription = Stream.fromFuture(
          ApiService.sendMessage(
            authToken: widget.authToken,
            message: promptForBackend,
            memories: _memories,
            history: history,
            image: imageItems.isNotEmpty ? imageItems.first.bytes : null,
            imageMimeType:
                imageItems.isNotEmpty ? imageItems.first.mimeType : null,
            documents: documentsPayload,
          ),
        ).listen((res) {
          if (!completer.isCompleted) completer.complete(res);
        }, onError: (err) {
          if (!completer.isCompleted) completer.completeError(err);
        });

        final responseMap = await completer.future;
        reply = responseMap['reply']?.toString() ?? '';
        final rawFile = responseMap['generated_file'];
        if (rawFile is Map<String, dynamic>) {
          downloadedFile = GeneratedDownloadFile.fromJson(rawFile);
        } else if (rawFile is Map) {
          downloadedFile = GeneratedDownloadFile.fromJson(
            Map<String, dynamic>.from(rawFile),
          );
        }
      }

      if (mounted) {
        await _addMessage(
          false,
          reply,
          generatedFile: downloadedFile,
        );
        if (_speakReplies) await _speak(reply);
      }
    } catch (error) {
      if (mounted) {
        await _addMessage(
          false,
          'Error: ${_friendlyError(error)}',
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
          _currentRequestSubscription = null;
        });
      }
    }
  }

  String _friendlyError(Object error) {
    final text = error.toString().replaceFirst('Exception: ', '');
    if (text.contains('Failed to fetch') || text.contains('XMLHttpRequest')) {
      return 'Falló la conexión con Render. Revisa el backend.';
    }
    return text;
  }

  String _mimeFromFilename(String filename) {
    final lower = filename.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    if (lower.endsWith('.gif')) return 'image/gif';
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'image/jpeg';
    if (lower.endsWith('.pdf')) return 'application/pdf';
    if (lower.endsWith('.docx')) {
      return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
    }
    if (lower.endsWith('.xlsx') || lower.endsWith('.xlsm')) {
      return 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
    }
    if (lower.endsWith('.pptx')) {
      return 'application/vnd.openxmlformats-officedocument.presentationml.presentation';
    }
    if (lower.endsWith('.txt')) return 'text/plain';
    if (lower.endsWith('.csv')) return 'text/csv';
    if (lower.endsWith('.json')) return 'application/json';
    if (lower.endsWith('.md')) return 'text/markdown';
    return 'application/octet-stream';
  }

  bool _isImageFilename(String filename) {
    final lower = filename.toLowerCase();
    return lower.endsWith('.png') ||
        lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg') ||
        lower.endsWith('.webp') ||
        lower.endsWith('.gif');
  }

  String? _tryExtractReadableText(Uint8List bytes, String filename) {
    final lower = filename.toLowerCase();
    final isTextLike = lower.endsWith('.txt') ||
        lower.endsWith('.md') ||
        lower.endsWith('.csv') ||
        lower.endsWith('.json') ||
        lower.endsWith('.xml') ||
        lower.endsWith('.html') ||
        lower.endsWith('.dart') ||
        lower.endsWith('.py') ||
        lower.endsWith('.js');
    if (isTextLike) {
      try {
        return utf8.decode(bytes, allowMalformed: true);
      } catch (_) {}
    }

    if (lower.endsWith('.pdf')) {
      try {
        final raw = latin1.decode(bytes);
        final matches = RegExp(r'\(([^\(\)\]{2,200})\)').allMatches(raw);
        final extracted = matches
            .map((m) => m.group(1) ?? '')
            .where((s) => RegExp(r'[A-Za-zÁÉÍÓÚáéíóúÑñ0-9]').hasMatch(s))
            .join(' ');
        if (extracted.trim().isNotEmpty) {
          return extracted.trim();
        }
      } catch (_) {}
    }
    return null;
  }

  Future<void> _pickMultiplePhotos() async {
    try {
      final files = await _picker.pickMultiImage(
        imageQuality: 85,
        maxWidth: 1920,
      );
      if (files.isEmpty) return;

      final added = <PendingAttachment>[];
      for (final file in files) {
        final bytes = await file.readAsBytes();
        final name = file.name.isNotEmpty ? file.name : 'Foto.jpg';
        added.add(
          PendingAttachment(
            name: name,
            bytes: bytes,
            mimeType: _mimeFromFilename(name),
            isImage: true,
          ),
        );
      }

      if (!mounted) return;
      setState(() {
        _attachments.addAll(added);
        _page = 0;
      });
    } catch (_) {
      _toast('No pude abrir fotos. Revisa los permisos.');
    }
  }

  Future<void> _pickFromCamera() async {
    try {
      final file = await _picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 85,
        maxWidth: 1920,
      );
      if (file == null) return;

      final bytes = await file.readAsBytes();
      final name = file.name.isNotEmpty ? file.name : 'Captura_camara.jpg';

      if (!mounted) return;
      setState(() {
        _attachments.add(
          PendingAttachment(
            name: name,
            bytes: bytes,
            mimeType: _mimeFromFilename(name),
            isImage: true,
          ),
        );
        _page = 0;
      });
    } catch (_) {
      _toast(
        'No pude abrir la cámara. Revisa los permisos del navegador o dispositivo.',
      );
    }
  }

  Future<void> _pickFiles() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        withData: true,
        type: FileType.custom,
        allowedExtensions: const [
          'pdf',
          'docx',
          'xlsx',
          'xlsm',
          'pptx',
          'txt',
          'md',
          'csv',
          'tsv',
          'json',
          'xml',
          'html',
          'htm',
          'dart',
          'py',
          'js',
          'ts',
          'png',
          'jpg',
          'jpeg',
          'webp',
        ],
      );
      if (result == null || result.files.isEmpty) return;

      final added = <PendingAttachment>[];
      for (final file in result.files) {
        final bytes = file.bytes;
        if (bytes == null || bytes.isEmpty) continue;
        final name = file.name.isNotEmpty ? file.name : 'Documento';
        final isImg = _isImageFilename(name);
        added.add(
          PendingAttachment(
            name: name,
            bytes: bytes,
            mimeType: _mimeFromFilename(name),
            isImage: isImg,
            extractedText:
                isImg ? null : _tryExtractReadableText(bytes, name),
          ),
        );
      }

      if (added.isEmpty) {
        _toast('No pude leer los bytes del archivo seleccionado.');
        return;
      }

      if (!mounted) return;
      setState(() {
        _attachments.addAll(added);
        _page = 0;
      });
    } catch (_) {
      _toast('No pude abrir el selector de documentos y archivos.');
    }
  }

  void _openAttachMenu() {
    if (_loading || _recording) return;

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF08132A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.upload_file_outlined, color: cyan),
                title: const Text('Subir documentos y archivos'),
                subtitle: const Text(
                  'PDF, Word (.docx), Excel (.xlsx), PowerPoint (.pptx), TXT, CSV y más',
                  style: TextStyle(color: muted, fontSize: 12),
                ),
                onTap: () {
                  Navigator.pop(sheetCtx);
                  _pickFiles();
                },
              ),
              ListTile(
                leading: const Icon(Icons.photo_library_outlined, color: cyan),
                title: const Text('Fotos'),
                subtitle: const Text(
                  'Selecciona una o varias fotos o capturas',
                  style: TextStyle(color: muted, fontSize: 12),
                ),
                onTap: () {
                  Navigator.pop(sheetCtx);
                  _pickMultiplePhotos();
                },
              ),
              ListTile(
                leading: const Icon(Icons.camera_alt_outlined, color: cyan),
                title: const Text('Cámara'),
                subtitle: const Text(
                  'Toma una foto de un examen, texto o documento',
                  style: TextStyle(color: muted, fontSize: 12),
                ),
                onTap: () {
                  Navigator.pop(sheetCtx);
                  _pickFromCamera();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _toggleRecording() async {
    if (_recording) {
      await _stopRecordingAndSend();
      return;
    }

    if (_loading) return;

    try {
      final allowed = await _recorder.hasPermission();

      if (!allowed) {
        _toast('Permite el uso del micrófono para grabar una nota de voz.');
        return;
      }

      _recordedPcmChunks.clear();

      final stream = await _recorder.startStream(
        const RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: 16000,
          numChannels: 1,
        ),
      );

      _recordingSubscription = stream.listen(
        (chunk) => _recordedPcmChunks.add(chunk),
        onError: (_) => _toast('Hubo un problema grabando el audio.'),
      );

      setState(() {
        _recording = true;
        _recordingSeconds = 0;
      });

      _recordingTimer = Timer.periodic(
        const Duration(seconds: 1),
        (timer) {
          if (!mounted || !_recording) {
            timer.cancel();
            return;
          }

          setState(() => _recordingSeconds++);

          if (_recordingSeconds >= 60) {
            _stopRecordingAndSend();
          }
        },
      );
    } catch (error) {
      _toast('No pude iniciar la grabación: ${_friendlyError(error)}');
    }
  }

  Future<void> _stopRecordingAndSend() async {
    if (!_recording) return;

    final seconds = _recordingSeconds;

    setState(() => _recording = false);
    _recordingTimer?.cancel();
    _recordingTimer = null;

    try {
      await _recorder.stop();
      await _recordingSubscription?.cancel();
      _recordingSubscription = null;

      final pcm = _joinChunks(_recordedPcmChunks);
      _recordedPcmChunks.clear();

      if (pcm.isEmpty) {
        _toast('No se grabó audio.');
        return;
      }

      await _sendVoice(_makeWav(pcm), seconds < 1 ? 1 : seconds);
    } catch (error) {
      _toast('No pude preparar la nota de voz: ${_friendlyError(error)}');
    }
  }

  Uint8List _joinChunks(List<Uint8List> chunks) {
    final length = chunks.fold<int>(
      0,
      (sum, chunk) => sum + chunk.length,
    );

    final result = Uint8List(length);
    var offset = 0;

    for (final chunk in chunks) {
      result.setRange(offset, offset + chunk.length, chunk);
      offset += chunk.length;
    }

    return result;
  }

  Uint8List _makeWav(Uint8List pcm) {
    const sampleRate = 16000;
    const channels = 1;
    const bitsPerSample = 16;

    final wav = Uint8List(44 + pcm.length);
    final data = ByteData.sublistView(wav);

    void writeText(int offset, String text) {
      for (var i = 0; i < text.length; i++) {
        wav[offset + i] = text.codeUnitAt(i);
      }
    }

    writeText(0, 'RIFF');
    data.setUint32(4, 36 + pcm.length, Endian.little);
    writeText(8, 'WAVE');
    writeText(12, 'fmt ');
    data.setUint32(16, 16, Endian.little);
    data.setUint16(20, 1, Endian.little);
    data.setUint16(22, channels, Endian.little);
    data.setUint32(24, sampleRate, Endian.little);
    data.setUint32(
      28,
      sampleRate * channels * bitsPerSample ~/ 8,
      Endian.little,
    );
    data.setUint16(32, channels * bitsPerSample ~/ 8, Endian.little);
    data.setUint16(34, bitsPerSample, Endian.little);
    writeText(36, 'data');
    data.setUint32(40, pcm.length, Endian.little);
    wav.setRange(44, wav.length, pcm);

    return wav;
  }

  Future<void> _sendVoice(Uint8List wav, int seconds) async {
    if (_loading) return;

    final history = _conversationHistory();
    final wavB64 = base64Encode(wav);
    setState(() => _loading = true);

    try {
      await _addMessage(
        true,
        'Nota de voz · ${_formatDuration(seconds)}',
        isVoice: true,
        voiceDurationSeconds: seconds,
        audioBase64: wavB64,
      );

      final completer = Completer<Map<String, dynamic>>();
      _currentRequestSubscription = Stream.fromFuture(
        ApiService.sendMessage(
          authToken: widget.authToken,
          message: _withIdentityInstruction(''),
          memories: _memories,
          history: history,
          audioWav: wav,
        ),
      ).listen(
        (res) {
          if (!completer.isCompleted) completer.complete(res);
        },
        onError: (err) {
          if (!completer.isCompleted) completer.completeError(err);
        },
      );

      final responseMap = await Future.any<Map<String, dynamic>>([
        completer.future,
        Future<Map<String, dynamic>>.delayed(
          const Duration(seconds: 120),
          () => throw TimeoutException(
            'El servidor tardó más de 120 segundos en responder al audio.',
          ),
        ),
      ]);

      final reply = responseMap['reply']?.toString() ?? '';

      if (!mounted) return;

      await _addMessage(false, reply);
      if (_speakReplies) await _speak(reply);
    } catch (error) {
      if (mounted) {
        await _addMessage(
          false,
          'No pude enviar la nota de voz: ${_friendlyError(error)}',
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
          _currentRequestSubscription = null;
        });
      }
    }
  }

  String _formatDuration(int seconds) {
    final minutes = seconds ~/ 60;
    final remainder = seconds % 60;

    return '${minutes.toString().padLeft(2, '0')}:'
        '${remainder.toString().padLeft(2, '0')}';
  }

  Future<void> _speak(String text) async {
    try {
      await _tts.setLanguage('es-ES');
      await _tts.speak(text);
    } catch (_) {
      _toast('La voz no está disponible en este dispositivo.');
    }
  }

  Future<void> _saveMemory() async {
    final value = _memoryInput.text.trim();
    if (value.isEmpty) return;

    setState(() => _memories.add(value));
    _memoryInput.clear();

    await _save();
    _toast('Nota guardada.');
  }

  Future<void> _saveSettings() async {
    setState(() {
      _assistantName = _nameInput.text.trim().isEmpty
          ? 'Son Goku'
          : _nameInput.text.trim();
    });

    await _save();
    _toast('Ajustes guardados.');
  }

  Future<void> _eraseAll() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Borrar datos locales'),
        content: const Text(
          'Se borrarán tus conversaciones recientes, imágenes guardadas y memorias en este dispositivo.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Borrar'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_chatKey);
    await prefs.remove(_conversationsKey);
    await prefs.remove(_memoryKey);
    await prefs.remove(_sentImagesKey);

    setState(() {
      _messages.clear();
      _conversations.clear();
      _memories.clear();
      _sentImages.clear();
      _activeConversationId =
          DateTime.now().microsecondsSinceEpoch.toString();
    });

    _toast('Datos borrados.');
  }

  @override
  void dispose() {
    if (kIsWeb) {
      try {
        globalContext.setProperty('superiaPasteCallback'.toJS, null);
      } catch (_) {}
    }
    _jsPasteCallback = null;
    _recordingTimer?.cancel();
    _recordingSubscription?.cancel();
    _currentRequestSubscription?.cancel();
    _recorder.dispose();
    _tts.stop();
    _input.dispose();
    _inputFocus.dispose();
    _searchCtrl.dispose();
    _memoryInput.dispose();
    _nameInput.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 760;

        return Scaffold(
          key: _scaffoldKey,
          drawer: wide
              ? null
              : Drawer(
                  width: 280,
                  backgroundColor: const Color(0xF5040A1E),
                  child: SafeArea(
                    child: _sidebarContent(inDrawer: true),
                  ),
                ),
          body: Stack(
            children: [
              Positioned.fill(
                child: Image.asset(
                  'assets/images/goku.jpg',
                  fit: BoxFit.cover,
                  alignment: const Alignment(0.45, -0.15),
                ),
              ),
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                      colors: [
                        bg.withOpacity(.96),
                        bg.withOpacity(.82),
                        bg.withOpacity(.57),
                      ],
                    ),
                  ),
                ),
              ),
              SafeArea(
                child: Row(
                  children: [
                    if (wide && _sidebarOpen)
                      Container(
                        width: 265,
                        decoration: BoxDecoration(
                          color: const Color(0xF203071A),
                          border: Border(
                            right: BorderSide(color: blue.withOpacity(.45)),
                          ),
                        ),
                        child: _sidebarContent(inDrawer: false),
                      ),
                    Expanded(
                      child: Column(
                        children: [
                          _topBar(wide),
                          Expanded(
                            child: Padding(
                              padding: EdgeInsets.fromLTRB(
                                wide ? 28 : 12,
                                14,
                                wide ? 28 : 12,
                                12,
                              ),
                              child: _pageBody(wide),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _sidebarContent({required bool inDrawer}) {
    final filteredConversations = _searchQuery.trim().isEmpty
        ? _conversations
        : _conversations
            .where(
              (c) => c.title.toLowerCase().contains(
                    _searchQuery.trim().toLowerCase(),
                  ),
            )
            .toList();

    final displayName = widget.userName.trim().isNotEmpty
        ? widget.userName.trim()
        : widget.userEmail.split('@').first;
    final currentAvatar = _currentStoredAccount?.avatarBase64;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 10, 8),
          child: Row(
            children: [
              const Icon(Icons.all_inclusive, size: 24, color: cyan),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _assistantName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Buscar en recientes',
                onPressed: () {
                  setState(() {
                    _searchingChats = !_searchingChats;
                    if (!_searchingChats) {
                      _searchQuery = '';
                      _searchCtrl.clear();
                    }
                  });
                },
                icon: Icon(
                  _searchingChats ? Icons.close : Icons.search,
                  color: muted,
                  size: 20,
                ),
                visualDensity: VisualDensity.compact,
              ),
              IconButton(
                tooltip: 'Cerrar barra lateral',
                onPressed: () {
                  if (inDrawer) {
                    Navigator.pop(context);
                  } else {
                    setState(() => _sidebarOpen = false);
                  }
                },
                icon: const Icon(
                  Icons.view_sidebar_outlined,
                  color: muted,
                  size: 20,
                ),
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
        ),
        if (_searchingChats)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: TextField(
              controller: _searchCtrl,
              autofocus: true,
              onChanged: (v) => setState(() => _searchQuery = v),
              style: const TextStyle(fontSize: 13),
              decoration: InputDecoration(
                hintText: 'Buscar chat reciente…',
                hintStyle: const TextStyle(color: muted, fontSize: 13),
                isDense: true,
                filled: true,
                fillColor: const Color(0xFF0B1836),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 9,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: blue.withOpacity(0.45)),
                ),
              ),
            ),
          ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Column(
            children: [
              _sidebarMenuRow(
                icon: Icons.edit_square,
                label: 'Chat nuevo',
                selected: _page == 0 && _messages.isEmpty,
                onTap: () async {
                  if (inDrawer) Navigator.pop(context);
                  await _startNewConversation();
                },
              ),
              _sidebarMenuRow(
                icon: Icons.photo_library_outlined,
                label: 'Imágenes',
                selected: _page == 4,
                onTap: () {
                  if (inDrawer) Navigator.pop(context);
                  _setPage(4);
                },
              ),
              _sidebarMenuRow(
                icon: Icons.bolt,
                label: 'Comandos',
                selected: _page == 1,
                onTap: () {
                  if (inDrawer) Navigator.pop(context);
                  _setPage(1);
                },
              ),
              _sidebarMenuRow(
                icon: Icons.psychology_alt_outlined,
                label: 'Memoria',
                selected: _page == 2,
                onTap: () {
                  if (inDrawer) Navigator.pop(context);
                  _setPage(2);
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 4, 16, 6),
          child: Text(
            'Recientes',
            style: TextStyle(
              color: muted,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Expanded(
          child: filteredConversations.isEmpty
              ? const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  child: Text(
                    'Tus conversaciones guardadas aparecerán aquí.',
                    style: TextStyle(color: muted, fontSize: 12),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  itemCount: filteredConversations.length,
                  itemBuilder: (context, index) {
                    final conv = filteredConversations[index];
                    final isCurrent =
                        _page == 0 && conv.id == _activeConversationId;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 2),
                      child: Material(
                        color: isCurrent
                            ? const Color(0xFF10366F).withOpacity(0.72)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(10),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(10),
                          onTap: () async {
                            if (inDrawer) Navigator.pop(context);
                            await _openConversation(conv);
                          },
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(10, 7, 4, 7),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    conv.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: isCurrent
                                          ? Colors.white
                                          : Colors.white.withOpacity(0.88),
                                      fontSize: 13.5,
                                      fontWeight: isCurrent
                                          ? FontWeight.w600
                                          : FontWeight.normal,
                                    ),
                                  ),
                                ),
                                IconButton(
                                  tooltip: 'Eliminar chat',
                                  onPressed: () => _deleteConversation(conv.id),
                                  icon: const Icon(
                                    Icons.delete_outline,
                                    size: 16,
                                    color: muted,
                                  ),
                                  visualDensity: VisualDensity.compact,
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(
                                    minWidth: 26,
                                    minHeight: 26,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
        ),
        Container(
          padding: const EdgeInsets.fromLTRB(10, 8, 8, 10),
          decoration: BoxDecoration(
            border: Border(
              top: BorderSide(color: blue.withOpacity(0.32)),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Material(
                  color: Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () {
                      if (inDrawer) Navigator.pop(context);
                      _openProfileSwitcherModal();
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 6,
                      ),
                      child: Row(
                        children: [
                          _buildUserAvatar(
                            name: displayName,
                            email: widget.userEmail,
                            avatarBase64: currentAvatar,
                            radius: 17,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  displayName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 13.5,
                                    color: Colors.white,
                                  ),
                                ),
                                Text(
                                  widget.userEmail,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: muted,
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Configuración',
                onPressed: () {
                  if (inDrawer) Navigator.pop(context);
                  _setPage(3);
                },
                icon: Icon(
                  Icons.settings_outlined,
                  color: _page == 3 ? cyan : muted,
                  size: 21,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _sidebarMenuRow({
    required IconData icon,
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Material(
        color: selected ? const Color(0xFF10366F) : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
            child: Row(
              children: [
                Icon(
                  icon,
                  color: selected ? cyan : Colors.white.withOpacity(0.85),
                  size: 19,
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight:
                          selected ? FontWeight.w600 : FontWeight.normal,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _topBar(bool wide) => Container(
        height: 58,
        padding: EdgeInsets.symmetric(horizontal: wide ? 20 : 10),
        decoration: BoxDecoration(
          color: const Color(0x9905091B),
          border: Border(bottom: BorderSide(color: blue.withOpacity(.25))),
        ),
        child: Row(
          children: [
            if (!wide || !_sidebarOpen)
              IconButton(
                tooltip: 'Abrir menú',
                onPressed: () {
                  if (wide) {
                    setState(() => _sidebarOpen = true);
                  } else {
                    _scaffoldKey.currentState?.openDrawer();
                  }
                },
                icon: const Icon(
                  Icons.view_sidebar_outlined,
                  color: Colors.white,
                ),
              ),
            Expanded(
              child: Text(
                '✨ $_assistantName',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: const Color(0xFF05221F),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0xFF087C78)),
              ),
              child: const Text(
                '● RENDER CONECTADO',
                style: TextStyle(
                  color: Color(0xFF58F6B5),
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(width: 6),
            IconButton(
              tooltip: 'Chat nuevo',
              onPressed: _startNewConversation,
              icon: const Icon(
                Icons.edit_square,
                color: Colors.white,
                size: 20,
              ),
            ),
          ],
        ),
      );

  Widget _pageBody(bool wide) {
    switch (_page) {
      case 1:
        return _commandsView(wide);
      case 2:
        return _memoryView();
      case 3:
        return _settingsView();
      case 4:
        return _imagesGalleryView(wide);
      default:
        return _chatView(wide);
    }
  }

  Widget _imagesGalleryView(bool wide) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _title(
                'Imágenes mandadas',
                'Aquí quedan guardadas las imágenes que has enviado en tus chats.',
              ),
            ),
            TextButton.icon(
              onPressed: () => _setPage(0),
              icon: const Icon(Icons.chat_bubble_outline, size: 18, color: cyan),
              label: const Text('Volver al chat', style: TextStyle(color: cyan)),
            ),
          ],
        ),
        Expanded(
          child: _sentImages.isEmpty
              ? Center(
                  child: _glassCard(
                    padding: const EdgeInsets.all(24),
                    child: const Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.photo_library_outlined,
                          size: 42,
                          color: cyan,
                        ),
                        SizedBox(height: 10),
                        Text(
                          'Aún no has mandado imágenes',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'Cuando envíes una foto o captura desde el chat, aparecerá guardada aquí.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: muted, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                )
              : GridView.builder(
                  gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: wide ? 230 : 185,
                    mainAxisExtent: 215,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                  ),
                  itemCount: _sentImages.length,
                  itemBuilder: (context, index) {
                    final img = _sentImages[index];
                    return _glassCard(
                      padding: const EdgeInsets.all(8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(
                            child: GestureDetector(
                              onTap: () => _openImagePreviewDialog(img),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(11),
                                child: Image.memory(
                                  base64Decode(img.imageBase64),
                                  fit: BoxFit.cover,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  img.caption.isNotEmpty
                                      ? img.caption
                                      : img.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              InkWell(
                                onTap: () => _deleteSentImage(img.id),
                                borderRadius: BorderRadius.circular(8),
                                child: const Padding(
                                  padding: EdgeInsets.all(4),
                                  child: Icon(
                                    Icons.delete_outline,
                                    size: 17,
                                    color: Colors.redAccent,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          Text(
                            TimeOfDay.fromDateTime(img.sentAt).format(context),
                            style: const TextStyle(color: muted, fontSize: 10.5),
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _chatView(bool wide) {
    if (_messages.isEmpty) {
      return Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _heroWelcomeTitle,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: wide ? 30 : 23,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                    height: 1.25,
                  ),
                ),
                const SizedBox(height: 22),
                if (_attachments.isNotEmpty) ...[
                  _attachmentsPreview(),
                  const SizedBox(height: 8),
                ],
                _composer(),
              ],
            ),
          ),
        ),
      );
    }

    return Column(
      children: [
        Expanded(
          child: ListView.builder(
            controller: _scroll,
            reverse: false,
            padding: const EdgeInsets.symmetric(vertical: 5),
            itemCount: _messages.length,
            itemBuilder: (context, index) {
              return _messageBubble(_messages[index]);
            },
          ),
        ),
        if (_attachments.isNotEmpty) _attachmentsPreview(),
        const SizedBox(height: 8),
        _composer(),
      ],
    );
  }

  Widget _attachmentsPreview() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: panel,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: blue.withOpacity(0.45)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (int i = 0; i < _attachments.length; i++) ...[
              _attachmentThumbnailCard(_attachments[i], i),
              if (i < _attachments.length - 1) const SizedBox(width: 10),
            ],
          ],
        ),
      ),
    );
  }

  Widget _attachmentThumbnailCard(PendingAttachment item, int index) {
    return SizedBox(
      width: 78,
      height: 78,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: 0,
            bottom: 0,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: const Color(0xFF0E2247),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: cyan.withOpacity(0.5)),
                ),
                child: item.isImage
                    ? Image.memory(
                        item.bytes,
                        width: 72,
                        height: 72,
                        fit: BoxFit.cover,
                      )
                    : Padding(
                        padding: const EdgeInsets.all(6),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(
                              Icons.description_outlined,
                              color: cyan,
                              size: 24,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              item.name,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 9.5,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ),
              ),
            ),
          ),
          Positioned(
            top: 0,
            right: 0,
            child: GestureDetector(
              onTap: () {
                setState(() {
                  _attachments.removeAt(index);
                });
              },
              child: Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  color: const Color(0xFF040918),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white70, width: 1.2),
                  boxShadow: const [
                    BoxShadow(
                      color: Colors.black54,
                      blurRadius: 4,
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.close,
                  size: 14,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _messageBubble(ChatItem item) {
    final images = item.allImagesBase64;
    final names = item.allImageNames;
    final docs = item.documentNames;

    final bubble = Container(
      margin: const EdgeInsets.symmetric(vertical: 5),
      padding: const EdgeInsets.all(12),
      constraints: BoxConstraints(
        maxWidth: MediaQuery.of(context).size.width * .72,
      ),
      decoration: BoxDecoration(
        color: item.user ? const Color(0xE80A3571) : panel,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(
          color: item.user ? blue.withOpacity(.8) : blue.withOpacity(.45),
        ),
        boxShadow: [
          BoxShadow(color: blue.withOpacity(.10), blurRadius: 15),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (item.isVoice)
            WhatsAppVoiceBubble(
              durationSeconds: item.voiceDurationSeconds,
              audioBase64: item.audioBase64,
            ),
          if (docs.isNotEmpty) ...[
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                for (final docName in docs)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 7,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0E2554),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: cyan.withOpacity(0.55)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.description_rounded,
                          color: cyan,
                          size: 18,
                        ),
                        const SizedBox(width: 7),
                        Flexible(
                          child: Text(
                            docName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
            if (item.text.isNotEmpty || images.isNotEmpty)
              const SizedBox(height: 8),
          ],
          if (images.isNotEmpty) ...[
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (int i = 0; i < images.length; i++)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Image.memory(
                      base64Decode(images[i]),
                      height: images.length == 1 ? 160 : 110,
                      width: images.length == 1 ? null : 110,
                      fit: BoxFit.cover,
                    ),
                  ),
              ],
            ),
            if (item.text.isNotEmpty) const SizedBox(height: 6),
          ] else if (names.isNotEmpty) ...[
            Text(
              '📄 ${names.join(', ')}',
              style: const TextStyle(color: cyan, fontSize: 12),
            ),
            const SizedBox(height: 5),
          ],
          if (item.text.isNotEmpty && !item.isVoice)
            item.user
                ? SelectableText(item.text)
                : MarkdownBody(
                    data: item.text,
                    selectable: true,
                    styleSheet: MarkdownStyleSheet.fromTheme(
                      Theme.of(context),
                    ).copyWith(
                      p: const TextStyle(color: Colors.white, height: 1.45),
                      strong: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                      ),
                      h1: const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                      ),
                      h2: const TextStyle(
                        color: Colors.white,
                        fontSize: 19,
                        fontWeight: FontWeight.w700,
                      ),
                      h3: const TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                      a: const TextStyle(
                        color: cyan,
                        decoration: TextDecoration.underline,
                      ),
                      listBullet: const TextStyle(color: Colors.white),
                    ),
                  ),
          if (item.generatedFile != null &&
              item.generatedFile!.base64Data.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFF0D234D),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: cyan.withOpacity(0.6)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.file_present_rounded,
                    color: cyan,
                    size: 22,
                  ),
                  const SizedBox(width: 10),
                  Flexible(
                    child: Text(
                      item.generatedFile!.filename,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  FilledButton.icon(
                    onPressed: () =>
                        _downloadGeneratedFile(item.generatedFile!),
                    style: FilledButton.styleFrom(
                      backgroundColor: blue,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                    ),
                    icon: const Icon(Icons.download_rounded, size: 17),
                    label: const Text(
                      'Descargar',
                      style: TextStyle(fontSize: 12.5),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 6),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${item.user ? 'Tú' : _assistantName} · '
                '${TimeOfDay.fromDateTime(item.time).format(context)}',
                style: const TextStyle(color: muted, fontSize: 10),
              ),
              if (item.text.isNotEmpty && !item.isVoice) ...[
                const SizedBox(width: 8),
                InkWell(
                  onTap: () => _copyMessageText(item.text),
                  borderRadius: BorderRadius.circular(6),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.copy, size: 12, color: muted),
                        SizedBox(width: 3),
                        Text(
                          'Copiar',
                          style: TextStyle(color: muted, fontSize: 10),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );

    if (item.user) {
      return Align(
        alignment: Alignment.centerRight,
        child: bubble,
      );
    }

    return Align(
      alignment: Alignment.centerLeft,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Container(
            width: 38,
            height: 38,
            margin: const EdgeInsets.only(right: 8, bottom: 8),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: cyan, width: 2),
              boxShadow: [
                BoxShadow(color: cyan.withOpacity(.35), blurRadius: 10),
              ],
            ),
            child: ClipOval(
              child: Image.asset(
                'assets/images/goku.jpg',
                fit: BoxFit.cover,
                alignment: const Alignment(0, -.25),
              ),
            ),
          ),
          Flexible(child: bubble),
        ],
      ),
    );
  }

  Widget _composer() => Container(
        margin: const EdgeInsets.symmetric(horizontal: 2),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: const Color(0xF208122B),
          borderRadius: BorderRadius.circular(32),
          border: Border.all(color: blue.withOpacity(.45)),
          boxShadow: [
            BoxShadow(color: blue.withOpacity(.12), blurRadius: 18),
          ],
        ),
        child: Row(
          children: [
            IconButton(
              tooltip: 'Subir documentos, Fotos y Cámara',
              onPressed: (_loading || _recording) ? null : _openAttachMenu,
              icon: const Icon(Icons.add_rounded, color: muted, size: 25),
              visualDensity: VisualDensity.compact,
            ),
            Expanded(
              child: TextField(
                controller: _input,
                focusNode: _inputFocus,
                minLines: 1,
                maxLines: 4,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _handleSendOrStop(),
                decoration: InputDecoration(
                  border: InputBorder.none,
                  hintText: 'Preguntar a $_assistantName',
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(vertical: 10),
                ),
              ),
            ),
            IconButton(
              tooltip: _recording
                  ? 'Terminar y enviar nota de voz'
                  : 'Grabar nota de voz',
              onPressed: _loading ? null : _toggleRecording,
              icon: Icon(
                _recording ? Icons.stop_circle : Icons.mic_none_rounded,
                color: _recording ? Colors.redAccent : muted,
                size: 23,
              ),
              visualDensity: VisualDensity.compact,
            ),
            const SizedBox(width: 3),
            SizedBox(
              width: 40,
              height: 40,
              child: IconButton.filled(
                tooltip: _loading ? 'Detener' : 'Enviar mensaje',
                onPressed: _recording ? null : _handleSendOrStop,
                style: IconButton.styleFrom(
                  backgroundColor: _loading ? Colors.redAccent : blue,
                  foregroundColor: Colors.white,
                ),
                icon: Icon(
                  _loading ? Icons.stop_rounded : Icons.arrow_upward_rounded,
                  size: 22,
                ),
              ),
            ),
          ],
        ),
      );

  Widget _commandsView(bool wide) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _title(
            'Comandos',
            'Atajos que puedes usar también desde el chat.',
          ),
          Expanded(
            child: GridView.builder(
              gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: wide ? 290 : 420,
                mainAxisExtent: 160,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
              ),
              itemCount: _commands.length,
              itemBuilder: (context, index) {
                final command = _commands[index];

                return _glassCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${command.icon}  ${command.title}',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Expanded(
                        child: Text(
                          command.description,
                          style: const TextStyle(
                            color: muted,
                            fontSize: 13,
                          ),
                        ),
                      ),
                      Align(
                        alignment: Alignment.centerRight,
                        child: FilledButton.tonal(
                          onPressed: () {
                            _setPage(0);

                            if (command.command == '/recordar') {
                              _input.text = '/recordar ';
                            } else {
                              _input.text = command.command;
                              _sendText();
                            }
                          },
                          child: const Text('Probar'),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      );

  Widget _memoryView() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _title(
            'Memoria',
            'Notas guardadas en este dispositivo.',
          ),
          _glassCard(
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _memoryInput,
                    onSubmitted: (_) => _saveMemory(),
                    decoration: const InputDecoration(
                      hintText: 'Añade algo para recordar…',
                      border: InputBorder.none,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _saveMemory,
                  child: const Text('Guardar'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: _memories.isEmpty
                ? const Center(
                    child: Text(
                      'Todavía no has guardado ninguna nota.',
                      style: TextStyle(color: muted),
                    ),
                  )
                : ListView.builder(
                    itemCount: _memories.length,
                    itemBuilder: (context, index) => _glassCard(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        children: [
                          Expanded(
                            child: SelectableText(_memories[index]),
                          ),
                          IconButton(
                            tooltip: 'Eliminar nota',
                            onPressed: () async {
                              setState(() => _memories.removeAt(index));
                              await _save();
                            },
                            icon: const Icon(
                              Icons.delete_outline,
                              color: Colors.pinkAccent,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
          ),
        ],
      );

  Widget _settingsView() => ListView(
        children: [
          _title('Ajustes', 'Personaliza tu asistente y tu cuenta.'),
          _glassCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Cuenta activa',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                const SizedBox(height: 6),
                Text(
                  'Nombre: ${widget.userName}',
                  style: const TextStyle(color: muted),
                ),
                Text(
                  'Correo: ${widget.userEmail}',
                  style: const TextStyle(color: muted),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  alignment: WrapAlignment.end,
                  children: [
                    OutlinedButton.icon(
                      onPressed: _openEditProfileDialog,
                      icon: const Icon(Icons.edit, color: cyan, size: 18),
                      label: const Text('Editar perfil'),
                    ),
                    OutlinedButton.icon(
                      onPressed: _openProfileSwitcherModal,
                      icon: const Icon(
                        Icons.switch_account,
                        color: cyan,
                        size: 18,
                      ),
                      label: const Text('Cambiar cuenta'),
                    ),
                    OutlinedButton.icon(
                      onPressed: widget.onLogoutAll,
                      icon: const Icon(
                        Icons.logout,
                        color: Colors.amberAccent,
                        size: 18,
                      ),
                      label: const Text('Cerrar sesión'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _glassCard(
            child: Column(
              children: [
                TextField(
                  controller: _nameInput,
                  maxLength: 24,
                  decoration: const InputDecoration(
                    labelText: 'Nombre del asistente',
                    prefixIcon: Icon(Icons.auto_awesome),
                    counterText: '',
                  ),
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _speakReplies,
                  onChanged: (value) async {
                    setState(() => _speakReplies = value);
                    await _save();
                  },
                  title: const Text('Leer respuestas en voz alta'),
                  subtitle: const Text(
                    'Usa la voz disponible en tu dispositivo.',
                  ),
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton.icon(
                    onPressed: _saveSettings,
                    icon: const Icon(Icons.save_outlined),
                    label: const Text('Guardar ajustes'),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _glassCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Conexión',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 5),
                const Text(
                  'isaias titan se conecta automáticamente a su servicio seguro. '
                  'No necesitas ingresar URL ni claves aquí.',
                  style: TextStyle(color: muted, height: 1.4),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _glassCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Datos locales',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 5),
                const Text(
                  'Tus conversaciones recientes, imágenes enviadas y memoria se guardan en este dispositivo. '
                  'Las imágenes y el audio se envían al servidor para que la IA los analice.',
                  style: TextStyle(color: muted, height: 1.4),
                ),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerRight,
                  child: OutlinedButton.icon(
                    onPressed: _eraseAll,
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('Borrar datos locales'),
                  ),
                ),
              ],
            ),
          ),
        ],
      );

  Widget _title(String title, String subtitle) => Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontSize: 25,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              subtitle,
              style: const TextStyle(color: muted),
            ),
          ],
        ),
      );

  Widget _glassCard({
    required Widget child,
    EdgeInsetsGeometry padding = const EdgeInsets.all(14),
    EdgeInsetsGeometry? margin,
  }) =>
      Container(
        width: double.infinity,
        margin: margin,
        padding: padding,
        decoration: BoxDecoration(
          color: panel,
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: blue.withOpacity(.48)),
          boxShadow: [
            BoxShadow(color: blue.withOpacity(.08), blurRadius: 18),
          ],
        ),
        child: child,
      );
}
