/// Unified local TTS backend powered by sherpa-onnx, run in a worker isolate.
///
/// One backend runs every local model family (VITS/Piper, MMS, Kokoro, Matcha,
/// Kitten). Inference is the heaviest, fully-synchronous part, so it runs in a
/// **persistent background isolate**: the model loads once there, and each
/// `synth` call is a message round-trip that returns ready-to-write WAV bytes.
/// This keeps the UI isolate responsive (no beachball during conversion).
library;

import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

import '../../domain/voice.dart';
import '../audio/wav_writer.dart';
import '../deps/sherpa_model_installer.dart';
import 'sherpa_catalog.dart';
import 'tts_backend.dart';

/// A [TtsBackend] that synthesizes with a downloaded sherpa-onnx engine, using
/// the voice that matches [languageCode], in a background isolate.
class SherpaTtsBackend extends TtsBackend {
  final SherpaModel model;
  final String languageCode;
  final SherpaModelInstaller installer;
  final double speed;
  final int numThreads;

  /// Directory containing the sherpa native libs. Null in the Flutter app
  /// (resolved via the bundle's rpath); set by the CLI where there's no bundle.
  static String? libraryDir;

  late final SherpaVoice _voice = model.voiceFor(languageCode);

  SherpaTtsBackend({
    required this.model,
    required this.languageCode,
    required this.installer,
    this.speed = 1.0,
    this.numThreads = 2,
  });

  Isolate? _isolate;
  SendPort? _send;
  Completer<void>? _ready;
  final _pending = <int, Completer<Uint8List>>{};
  int _seq = 0;

  @override
  int get sampleRate => _voice.sampleRate;

  @override
  int get maxChars => 1800;

  @override
  List<Language> get supportedLanguages =>
      [for (final c in model.languages) Language(c, c.toUpperCase())];

  @override
  List<Voice> voicesFor(String languageCode) => const [];

  /// Spawns the worker isolate (once) and waits until it has loaded the model.
  Future<void> _ensureWorker() async {
    if (_send != null) return;
    if (_ready != null) return _ready!.future;
    _ready = Completer<void>();

    final v = _voice;
    final init = _WorkerInit(
      family: v.family.index,
      speed: speed,
      numThreads: numThreads,
      libDir: libraryDir,
      model: installer.modelPath(v),
      tokens: installer.fileIn(v, v.tokensFile),
      dataDir: installer.fileIn(v, v.dataDir),
      voices: installer.fileIn(v, v.voicesFile),
      lexicon: _joinLexicon(installer.dirOf(v), v.lexicon),
      lang: v.lang,
      vocoder: installer.vocoderPath(v),
    );

    final fromWorker = ReceivePort();
    fromWorker.listen((msg) {
      if (msg is SendPort) {
        _send = msg;
        _ready!.complete();
      } else if (msg is _WorkerOk) {
        _pending.remove(msg.id)?.complete(msg.wav);
      } else if (msg is _WorkerErr) {
        _pending.remove(msg.id)?.completeError(StateError(msg.message));
      }
    });
    _isolate = await Isolate.spawn(
        _workerMain, _WorkerBoot(fromWorker.sendPort, init));
    return _ready!.future;
  }

  @override
  Future<void> synth(String text, String outWavPath) async {
    await _ensureWorker();
    final id = _seq++;
    final completer = Completer<Uint8List>();
    _pending[id] = completer;
    _send!.send(_WorkerReq(id, text));
    final wav = await completer.future; // yields to the event loop → UI stays live
    await File(outWavPath).writeAsBytes(wav);
  }

  static String _joinLexicon(String dir, String lexicon) {
    if (lexicon.isEmpty) return '';
    return lexicon.split(',').map((f) => '$dir/${f.trim()}').join(',');
  }

  /// Terminates the worker isolate.
  @override
  Future<void> dispose() async {
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
    _send = null;
  }
}

// --- isolate messages ---

class _WorkerInit {
  final int family;
  final double speed;
  final int numThreads;
  final String? libDir;
  final String model, tokens, dataDir, voices, lexicon, lang, vocoder;
  const _WorkerInit({
    required this.family,
    required this.speed,
    required this.numThreads,
    required this.libDir,
    required this.model,
    required this.tokens,
    required this.dataDir,
    required this.voices,
    required this.lexicon,
    required this.lang,
    required this.vocoder,
  });
}

class _WorkerBoot {
  final SendPort reply;
  final _WorkerInit init;
  const _WorkerBoot(this.reply, this.init);
}

class _WorkerReq {
  final int id;
  final String text;
  const _WorkerReq(this.id, this.text);
}

class _WorkerOk {
  final int id;
  final Uint8List wav;
  const _WorkerOk(this.id, this.wav);
}

class _WorkerErr {
  final int id;
  final String message;
  const _WorkerErr(this.id, this.message);
}

/// Worker isolate entry: loads the model once, then answers synth requests.
void _workerMain(_WorkerBoot boot) {
  final init = boot.init;
  if (init.libDir != null) {
    sherpa.initBindings(init.libDir);
  } else {
    sherpa.initBindings();
  }
  final modelCfg = _buildModelConfig(init);
  final tts = sherpa.OfflineTts(sherpa.OfflineTtsConfig(model: modelCfg));

  final inbox = ReceivePort();
  boot.reply.send(inbox.sendPort);
  inbox.listen((msg) {
    if (msg is! _WorkerReq) return;
    try {
      final audio = tts.generate(text: msg.text, sid: 0, speed: init.speed);
      final wav = buildWavPcm16Mono(floatToPcm16(audio.samples), audio.sampleRate);
      boot.reply.send(_WorkerOk(msg.id, wav));
    } on Object catch (e) {
      boot.reply.send(_WorkerErr(msg.id, e.toString()));
    }
  });
}

sherpa.OfflineTtsModelConfig _buildModelConfig(_WorkerInit i) {
  final family = SherpaFamily.values[i.family];
  return switch (family) {
    SherpaFamily.vits => sherpa.OfflineTtsModelConfig(
        vits: sherpa.OfflineTtsVitsModelConfig(
            model: i.model, tokens: i.tokens, dataDir: i.dataDir),
        numThreads: i.numThreads,
        debug: false,
      ),
    SherpaFamily.kokoro => sherpa.OfflineTtsModelConfig(
        kokoro: sherpa.OfflineTtsKokoroModelConfig(
            model: i.model,
            voices: i.voices,
            tokens: i.tokens,
            dataDir: i.dataDir,
            lexicon: i.lexicon,
            lang: i.lang),
        numThreads: i.numThreads,
        debug: false,
      ),
    SherpaFamily.matcha => sherpa.OfflineTtsModelConfig(
        matcha: sherpa.OfflineTtsMatchaModelConfig(
            acousticModel: i.model,
            vocoder: i.vocoder,
            tokens: i.tokens,
            dataDir: i.dataDir),
        numThreads: i.numThreads,
        debug: false,
      ),
    SherpaFamily.kitten => sherpa.OfflineTtsModelConfig(
        kitten: sherpa.OfflineTtsKittenModelConfig(
            model: i.model,
            voices: i.voices,
            tokens: i.tokens,
            dataDir: i.dataDir),
        numThreads: i.numThreads,
        debug: false,
      ),
  };
}
