/// Step 2: verify required tools are installed, with one-click install.
library;

import 'package:flutter/material.dart';

import '../../domain/dependency.dart';
import '../../logic/app_controller.dart';
import '../theme.dart';
import 'section_card.dart';

/// Shows the dependency statuses for the selected backend and offers to install
/// missing system packages.
class DependencyCard extends StatelessWidget {
  final AppController controller;
  const DependencyCard({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    final deps = controller.deps;
    final missing = controller.missingDeps;
    final allOk = controller.depsChecked && missing.isEmpty;

    return SectionCard(
      step: 2,
      title: 'Check your toolkit',
      subtitle: 'Tools the selected engine needs',
      dimmed: controller.book == null,
      trailing: !controller.depsChecked
          ? null
          : allOk
              ? const StatusPill('All set', icon: Icons.check_rounded)
              : StatusPill('${missing.length} missing',
                  color: AppTokens.rust, icon: Icons.error_outline_rounded),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!controller.depsChecked)
            const Text('Load a book to check dependencies.',
                style: TextStyle(color: AppTokens.muted))
          else
            ...deps.map((d) => _DepRow(d)),
          if (missing.any((d) => d.kind.isSystemPackage)) ...[
            const SizedBox(height: 14),
            Row(
              children: [
                FilledButton.icon(
                  onPressed: controller.installing ? null : controller.installMissing,
                  icon: controller.installing
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: AppTokens.ink))
                      : const Icon(Icons.download_rounded, size: 18),
                  label: Text(controller.installing
                      ? 'Installing…'
                      : 'Install missing packages'),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Runs your system package manager. Watch the log below.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _DepRow extends StatelessWidget {
  final DependencyStatus dep;
  const _DepRow(this.dep);

  @override
  Widget build(BuildContext context) {
    final ok = dep.found;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Icon(
            ok ? Icons.check_circle_rounded : Icons.cancel_rounded,
            size: 18,
            color: ok ? AppTokens.sage : AppTokens.rust,
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 110,
            child: Text(dep.kind.label,
                style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
          Expanded(
            child: Text(
              ok
                  ? (dep.version ?? dep.location ?? 'found')
                  : (dep.installHint ?? 'missing'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}
