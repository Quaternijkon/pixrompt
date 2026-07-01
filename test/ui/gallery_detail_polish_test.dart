import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pixrompt/app/pixrompt_controller.dart';
import 'package:pixrompt/app/pixrompt_sync_controller.dart';
import 'package:pixrompt/data/memory_pixrompt_repository.dart';
import 'package:pixrompt/data/sync_state_repository.dart';
import 'package:pixrompt/domain/category_dimension.dart';
import 'package:pixrompt/domain/prompt_image.dart';
import 'package:pixrompt/platform/pixrompt_file_actions.dart';
import 'package:pixrompt/ui/gallery_shell.dart';
import 'package:pixrompt/ui/gallery_tile.dart';
import 'package:pixrompt/ui/prompt_detail_sheet.dart';

void main() {
  testWidgets('gallery waterfall and add action reserve bottom safe space',
      (tester) async {
    final controller = await _controller(
      images: [
        PromptImageItem.sample(
          uid: 'a',
          imageKey: 'missing-a',
          prompt: 'A quiet library',
          createdAt: 20,
        ),
        PromptImageItem.sample(
          uid: 'b',
          imageKey: 'missing-b',
          prompt: 'A neon street',
          createdAt: 10,
        ),
      ],
    );

    await tester.pumpWidget(_galleryShell(controller));
    await tester.pump();

    final grid = tester.widget<MasonryGridView>(
      find.byKey(const ValueKey('gallery.waterfall')),
    );
    expect(
      grid.padding?.resolve(TextDirection.ltr).bottom,
      greaterThanOrEqualTo(96),
    );
    expect(
      find.ancestor(
        of: find.byKey(const ValueKey('gallery.addAction')),
        matching: find.byType(SafeArea),
      ),
      findsOneWidget,
    );
  });

  testWidgets('gallery tile exposes a single meaningful button semantic',
      (tester) async {
    final semantics = tester.ensureSemantics();
    addTearDown(semantics.dispose);
    final image = PromptImageItem.sample(
      uid: 'tile',
      imageKey: 'missing-tile',
      prompt: 'A quiet library',
      originalFileName: 'library.png',
      categoryAssignments: const {sourceDimensionId: 'Gemini'},
    );
    final controller = await _controller(images: [image]);

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(useMaterial3: true, brightness: Brightness.dark),
        home: Scaffold(
          body: GalleryTile(
            controller: controller,
            image: image,
            onTap: () {},
            onLongPress: () {},
          ),
        ),
      ),
    );
    await tester.pump();

    final node = tester.getSemantics(
      find.byKey(const ValueKey('gallery.tile.tile')),
    );
    expect(node.hasFlag(SemanticsFlag.isButton), isTrue);
    expect(node.hasAction(SemanticsAction.tap), isTrue);
    expect(node.label, contains('打开图片'));
    expect(node.label, contains('A quiet library'));
    expect(node.label, contains('library.png'));
    expect(node.label, contains('Gemini'));
    expect(node.label, isNot(contains('image_not_supported')));
  });

  testWidgets('selected gallery tile announces selection state', (tester) async {
    final semantics = tester.ensureSemantics();
    addTearDown(semantics.dispose);
    final image = PromptImageItem.sample(
      uid: 'selected',
      imageKey: 'missing-selected',
      prompt: 'Selected prompt',
    );
    final controller = await _controller(images: [image]);

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(useMaterial3: true, brightness: Brightness.dark),
        home: Scaffold(
          body: GalleryTile(
            controller: controller,
            image: image,
            selected: true,
            selectionMode: true,
            onTap: () {},
            onLongPress: () {},
          ),
        ),
      ),
    );
    await tester.pump();

    final node = tester.getSemantics(
      find.byKey(const ValueKey('gallery.tile.selected')),
    );
    expect(node.hasFlag(SemanticsFlag.isSelected), isTrue);
    expect(node.label, contains('已选择'));
    expect(node.label, contains('切换选择'));
  });

  testWidgets('detail bottom controls fit a 320px wide surface',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 640));
    addTearDown(() async => tester.binding.setSurfaceSize(null));
    final controller = await _controller(
      images: [
        PromptImageItem.sample(
          uid: 'detail',
          imageKey: 'missing-detail',
          prompt: 'A prompt that keeps the controls visible',
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(useMaterial3: true, brightness: Brightness.dark),
        home: PromptDetailSheet(
          controller: controller,
          images: controller.state.allImages,
          initialIndex: 0,
          onCopy: (_) {},
          onAppendEdit: (_) {},
          onEditText: (_) {},
          onDelete: (_) {},
          onFilterSamePrompt: (_) {},
        ),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    final controls = find.byKey(const ValueKey('detail.controlsRow'));
    expect(controls, findsOneWidget);
    expect(tester.getSize(controls).width, lessThanOrEqualTo(280));
    for (final element in tester.elementList(
      find.descendant(of: controls, matching: find.byType(IconButton)),
    )) {
      expect(
        tester.getSize(find.byWidget(element.widget)),
        const Size(48, 48),
      );
    }
  });

  testWidgets('detail image surface exposes replacement semantics',
      (tester) async {
    final semantics = tester.ensureSemantics();
    addTearDown(semantics.dispose);
    final controller = await _controller(
      images: [
        PromptImageItem.sample(
          uid: 'detail',
          imageKey: 'missing-detail',
          prompt: 'A quiet library',
          originalFileName: 'library.png',
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(useMaterial3: true, brightness: Brightness.dark),
        home: PromptDetailSheet(
          controller: controller,
          images: controller.state.allImages,
          initialIndex: 0,
          onCopy: (_) {},
          onAppendEdit: (_) {},
          onEditText: (_) {},
          onDelete: (_) {},
          onFilterSamePrompt: (_) {},
        ),
      ),
    );
    await tester.pump();

    final node = tester.getSemantics(
      find.byKey(const ValueKey('detail.imageSemantics.detail')),
    );
    expect(node.hasFlag(SemanticsFlag.isImage), isTrue);
    expect(node.label, contains('图片'));
    expect(node.label, contains('A quiet library'));
    expect(node.label, contains('library.png'));
    expect(node.label, isNot(contains('image_not_supported')));
  });

  testWidgets('edit history graph controls have touch-sized semantics',
      (tester) async {
    final semantics = tester.ensureSemantics();
    addTearDown(semantics.dispose);
    final controller = await _controller(
      images: [
        PromptImageItem.sample(
          uid: 'root',
          imageKey: 'missing-root',
          prompt: 'Base prompt',
          createdAt: 10,
        ),
        PromptImageItem.sample(
          uid: 'edit',
          imageKey: 'missing-edit',
          prompt: 'Make it warmer',
          parentImageUid: 'root',
          promptParts: const ['Base prompt', 'Make it warmer'],
          createdAt: 20,
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(useMaterial3: true, brightness: Brightness.dark),
        home: ImageEditHistoryPage(
          controller: controller,
          image: controller.state.allImages.last,
          onCopy: (_) {},
          onAppendEdit: (_) {},
          onEditText: (_) {},
          onDelete: (_) {},
          onFilterSamePrompt: (_) {},
        ),
      ),
    );
    await tester.pump();

    final edgeFinder = find.byKey(
      const ValueKey('history.edge.root.Make it warmer'),
    );
    expect(tester.getSize(edgeFinder).height, greaterThanOrEqualTo(44));
    final edgeNode = tester.getSemantics(edgeFinder);
    expect(edgeNode.hasFlag(SemanticsFlag.isButton), isTrue);
    expect(edgeNode.hasAction(SemanticsAction.tap), isTrue);
    expect(edgeNode.label, contains('查看编辑 Prompt'));
    expect(edgeNode.label, contains('Make it warmer'));

    final nodeFinder = find.byKey(const ValueKey('history.node.root'));
    final nodeSemantics = tester.getSemantics(nodeFinder);
    expect(nodeSemantics.hasFlag(SemanticsFlag.isButton), isTrue);
    expect(nodeSemantics.hasAction(SemanticsAction.tap), isTrue);
    expect(nodeSemantics.label, contains('打开历史图片'));
    expect(nodeSemantics.label, contains('Base prompt'));
  });
}

Future<PixromptController> _controller({
  required List<PromptImageItem> images,
}) async {
  final controller = PixromptController(
    MemoryPixromptRepository(initialImages: images),
  );
  await controller.initialize();
  return controller;
}

Widget _galleryShell(PixromptController controller) {
  final syncController = PixromptSyncController(
    pixromptController: controller,
    syncStateRepository: MemorySyncStateRepository(),
  );
  addTearDown(syncController.dispose);
  return MaterialApp(
    theme: ThemeData(useMaterial3: true, brightness: Brightness.dark),
    home: GalleryShell(
      controller: controller,
      syncController: syncController,
      fileActions: const _NoopFileActions(),
    ),
  );
}

class _NoopFileActions extends PixromptFileActions {
  const _NoopFileActions();
}
