/// Unified local TTS backend powered by sherpa-onnx.
///
/// One backend runs every local model family (VITS/Piper, MMS, Kokoro, Matcha,
/// Kitten): sherpa-onnx handles phonemization, tokenization and inference
/// internally. The model files come from [SherpaModelInstaller]; the family in
/// the [SherpaModel] descriptor selects the right sub-config.
library;

import 'dart:io';

import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

import '../../domain/voice.dart';
import '../audio/wav_writer.dart';
import '../deps/sherpa_model_installer.dart';
import 'sherpa_catalog.dart';
import 'tts_backend.dart';

/// A [TtsBackend] that synthesizes with a downloaded sherpa-onnx [SherpaModel].
class SherpaTtsBackend extends TtsBackend {
  final SherpaModel model;
  final SherpaModelInstaller installer;
  final double speed;
  final int numThreads;

  SherpaTtsBackend({
    required this.model,
    required this.installer,
    this.speed = 1.0,
    this.numThreads = 2,
  });

  static bool _bindingsReady = false;
  sherpa.OfflineTts? _tts;

  @override
  int get sampleRate => model.sampleRate;

  @override
  int get maxChars => 1800;

  @override
  List<Language> get supportedLanguages =>
      [for (final c in model.languages) Language(c, c.toUpperCase())];

  @override
  List<Voice> voicesFor(String languageCode) => const [];

  /// Builds the sherpa config for this model's family and opens the engine.
  void _ensureLoaded() {
    if (_tts != null) return;
    if (!_bindingsReady) {
      sherpa.initBindings();
      _bindingsReady = true;
    }
    final dir = installer.dirOf(model);
    final modelCfg = switch (model.family) {
      SherpaFamily.vits => sherpa.OfflineTtsModelConfig(
          vits: sherpa.OfflineTtsVitsModelConfig(
            model: installer.modelPath(model),
            tokens: installer.fileIn(model, model.tokensFile),
            dataDir: installer.fileIn(model, model.dataDir),
          ),
          numThreads: numThreads,
          debug: false,
        ),
      SherpaFamily.kokoro => sherpa.OfflineTtsModelConfig(
          kokoro: sherpa.OfflineTtsKokoroModelConfig(
            model: installer.modelPath(model),
            voices: installer.fileIn(model, model.voicesFile),
            tokens: installer.fileIn(model, model.tokensFile),
            dataDir: installer.fileIn(model, model.dataDir),
            lexicon: _joinLexicon(dir, model.lexicon),
            lang: model.lang,
          ),
          numThreads: numThreads,
          debug: false,
        ),
      SherpaFamily.matcha => sherpa.OfflineTtsModelConfig(
          matcha: sherpa.OfflineTtsMatchaModelConfig(
            acousticModel: installer.modelPath(model),
            vocoder: installer.vocoderPath(model),
            tokens: installer.fileIn(model, model.tokensFile),
            dataDir: installer.fileIn(model, model.dataDir),
          ),
          numThreads: numThreads,
          debug: false,
        ),
      SherpaFamily.kitten => sherpa.OfflineTtsModelConfig(
          kitten: sherpa.OfflineTtsKittenModelConfig(
            model: installer.modelPath(model),
            voices: installer.fileIn(model, model.voicesFile),
            tokens: installer.fileIn(model, model.tokensFile),
            dataDir: installer.fileIn(model, model.dataDir),
          ),
          numThreads: numThreads,
          debug: false,
        ),
    };
    _tts = sherpa.OfflineTts(sherpa.OfflineTtsConfig(model: modelCfg));
  }

  /// Resolves comma-separated lexicon file names to absolute paths.
  static String _joinLexicon(String dir, String lexicon) {
    if (lexicon.isEmpty) return '';
    return lexicon
        .split(',')
        .map((f) => '$dir/${f.trim()}')
        .join(',');
  }

  @override
  Future<void> synth(String text, String outWavPath) async {
    _ensureLoaded();
    final audio = _tts!.generate(text: text, sid: 0, speed: speed);
    final pcm = floatToPcm16(audio.samples);
    await File(outWavPath).writeAsBytes(buildWavPcm16Mono(pcm, audio.sampleRate));
  }

  /// Releases the native engine.
  void dispose() {
    _tts?.free();
    _tts = null;
  }
}
