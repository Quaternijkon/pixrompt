import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pixrompt/app/pixrompt_controller.dart';
import 'package:pixrompt/data/memory_pixrompt_repository.dart';
import 'package:pixrompt/domain/category_dimension.dart';
import 'package:pixrompt/domain/prompt_image.dart';
import 'package:pixrompt/domain/search_filters.dart';

void main() {
  test('adds multiple images without pro gates or category steps', () async {
    final controller = PixromptController(
      MemoryPixromptRepository(),
      uidFactory: _uids(['a', 'b']),
    );
    await controller.initialize();

    final result = await controller.addPromptImages(
      images: [
        PickedImageBytes(
          name: 'teapot.png',
          bytes: Uint8List.fromList([1, 2, 3]),
          width: 100,
          height: 50,
        ),
        PickedImageBytes(name: 'cup.png', bytes: Uint8List.fromList([4])),
      ],
      prompt: 'A glass teapot',
    );

    expect(result.success, isTrue);
    expect(controller.state.allImages, hasLength(2));
    expect(controller.state.visibleImages.first.prompt, 'A glass teapot');
    expect(controller.state.visibleImages.first.aspectRatio, 2);
    expect(controller.state.visibleImages.first.categoryAssignments, isEmpty);
    expect(
      controller.state.visibleImages.first.categoryLabel(sourceDimensionId),
      uncategorizedCategory,
    );
  });

  test('migrates old full-feature records into the dimensional image model',
      () {
    final item = PromptImageItem.fromJson({
      'uid': 'old',
      'archiveUid': 'archive-a',
      'imageKey': 'image-old',
      'prompt': 'Keep this prompt',
      'category': 'Imagen',
      'optionalTags': ['tag-a'],
      'isPrivate': true,
      'isFavorite': true,
      'promptHash': 'hash',
      'fileSha256': 'sha',
      'aspectRatio': 1.4,
      'createdAt': 10,
      'updatedAt': 12,
      'parentImageUid': 'root',
      'promptParts': ['Base', 'Edit'],
    });

    expect(item.uid, 'old');
    expect(item.imageKey, 'image-old');
    expect(item.prompt, 'Keep this prompt');
    expect(item.categoryAssignments[sourceDimensionId], 'Imagen');
    expect(item.categoryLabel(sourceDimensionId), 'Imagen');
    expect(item.parentImageUid, 'root');
    expect(item.promptParts, ['Base', 'Edit']);
    expect(item.toJson().keys, contains('categoryAssignments'));
    expect(item.toJson().keys, isNot(contains('archiveUid')));
    expect(item.toJson().keys, isNot(contains('optionalTags')));
    expect(item.toJson().keys, isNot(contains('isPrivate')));
    expect(item.toJson().keys, isNot(contains('isFavorite')));
  });

  test('assigns selected images to independent category dimensions', () async {
    final repository = MemoryPixromptRepository();
    final controller =
        PixromptController(repository, uidFactory: _uids(['a', 'b']));
    await controller.initialize();
    await controller.addPromptImages(
      images: [
        PickedImageBytes(name: 'a.png', bytes: Uint8List.fromList([1])),
        PickedImageBytes(name: 'b.png', bytes: Uint8List.fromList([2])),
      ],
      prompt: 'Batch prompt',
    );

    await controller.assignCategoryToImages(
      ['a', 'b'],
      dimensionId: sourceDimensionId,
      item: 'Gemini',
    );
    await controller.assignCategoryToImages(
      ['a'],
      dimensionId: 'subject',
      item: 'Sports',
    );

    final a =
        controller.state.allImages.firstWhere((image) => image.uid == 'a');
    final b =
        controller.state.allImages.firstWhere((image) => image.uid == 'b');
    expect(a.categoryAssignments, {
      sourceDimensionId: 'Gemini',
      'subject': 'Sports',
    });
    expect(b.categoryAssignments, {sourceDimensionId: 'Gemini'});

    await controller.updateSearchFilters(
      const SearchFilters(categoryDimensionId: 'subject', category: 'Sports'),
    );
    expect(controller.state.visibleImages.map((image) => image.uid), ['a']);
  });

  test('filters unclassified images inside a dimension', () async {
    final controller = PixromptController(MemoryPixromptRepository(),
        uidFactory: _uids(['a']));
    await controller.initialize();
    await controller.addPromptImages(
      images: [
        PickedImageBytes(name: 'a.png', bytes: Uint8List.fromList([1]))
      ],
      prompt: 'No source yet',
    );

    await controller.updateSearchFilters(
      const SearchFilters(
        categoryDimensionId: sourceDimensionId,
        category: uncategorizedCategory,
      ),
    );

    expect(controller.state.visibleImages.map((image) => image.uid), ['a']);
  });

  test('adds category dimensions and items for later assignment', () async {
    final controller = PixromptController(MemoryPixromptRepository());
    await controller.initialize();

    await controller.addCategoryDimension('Mood');
    await controller.addCategoryItem('mood', 'Warm');

    final mood = controller.state.categoryDimensions
        .firstWhere((dimension) => dimension.id == 'mood');
    expect(mood.name, 'Mood');
    expect(mood.items, contains('Warm'));
  });

  test('adds non-latin category dimensions for later assignment', () async {
    final controller = PixromptController(MemoryPixromptRepository());
    await controller.initialize();

    await controller.addCategoryDimension('情绪');

    final dimension = controller.state.categoryDimensions
        .firstWhere((dimension) => dimension.name == '情绪');
    expect(dimension.id, isNotEmpty);
    expect(
      controller.state.settings.categoryDimensions.any(
        (candidate) =>
            candidate.id == dimension.id && candidate.name == dimension.name,
      ),
      isTrue,
    );
  });

  test('delete and undo restore the removed image and payload', () async {
    final repository = MemoryPixromptRepository();
    final controller = PixromptController(repository);
    await controller.initialize();
    await controller.addPromptImages(
      images: [
        PickedImageBytes(name: 'a.png', bytes: Uint8List.fromList([1]))
      ],
      prompt: 'Undo prompt',
    );
    final uid = controller.state.allImages.single.uid;
    final imageKey = controller.state.allImages.single.imageKey;

    await controller.deleteImage(uid);
    expect(controller.state.allImages, isEmpty);
    expect(await repository.readImageBytes(imageKey), isNull);
    expect(controller.state.pendingUndo, isNotNull);

    await controller.undoLastDelete();
    expect(controller.state.allImages.single.uid, uid);
    expect(await repository.readImageBytes(imageKey), [1]);
  });

  test('deletes multiple selected images and their payloads', () async {
    final repository = MemoryPixromptRepository();
    final controller =
        PixromptController(repository, uidFactory: _uids(['a', 'b', 'c']));
    await controller.initialize();
    await controller.addPromptImages(
      images: [
        PickedImageBytes(name: 'a.png', bytes: Uint8List.fromList([1])),
        PickedImageBytes(name: 'b.png', bytes: Uint8List.fromList([2])),
        PickedImageBytes(name: 'c.png', bytes: Uint8List.fromList([3])),
      ],
      prompt: 'Batch prompt',
    );

    await controller.deleteImages(['a', 'c']);

    expect(controller.state.allImages.map((image) => image.uid), ['b']);
    expect(await repository.readImageBytes('image-a'), isNull);
    expect(await repository.readImageBytes('image-c'), isNull);
    expect(await repository.readImageBytes('image-b'), [2]);
  });

  test('backup export and import restore images and payloads only', () async {
    final source = PixromptController(MemoryPixromptRepository());
    await source.initialize();
    await source.addPromptImages(
      images: [
        PickedImageBytes(name: 'a.png', bytes: Uint8List.fromList([1, 2, 3]))
      ],
      prompt: 'Backup prompt',
    );
    await source.assignCategoryToImages(
      [source.state.allImages.single.uid],
      dimensionId: sourceDimensionId,
      item: 'Gemini',
    );
    final backup = await source.exportBackupJson();

    final target = PixromptController(MemoryPixromptRepository());
    await target.initialize();
    await target.importBackupJson(backup);

    expect(target.state.allImages.single.prompt, 'Backup prompt');
    expect(
      target.state.allImages.single.categoryAssignments[sourceDimensionId],
      'Gemini',
    );
    expect(
      await target.repository
          .readImageBytes(target.state.allImages.single.imageKey),
      [1, 2, 3],
    );
  });

  test('adds prompt edits as child images with prompt chain and categories',
      () async {
    final controller = PixromptController(
      MemoryPixromptRepository(),
      uidFactory: _uids(['root', 'edit']),
    );
    await controller.initialize();
    await controller.addPromptImages(
      images: [
        PickedImageBytes(name: 'root.png', bytes: Uint8List.fromList([1]))
      ],
      prompt: 'Base prompt',
    );
    final root = controller.state.allImages.single;
    await controller.assignCategoryToImages(
      [root.uid],
      dimensionId: sourceDimensionId,
      item: 'Gemini',
    );

    final result = await controller.addPromptEdit(
      sourceImageUid: root.uid,
      editPrompt: 'make it warmer',
      images: [
        PickedImageBytes(name: 'edit.png', bytes: Uint8List.fromList([2]))
      ],
    );

    expect(result.success, isTrue);
    final edit =
        controller.state.allImages.firstWhere((image) => image.uid == 'edit');
    expect(edit.parentImageUid, root.uid);
    expect(edit.prompt, 'Base prompt\nmake it warmer');
    expect(edit.categoryAssignments[sourceDimensionId], 'Gemini');
    expect(edit.promptParts, ['Base prompt', 'make it warmer']);
    expect(
      edit.editHistory.map((entry) => entry.prompt),
      ['Base prompt', 'make it warmer'],
    );
    expect(edit.editHistory.last.imageUid, 'edit');
  });

  test('updates columns from scale with clamping', () async {
    final controller = PixromptController(MemoryPixromptRepository());
    await controller.initialize();

    expect(columnCountFromScale(baseColumns: 3, scale: 1.4), 2);
    expect(columnCountFromScale(baseColumns: 3, scale: 0.7), 4);

    await controller.setColumnsFromScale(baseColumns: 3, scale: 0.1);
    expect(controller.state.settings.columns, 6);
  });

  test(
      'cleanup removes image bytes that are not referenced by any image record',
      () async {
    final repository = MemoryPixromptRepository(
      initialImageBytes: {
        'orphan': Uint8List.fromList([9]),
      },
    );
    final controller = PixromptController(repository);
    await controller.initialize();
    await controller.addPromptImages(
      images: [
        PickedImageBytes(name: 'a.png', bytes: Uint8List.fromList([1]))
      ],
      prompt: 'Keep me',
    );
    final imageKey = controller.state.allImages.single.imageKey;

    final deletedCount = await controller.cleanupOrphanedImageBytes();

    expect(deletedCount, 1);
    expect(await repository.readImageBytes('orphan'), isNull);
    expect(await repository.readImageBytes(imageKey), [1]);
  });
}

String Function() _uids(List<String> values) {
  var index = 0;
  return () => values[index++];
}
