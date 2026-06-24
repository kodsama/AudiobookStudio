// Verifies sherpa-onnx TTS runs via the worker-isolate backend on macOS,
// producing French audio. Requires the Piper model pre-downloaded to the
// scratchpad models dir (the CLI e2e leaves it there).
//
// Run with: flutter test integration_test/sherpa_tts_test.dart -d macos
import 'dart:io';

import 'package:audiobook_studio/data/deps/sherpa_model_installer.dart';
import 'package:audiobook_studio/data/tts/sherpa_catalog.dart';
import 'package:audiobook_studio/data/tts/sherpa_tts_backend.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:integration_test/integration_test.dart';

const _modelsDir =
    '/private/tmp/claude-501/-Users-alexandremartins-Developer-EpubToM4b/7496ede6-f7e9-479b-a9fc-f27224df3676/scratchpad/climodels';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('SherpaTtsBackend synthesizes French audio via a worker isolate',
      (tester) async {
    final installer =
        SherpaModelInstaller(modelsDir: _modelsDir, client: http.Client());
    final model = sherpaModelById('piper')!;
    if (!installer.isInstalled(model)) {
      markTestSkipped('piper model not downloaded to $_modelsDir');
      return;
    }
    final backend = SherpaTtsBackend(
        model: model, languageCode: 'fr', installer: installer);
    final out = '$_modelsDir/../sherpa_backend_test.wav';
    await backend.synth('Bonjour, ceci est un test.', out);
    await backend.dispose();

    final f = File(out);
    expect(f.existsSync(), isTrue);
    expect(f.lengthSync(), greaterThan(44 + 22050)); // > ~0.5s of 22kHz audio
  });
}
