/// Cloud-engine voice catalog (OpenAI / ElevenLabs).
///
/// Local voices live in `sherpa_catalog.dart`; this covers the cloud backends,
/// whose voices are language-agnostic (multilingual models).
library;

import '../../domain/conversion_options.dart';
import '../../domain/voice.dart';

/// Lookups for cloud-engine voices.
class VoiceCatalog {
  /// Human labels for language codes used across the app.
  static const Map<String, String> languageLabels = {
    'fr': 'Français',
    'en': 'English',
    'es': 'Español',
    'de': 'Deutsch',
    'it': 'Italiano',
    'pt': 'Português',
  };

  static const List<Voice> _cloud = [
    Voice(id: 'alloy', label: 'Alloy', languageCode: '*', backend: TtsBackendKind.openai),
    Voice(id: 'nova', label: 'Nova', languageCode: '*', backend: TtsBackendKind.openai),
    Voice(id: 'shimmer', label: 'Shimmer', languageCode: '*', backend: TtsBackendKind.openai),
    Voice(id: 'EXAVITQu4vr4xnSDxMaL', label: 'Sarah (multilingual)', languageCode: '*', backend: TtsBackendKind.elevenlabs),
  ];

  /// Languages offered for cloud engines (multilingual models cover these).
  static List<Language> languages(TtsBackendKind backend) => [
        for (final e in languageLabels.entries) Language(e.key, e.value),
      ];

  /// Cloud voices for [backend] (language-agnostic).
  static List<Voice> voices(TtsBackendKind backend, String languageCode) =>
      _cloud.where((v) => v.backend == backend).toList();

  /// The default cloud voice id for [backend], or empty.
  static String defaultVoiceId(TtsBackendKind backend, String languageCode) {
    final vs = voices(backend, languageCode);
    return vs.isEmpty ? '' : vs.first.id;
  }
}
