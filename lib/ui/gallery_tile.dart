import 'package:flutter/material.dart';

import '../app/pixrompt_controller.dart';
import '../domain/category_dimension.dart';
import '../domain/prompt_image.dart';
import 'stored_image.dart';

class GalleryTile extends StatelessWidget {
  const GalleryTile({
    super.key,
    required this.controller,
    required this.image,
    required this.onTap,
    required this.onLongPress,
    this.selected = false,
    this.selectionMode = false,
  });

  final PixromptController controller;
  final PromptImageItem image;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final bool selected;
  final bool selectionMode;

  @override
  Widget build(BuildContext context) {
    final ratio = image.aspectRatio.isFinite && image.aspectRatio > 0
        ? image.aspectRatio
        : 1.0;
    return Semantics(
      key: ValueKey('gallery.tile.${image.uid}'),
      label: _semanticLabel,
      button: true,
      selected: selectionMode ? selected : null,
      onTap: onTap,
      onLongPress: onLongPress,
      child: Material(
        color: Colors.transparent,
        clipBehavior: Clip.hardEdge,
        child: InkWell(
          excludeFromSemantics: true,
          splashColor: Colors.white.withOpacity(0.18),
          highlightColor: Colors.white.withOpacity(0.10),
          focusColor: Colors.white.withOpacity(0.14),
          hoverColor: Colors.white.withOpacity(0.08),
          onTap: onTap,
          onLongPress: onLongPress,
          child: AspectRatio(
            aspectRatio: ratio,
            child: Stack(
              fit: StackFit.expand,
              children: [
                StoredImage(
                  loader: controller.imageBytes(image.imageKey),
                  fit: BoxFit.contain,
                  backgroundColor: Colors.black,
                ),
                if (selectionMode)
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: selected
                            ? Colors.black.withOpacity(0.38)
                            : Colors.black.withOpacity(0.12),
                      ),
                    ),
                  ),
                if (selectionMode)
                  Positioned(
                    right: 8,
                    top: 8,
                    child: Icon(
                      selected
                          ? Icons.check_circle
                          : Icons.radio_button_unchecked,
                      color: Colors.white,
                      shadows: const [
                        Shadow(color: Colors.black87, blurRadius: 8),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String get _semanticLabel {
    final action = selectionMode
        ? selected
            ? '已选择，切换选择'
            : '未选择，切换选择'
        : '打开图片';
    final prompt = image.prompt.trim();
    final fileName = image.originalFileName?.trim();
    final categories = <String>{
      for (final category in image.categoryAssignments.values)
        if (_meaningfulCategory(category)) category.trim(),
      if (_meaningfulCategory(image.category)) image.category.trim(),
    }.toList(growable: false);
    return [
      action,
      if (prompt.isNotEmpty) 'Prompt：$prompt',
      if (fileName != null && fileName.isNotEmpty) '文件：$fileName',
      if (categories.isNotEmpty) '分类：${categories.join('、')}',
    ].join('，');
  }

  bool _meaningfulCategory(String category) {
    final value = category.trim();
    return value.isNotEmpty && value != uncategorizedCategory;
  }
}
