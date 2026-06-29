import 'package:flutter/material.dart';

import '../app/pixrompt_controller.dart';
import '../domain/category_dimension.dart';
import 'pixrompt_design.dart';

Future<void> showCategoryAssignmentSheet(
  BuildContext context, {
  required PixromptController controller,
  required List<String> selectedImageUids,
}) {
  return showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    builder: (context) {
      return CategoryAssignmentSheet(
        controller: controller,
        selectedImageUids: selectedImageUids,
      );
    },
  );
}

class CategoryAssignmentSheet extends StatelessWidget {
  const CategoryAssignmentSheet({
    super.key,
    required this.controller,
    required this.selectedImageUids,
  });

  final PixromptController controller;
  final List<String> selectedImageUids;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        return PixromptSheetFrame(
          scrollable: false,
          child: ListView(
            shrinkWrap: true,
            children: [
              Text(
                '\u8bbe\u7f6e\u5206\u7c7b',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: PixromptSpace.lg),
              for (final dimension in controller.state.categoryDimensions)
                _DimensionPicker(
                  controller: controller,
                  selectedImageUids: selectedImageUids,
                  dimension: dimension,
                ),
            ],
          ),
        );
      },
    );
  }
}

class _DimensionPicker extends StatelessWidget {
  const _DimensionPicker({
    required this.controller,
    required this.selectedImageUids,
    required this.dimension,
  });

  final PixromptController controller;
  final List<String> selectedImageUids;
  final CategoryDimension dimension;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: PixromptSpace.lg),
      child: DecoratedBox(
        decoration: pixromptSurfaceDecoration(
          color: PixromptPalette.darkSurfaceHigh.withOpacity(0.44),
          radius: PixromptRadius.lg,
          elevated: false,
        ),
        child: Padding(
          padding: const EdgeInsets.all(PixromptSpace.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                dimension.name,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: PixromptSpace.md),
              Wrap(
                spacing: PixromptSpace.sm,
                runSpacing: PixromptSpace.sm,
                children: [
                  ActionChip(
                    label: const Text(uncategorizedCategory),
                    onPressed: () => _assign(context, uncategorizedCategory),
                  ),
                  for (final item in dimension.items)
                    ActionChip(
                      label: Text(item),
                      onPressed: () => _assign(context, item),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _assign(BuildContext context, String item) async {
    await controller.assignCategoryToImages(
      selectedImageUids,
      dimensionId: dimension.id,
      item: item,
    );
    if (context.mounted) Navigator.of(context).pop();
  }
}
