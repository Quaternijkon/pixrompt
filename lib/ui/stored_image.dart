import 'dart:typed_data';

import 'package:flutter/material.dart';

class StoredImage extends StatelessWidget {
  const StoredImage({
    super.key,
    required this.loader,
    this.fit = BoxFit.cover,
    this.backgroundColor = const Color(0xFF111111),
    this.fadeInDuration = const Duration(milliseconds: 180),
  });

  final Future<Uint8List?> loader;
  final BoxFit fit;
  final Color backgroundColor;
  final Duration fadeInDuration;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Uint8List?>(
      future: loader,
      builder: (context, snapshot) {
        final bytes = snapshot.data;
        if (bytes == null || bytes.isEmpty) {
          return ImageFallback(
            backgroundColor: backgroundColor,
            showIcon: snapshot.connectionState == ConnectionState.done,
          );
        }
        return ExcludeSemantics(
          child: _FadeInMemoryImage(
            bytes,
            fit: fit,
            backgroundColor: backgroundColor,
            fadeInDuration: fadeInDuration,
          ),
        );
      },
    );
  }
}

class _FadeInMemoryImage extends StatelessWidget {
  const _FadeInMemoryImage(
    this.bytes, {
    required this.fit,
    required this.backgroundColor,
    required this.fadeInDuration,
  });

  final Uint8List bytes;
  final BoxFit fit;
  final Color backgroundColor;
  final Duration fadeInDuration;

  @override
  Widget build(BuildContext context) {
    return Image.memory(
      bytes,
      fit: fit,
      gaplessPlayback: true,
      filterQuality: FilterQuality.medium,
      frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
        final visible = wasSynchronouslyLoaded || frame != null;
        if (wasSynchronouslyLoaded) return child;
        return Stack(
          fit: StackFit.expand,
          children: [
            ImageFallback(
              backgroundColor: backgroundColor,
              showIcon: false,
            ),
            AnimatedOpacity(
              opacity: visible ? 1 : 0,
              duration: visible ? fadeInDuration : Duration.zero,
              curve: Curves.easeOutCubic,
              child: child,
            ),
          ],
        );
      },
      errorBuilder: (context, error, stackTrace) {
        return ImageFallback(backgroundColor: backgroundColor);
      },
    );
  }
}

class ImageFallback extends StatelessWidget {
  const ImageFallback({
    super.key,
    this.backgroundColor = const Color(0xFF111111),
    this.showIcon = true,
  });

  final Color backgroundColor;
  final bool showIcon;

  @override
  Widget build(BuildContext context) {
    final color = _softPlaceholderColor(backgroundColor);
    return ExcludeSemantics(
      child: DecoratedBox(
        key: const ValueKey('storedImage.placeholder'),
        decoration: BoxDecoration(
          color: color,
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              _tint(color, Colors.white, 0.04),
              color,
              _tint(color, Colors.white, 0.09),
              _tint(color, Colors.black, 0.06),
            ],
            stops: const [0, 0.42, 0.72, 1],
          ),
        ),
        child: showIcon
            ? const Center(
                child: Icon(
                  key: ValueKey('storedImage.missingIcon'),
                  Icons.image_not_supported_outlined,
                  color: Colors.white38,
                ),
              )
            : const SizedBox.expand(),
      ),
    );
  }
}

Color _softPlaceholderColor(Color color) {
  if (color.alpha == 0) return const Color(0xFF17171C);
  if (color.computeLuminance() < 0.03) {
    return Color.alphaBlend(
      const Color(0xFF2A2631).withOpacity(0.72),
      color,
    );
  }
  return _tint(color, Colors.white, 0.08);
}

Color _tint(Color color, Color overlay, double opacity) {
  return Color.alphaBlend(overlay.withOpacity(opacity), color);
}
