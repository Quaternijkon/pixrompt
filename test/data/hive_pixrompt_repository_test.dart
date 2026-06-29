import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:pixrompt/domain/category_dimension.dart';
import 'package:pixrompt/data/hive_pixrompt_repository.dart';
import 'package:pixrompt/domain/pixrompt_settings.dart';
import 'package:pixrompt/domain/prompt_image.dart';

void main() {
  test('persists images, settings, and bytes', () async {
    final directory =
        await Directory.systemTemp.createTemp('pixrompt_hive_test_');
    Hive.init(directory.path);
    final repository = await HivePixromptRepository.open(prefix: 'case1');

    final image = PromptImageItem.sample(
      uid: 'i1',
      imageKey: 'bytes-i1',
      prompt: 'Persist me',
      categoryAssignments: const {
        sourceDimensionId: 'Gemini',
        'subject': '运动',
      },
    );

    await repository.writeImages([image]);
    await repository.writeSettings(
      const PixromptSettings(
        columns: 4,
        categoryDimensions: [
          ...defaultCategoryDimensions,
          CategoryDimension(id: 'mood', name: '情绪', items: ['温暖']),
        ],
      ),
    );
    await repository.writeImageBytes('bytes-i1', Uint8List.fromList([9, 8, 7]));

    final reopened = await HivePixromptRepository.open(prefix: 'case1');

    final persistedImage = (await reopened.readImages()).single;
    final persistedSettings = await reopened.readSettings();
    expect(persistedImage.prompt, 'Persist me');
    expect(persistedImage.categoryAssignments[sourceDimensionId], 'Gemini');
    expect(persistedImage.categoryAssignments['subject'], '运动');
    expect(persistedSettings.columns, 4);
    expect(
      persistedSettings.categoryDimensions
          .firstWhere((dimension) => dimension.id == 'mood')
          .items,
      ['温暖'],
    );
    expect(await reopened.readImageBytes('bytes-i1'), [9, 8, 7]);

    await Hive.close();
    await directory.delete(recursive: true);
  });
}
