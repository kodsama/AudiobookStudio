import 'dart:ffi' show Abi;
import 'dart:io';

import 'package:audiobook_studio/data/deps/piper_installer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

void main() {
  final client = MockClient((_) async => http.Response('', 200));

  group('release assets', () {
    test('maps ABI to the correct release asset', () {
      expect(PiperInstaller.assetName(Abi.linuxX64), 'piper_linux_x86_64.tar.gz');
      expect(PiperInstaller.assetName(Abi.linuxArm64), 'piper_linux_aarch64.tar.gz');
      expect(PiperInstaller.assetName(Abi.windowsX64), 'piper_windows_amd64.zip');
      expect(PiperInstaller.assetName(Abi.macosArm64), 'piper_macos_aarch64.tar.gz');
    });

    test('release URL includes the pinned tag', () {
      final url = PiperInstaller.releaseUrl(Abi.linuxX64);
      expect(url, contains(kPiperReleaseTag));
      expect(url, endsWith('piper_linux_x86_64.tar.gz'));
    });
  });

  group('voice URLs', () {
    test('builds Hugging Face paths from a voice id', () {
      final (onnx, config) = PiperInstaller.voiceUrls('fr_FR-siwis-medium');
      expect(onnx,
          'https://huggingface.co/rhasspy/piper-voices/resolve/main/fr/fr_FR/siwis/medium/fr_FR-siwis-medium.onnx');
      expect(config, '$onnx.json');
    });

    test('rejects a malformed voice id', () {
      expect(() => PiperInstaller.voiceUrls('weird'), throwsFormatException);
    });
  });

  group('auto-install support', () {
    test('enabled on Linux/Windows, disabled on macOS (broken upstream)', () {
      expect(PiperInstaller.autoInstallSupportedFor(Abi.linuxX64), isTrue);
      expect(PiperInstaller.autoInstallSupportedFor(Abi.windowsX64), isTrue);
      expect(PiperInstaller.autoInstallSupportedFor(Abi.macosArm64), isFalse);
      expect(PiperInstaller.autoInstallSupportedFor(Abi.macosX64), isFalse);
    });
  });

  group('install-state detection', () {
    test('reflects files on disk', () {
      final tmp = Directory.systemTemp.createTempSync('piper_');
      final piper = PiperInstaller(modelsDir: tmp.path, client: client);
      expect(piper.isBinaryInstalled(), isFalse);
      expect(piper.isVoiceInstalled('fr_FR-siwis-medium'), isFalse);

      Directory(piper.piperDir).createSync(recursive: true);
      File(piper.binaryPath).writeAsBytesSync(const [0]);
      File(piper.voicePath('fr_FR-siwis-medium')).writeAsBytesSync(const [0]);
      File(piper.voiceConfigPath('fr_FR-siwis-medium')).writeAsStringSync('{}');

      expect(piper.isBinaryInstalled(), isTrue);
      expect(piper.isVoiceInstalled('fr_FR-siwis-medium'), isTrue);
      expect(piper.hasAnyVoice(), isTrue);
      expect(p.basename(piper.voicePath('x-y-z')), 'x-y-z.onnx');
      tmp.deleteSync(recursive: true);
    });
  });
}
