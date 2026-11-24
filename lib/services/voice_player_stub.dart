class VoiceAudioPlayer {
  Future<void> playBase64Wav(
    String base64Wav, {
    required void Function() onEnded,
  }) async {}

  Future<void> pause() async {}

  Future<void> resume({required void Function() onEnded}) async {}

  Future<void> stop() async {}

  void dispose() {}
}