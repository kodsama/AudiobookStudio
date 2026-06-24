/// Step 4: the primary Convert / Cancel action with a readiness hint.
library;

import 'package:flutter/material.dart';

import '../../domain/progress.dart';
import '../../logic/app_controller.dart';
import '../theme.dart';
import 'section_card.dart';

/// The prominent call to action. Enabled only when [AppController.canConvert];
/// swaps to a Cancel button while a run is in flight.
class ConvertBar extends StatelessWidget {
  final AppController controller;
  final bool expanded;
  final VoidCallback? onToggle;
  final bool done;
  const ConvertBar({
    super.key,
    required this.controller,
    this.expanded = true,
    this.onToggle,
    this.done = false,
  });

  @override
  Widget build(BuildContext context) {
    final converting = controller.isConverting;
    return SectionCard(
      step: 4,
      title: 'Create the audiobook',
      dimmed: controller.book == null,
      expanded: expanded,
      onToggle: onToggle,
      done: done,
      child: Row(
        children: [
          if (converting)
            FilledButton.icon(
              key: const Key('cancel-button'),
              style: FilledButton.styleFrom(backgroundColor: AppTokens.rust),
              onPressed: controller.cancel,
              icon: const Icon(Icons.stop_rounded, size: 18),
              label: const Text('Cancel'),
            )
          else
            FilledButton.icon(
              key: const Key('convert-button'),
              onPressed: controller.canConvert ? controller.startConversion : null,
              icon: const Icon(Icons.graphic_eq_rounded, size: 18),
              label: const Text('Convert to M4B'),
            ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              _hint(controller),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }

  String _hint(AppController c) {
    if (c.isConverting) return 'Converting… you can cancel and resume later.';
    if (c.progress.phase == ConvPhase.done) return 'Finished. Saved to ${c.options?.outputPath}.';
    if (c.canConvert) return 'Ready when you are.';
    if (c.book == null) return 'Choose an EPUB to begin.';
    if (c.options?.selectedChapterIndices.isEmpty ?? true) {
      return 'Select at least one chapter.';
    }
    final o = c.options!;
    if (o.backend.isCloud && (o.apiKeys[o.backend.name] ?? '').trim().isEmpty) {
      return 'Enter your ${o.backend.label} API key to enable conversion.';
    }
    if (!c.selectedBackendReady) {
      return '${o.backend.label} isn\'t installed yet — install it in the '
          'toolkit step, or pick another engine.';
    }
    return 'Almost there.';
  }
}
