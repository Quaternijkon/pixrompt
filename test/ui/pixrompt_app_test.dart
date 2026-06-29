import 'dart:typed_data';

import 'package:flutter/material.dart';
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
import 'package:pixrompt/ui/pixrompt_app.dart';

void main() {
  testWidgets(
      'home is a chrome-free full-screen waterfall with floating actions',
      (tester) async {
    final controller = PixromptController(
      MemoryPixromptRepository(
        initialImages: [
          PromptImageItem.sample(
            uid: 'a',
            imageKey: 'missing-a',
            prompt: 'A quiet library',
            categoryAssignments: const {sourceDimensionId: 'Gemini'},
            aspectRatio: 0.75,
            createdAt: 30,
          ),
          PromptImageItem.sample(
            uid: 'b',
            imageKey: 'missing-b',
            prompt: 'A neon street',
            categoryAssignments: const {sourceDimensionId: 'ChatGPT'},
            aspectRatio: 1.4,
            createdAt: 20,
          ),
        ],
      ),
    );
    await controller.initialize();

    await tester.pumpWidget(_app(controller));
    await tester.pump();

    expect(find.byKey(const ValueKey('gallery.waterfall')), findsOneWidget);
    final grid = tester.widget<MasonryGridView>(
      find.byKey(const ValueKey('gallery.waterfall')),
    );
    expect(grid.mainAxisSpacing, 0);
    expect(grid.crossAxisSpacing, 0);
    expect(find.byKey(const ValueKey('gallery.topActions')), findsOneWidget);
    expect(
        find.byKey(const ValueKey('gallery.categoryAction')), findsOneWidget);
    expect(find.byKey(const ValueKey('gallery.addAction')), findsOneWidget);
    expect(find.byType(FloatingActionButton), findsNothing);
    expect(find.byType(AppBar), findsNothing);
    expect(find.byType(NavigationBar), findsNothing);
    expect(find.byType(NavigationRail), findsNothing);
    expect(find.byType(BottomAppBar), findsNothing);
    expect(find.text('Pro'), findsNothing);
    expect(find.text('A quiet library'), findsNothing);
    expect(find.text('Gemini'), findsNothing);
  });

  testWidgets('category drawer exposes dimensions, items, and uncategorized',
      (tester) async {
    final controller = PixromptController(MemoryPixromptRepository());
    await controller.initialize();

    await tester.pumpWidget(_app(controller));
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('gallery.categoryAction')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('category.drawer')), findsOneWidget);
    expect(find.byKey(const ValueKey('category.dimension.source')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('category.item.source.Gemini')),
        findsOneWidget);
    expect(
      find.byKey(const ValueKey('category.item.source.$uncategorizedCategory')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('category.addDimension')), findsOneWidget);
  });

  testWidgets('category drawer creates non-latin dimensions', (tester) async {
    final controller = PixromptController(MemoryPixromptRepository());
    await controller.initialize();

    await tester.pumpWidget(_app(controller));
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('gallery.categoryAction')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('category.addDimension')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '情绪');
    await tester.pump();
    await tester.tap(find.byType(FilledButton).last);
    await tester.pumpAndSettle();

    expect(find.text('情绪'), findsOneWidget);
    expect(
      controller.state.categoryDimensions.any(
        (dimension) => dimension.name == '情绪',
      ),
      isTrue,
    );
  });

  testWidgets('settings exposes an Account and Sync entry', (tester) async {
    final controller = PixromptController(MemoryPixromptRepository());
    await controller.initialize();

    await tester.pumpWidget(_app(controller));
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('gallery.settingsAction')));
    await tester.pumpAndSettle();

    expect(find.text('Account and Sync'), findsOneWidget);
    expect(find.byKey(const ValueKey('settings.accountSyncAction')),
        findsOneWidget);
  });

  testWidgets('adding images only asks for a prompt, not a category',
      (tester) async {
    final controller = PixromptController(
      MemoryPixromptRepository(),
      uidFactory: _uids(['added']),
    );
    await controller.initialize();

    await tester.pumpWidget(
      _app(
        controller,
        fileActions: _FakeFileActions([
          PickedImageLoader(
            name: 'added.png',
            load: () async => PickedImageBytes(
              name: 'added.png',
              bytes: Uint8List.fromList([1, 2, 3]),
              width: 40,
              height: 80,
            ),
          ),
        ]),
      ),
    );
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('gallery.addAction')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('prompt.editor')), findsOneWidget);
    expect(find.byKey(const ValueKey('prompt.categoryChoices')), findsNothing);
    await tester.enterText(
      find.byKey(const ValueKey('prompt.input')),
      'Only prompt',
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('prompt.save')));
    await tester.pumpAndSettle();

    expect(controller.state.allImages.single.prompt, 'Only prompt');
    expect(controller.state.allImages.single.categoryAssignments, isEmpty);
  });

  testWidgets('search opens prompt choices on a second-level page',
      (tester) async {
    final controller = PixromptController(
      MemoryPixromptRepository(
        initialImages: [
          PromptImageItem.sample(
            uid: 'a',
            imageKey: 'missing-a',
            prompt: 'Shared prompt',
            createdAt: 30,
          ),
          PromptImageItem.sample(
            uid: 'b',
            imageKey: 'missing-b',
            prompt: 'Other prompt',
            createdAt: 20,
          ),
          PromptImageItem.sample(
            uid: 'c',
            imageKey: 'missing-c',
            prompt: 'Shared prompt',
            createdAt: 10,
          ),
        ],
      ),
    );
    await controller.initialize();

    await tester.pumpWidget(_app(controller));
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('gallery.searchAction')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('search.promptListAction')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('prompt.filterPage')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('prompt.filter.Shared prompt')));
    await tester.pumpAndSettle();

    expect(controller.state.searchFilters.prompt, 'Shared prompt');
    expect(
        controller.state.visibleImages.map((image) => image.uid), ['a', 'c']);
  });

  testWidgets('home horizontal gestures open category drawer and search',
      (tester) async {
    final controller = PixromptController(MemoryPixromptRepository());
    await controller.initialize();

    await tester.pumpWidget(_app(controller));
    await tester.pump();

    await tester.dragFrom(const Offset(20, 360), const Offset(320, 0));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('category.drawer')), findsOneWidget);

    Navigator.of(tester.element(find.byType(GalleryShell))).pop();
    await tester.pumpAndSettle();

    await tester.dragFrom(const Offset(380, 360), const Offset(-320, 0));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('search.sheet')), findsOneWidget);
  });

  testWidgets('detail view is zoomable and keeps prompt collapsed until pulled',
      (tester) async {
    final controller = PixromptController(
      MemoryPixromptRepository(
        initialImages: [
          PromptImageItem.sample(
            uid: 'a',
            imageKey: 'missing-a',
            prompt: 'Shared prompt that should stay collapsed',
            categoryAssignments: const {sourceDimensionId: 'Gemini'},
            createdAt: 30,
          ),
          PromptImageItem.sample(
            uid: 'b',
            imageKey: 'missing-b',
            prompt: 'Other prompt',
            createdAt: 20,
          ),
        ],
      ),
    );
    await controller.initialize();

    await tester.pumpWidget(_app(controller));
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('gallery.tile.a')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('detail.fullscreen')), findsOneWidget);
    expect(find.byKey(const ValueKey('detail.viewer')), findsOneWidget);
    expect(find.byKey(const ValueKey('detail.pageView')), findsOneWidget);
    expect(find.byKey(const ValueKey('detail.zoomViewer.a')), findsOneWidget);
    expect(find.byKey(const ValueKey('detail.bottomOverlay')), findsOneWidget);
    expect(find.byKey(const ValueKey('detail.controlsRow')), findsOneWidget);
    expect(find.byKey(const ValueKey('detail.detailsAction')), findsOneWidget);
    expect(find.byKey(const ValueKey('detail.relatedAction')), findsOneWidget);
    expect(find.byKey(const ValueKey('detail.deleteAction')), findsOneWidget);
    expect(find.byKey(const ValueKey('detail.promptText')), findsNothing);
    expect(find.text('Gemini'), findsNothing);

    final initialMatrix = _imageMatrix(tester, 'a');
    final initialPage = _detailPage(tester);
    await tester.drag(
      find.byKey(const ValueKey('detail.zoomViewer.a')),
      const Offset(40, 0),
    );
    await tester.pumpAndSettle();
    expect(_imageMatrix(tester, 'a'), initialMatrix);
    expect(_detailPage(tester), initialPage);

    await _pinchZoom(tester, 'a');
    expect(_imageScale(tester, 'a'), greaterThan(1));
    await tester.drag(
      find.byKey(const ValueKey('detail.zoomViewer.a')),
      const Offset(900, 900),
    );
    await tester.pumpAndSettle();
    final zoomedMatrix = _imageMatrix(tester, 'a');
    expect(zoomedMatrix.getTranslation().x, lessThanOrEqualTo(0));
    expect(zoomedMatrix.getTranslation().y, lessThanOrEqualTo(0));

    await tester.drag(
      find.byKey(const ValueKey('detail.viewer')),
      const Offset(-360, 0),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('detail.zoomViewer.a')), findsOneWidget);

    await tester.tapAt(
      tester.getCenter(find.byKey(const ValueKey('detail.zoomViewer.a'))),
    );
    await tester.pump(const Duration(milliseconds: 80));
    await tester.tapAt(
      tester.getCenter(find.byKey(const ValueKey('detail.zoomViewer.a'))),
    );
    await tester.pumpAndSettle();
    expect(_imageScale(tester, 'a'), 1);

    await tester.tapAt(
      tester.getCenter(find.byKey(const ValueKey('detail.zoomViewer.a'))),
    );
    await tester.pump(const Duration(milliseconds: 80));
    await tester.tapAt(
      tester.getCenter(find.byKey(const ValueKey('detail.zoomViewer.a'))),
    );
    await tester.pumpAndSettle();
    expect(_imageScale(tester, 'a'), greaterThan(1));

    await tester.tapAt(
      tester.getCenter(find.byKey(const ValueKey('detail.zoomViewer.a'))),
    );
    await tester.pump(const Duration(milliseconds: 80));
    await tester.tapAt(
      tester.getCenter(find.byKey(const ValueKey('detail.zoomViewer.a'))),
    );
    await tester.pumpAndSettle();

    await tester.drag(
      find.byKey(const ValueKey('detail.viewer')),
      const Offset(-360, 0),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('detail.zoomViewer.b')), findsOneWidget);
    expect(_detailPage(tester), 1);
    await _pinchZoom(tester, 'b', pointerStart: 21);
    expect(_imageScale(tester, 'b'), greaterThan(1));
    final controlsSize = tester.getSize(
      find.byKey(const ValueKey('detail.controlsRow')),
    );
    expect(controlsSize.height, greaterThanOrEqualTo(48));

    await tester.drag(
      find.byKey(const ValueKey('detail.bottomOverlay')),
      const Offset(0, -180),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('detail.promptText')), findsOneWidget);
    expect(find.textContaining('Other prompt'), findsOneWidget);
    expect(find.byType(BottomSheet), findsNothing);
  });

  testWidgets('detail page width-fits tall images and keeps page gestures',
      (tester) async {
    final controller = PixromptController(
      MemoryPixromptRepository(
        initialImages: [
          PromptImageItem.sample(
            uid: 'tall',
            imageKey: 'missing-tall',
            prompt: 'Tall image',
            aspectRatio: 0.25,
            createdAt: 30,
          ),
          PromptImageItem.sample(
            uid: 'wide',
            imageKey: 'missing-wide',
            prompt: 'Wide image',
            aspectRatio: 1.6,
            createdAt: 20,
          ),
        ],
      ),
    );
    await controller.initialize();

    await tester.pumpWidget(_app(controller));
    await tester.pump();
    final tallTileTop =
        tester.getTopLeft(find.byKey(const ValueKey('gallery.tile.tall')));
    await tester.tapAt(tallTileTop + const Offset(24, 24));
    await tester.pumpAndSettle();

    final viewportSize =
        tester.getSize(find.byKey(const ValueKey('detail.viewport.tall')));
    final imageSurfaceSize =
        tester.getSize(find.byKey(const ValueKey('detail.imageSurface.tall')));
    expect(imageSurfaceSize.width, viewportSize.width);
    expect(imageSurfaceSize.height, greaterThan(viewportSize.height));
    expect(_imageScale(tester, 'tall'), 1);

    await tester.drag(
      find.byKey(const ValueKey('detail.zoomViewer.tall')),
      const Offset(0, -180),
    );
    await tester.pumpAndSettle();
    expect(_imageScale(tester, 'tall'), 1);
    expect(
        find.byKey(const ValueKey('detail.zoomViewer.tall')), findsOneWidget);

    await tester.drag(
      find.byKey(const ValueKey('detail.viewer')),
      const Offset(-360, 0),
    );
    await tester.pumpAndSettle();
    expect(
        find.byKey(const ValueKey('detail.zoomViewer.wide')), findsOneWidget);
  });

  testWidgets(
      'detail actions edit metadata, show edit history, and pop on back',
      (tester) async {
    final controller = PixromptController(
      MemoryPixromptRepository(
        initialImages: [
          PromptImageItem.sample(
            uid: 'root',
            imageKey: 'missing-root',
            prompt: 'Base prompt',
            categoryAssignments: const {
              sourceDimensionId: 'Gemini',
              'subject': '运动',
            },
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
      ),
    );
    await controller.initialize();

    await tester.pumpWidget(_app(controller));
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('gallery.tile.edit')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('detail.fullscreen')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('detail.detailsAction')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('image.metadataPage')), findsOneWidget);
    expect(find.text('Prompt 编辑信息'), findsOneWidget);
    expect(find.byKey(const ValueKey('image.categoryAction.source')),
        findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('image.categoryAction.source')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('image.categoryEditor.source')),
        findsOneWidget);
    await tester
        .tap(find.byKey(const ValueKey('image.categoryChoice.source.ChatGPT')));
    await tester.pumpAndSettle();
    expect(
      controller.state.allImages
          .firstWhere((image) => image.uid == 'edit')
          .categoryAssignments[sourceDimensionId],
      'ChatGPT',
    );
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('detail.fullscreen')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('detail.relatedAction')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('image.editHistoryPage')), findsOneWidget);
    expect(find.byKey(const ValueKey('systemUi.edgeToEdge')), findsWidgets);
    expect(find.byKey(const ValueKey('history.graphCanvas')), findsOneWidget);
    expect(find.byKey(const ValueKey('history.node.root')), findsOneWidget);
    expect(find.byKey(const ValueKey('history.node.edit')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('history.edge.root.Make it warmer')),
      findsOneWidget,
    );
    expect(
        find.byKey(const ValueKey('history.userMessage.root')), findsNothing);
    expect(
      find.byKey(const ValueKey('history.assistantMessage.root')),
      findsNothing,
    );

    await tester.tap(
      find.byKey(const ValueKey('history.edge.root.Make it warmer')),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('history.promptSheet')), findsOneWidget);
    expect(find.text('Make it warmer'), findsWidgets);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('history.node.root')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('detail.fullscreen')), findsOneWidget);
    expect(find.byKey(const ValueKey('detail.relatedAction')), findsNothing);
    expect(
        find.byKey(const ValueKey('detail.zoomViewer.root')), findsOneWidget);
    await tester.drag(
      find.byKey(const ValueKey('detail.viewer')),
      const Offset(-360, 0),
    );
    await tester.pumpAndSettle();
    expect(
        find.byKey(const ValueKey('detail.zoomViewer.edit')), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('image.editHistoryPage')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('history.returnHighlight.edit')),
      findsOneWidget,
    );

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('detail.fullscreen')), findsOneWidget);
    await _pinchZoom(tester, 'edit', pointerStart: 31);
    expect(_imageScale(tester, 'edit'), greaterThan(1));

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('detail.fullscreen')), findsNothing);
    expect(find.byKey(const ValueKey('gallery.waterfall')), findsOneWidget);
  });

  testWidgets(
      'long press shows a bottom selection toolbar with category action',
      (tester) async {
    final controller = PixromptController(
      MemoryPixromptRepository(
        initialImages: [
          PromptImageItem.sample(uid: 'a', imageKey: 'missing-a', createdAt: 2),
          PromptImageItem.sample(uid: 'b', imageKey: 'missing-b', createdAt: 1),
        ],
      ),
    );
    await controller.initialize();

    await tester.pumpWidget(_app(controller));
    await tester.pump();

    await tester.longPress(find.byKey(const ValueKey('gallery.tile.a')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('gallery.tile.b')));
    await tester.pump();

    expect(
        find.byKey(const ValueKey('gallery.selectionToolbar')), findsOneWidget);
    expect(
        find.byKey(const ValueKey('selection.assignCategory')), findsOneWidget);
    expect(find.byKey(const ValueKey('selection.delete')), findsOneWidget);
    expect(find.text('2'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('selection.delete')));
    await tester.pumpAndSettle();

    expect(controller.state.allImages, isEmpty);
  });
}

