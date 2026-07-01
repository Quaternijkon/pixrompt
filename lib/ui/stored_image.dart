import 'dart:typed_data';

import 'package:flutter/material.dart';

class StoredImage extends StatelessWidget {
  const StoredImage({
    super.key,
    required this.loader,
    this.fit = BoxFit.cover,
    this.backgroundColor = const Color(0xFF111111),
  });

  final Future<Uint8List?> loader;
  final BoxFit fit;
  final Color backgroundColor;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Uint8List?>(
      future: loader,
      builder: (context, snapshot) {
        final bytes = snapshot.data;
        if (bytes == null || bytes.isEmpty) {
          return ImageFallback(backgroundColor: backgroundColor);
        }
        return ExcludeSemantics(
          child: Image.memory(
            bytes,
            fit: fit,
            gaplessPlayback: true,
            errorBuilder: (context, error, stackTrace) {
              return ImageFallback(backgroundColor: backgroundColor);
            },
          ),
        );
      },
    );
  }
}

class ImageFallback extends StatelessWidget {
  const ImageFallback({
    super.key,
    this.backgroundColor = const Color(0xFF111111),
  });

  final Color backgroundColor;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: ColoredBox(
        color: backgroundColor,
        child: const Center(
          child: Icon(
            Icons.image_not_supported_outlined,
            color: Colors.white38,
          ),
        ),
      ),
    );
  }
}
