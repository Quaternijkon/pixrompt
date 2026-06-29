import 'dart:convert';
import 'dart:typed_data';

import 'prompt_image.dart';

class BackupFormatException implements Exception {
  const BackupFormatException(this.message);

  final String message;

  @override
  String toString() => 'BackupFormatException: $message';
}

class PromptBackup {
  const PromptBackup({
    required this.images,
    required this.imageBytesByKey,
  });

  final List<PromptImageItem> images;
  final Map<String, Uint8List> imageBytesByKey;
}

class PromptBackupCodec {
  static const schemaVersion = 2;

  static String encode({
    required List<PromptImageItem> images,
    required Map<String, Uint8List> imageBytesByKey,
  }) {
    final payloads = <String, String>{};
    for (final entry in imageBytesByKey.entries) {
      payloads[entry.key] = base64Encode(entry.value);
    }
    return const JsonEncoder.withIndent('  ').convert({
      'schemaVersion': schemaVersion,
      'exportedAt': DateTime.now().toIso8601String(),
      'images': images.map((image) => image.toJson()).toList(),
      'imagePayloads': payloads,
    });
  }

  static PromptBackup decode(String jsonText) {
    final decoded = jsonDecode(jsonText);
    if (decoded is! Map<String, dynamic>) {
      throw const BackupFormatException('Invalid backup file.');
    }
    final version = decoded['schemaVersion'];
    if (version != 1 && version != schemaVersion) {
      throw BackupFormatException('Unsupported backup version: $version.');
    }
    final images = (decoded['images'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(PromptImageItem.fromJson)
        .toList();
    final payloads = <String, Uint8List>{};
    final rawPayloads = decoded['imagePayloads'];
    if (rawPayloads is Map<String, dynamic>) {
      for (final entry in rawPayloads.entries) {
        final value = entry.value;
        if (value is! String) {
          throw BackupFormatException('Invalid image payload: ${entry.key}.');
        }
        payloads[entry.key] = base64Decode(value);
      }
    }
    return PromptBackup(
      images: images,
      imageBytesByKey: payloads,
    );
  }
}
