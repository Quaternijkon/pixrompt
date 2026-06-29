import 'package:flutter/material.dart';

import '../app/pixrompt_controller.dart';
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
    return GestureDetector(
      key: ValueKey('gallery.tile.${image.uid}'),
      behavior: HitTestBehavior.opaque,
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
                  selected ? Icons.check_circle : Icons.radio_button_unchecked,
                  color: Colors.white,
                  shadows: const [
                    Shadow(color: Colors.black87, blurRadius: 8),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
