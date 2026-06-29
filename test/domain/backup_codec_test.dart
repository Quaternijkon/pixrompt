import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pixrompt/domain/backup.dart';
import 'package:pixrompt/domain/prompt_image.dart';

void main() {
  test('exports and imports a simplified backup with image payloads', () {
    final image = PromptImageItem.sample(
      uid: 'image-1',
      imageKey: 'image-key-1',
      prompt: 'A glass teapot',
      category: 'Gemini',
    );
    final jsonText = PromptBackupCodec.encode(
      images: [image],
      imageBytesByKey: {
        'image-key-1': Uint8List.fromList([1, 2, 3, 4])
      },
    );

    final decodedMap = jsonDecode(jsonText) as Map<String, dynamic>;
    expect(decodedMap['schemaVersion'], PromptBackupCodec.schemaVersion);
    expect(decodedMap.keys, isNot(contains('archives')));

    final decoded = PromptBackupCodec.decode(jsonText);

    expect(decoded.images.single.prompt, 'A glass teapot');
    expect(decoded.imageBytesByKey['image-key-1'],
        Uint8List.fromList([1, 2, 3, 4]));
  });

  test('decodes old archive backups while ignoring archive metadata', () {
    final jsonText = jsonEncode({
      'schemaVersion': 1,
      'archives': [
        {'uid': 'archive-a', 'name': 'Old'}
      ],
      'images': [
        {
          'uid': 'image-1',
          'archiveUid': 'archive-a',
          'imageKey': 'image-key-1',
          'prompt': 'Old prompt',
          'category': 'Gemini',
          'optionalTags': ['tag'],
          'isPrivate': true,
          'isFavorite': true,
          'aspectRatio': 1,
          'createdAt': 1,
          'updatedAt': 1,
        }
      ],
      'imagePayloads': {
        'image-key-1': base64Encode(Uint8List.fromList([7, 8])),
      },
    });

    final decoded = PromptBackupCodec.decode(jsonText);

    expect(decoded.images.single.prompt, 'Old prompt');
    expect(decoded.images.single.toJson().keys, isNot(contains('archiveUid')));
    expect(
        decoded.images.single.toJson().keys, isNot(contains('optionalTags')));
    expect(decoded.imageBytesByKey['image-key-1'], [7, 8]);
  });

  test('rejects unsupported backup schema versions', () {
    expect(
      () => PromptBackupCodec.decode(
          '{"schemaVersion":999,"images":[],"imagePayloads":{}}'),
      throwsA(isA<BackupFormatException>()),
    );
  });
}
