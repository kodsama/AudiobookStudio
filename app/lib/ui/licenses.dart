/// A curated licenses page: the app's own license plus the notable attached
/// software (one entry per component — not the per-package/per-file dump that
/// Flutter's default license page produces).
library;

import 'package:flutter/material.dart';

import 'theme.dart';

const _gpl = '''Audiobook Studio
Copyright (C) 2026 Kodsama

This program is free software: you can redistribute it and/or modify it under
the terms of the GNU General Public License as published by the Free Software
Foundation, either version 3 of the License, or (at your option) any later
version.

This program is distributed in the hope that it will be useful, but WITHOUT ANY
WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A
PARTICULAR PURPOSE. See the GNU General Public License for more details.

Full text: https://github.com/kodsama/AudiobookStudio/blob/main/LICENSE''';

/// One attached component (deduplicated — listed once even if pulled in by
/// several packages).
class _Component {
  final String name;
  final String license;
  final String role;
  const _Component(this.name, this.license, this.role);
}

const _attached = <_Component>[
  _Component('ffmpeg / ffmpeg-kit', 'LGPL-3.0 (with GPL parts)',
      'Audio assembly & the .m4b muxer'),
  _Component(
      'sherpa-onnx', 'Apache-2.0', 'Offline text-to-speech (Piper, Kokoro, …)'),
  _Component('ONNX Runtime', 'MIT', 'Neural-network inference for the TTS models'),
  _Component('espeak-ng', 'GPL-3.0', 'Phonemization for the TTS engines'),
  _Component('Flutter & Dart', 'BSD-3-Clause', 'App framework and language'),
  _Component('file_picker · path_provider · share_plus', 'BSD/MIT',
      'File selection, app storage, sharing'),
  _Component('archive · xml · html', 'Apache-2.0 / MIT', 'EPUB parsing'),
  _Component('http · crypto · google_fonts', 'BSD/MIT',
      'Cloud TTS, checksums, typography'),
];

/// Opens the curated licenses page.
void showAppLicenses(BuildContext context) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(builder: (_) => const LicensesPage()),
  );
}

/// Scrollable licenses screen.
class LicensesPage extends StatelessWidget {
  const LicensesPage({super.key});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Licenses')),
      body: ListView(
        padding: const EdgeInsets.all(AppTokens.pad),
        children: [
          Text('Audiobook Studio', style: text.headlineSmall),
          const SizedBox(height: 4),
          Text('Licensed under GPL-3.0', style: text.bodySmall),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppTokens.surfaceHigh,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTokens.line),
            ),
            child: SelectableText(_gpl,
                style: text.bodySmall?.copyWith(height: 1.5)),
          ),
          const SizedBox(height: 24),
          Text('Attached software', style: text.titleLarge),
          const SizedBox(height: 4),
          Text(
            'The libraries and tools Audiobook Studio bundles or builds on — '
            'listed once each, by component.',
            style: text.bodySmall,
          ),
          const SizedBox(height: 12),
          for (final c in _attached)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.circle, size: 7, color: AppTokens.amber),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                                child: Text(c.name,
                                    style: text.titleMedium)),
                            Text(c.license,
                                style: text.bodySmall
                                    ?.copyWith(color: AppTokens.amberBright)),
                          ],
                        ),
                        Text(c.role, style: text.bodySmall),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 16),
          Text(
            'Downloaded TTS model weights carry their own licenses (Meta MMS '
            'voices are CC-BY-NC / non-commercial). Full third-party texts: '
            'github.com/kodsama/AudiobookStudio/blob/main/THIRD_PARTY_LICENSES.md',
            style: text.bodySmall,
          ),
        ],
      ),
    );
  }
}
