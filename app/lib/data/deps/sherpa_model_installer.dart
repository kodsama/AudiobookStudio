/// Downloads and extracts sherpa-onnx TTS model archives on demand.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import '../tts/sherpa_catalog.dart';

/// Resolves model file paths under a models dir and downloads/extracts the
/// `.tar.bz2` archives (plus any separate Matcha vocoder).
class SherpaModelInstaller {
  /// Root models directory.
  final String modelsDir;

  /// HTTP client for downloads.
  final http.Client client;

  SherpaModelInstaller({required this.modelsDir, required this.client});

  /// Directory holding all sherpa models.
  String get root => p.join(modelsDir, 'sherpa');

  /// The extracted directory for [model].
  String dirOf(SherpaModel model) => p.join(root, model.dirName);

  /// Absolute path to the main model file.
  String modelPath(SherpaModel model) => p.join(dirOf(model), model.modelFile);

  /// Absolute path to a relative file within the model dir.
  String fileIn(SherpaModel model, String relative) =>
      relative.isEmpty ? '' : p.join(dirOf(model), relative);

  /// Absolute vocoder path (Matcha), or '' if none.
  String vocoderPath(SherpaModel model) =>
      model.vocoderFile.isEmpty ? '' : p.join(dirOf(model), model.vocoderFile);

  /// Whether [model] (and its vocoder, if any) is fully downloaded.
  bool isInstalled(SherpaModel model) {
    if (!File(modelPath(model)).existsSync()) return false;
    if (model.vocoderFile.isNotEmpty && !File(vocoderPath(model)).existsSync()) {
      return false;
    }
    return true;
  }

  /// Downloads + extracts [model] (and vocoder) if missing, streaming progress.
  Stream<String> ensureInstalled(SherpaModel model) async* {
    Directory(root).createSync(recursive: true);
    if (File(modelPath(model)).existsSync()) {
      yield '${model.label} already installed.';
    } else {
      yield 'Downloading ${model.label} (~${model.sizeMb} MB)…';
      final bytes = await _download(model.archiveUrl);
      yield 'Extracting ${model.label}…';
      _extractTarBz2(bytes, root);
      yield '${model.label} installed.';
    }
    if (model.vocoderFile.isNotEmpty && !File(vocoderPath(model)).existsSync()) {
      yield 'Downloading vocoder…';
      final vb = await _download(model.vocoderUrl);
      File(vocoderPath(model)).writeAsBytesSync(vb);
      yield 'Vocoder installed.';
    }
    yield '${model.label} is ready.';
  }

  /// Extracts a `.tar.bz2` archive into [destDir].
  void _extractTarBz2(Uint8List bytes, String destDir) {
    final tar = BZip2Decoder().decodeBytes(bytes);
    final archive = TarDecoder().decodeBytes(tar);
    for (final entry in archive) {
      if (!entry.isFile) continue;
      final out = File(p.join(destDir, entry.name));
      out.parent.createSync(recursive: true);
      out.writeAsBytesSync(entry.content as List<int>);
    }
  }

  Future<Uint8List> _download(String url) async {
    final resp = await client.get(Uri.parse(url));
    if (resp.statusCode != 200) {
      throw HttpException('Download failed (${resp.statusCode}): $url');
    }
    return resp.bodyBytes;
  }
}
