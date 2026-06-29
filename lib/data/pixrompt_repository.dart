import 'dart:typed_data';

import '../domain/pixrompt_settings.dart';
import '../domain/prompt_image.dart';

abstract class PixromptRepository {
  Future<List<PromptImageItem>> readImages();
  Future<void> writeImages(List<PromptImageItem> images);

  Future<PixromptSettings> readSettings();
  Future<void> writeSettings(PixromptSettings settings);

  Future<Uint8List?> readImageBytes(String imageKey);
  Future<void> writeImageBytes(String imageKey, Uint8List bytes);
  Future<void> deleteImageBytes(String imageKey);
  Future<List<String>> listImageByteKeys();
}
