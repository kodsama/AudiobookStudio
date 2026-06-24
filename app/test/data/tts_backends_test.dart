import 'dart:io';
import 'dart:typed_data';

import 'package:audiobook_studio/data/audio/wav_writer.dart';
import 'package:audiobook_studio/data/deps/sherpa_model_installer.dart';
import 'package:audiobook_studio/data/process_runner.dart';
import 'package:audiobook_studio/data/tts/backend_factory.dart';
import 'package:audiobook_studio/data/tts/elevenlabs_backend.dart';
import 'package:audiobook_studio/data/tts/openai_backend.dart';
import 'package:audiobook_studio/data/tts/sherpa_catalog.dart';
import 'package:audiobook_studio/data/tts/sherpa_tts_backend.dart';
import 'package:audiobook_studio/domain/book.dart';
import 'package:audiobook_studio/domain/conversion_options.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path/path.dart' as p;

class RecordingRunner extends ProcessRunner {
  @override
  Future<ProcessRunResult> run(String e, List<String> a, {String? stdinText}) async =>
      const ProcessRunResult(0, '', '');
  @override
  Stream<String> stream(String e, List<String> a, {String? stdinText}) =>
      const Stream.empty();
}

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('tts_test_'));
  tearDown(() => tmp.deleteSync(recursive: true));

  group('OpenAiBackend', () {
    test('POSTs model/voice/input and writes the WAV body', () async {
      late http.Request captured;
      final client = MockClient((req) async {
        captured = req;
        return http.Response.bytes(Uint8List.fromList([1, 2, 3]), 200);
      });
      final out = p.join(tmp.path, 'o.wav');
      await OpenAiBackend(client: client, apiKey: 'sk-x', voice: 'nova')
          .synth('Hello', out);

      expect(captured.method, 'POST');
      expect(captured.headers['Authorization'], 'Bearer sk-x');
      expect(captured.body, contains('"voice":"nova"'));
      expect(captured.body, contains('"input":"Hello"'));
      expect(File(out).readAsBytesSync(), [1, 2, 3]);
    });

    test('throws on non-200', () async {
      final client = MockClient((req) async => http.Response('nope', 401));
      expect(
        () => OpenAiBackend(client: client, apiKey: 'bad')
            .synth('x', p.join(tmp.path, 'o.wav')),
        throwsA(isA<HttpException>()),
      );
    });
  });

  group('ElevenLabsBackend', () {
    test('wraps returned PCM into a valid WAV header', () async {
      final pcm = Uint8List.fromList(List<int>.filled(8, 7));
      final client = MockClient((req) async {
        expect(req.url.path, contains('voice-123'));
        expect(req.headers['xi-api-key'], 'el-key');
        return http.Response.bytes(pcm, 200);
      });
      final out = p.join(tmp.path, 'o.wav');
      await ElevenLabsBackend(client: client, apiKey: 'el-key', voiceId: 'voice-123')
          .synth('Salut', out);

      final bytes = File(out).readAsBytesSync();
      expect(String.fromCharCodes(bytes.sublist(0, 4)), 'RIFF');
      expect(String.fromCharCodes(bytes.sublist(8, 12)), 'WAVE');
      expect(bytes.length, 44 + pcm.length);
    });
  });

  group('buildWavPcm16Mono', () {
    test('produces a 44-byte header and correct data size', () {
      final pcm = Uint8List.fromList(List<int>.filled(100, 0));
      final wav = buildWavPcm16Mono(pcm, 22050);
      expect(wav.length, 44 + 100);
      expect(String.fromCharCodes(wav.sublist(0, 4)), 'RIFF');
    });
  });

  group('makeBackend', () {
    Book b() => const Book(title: 't', author: 'a', languageCode: 'fr', chapters: [
          Chapter(index: 0, title: 'c', text: 'hello world this is text'),
        ]);
    ConversionOptions o(TtsBackendKind k, String voiceId) =>
        ConversionOptions.defaults(b(), outputPath: '/o.m4b', workDir: '/w')
            .copyWith(backend: k, voiceId: voiceId, apiKeys: {
          'openai': 'key',
          'elevenlabs': 'key',
        });

    test('returns the right backend per engine kind', () {
      final runner = RecordingRunner();
      final client = MockClient((_) async => http.Response('', 200));
      final sherpa = SherpaModelInstaller(modelsDir: '/m', client: client);
      expect(
          makeBackend(o(TtsBackendKind.local, kSherpaModels.first.id),
              runner: runner, httpClient: client, sherpa: sherpa),
          isA<SherpaTtsBackend>());
      expect(
          makeBackend(o(TtsBackendKind.openai, 'nova'),
              runner: runner, httpClient: client, sherpa: sherpa),
          isA<OpenAiBackend>());
      expect(
          makeBackend(o(TtsBackendKind.elevenlabs, 'v'),
              runner: runner, httpClient: client, sherpa: sherpa),
          isA<ElevenLabsBackend>());
    });

    test('local engine throws for an unknown model id', () {
      final runner = RecordingRunner();
      final client = MockClient((_) async => http.Response('', 200));
      final sherpa = SherpaModelInstaller(modelsDir: '/m', client: client);
      expect(
        () => makeBackend(o(TtsBackendKind.local, 'nope'),
            runner: runner, httpClient: client, sherpa: sherpa),
        throwsStateError,
      );
    });
  });
}