class _FakeFileActions extends PixromptFileActions {
  const _FakeFileActions(this.loaders);

  final List<PickedImageLoader> loaders;

  @override
  Future<List<PickedImageLoader>> pickImageLoaders() async => loaders;
}

PixromptApp _app(
  PixromptController controller, {
  PixromptFileActions? fileActions,
}) {
  return PixromptApp(
    controller: controller,
    syncController: PixromptSyncController(
      pixromptController: controller,
      syncStateRepository: MemorySyncStateRepository(),
    ),
    fileActions: fileActions,
  );
}

String Function() _uids(List<String> values) {
  var index = 0;
  return () => values[index++];
}

Future<void> _pinchZoom(
  WidgetTester tester,
  String uid, {
  int pointerStart = 11,
}) async {
  final finder = find.byKey(ValueKey('detail.zoomViewer.$uid'));
  final center = tester.getCenter(finder);
  final firstFinger = await tester.createGesture(pointer: pointerStart);
  final secondFinger = await tester.createGesture(pointer: pointerStart + 1);
  await firstFinger.down(center - const Offset(20, 0));
  await secondFinger.down(center + const Offset(20, 0));
  await tester.pump();
  await firstFinger.moveTo(center - const Offset(100, 0));
  await secondFinger.moveTo(center + const Offset(100, 0));
  await tester.pump();
  await firstFinger.up();
  await secondFinger.up();
  await tester.pumpAndSettle();
}

double _imageScale(WidgetTester tester, String uid) {
  final viewer = tester.widget<InteractiveViewer>(
    find.byKey(ValueKey('detail.zoomViewer.$uid')),
  );
  return viewer.transformationController!.value.getMaxScaleOnAxis();
}

Matrix4 _imageMatrix(WidgetTester tester, String uid) {
  final viewer = tester.widget<InteractiveViewer>(
    find.byKey(ValueKey('detail.zoomViewer.$uid')),
  );
  return viewer.transformationController!.value.clone();
}

double _detailPage(WidgetTester tester) {
  final pageView = tester.widget<PageView>(
    find.byKey(const ValueKey('detail.pageView')),
  );
  return pageView.controller!.page ??
      pageView.controller!.initialPage.toDouble();
}
