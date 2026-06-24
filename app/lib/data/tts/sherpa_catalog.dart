/// Catalog of local TTS models runnable via sherpa-onnx.
///
/// Each entry knows where to download its archive and how its files map onto a
/// sherpa `OfflineTtsModelConfig` (the family decides which sub-config is used).
/// Adding a model is a single entry here — the backend, installer and UI pick it
/// up automatically.
library;

/// Which sherpa model family an entry belongs to (selects the sub-config).
enum SherpaFamily { vits, kokoro, matcha, kitten }

/// A downloadable local TTS model.
class SherpaModel {
  /// Stable id (also the local folder name) used as the selected "voice".
  final String id;

  /// Human-readable label for the UI.
  final String label;

  /// Model family (drives the sherpa config).
  final SherpaFamily family;

  /// ISO 639-1 languages this model speaks.
  final List<String> languages;

  /// Output sample rate (Hz) — used for chapter concat before the first synth.
  final int sampleRate;

  /// Approximate download size, for the UI.
  final int sizeMb;

  /// Archive URL (`.tar.bz2`) of the model.
  final String archiveUrl;

  /// Extracted top-level folder name inside the archive.
  final String dirName;

  /// Main model file (relative to [dirName]). For Matcha this is the acoustic
  /// model.
  final String modelFile;

  /// Tokens file (relative to [dirName]).
  final String tokensFile;

  /// espeak-ng-data dir (relative), or '' if the model needs none (e.g. MMS).
  final String dataDir;

  /// Kokoro voices file (relative), or ''.
  final String voicesFile;

  /// Comma-separated lexicon files (relative), or ''.
  final String lexicon;

  /// Kokoro language hint, or ''.
  final String lang;

  /// Matcha vocoder archive URL, or '' for non-Matcha families.
  final String vocoderUrl;

  /// Matcha vocoder file name (after extraction), or ''.
  final String vocoderFile;

  const SherpaModel({
    required this.id,
    required this.label,
    required this.family,
    required this.languages,
    required this.sampleRate,
    required this.sizeMb,
    required this.archiveUrl,
    required this.dirName,
    required this.modelFile,
    required this.tokensFile,
    this.dataDir = '',
    this.voicesFile = '',
    this.lexicon = '',
    this.lang = '',
    this.vocoderUrl = '',
    this.vocoderFile = '',
  });
}

const String _rel =
    'https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models';
const String _voc =
    'https://github.com/k2-fsa/sherpa-onnx/releases/download/vocoder-models';

/// All known local models. Curated across the requested families, covering
/// French and English plus broad coverage via MMS and multilingual Kokoro.
const List<SherpaModel> kSherpaModels = [
  // --- VITS / Piper (verified end-to-end on macOS) ---
  SherpaModel(
    id: 'vits-piper-fr_FR-siwis-medium',
    label: 'Piper · Siwis (FR)',
    family: SherpaFamily.vits,
    languages: ['fr'],
    sampleRate: 22050,
    sizeMb: 64,
    archiveUrl: '$_rel/vits-piper-fr_FR-siwis-medium.tar.bz2',
    dirName: 'vits-piper-fr_FR-siwis-medium',
    modelFile: 'fr_FR-siwis-medium.onnx',
    tokensFile: 'tokens.txt',
    dataDir: 'espeak-ng-data',
  ),
  SherpaModel(
    id: 'vits-piper-en_US-amy-medium',
    label: 'Piper · Amy (EN-US)',
    family: SherpaFamily.vits,
    languages: ['en'],
    sampleRate: 22050,
    sizeMb: 64,
    archiveUrl: '$_rel/vits-piper-en_US-amy-medium.tar.bz2',
    dirName: 'vits-piper-en_US-amy-medium',
    modelFile: 'en_US-amy-medium.onnx',
    tokensFile: 'tokens.txt',
    dataDir: 'espeak-ng-data',
  ),

  // --- MMS (very broad language coverage; char tokenizer, no espeak data) ---
  SherpaModel(
    id: 'vits-mms-fra',
    label: 'MMS (FR)',
    family: SherpaFamily.vits,
    languages: ['fr'],
    sampleRate: 16000,
    sizeMb: 103,
    archiveUrl: '$_rel/vits-mms-fra.tar.bz2',
    dirName: 'vits-mms-fra',
    modelFile: 'model.onnx',
    tokensFile: 'tokens.txt',
  ),
  SherpaModel(
    id: 'vits-mms-eng',
    label: 'MMS (EN)',
    family: SherpaFamily.vits,
    languages: ['en'],
    sampleRate: 16000,
    sizeMb: 103,
    archiveUrl: '$_rel/vits-mms-eng.tar.bz2',
    dirName: 'vits-mms-eng',
    modelFile: 'model.onnx',
    tokensFile: 'tokens.txt',
  ),

  // --- Kokoro (multilingual, high quality) ---
  SherpaModel(
    id: 'kokoro-multi-lang-v1_0',
    label: 'Kokoro · multilingual',
    family: SherpaFamily.kokoro,
    languages: ['en', 'fr', 'zh', 'es', 'it', 'pt'],
    sampleRate: 24000,
    sizeMb: 380,
    archiveUrl: '$_rel/kokoro-multi-lang-v1_0.tar.bz2',
    dirName: 'kokoro-multi-lang-v1_0',
    modelFile: 'model.onnx',
    tokensFile: 'tokens.txt',
    dataDir: 'espeak-ng-data',
    voicesFile: 'voices.bin',
    lexicon: 'lexicon-us-en.txt,lexicon-zh.txt',
    lang: 'en-us',
  ),

  // --- Matcha (fast, high quality; needs a separate vocoder) ---
  SherpaModel(
    id: 'matcha-icefall-en_US-ljspeech',
    label: 'Matcha · LJSpeech (EN)',
    family: SherpaFamily.matcha,
    languages: ['en'],
    sampleRate: 22050,
    sizeMb: 73,
    archiveUrl: '$_rel/matcha-icefall-en_US-ljspeech.tar.bz2',
    dirName: 'matcha-icefall-en_US-ljspeech',
    modelFile: 'model-steps-3.onnx',
    tokensFile: 'tokens.txt',
    dataDir: 'espeak-ng-data',
    vocoderUrl: '$_voc/vocos-22khz-univ.onnx',
    vocoderFile: 'vocos-22khz-univ.onnx',
  ),

  // --- Kitten (newer compact family) ---
  SherpaModel(
    id: 'kitten-nano-en-v0_1-fp16',
    label: 'Kitten · nano (EN)',
    family: SherpaFamily.kitten,
    languages: ['en'],
    sampleRate: 24000,
    sizeMb: 25,
    archiveUrl: '$_rel/kitten-nano-en-v0_1-fp16.tar.bz2',
    dirName: 'kitten-nano-en-v0_1-fp16',
    modelFile: 'model.fp16.onnx',
    tokensFile: 'tokens.txt',
    dataDir: 'espeak-ng-data',
    voicesFile: 'voices.bin',
  ),
];

/// Models available for a given [languageCode].
List<SherpaModel> sherpaModelsFor(String languageCode) =>
    kSherpaModels.where((m) => m.languages.contains(languageCode)).toList();

/// Looks up a model by id, or null.
SherpaModel? sherpaModelById(String id) {
  for (final m in kSherpaModels) {
    if (m.id == id) return m;
  }
  return null;
}

/// The default local model id for a language (first available, else first overall).
String defaultSherpaModelId(String languageCode) {
  final forLang = sherpaModelsFor(languageCode);
  if (forLang.isNotEmpty) return forLang.first.id;
  return kSherpaModels.first.id;
}
