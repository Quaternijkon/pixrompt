import 'package:flutter/material.dart';

import '../app/pixrompt_controller.dart';
import '../platform/pixrompt_file_actions.dart';
import 'pixrompt_design.dart';

class SettingsSheet extends StatelessWidget {
  const SettingsSheet({
    super.key,
    required this.controller,
    required this.fileActions,
  });

  final PixromptController controller;
  final PixromptFileActions fileActions;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final state = controller.state;
        return PixromptSheetFrame(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Text(
                    '\u8bbe\u7f6e',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const Spacer(),
                  _Metric(
                    label: '\u56fe\u7247',
                    value: '${state.allImages.length}',
                  ),
                  const SizedBox(width: PixromptSpace.md),
                  _Metric(
                    label: '\u5206\u7c7b\u7ef4\u5ea6',
                    value: '${state.categoryDimensions.length}',
                  ),
                ],
              ),
              const SizedBox(height: PixromptSpace.xl),
              Text('\u6570\u636e',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: PixromptSpace.sm),
              DecoratedBox(
                decoration: pixromptSurfaceDecoration(
                  color: PixromptPalette.darkSurfaceHigh.withOpacity(0.46),
                  radius: PixromptRadius.lg,
                  elevated: false,
                ),
                child: Padding(
                  padding: const EdgeInsets.all(PixromptSpace.sm),
                  child: Wrap(
                    spacing: PixromptSpace.sm,
                    runSpacing: PixromptSpace.sm,
                    children: [
                      FilledButton.tonalIcon(
                        onPressed: () => _exportBackup(context),
                        icon: const Icon(Icons.ios_share),
                        label: const Text('\u5bfc\u51fa'),
                      ),
                      FilledButton.tonalIcon(
                        onPressed: () => _importBackup(context),
                        icon: const Icon(Icons.file_open_outlined),
                        label: const Text('\u5bfc\u5165'),
                      ),
                      FilledButton.tonalIcon(
                        onPressed: () => _cleanup(context),
                        icon: const Icon(Icons.cleaning_services_outlined),
                        label: const Text('\u6e05\u7406'),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _exportBackup(BuildContext context) async {
    final jsonText = await controller.exportBackupJson();
    await fileActions.saveBackupJson(jsonText);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('\u5df2\u5bfc\u51fa\u3002')),
    );
  }

  Future<void> _importBackup(BuildContext context) async {
    final jsonText = await fileActions.pickBackupJson();
    if (jsonText == null) return;
    await controller.importBackupJson(jsonText);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('\u5df2\u5bfc\u5165\u3002')),
    );
  }

  Future<void> _cleanup(BuildContext context) async {
    final count = await controller.cleanupOrphanedImageBytes();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '\u5df2\u6e05\u7406 $count \u4e2a\u5b64\u7acb\u56fe\u7247\u3002',
        ),
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: PixromptPalette.darkSurfaceHigh.withOpacity(0.52),
        borderRadius: BorderRadius.circular(PixromptRadius.sm),
        border: Border.all(color: PixromptPalette.darkOutline),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(label, style: Theme.of(context).textTheme.labelSmall),
            Text(value, style: Theme.of(context).textTheme.titleMedium),
          ],
        ),
      ),
    );
  }
}
