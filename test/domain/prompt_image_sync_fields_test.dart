import 'package:flutter_test/flutter_test.dart';
import 'package:pixrompt/domain/prompt_image.dart';

void main() {
  test('loads old image JSON without sync maintenance fields', () {
    final image = PromptImageItem.fromJson({
      'uid': 'image-1',
      'imageKey': 'bytes-1',
      'prompt': 'Old prompt',
      'aspectRatio': 1.25,
      'createdAt': 10,
      'updatedAt': 11,
    });

    expect(image.uid, 'image-1');
    expect(image.imageKey, 'bytes-1');
    expect(image.originalFileName, isNull);
    expect(image.contentSha256, isNull);
    expect(image.mimeType, isNull);
    expect(image.importedAt, isNull);
    expect(image.lastSyncedAt, isNull);
  });

  test('round-trips optional sync maintenance fields', () {
    final image = PromptImageItem.sample(
      uid: 'image-2',
      imageKey: 'bytes-2',
      prompt: 'Sync prompt',
      originalFileName: 'source.png',
      contentSha256: _repeat('a', 64),
      mimeType: 'image/png',
      importedAt: 20,
      lastSyncedAt: 30,
    );

    final roundTrip = PromptImageItem.fromJson(image.toJson());

    expect(roundTrip.originalFileName, 'source.png');
    expect(roundTrip.contentSha256, _repeat('a', 64));
    expect(roundTrip.mimeType, 'image/png');
    expect(roundTrip.importedAt, 20);
    expect(roundTrip.lastSyncedAt, 30);
    expect(
      roundTrip.copyWith(lastSyncedAt: null).lastSyncedAt,
      isNull,
    );
  });
}

String _repeat(String value, int count) {
  return List.filled(count, value).join();
}
