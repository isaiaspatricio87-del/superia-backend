import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:record/record.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'services/api_service.dart';

const Color bg = Color(0xFF05091B);
const Color panel = Color(0xE608122B);
const Color cyan = Color(0xFF19C7FF);
const Color blue = Color(0xFF3475FF);
const Color muted = Color(0xFFAAC0E0);

void main() => runApp(const SuperIAApp());

class SuperIAApp extends StatelessWidget {
  const SuperIAApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SuperIA',
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

  @override
  void initState() {
    super.initState();
    _restoreSession();
  }

  Future<void> _restoreSession() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('authToken');
    final name = prefs.getString('userName') ?? '';
    final email = prefs.getString('userEmail') ?? '';

    if (mounted) {
      setState(() {
        _token = (token != null && token.isNotEmpty) ? token : null;
        _userName = name;
        _userEmail = email;
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

    if (mounted) {
      setState(() {
        _token = token;
        _userName = name;
        _userEmail = email;
      });
    }
  }

  Future<void> _logout() async {
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
      authToken: _token!,
      userName: _userName,
      userEmail: _userEmail,
      onLogout: _logout,
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
  bool _isRegister = false;
  bool _submitting = false;
  bool _obscurePassword = true;

  final TextEditingController _nameCtrl = TextEditingController();
  final TextEditingController _emailCtrl = TextEditingController();
  final TextEditingController _passwordCtrl = TextEditingController();

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
      final result = _isRegister
          ? await ApiService.register(
              name: name,
              email: email,
              password: password,
            )
          : await ApiService.login(
              email: email,
              password: password,
            );

      final token = result['token']?.toString() ?? '';
      final userMap = Map<String, dynamic>.from(
        (result['user'] as Map?) ?? const {},
      );
      final resolvedName = userMap['name']?.toString() ?? name;
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

  Future<void> _loginWithGoogle() async {
    final typedEmail = _emailCtrl.text.trim();
    final emailToUse =
        typedEmail.contains('@') ? typedEmail : 'cuenta.google@superia.app';
    final nameToUse = _nameCtrl.text.trim().isNotEmpty
        ? _nameCtrl.text.trim()
        : emailToUse.split('@').first;

    setState(() => _submitting = true);

    try {
      final result = await ApiService.googleQuickLogin(
        name: nameToUse,
        email: emailToUse,
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
        name: userMap['name']?.toString() ?? nameToUse,
        email: userMap['email']?.toString() ?? emailToUse,
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

  @override
  void dispose() {
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
                      borderRadius: BorderRadius.circular(20),
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
                        const Icon(Icons.all_inclusive, size: 46, color: cyan),
                        const SizedBox(height: 6),
                        const Text(
                          'SuperIA',
                          style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Text(
                          _isRegister
                              ? 'Crea tu cuenta para entrar'
                              : 'Inicia sesión para entrar',
                          style: const TextStyle(color: muted, fontSize: 13),
                        ),
                        const SizedBox(height: 22),
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
                            prefixIcon: Icon(Icons.email_outlined, color: cyan),
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
                        const SizedBox(height: 12),
                        if (!_isRegister) ...[
                          SizedBox(
                            width: double.infinity,
                            height: 44,
                            child: OutlinedButton.icon(
                              onPressed: _submitting ? null : _loginWithGoogle,
                              icon: const Icon(
                                Icons.g_mobiledata,
                                size: 28,
                                color: cyan,
                              ),
                              label: const Text(
                                'Continuar con Google',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                        ],
                        TextButton(
                          onPressed: _submitting
                              ? null
                              : () => setState(() => _isRegister = !_isRegister),
                          child: Text(
                            _isRegister
                                ? '¿Ya tienes cuenta? Inicia sesión'
                                : '¿No tienes cuenta? Regístrate aquí',
                            style: const TextStyle(color: cyan),
                          ),
                        ),
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
    this.isVoice = false,
    this.voiceDurationSeconds = 0,
  });

  final bool user;
  final String text;
  final DateTime time;
  final String? imageBase64;
  final String? imageName;
  final bool isVoice;
  final int voiceDurationSeconds;

  Map<String, dynamic> toJson() => {
        'user': user,
        'text': text,
        'time': time.toIso8601String(),
        'imageBase64': imageBase64,
        'imageName': imageName,
        'isVoice': isVoice,
        'voiceDurationSeconds': voiceDurationSeconds,
      };

  factory ChatItem.fromJson(Map<String, dynamic> json) => ChatItem(
        user: json['user'] == true,
        text: json['text']?.toString() ?? '',
        time: DateTime.tryParse(json['time']?.toString() ?? '') ??
            DateTime.now(),
        imageBase64: json['imageBase64']?.toString(),
        imageName: json['imageName']?.toString(),
        isVoice: json['isVoice'] == true,
        voiceDurationSeconds:
            (json['voiceDurationSeconds'] as num?)?.toInt() ?? 0,
      );
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
    required this.onLogout,
  });

  final String authToken;
  final String userName;
  final String userEmail;
  final Future<void> Function() onLogout;

  @override
  State<SuperIAHome> createState() => _SuperIAHomeState();
}

class _SuperIAHomeState extends State<SuperIAHome> {
  int _page = 0;
  String _assistantName = 'SuperIA';

  bool _speakReplies = false;
  bool _loading = false;
  bool _ready = false;
  bool _recording = false;
  int _recordingSeconds = 0;

  StreamSubscription? _currentRequestSubscription;

  List<ChatItem> _messages = [];
  List<String> _memories = [];

  Uint8List? _pickedImage;
  String? _pickedImageName;
  String? _pickedImageMime;

  final TextEditingController _input = TextEditingController();
  final TextEditingController _memoryInput = TextEditingController();
  final TextEditingController _nameInput = TextEditingController();
  final ScrollController _scroll = ScrollController();

  final AudioRecorder _recorder = AudioRecorder();
  final ImagePicker _picker = ImagePicker();
  final FlutterTts _tts = FlutterTts();

  StreamSubscription<Uint8List>? _recordingSubscription;
  final List<Uint8List> _recordedPcmChunks = [];
  Timer? _recordingTimer;

  String get _chatKey => 'chat_${widget.userEmail.toLowerCase()}';
  String get _memoryKey => 'memories_${widget.userEmail.toLowerCase()}';

  String get _heroWelcomeTitle {
    final name = widget.userName.trim();
    if (name.isEmpty) return '¿En qué te ayudo hoy?';
    return '¿Qué tenemos en la agenda hoy, $name?';
  }

  static const List<String> _navLabels = [
    'Chat',
    'Comandos',
    'Memoria',
    'Ajustes',
  ];

  static const List<IconData> _navIcons = [
    Icons.chat_bubble_outline,
    Icons.bolt,
    Icons.psychology_alt_outlined,
    Icons.settings_outlined,
  ];

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
  }

  Future<void> _loadLocal() async {
    final prefs = await SharedPreferences.getInstance();

    try {
      final decoded = jsonDecode(prefs.getString(_chatKey) ?? '[]') as List;
      final loadedMessages = decoded
          .map(
            (item) => ChatItem.fromJson(
              Map<String, dynamic>.from(item as Map),
            ),
          )
          .toList();
      _messages = loadedMessages;
    } catch (_) {
      _messages = [];
    }

    _memories = prefs.getStringList(_memoryKey) ?? [];
    _assistantName = prefs.getString('assistantName') ?? 'SuperIA';
    _speakReplies = prefs.getBool('speakReplies') ?? false;
    _nameInput.text = _assistantName;

    if (mounted) setState(() => _ready = true);
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.setString(
      _chatKey,
      jsonEncode(_messages.map((item) => item.toJson()).toList()),
    );
    await prefs.setStringList(_memoryKey, _memories);
    await prefs.setString('assistantName', _assistantName);
    await prefs.setBool('speakReplies', _speakReplies);
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

  void _setPage(int page) {
    setState(() => _page = page);
  }

  Future<void> _addMessage(
    bool isUser,
    String text, {
    String? imageBase64,
    String? imageName,
    bool isVoice = false,
    int voiceDurationSeconds = 0,
  }) async {
    setState(() {
      _messages.add(
        ChatItem(
          user: isUser,
          text: text,
          time: DateTime.now(),
          imageBase64: imageBase64,
          imageName: imageName,
          isVoice: isVoice,
          voiceDurationSeconds: voiceDurationSeconds,
        ),
      );
    });

    await _save();

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

    final recent = previous.length > 12
        ? previous.sublist(previous.length - 12)
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
        return 'Esto es lo que recuerdo:\n• ${_memories.join('\n• ')}';

      case '/limpiar':
        setState(() {
          _messages.clear();
        });
        await _save();
        return 'Chat limpio. Tus notas siguen guardadas.';

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
    if (text.isEmpty && _pickedImage == null) return;
    if (_loading) return;

    final history = _conversationHistory();
    final image = _pickedImage;
    final imageName = _pickedImageName;
    final imageMime = _pickedImageMime;

    _input.clear();

    setState(() {
      _pickedImage = null;
      _pickedImageName = null;
      _pickedImageMime = null;
      _loading = true;
    });

    try {
      await _addMessage(
        true,
        text.isEmpty ? 'Imagen adjunta' : text,
        imageBase64: image == null ? null : base64Encode(image),
        imageName: imageName,
      );

      final commandReply = image == null ? await _runCommand(text) : null;
      final String reply;

      if (commandReply != null) {
        reply = commandReply;
      } else {
        final completer = Completer<String>();

        _currentRequestSubscription = Stream.fromFuture(
          ApiService.sendMessage(
            authToken: widget.authToken,
            message: text,
            memories: _memories,
            history: history,
            image: image,
            imageMimeType: imageMime,
          ),
        ).listen((res) {
          if (!completer.isCompleted) completer.complete(res);
        }, onError: (err) {
          if (!completer.isCompleted) completer.completeError(err);
        });

        reply = await completer.future;
      }

      if (mounted) {
        await _addMessage(false, reply);
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

  Future<void> _pickImage() async {
    try {
      final file = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 80,
        maxWidth: 1600,
      );

      if (file == null) return;

      final bytes = await file.readAsBytes();
      final name = file.name.toLowerCase();

      final mimeType = name.endsWith('.png')
          ? 'image/png'
          : name.endsWith('.webp')
              ? 'image/webp'
              : 'image/jpeg';

      setState(() {
        _pickedImage = bytes;
        _pickedImageName = file.name;
        _pickedImageMime = mimeType;
      });
    } catch (_) {
      _toast('No pude abrir la galería. Revisa los permisos.');
    }
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
    setState(() => _loading = true);

    try {
      await _addMessage(
        true,
        'Nota de voz · ${_formatDuration(seconds)}',
        isVoice: true,
        voiceDurationSeconds: seconds,
      );

      final reply = await ApiService.sendMessage(
        authToken: widget.authToken,
        message: '',
        memories: _memories,
        history: history,
        audioWav: wav,
      );

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
      if (mounted) setState(() => _loading = false);
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
          ? 'SuperIA'
          : _nameInput.text.trim();
    });

    await _save();
    _toast('Ajustes guardados.');
  }

  Future<void> _clearChat() async {
    setState(() {
      _messages.clear();
    });
    await _save();
    _toast('Nuevo chat iniciado.');
  }

  Future<void> _eraseAll() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Borrar datos locales'),
        content: const Text(
          'Se borrarán tu historial y memorias guardadas en este dispositivo.',
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
    await prefs.remove(_memoryKey);

    setState(() {
      _messages.clear();
      _memories.clear();
    });

    _toast('Datos borrados.');
  }

  @override
  void dispose() {
    _recordingTimer?.cancel();
    _recordingSubscription?.cancel();
    _currentRequestSubscription?.cancel();
    _recorder.dispose();
    _tts.stop();
    _input.dispose();
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
                    if (wide) _sideNav(),
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
                          if (!wide) _bottomNav(),
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

  Widget _sideNav() => Container(
        width: 215,
        padding: const EdgeInsets.fromLTRB(13, 20, 13, 14),
        decoration: BoxDecoration(
          color: const Color(0xF203071A),
          border: Border(right: BorderSide(color: blue.withOpacity(.45))),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Icon(Icons.all_inclusive, size: 38, color: cyan),
            Text(
              _assistantName,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 23, fontWeight: FontWeight.w800),
            ),
            const Text(
              'ASISTENTE IA',
              textAlign: TextAlign.center,
              style: TextStyle(color: cyan, fontSize: 11, letterSpacing: 2),
            ),
            const SizedBox(height: 14),
            _statusPill(),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: panel.withOpacity(.7),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: blue.withOpacity(.35)),
              ),
              child: Text(
                widget.userName.isNotEmpty ? widget.userName : widget.userEmail,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(color: muted, fontSize: 12),
              ),
            ),
            const SizedBox(height: 14),
            Padding(
              padding: const EdgeInsets.only(bottom: 7),
              child: Material(
                color: const Color(0xFF10366F).withOpacity(0.6),
                borderRadius: BorderRadius.circular(12),
                child: InkWell(
                  onTap: () {
                    _setPage(0);
                    _clearChat();
                  },
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: cyan.withOpacity(.5)),
                    ),
                    child: const Row(
                      children: [
                        Icon(
                          Icons.add_comment_outlined,
                          color: cyan,
                          size: 21,
                        ),
                        SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Nuevo chat',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            for (var i = 0; i < _navLabels.length; i++)
              _navButton(i, expanded: true),
            const Spacer(),
            Text(
              '“Pregunta, explora,\ndescubre el poder de la IA”',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: muted.withOpacity(.8),
                fontSize: 12,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ),
      );

  Widget _statusPill() => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        decoration: BoxDecoration(
          color: const Color(0xFF05221F),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: const Color(0xFF087C78)),
        ),
        child: const Text(
          '● RENDER CONECTADO',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Color(0xFF58F6B5),
            fontSize: 10,
            fontWeight: FontWeight.bold,
          ),
        ),
      );

  Widget _navButton(int index, {required bool expanded}) {
    final selected = _page == index;

    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Material(
        color: selected ? const Color(0xFF10366F) : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: () => _setPage(index),
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: EdgeInsets.symmetric(
              horizontal: expanded ? 12 : 5,
              vertical: expanded ? 12 : 8,
            ),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: selected ? cyan.withOpacity(.7) : Colors.transparent,
              ),
            ),
            child: expanded
                ? Row(
                    children: [
                      Icon(
                        _navIcons[index],
                        color: selected ? cyan : Colors.white70,
                        size: 21,
                      ),
                      const SizedBox(width: 12),
                      Text(_navLabels[index]),
                    ],
                  )
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _navIcons[index],
                        color: selected ? cyan : Colors.white70,
                        size: 20,
                      ),
                      Text(
                        _navLabels[index],
                        style: const TextStyle(fontSize: 10),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }

  Widget _bottomNav() => Container(
        decoration: BoxDecoration(
          color: const Color(0xF203071A),
          border: Border(top: BorderSide(color: blue.withOpacity(.45))),
        ),
        padding: EdgeInsets.fromLTRB(
          4,
          5,
          4,
          5 + MediaQuery.of(context).padding.bottom,
        ),
        child: Row(
          children: [
            for (var i = 0; i < _navLabels.length; i++)
              Expanded(child: _navButton(i, expanded: false)),
          ],
        ),
      );

  Widget _topBar(bool wide) => Container(
        height: 64,
        padding: EdgeInsets.symmetric(horizontal: wide ? 28 : 15),
        decoration: BoxDecoration(
          color: const Color(0x9905091B),
          border: Border(bottom: BorderSide(color: blue.withOpacity(.25))),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                '✨ ¡Hola! Soy $_assistantName 👋',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            IconButton(
              tooltip: 'Nuevo chat',
              onPressed: () {
                _setPage(0);
                _clearChat();
              },
              icon: const Icon(
                Icons.add_comment_outlined,
                color: Colors.white,
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
      default:
        return _chatView(wide);
    }
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
                if (_pickedImage != null) ...[
                  _imagePreview(),
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
        if (_pickedImage != null) _imagePreview(),
        const SizedBox(height: 8),
        _composer(),
      ],
    );
  }

  Widget _imagePreview() => Container(
        margin: const EdgeInsets.only(top: 6),
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: panel,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Image.memory(
              _pickedImage!,
              width: 46,
              height: 46,
              fit: BoxFit.cover,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                _pickedImageName ?? 'Imagen',
                overflow: TextOverflow.ellipsis,
              ),
            ),
            IconButton(
              onPressed: () => setState(() {
                _pickedImage = null;
                _pickedImageName = null;
                _pickedImageMime = null;
              }),
              icon: const Icon(Icons.close),
            ),
          ],
        ),
      );

  Widget _messageBubble(ChatItem item) {
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
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.graphic_eq, color: cyan),
                const SizedBox(width: 7),
                Text(
                  'Nota de voz · '
                  '${_formatDuration(item.voiceDurationSeconds)}',
                ),
              ],
            ),
          if (item.imageBase64 != null) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(9),
              child: Image.memory(
                base64Decode(item.imageBase64!),
                height: 150,
                fit: BoxFit.cover,
              ),
            ),
            if (item.imageName != null)
              Text(
                '🖼 ${item.imageName}',
                style: const TextStyle(color: muted, fontSize: 11),
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
          const SizedBox(height: 4),
          Text(
            '${item.user ? 'Tú' : _assistantName} · '
            '${TimeOfDay.fromDateTime(item.time).format(context)}',
            style: const TextStyle(color: muted, fontSize: 10),
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
              tooltip: 'Adjuntar imagen',
              onPressed: _loading ? null : _pickImage,
              icon: const Icon(Icons.add_rounded, color: muted, size: 25),
              visualDensity: VisualDensity.compact,
            ),
            Expanded(
              child: TextField(
                controller: _input,
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
                Align(
                  alignment: Alignment.centerRight,
                  child: OutlinedButton.icon(
                    onPressed: widget.onLogout,
                    icon: const Icon(Icons.logout, color: Colors.amberAccent),
                    label: const Text('Cerrar sesión'),
                  ),
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
                  'SuperIA se conecta automáticamente a su servicio seguro. '
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
                  'El historial y la memoria se guardan en este dispositivo. '
                  'El audio se envía al servidor para que la IA lo entienda.',
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