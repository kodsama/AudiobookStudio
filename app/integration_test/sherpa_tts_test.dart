// Make-or-break: verify sherpa-onnx builds and runs offline TTS on macOS,
// producing French audio from the VITS Piper model.
//
// Requires the model pre-extracted to the scratchpad path below.
// Run with: flutter test integration_test/sherpa_tts_test.dart -d macos
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

const _model =
    '/private/tmp/claude-501/-Users-alexandremartins-Developer-EpubToM4b/7496ede6-f7e9-479b-a9fc-f27224df3676/scratchpad/vits-piper-fr_FR-siwis-medium';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('sherpa-onnx synthesizes French audio (VITS) on macOS',
      (tester) async {
    if (!File('$_model/fr_FR-siwis-medium.onnx').existsSync()) {
      markTestSkipped('model not downloaded');
      return;
    }
    sherpa.initBindings();
    final tts = sherpa.OfflineTts(sherpa.OfflineTtsConfig(
      model: sherpa.OfflineTtsModelConfig(
        vits: sherpa.OfflineTtsVitsModelConfig(
          model: '$_model/fr_FR-siwis-medium.onnx',
          tokens: '$_model/tokens.txt',
          dataDir: '$_model/espeak-ng-data',
        ),
        numThreads: 2,
        debug: false,
      ),
    ));

    final audio = tts.generate(
        text: 'Bonjour, ceci est un test de synthèse vocale.', speed: 1.0);
    tts.free();

    expect(audio.sampleRate, greaterThan(0));
    expect(audio.samples.length, greaterThan(audio.sampleRate ~/ 2),
        reason: 'expected > ~0.5s of audio');
  });
}
