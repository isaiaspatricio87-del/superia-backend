import 'dart:js_interop';
import 'package:web/web.dart' as web;

class VoiceAudioPlayer {
  web.HTMLAudioElement? _audio;

  Future<void> playBase64Wav(
    String base64Wav, {
    required void Function() onEnded,
  }) async {
    await stop();
    final audio = web.HTMLAudioElement()
      ..src = 'data:audio/wav;base64,$base64Wav'
      ..preload = 'auto';

    audio.onended = ((web.Event _) {
      onEnded();
    }).toJS;

    _audio = audio;
    await audio.play().toDart;
  }

  Future<void> pause() async {
    _audio?.pause();
  }

  Future<void> resume({required void Function() onEnded}) async {
    final audio = _audio;
    if (audio == null) return;
    audio.onended = ((web.Event _) {
      onEnded();
    }).toJS;
    await audio.play().toDart;
  }

  Future<void> stop() async {
    final audio = _audio;
    if (audio != null) {
      audio.pause();
      audio.currentTime = 0;
      _audio = null;
    }
  }

  void dispose() {
    _audio?.pause();
    _audio = null;
  }
}