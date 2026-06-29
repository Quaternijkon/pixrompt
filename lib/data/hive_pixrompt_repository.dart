import 'dart:convert';
import 'dart:typed_data';

import 'package:hive/hive.dart';

import '../domain/pixrompt_settings.dart';
import '../domain/prompt_image.dart';
import 'pixrompt_repository.dart';

class HivePixromptRepository implements PixromptRepository {
  HivePixromptRepository._({
    required Box<dynamic> records,
    required Box<dynamic> imageBytes,
  })  : _records = records,
        _imageBytes = imageBytes;

  static Future<HivePixromptRepository> open(
      {String prefix = 'pixrompt'}) async {
    final records = await Hive.openBox<dynamic>('${prefix}_records');
    final imageBytes = await Hive.openBox<dynamic>('${prefix}_image_bytes');
    return HivePixromptRepository._(records: records, imageBytes: imageBytes);
  }

  final Box<dynamic> _records;
  final Box<dynamic> _imageBytes;

  @override
  Future<List<PromptImageItem>> readImages() async {
    final raw = _records.get(_imagesKey) as String?;
    if (raw == null || raw.isEmpty) return [];
    final decoded = jsonDecode(raw) as List<dynamic>;
    return decoded
        .whereType<Map<String, dynamic>>()
        .map(PromptImageItem.fromJson)
        .toList();
  }

  @override
  Future<void> writeImages(List<PromptImageItem> images) {
    return _records.put(
      _imagesKey,
      jsonEncode(images.map((image) => image.toJson()).toList()),
    );
  }

  @override
  Future<PixromptSettings> readSettings() async {
    final raw = _records.get(_settingsKey) as String?;
    if (raw == null || raw.isEmpty) return const PixromptSettings();
    return PixromptSettings.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  @override
  Future<void> writeSettings(PixromptSettings settings) {
    return _records.put(_settingsKey, jsonEncode(settings.toJson()));
  }

  @override
  Future<Uint8List?> readImageBytes(String imageKey) async {
    final raw = _imageBytes.get(imageKey);
    if (raw is Uint8List) return raw;
    if (raw is List<int>) return Uint8List.fromList(raw);
    if (raw is List<dynamic>) {
      return Uint8List.fromList(raw.whereType<int>().toList());
    }
    return null;
  }

  @override
  Future<void> writeImageBytes(String imageKey, Uint8List bytes) {
    return _imageBytes.put(imageKey, Uint8List.fromList(bytes));
  }

  @override
  Future<void> deleteImageBytes(String imageKey) {
    return _imageBytes.delete(imageKey);
  }

  @override
  Future<List<String>> listImageByteKeys() async {
    return _imageBytes.keys.whereType<String>().toList();
  }
}

const _imagesKey = 'images';
const _settingsKey = 'settings';
