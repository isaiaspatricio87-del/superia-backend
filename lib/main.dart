import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:record/record.dart';
import 'package:shared_preferences/shared_preferences.dart';

const Color bg = Color(0xFF05091B);
const Color panel = Color(0xE608122B);
const Color cyan = Color(0xFF19C7FF);
const Color blue = Color(0xFF3475FF);
const Color muted = Color(0xFFAAC0E0);

// Conexión fija al backend Render; no aparece en Ajustes.
const String backendChatUrl =
    'https://superia-backend-1.onrender.com/api/chat';

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
          backgroundColor: Color(0xFF10254A),
          behavior: SnackBarBehavior.floating,
        ),
      ),
      home: const SuperIAHome(),
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
  const SuperIAHome({super.key});

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
      final decoded = jsonDecode(prefs.getString('chat') ?? '[]') as List;
      _messages = decoded
          .map(
            (item) => ChatItem.fromJson(
              Map<String, dynamic>.from(item as Map),
            ),
          )
          .toList();
    } catch (_) {
      _messages = [];
    }

    _memories = prefs.getStringList('memories') ?? [];
    _assistantName = prefs.getString('assistantName') ?? 'SuperIA';
    _speakReplies = prefs.getBool('speakReplies') ?? false;
    _nameInput.text = _assistantName;

    if (mounted) setState(() => _ready = true);
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.setString(
      'chat',
      jsonEncode(_messages.map((item) => item.toJson()).toList()),
    );
    await prefs.setStringList('memories', _memories);
    await prefs.setString('assistantName', _assistantName);
    await prefs.setBool('speakReplies', _speakReplies);
  }

  void _toast(String text) {
    if (!mounted) return;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(text),
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
        final date =
            MaterialLocalizations.of(context).formatMediumDate(now);
        return 'Ahora son las \(time del \)date.';

      case '/recordar':
        if (argument.isEmpty) {
          return 'Escribe qué quieres recordar. '
              'Ejemplo: /recordar Me gusta el café.';
        }
        setState(() => _memories.add(argument));
        await _save();
        return 'Listo, guardé en este dispositivo: “$argument”.';

      case '/memoria':
        if (_memories.isEmpty) return 'Aún no hay notas guardadas.';
        return 'Esto es lo que recuerdo:\n• ${_memories.join('\n• ')}';

      case '/limpiar':
        setState(() => _messages.clear());
        await _save();
        return 'Chat limpio. Tus notas siguen guardadas.';

      case '/ayuda':
        return 'Comandos: /hora, /recordar [nota], '
            '/memoria, /limpiar y /ayuda.';

      default:
        return null;
    }
  }

  Future<Map<String, dynamic>> _askBackend({
    String message = '',
    Uint8List? audioWav,
    Uint8List? image,
    String? imageMimeType,
  }) async {
    final Map<String, dynamic> payload = {
      'message': message,
      'memories': _memories,
    };

    if (audioWav != null) {
      payload['audio_base64'] = base64Encode(audioWav);
      payload['audio_mime_type'] = 'audio/wav';
    }

    if (image != null) {
      payload['image_base64'] = base64Encode(image);
      payload['image_mime_type'] = imageMimeType ?? 'image/jpeg';
    }

    final response = await http
        .post(
          Uri.parse(backendChatUrl),
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

    if (body is! Map) {
      throw Exception('El servidor devolvió una respuesta inválida.');
    }

    return Map<String, dynamic>.from(body);
  }

  Future<void> _sendText() async {
    final text = _input.text.trim();
    if (text.isEmpty && _pickedImage == null) return;
    if (_loading) return;

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
        final result = await _askBackend(
          message: text,
          image: image,
          imageMimeType: imageMime,
        );
        reply = (result['reply'] ?? 'No recibí una respuesta.').toString();
      }

      await _addMessage(false, reply);
      if (_speakReplies) await _speak(reply);
    } catch (error) {
      await _addMessage(
        false,
        'No pude conectar con Render: ${_friendlyError(error)}',
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _friendlyError(Object error) {
    final text = error.toString().replaceFirst('Exception: ', '');

    if (text.contains('Failed to fetch') ||
        text.contains('XMLHttpRequest')) {
      return 'falló la conexión. Revisa el backend y CORS en Render.';
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
        _toast('No se grabó audio. Mantén presionado un momento.');
        return;
      }

      await _sendVoice(
        _makeWav(pcm),
        seconds < 1 ? 1 : seconds,
      );
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

    setState(() => _loading = true);

    try {
      await _addMessage(
        true,
        'Nota de voz · ${_formatDuration(seconds)}',
        isVoice: true,
        voiceDurationSeconds: seconds,
      );

      final result = await _askBackend(audioWav: wav);
      final reply = (result['reply'] ?? 'No recibí una respuesta.').toString();

      await _addMessage(false, reply);
      if (_speakReplies) await _speak(reply);
    } catch (error) {
      await _addMessage(
        false,
        'No pude enviar la nota de voz: ${_friendlyError(error)}',
      );
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

  Future<void> _deleteMemory(int index) async {
    setState(() => _memories.removeAt(index));
    await _save();
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
    setState(() => _messages.clear());
    await _save();
    _toast('Chat nuevo. La memoria se conservó.');
  }

  Future<void> _eraseAll() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Borrar datos locales'),
        content: const Text(
          'Se borrarán el historial, las memorias y los ajustes de este dispositivo.',
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
    await prefs.clear();

    setState(() {
      _messages.clear();
      _memories.clear();
      _assistantName = 'SuperIA';
      _speakReplies = false;
      _nameInput.text = 'SuperIA';
    });

    _toast('Datos borrados.');
  }

  @override
  void dispose() {
    _recordingTimer?.cancel();
    _recordingSubscription?.cancel();
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
        width: 205,
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
            const SizedBox(height: 20),
            _statusPill(),
            const SizedBox(height: 18),
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
              onPressed: _clearChat,
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

  Widget _chatView(bool wide) => Column(
        children: [
          _glassCard(
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: cyan, width: 2),
                    image: const DecorationImage(
                      image: AssetImage('assets/images/goku.jpg'),
                      fit: BoxFit.cover,
                      alignment: Alignment.topCenter,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '¿En qué puedo ayudarte hoy?',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: wide ? 16 : 14,
                        ),
                      ),
                      Text(
                        'Soy $_assistantName, tu asistente personal ✨',
                        style: const TextStyle(color: muted, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Expanded(
            child: _messages.isEmpty
                ? Center(
                    child: Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: panel.withOpacity(.8),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: blue.withOpacity(.3)),
                      ),
                      child: const Text(
                        'Escribe un mensaje o manda una nota de voz',
                        style: TextStyle(color: muted),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  )
                : ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.symmetric(vertical: 5),
                    itemCount: _messages.length + (_loading ? 1 : 0),
                    itemBuilder: (context, index) {
                      if (_loading && index == _messages.length) {
                        return const Align(
                          alignment: Alignment.centerLeft,
                          child: Padding(
                            padding: EdgeInsets.all(10),
                            child: Text(
                              'Pensando…',
                              style: TextStyle(color: cyan),
                            ),
                          ),
                        );
                      }
                      return _messageBubble(_messages[index]);
                    },
                  ),
          ),
          if (_pickedImage != null) _imagePreview(),
          const SizedBox(height: 8),
          _composer(),
        ],
      );

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
            SelectableText(item.text),
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

  Widget _composer() => _glassCard(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 5),
        child: Row(
          children: [
            IconButton(
              tooltip: _recording
                  ? 'Terminar y enviar nota de voz'
                  : 'Grabar nota de voz',
              onPressed: _loading ? null : _toggleRecording,
              icon: Icon(
                _recording ? Icons.stop_circle : Icons.mic_none,
                color: _recording ? Colors.redAccent : cyan,
                size: 25,
              ),
            ),
            if (_recording)
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: Text(
                  _formatDuration(_recordingSeconds),
                  style: const TextStyle(
                    color: Colors.redAccent,
                    fontSize: 12,
                  ),
                ),
              ),
            Expanded(
              child: TextField(
                controller: _input,
                minLines: 1,
                maxLines: 4,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _sendText(),
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  hintText: 'Escribe un mensaje…',
                  isDense: true,
                ),
              ),
            ),
            IconButton(
              tooltip: 'Adjuntar imagen',
              onPressed: _pickImage,
              icon: const Icon(Icons.image_outlined, color: cyan),
            ),
            IconButton(
              tooltip: _speakReplies
                  ? 'Desactivar lectura'
                  : 'Leer respuestas en voz alta',
              onPressed: () async {
                setState(() => _speakReplies = !_speakReplies);
                await _save();
                _toast(
                  _speakReplies
                      ? 'Lectura de voz activada.'
                      : 'Lectura desactivada.',
                );
              },
              icon: Icon(
                _speakReplies ? Icons.volume_up : Icons.volume_down,
                color: cyan,
              ),
            ),
            IconButton.filled(
              onPressed: _loading || _recording ? null : _sendText,
              icon: const Icon(Icons.send_rounded),
              style: IconButton.styleFrom(
                backgroundColor: blue,
                foregroundColor: Colors.white,
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
                        '\({command.icon}  \){command.title}',
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
          _title('Ajustes', 'Personaliza tu asistente.'),
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
