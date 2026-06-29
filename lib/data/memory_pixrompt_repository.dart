import 'dart:typed_data';

import '../domain/pixrompt_settings.dart';
import '../domain/prompt_image.dart';
import 'pixrompt_repository.dart';

class MemoryPixromptRepository implements PixromptRepository {
  MemoryPixromptRepository({
    List<PromptImageItem>? initialImages,
    PixromptSettings? initialSettings,
    Map<String, Uint8List>? initialImageBytes,
  })  : _images = initialImages ?? [],
        _settings = initialSettings ?? const PixromptSettings(),
        _imageBytes = initialImageBytes ?? {};

  List<PromptImageItem> _images;
  PixromptSettings _settings;
  final Map<String, Uint8List> _imageBytes;

  @override
  Future<List<PromptImageItem>> readImages() async => List.of(_images);

  @override
  Future<void> writeImages(List<PromptImageItem> images) async {
    _images = List.of(images);
  }

  @override
  Future<PixromptSettings> readSettings() async => _settings;

  @override
  Future<void> writeSettings(PixromptSettings settings) async {
    _settings = settings;
  }

  @override
  Future<Uint8List?> readImageBytes(String imageKey) async =>
      _imageBytes[imageKey];

  @override
  Future<void> writeImageBytes(String imageKey, Uint8List bytes) async {
    _imageBytes[imageKey] = Uint8List.fromList(bytes);
  }

  @override
  Future<void> deleteImageBytes(String imageKey) async {
    _imageBytes.remove(imageKey);
  }

  @override
  Future<List<String>> listImageByteKeys() async => _imageBytes.keys.toList();
}
