/// Downloads and installs the Piper binary and voices on demand.
///
/// Piper ships as a self-contained release archive (binary + bundled
/// onnxruntime + espeak-ng data) on GitHub, and voices are `.onnx`/`.onnx.json`
/// pairs on Hugging Face. This makes the free local engine turnkey: no manual
/// install, no Python. Pure URL/path helpers are separated from IO so they can
/// be unit-tested.
library;

import 'dart:ffi' show Abi;
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

/// Pins the Piper release used for binary downloads.
const String kPiperReleaseTag = '2023.11.14-2';

/// Manages the on-disk Piper binary and voices under a models directory.
class PiperInstaller {
  /// Root models directory (e.g. app support dir + `/models`).
  final String modelsDir;

  /// HTTP client used for downloads.
  final http.Client client;

  /// ABI used to choose the release asset (overridable for tests).
  final Abi abi;

  PiperInstaller({
    required this.modelsDir,
    required this.client,
    Abi? abi,
  }) : abi = abi ?? Abi.current();

  /// Directory holding the extracted binary and downloaded voices.
  String get piperDir => p.join(modelsDir, 'piper');

  /// Absolute path of the piper executable.
  String get binaryPath =>
      p.join(piperDir, Platform.isWindows ? 'piper.exe' : 'piper');

  /// Absolute path of a voice's `.onnx` model.
  String voicePath(String voiceId) => p.join(piperDir, '$voiceId.onnx');

  /// Absolute path of a voice's `.onnx.json` config.
  String voiceConfigPath(String voiceId) => '${voicePath(voiceId)}.json';

  /// Whether the piper binary is installed.
  bool isBinaryInstalled() => File(binaryPath).existsSync();

  /// Whether a specific voice (model + config) is installed.
  bool isVoiceInstalled(String voiceId) =>
      File(voicePath(voiceId)).existsSync() &&
      File(voiceConfigPath(voiceId)).existsSync();

  /// Whether any voice has been downloaded.
  bool hasAnyVoice() {
    final dir = Directory(piperDir);
    return dir.existsSync() &&
        dir.listSync().any((e) => e.path.endsWith('.onnx'));
  }

  // --- pure URL helpers ---

  /// Whether a *working* standalone Piper binary can be auto-downloaded for
  /// [abi]. Upstream's macOS release assets are broken (the "aarch64" asset
  /// actually contains an x86_64 binary and omits the bundled dylibs), and the
  /// maintained fork ships Python wheels only — so auto-install is limited to
  /// Linux and Windows, where the release binaries are self-contained and work.
  static bool autoInstallSupportedFor(Abi abi) => switch (abi) {
        Abi.linuxX64 || Abi.linuxArm64 || Abi.windowsX64 => true,
        _ => false,
      };

  /// Whether auto-install is supported on this installer's platform.
  bool get autoInstallSupported => autoInstallSupportedFor(abi);

  /// Release asset filename for [abi].
  static String assetName(Abi abi) => switch (abi) {
        Abi.macosArm64 => 'piper_macos_aarch64.tar.gz',
        Abi.macosX64 => 'piper_macos_x64.tar.gz',
        Abi.linuxX64 => 'piper_linux_x86_64.tar.gz',
        Abi.linuxArm64 => 'piper_linux_aarch64.tar.gz',
        Abi.windowsX64 => 'piper_windows_amd64.zip',
        _ => throw UnsupportedError('No Piper release for ABI $abi'),
      };

  /// GitHub release download URL for [abi].
  static String releaseUrl(Abi abi) =>
      'https://github.com/rhasspy/piper/releases/download/$kPiperReleaseTag/${assetName(abi)}';

  /// Hugging Face URLs (`.onnx`, `.onnx.json`) for a `<locale>-<name>-<quality>`
  /// voice id, e.g. `fr_FR-siwis-medium`.
  static (String onnx, String config) voiceUrls(String voiceId) {
    final parts = voiceId.split('-');
    if (parts.length != 3) {
      throw FormatException('Unexpected Piper voice id: $voiceId');
    }
    final locale = parts[0]; // fr_FR
    final name = parts[1]; // siwis
    final quality = parts[2]; // medium
    final lang = locale.split('_').first; // fr
    const base =
        'https://huggingface.co/rhasspy/piper-voices/resolve/main';
    final onnx = '$base/$lang/$locale/$name/$quality/$voiceId.onnx';
    return (onnx, '$onnx.json');
  }

  // --- install actions (stream progress lines) ---

  /// Ensures the binary and [voiceId] are installed, downloading what's missing.
  Stream<String> ensureInstalled(String voiceId) async* {
    if (!isBinaryInstalled()) {
      yield* _installBinary();
    } else {
      yield 'Piper engine already installed.';
    }
    if (!isVoiceInstalled(voiceId)) {
      yield* _installVoice(voiceId);
    } else {
      yield 'Voice $voiceId already installed.';
    }
    yield 'Piper is ready.';
  }

  Stream<String> _installBinary() async* {
    final url = releaseUrl(abi);
    yield 'Downloading Piper engine ($url)…';
    final bytes = await _download(url);
    yield 'Extracting Piper engine…';
    final isZip = url.endsWith('.zip');
    final archive = isZip
        ? ZipDecoder().decodeBytes(bytes)
        : TarDecoder().decodeBytes(GZipDecoder().decodeBytes(bytes));
    Directory(modelsDir).createSync(recursive: true);
    for (final entry in archive) {
      if (!entry.isFile) continue;
      final out = File(p.join(modelsDir, entry.name));
      out.parent.createSync(recursive: true);
      out.writeAsBytesSync(entry.content as List<int>);
    }
    if (!Platform.isWindows) {
      await Process.run('chmod', ['+x', binaryPath]);
    }
    yield 'Piper engine installed.';
  }

  Stream<String> _installVoice(String voiceId) async* {
    final (onnxUrl, configUrl) = voiceUrls(voiceId);
    Directory(piperDir).createSync(recursive: true);
    yield 'Downloading voice $voiceId (~60 MB)…';
    File(voicePath(voiceId)).writeAsBytesSync(await _download(onnxUrl));
    File(voiceConfigPath(voiceId)).writeAsBytesSync(await _download(configUrl));
    yield 'Voice $voiceId installed.';
  }

  Future<Uint8List> _download(String url) async {
    final resp = await client.get(Uri.parse(url));
    if (resp.statusCode != 200) {
      throw HttpException('Download failed (${resp.statusCode}): $url');
    }
    return resp.bodyBytes;
  }
}
