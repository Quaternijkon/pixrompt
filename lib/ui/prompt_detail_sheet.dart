import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../app/pixrompt_controller.dart';
import '../domain/category_dimension.dart';
import '../domain/prompt_image.dart';
import '../domain/prompt_lineage.dart';
import 'pixrompt_design.dart';
import 'stored_image.dart';
import 'system_ui.dart';

const _zoomGestureGateScale = 1.01;
const _mediaSurface = PixromptPalette.darkSurface;
const _mediaSurfaceHigh = PixromptPalette.darkSurfaceHigh;
const _mediaBorder = PixromptPalette.darkOutline;

class PromptDetailSheet extends StatefulWidget {
  const PromptDetailSheet({
    super.key,
    required this.controller,
    required this.images,
    required this.initialIndex,
    required this.onCopy,
    required this.onAppendEdit,
    required this.onEditText,
    required this.onDelete,
    required this.onFilterSamePrompt,
    this.showEditHistoryAction = true,
  });

  final PixromptController controller;
  final List<PromptImageItem> images;
  final int initialIndex;
  final ValueChanged<PromptImageItem> onCopy;
  final ValueChanged<PromptImageItem> onAppendEdit;
  final ValueChanged<PromptImageItem> onEditText;
  final ValueChanged<PromptImageItem> onDelete;
  final ValueChanged<PromptImageItem> onFilterSamePrompt;
  final bool showEditHistoryAction;

  @override
  State<PromptDetailSheet> createState() => _PromptDetailSheetState();
}

class _PromptDetailSheetState extends State<PromptDetailSheet> {
  final Map<String, TransformationController> _transformations = {};
  final Map<String, Size> _viewportSizes = {};
  final Map<String, Size> _contentSizes = {};
  final Set<String> _zoomedImageUids = {};
  final Set<int> _activePointers = {};
  Offset? _doubleTapLocalPosition;
  int? _pageDragPointer;
  Offset? _pageDragStart;
  Offset? _pageDragLast;
  double _pageDragStartPixels = 0;
  var _pageDragActive = false;
  var _pageDragRejected = false;
  late final PageController _pageController;
  late int _index;
  var _promptExpanded = false;

  @override
  void initState() {
    super.initState();
    _index = widget.images.isEmpty
        ? 0
        : math.max(0, math.min(widget.initialIndex, widget.images.length - 1));
    _pageController = PageController(initialPage: _index);
  }

  @override
  void dispose() {
    for (final controller in _transformations.values) {
      controller.dispose();
    }
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.images.isEmpty) {
      return const SizedBox.shrink();
    }
    final current = widget.images[_index];
    final parts =
        promptPartsForImage(current, widget.controller.state.allImages);
    return PixromptEdgeToEdge(
      child: PopScope(
        canPop: false,
        onPopInvoked: (didPop) {
          if (!didPop) _popWithCurrentImage();
        },
        child: Scaffold(
          key: const ValueKey('detail.fullscreen'),
          backgroundColor: Colors.black,
          extendBody: true,
          body: Stack(
            children: [
              Positioned.fill(
                child: KeyedSubtree(
                  key: const ValueKey('detail.viewer'),
                  child: Listener(
                    behavior: HitTestBehavior.opaque,
                    onPointerDown: _handlePagePointerDown,
                    onPointerMove: _handlePagePointerMove,
                    onPointerUp: _handlePagePointerEnd,
                    onPointerCancel: _handlePagePointerEnd,
                    child: PageView.builder(
                      key: const ValueKey('detail.pageView'),
                      controller: _pageController,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: widget.images.length,
                      onPageChanged: (index) {
                        setState(() {
                          _index = index;
                          _promptExpanded = false;
                        });
                      },
                      itemBuilder: (context, index) {
                        return _buildImageViewer(widget.images[index]);
                      },
                    ),
                  ),
                ),
              ),
              SafeArea(
                child: Align(
                  alignment: Alignment.topLeft,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: IconButton.filled(
                      tooltip: '关闭',
                      style: pixromptIconButtonStyle(
                        backgroundColor:
                            PixromptPalette.darkSurface.withOpacity(0.74),
                      ),
                      onPressed: _popWithCurrentImage,
                      icon: const Icon(Icons.close),
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 12,
                right: 12,
                bottom: 0,
                child: _DetailBottomOverlay(
                  expanded: _promptExpanded,
                  promptText: buildPromptChain(parts),
                  showEditHistoryAction: widget.showEditHistoryAction,
                  onExpand: () => setState(() => _promptExpanded = true),
                  onCollapse: () => setState(() => _promptExpanded = false),
                  onCopy: () => widget.onCopy(current),
                  onAppendEdit: () => widget.onAppendEdit(current),
                  onDetails: () => _showMetadata(current),
                  onRelated: () => _showEditHistory(current),
                  onDelete: () => widget.onDelete(current),
                  onFilterSamePrompt: () => widget.onFilterSamePrompt(current),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildImageViewer(PromptImageItem image) {
    final transformation = _transformationFor(image.uid);
    final zoomed = _isZoomed(image.uid);
    return LayoutBuilder(
      builder: (context, constraints) {
        final viewportSize = Size(
          constraints.maxWidth,
          constraints.maxHeight,
        );
        final aspectRatio = image.aspectRatio > 0 ? image.aspectRatio : 1.0;
        final imageHeight = viewportSize.width / aspectRatio;
        final contentHeight = math.max(viewportSize.height, imageHeight);
        final contentSize = Size(viewportSize.width, contentHeight);
        final canPanVertically = imageHeight > viewportSize.height;
        _viewportSizes[image.uid] = viewportSize;
        _contentSizes[image.uid] = contentSize;
        final imageContent = _buildWidthFittedImage(
          image: image,
          viewportSize: viewportSize,
          imageHeight: imageHeight,
          contentHeight: contentHeight,
          alignTop: canPanVertically,
        );
        final viewerChild = zoomed
            ? imageContent
            : SizedBox(
                width: viewportSize.width,
                height: viewportSize.height,
                child: SingleChildScrollView(
                  physics: canPanVertically
                      ? const ClampingScrollPhysics()
                      : const NeverScrollableScrollPhysics(),
                  child: imageContent,
                ),
              );

        return SizedBox.expand(
          key: ValueKey('detail.viewport.${image.uid}'),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onDoubleTapDown: (details) {
              _doubleTapLocalPosition = details.localPosition;
            },
            onDoubleTap: () => _toggleDoubleTapZoom(image.uid),
            child: InteractiveViewer(
              key: ValueKey('detail.zoomViewer.${image.uid}'),
              transformationController: transformation,
              constrained: false,
              minScale: 1,
              maxScale: 8,
              panEnabled: zoomed,
              scaleEnabled: true,
              boundaryMargin: EdgeInsets.zero,
              clipBehavior: Clip.hardEdge,
              child: viewerChild,
            ),
          ),
        );
      },
    );
  }

  Widget _buildWidthFittedImage({
    required PromptImageItem image,
    required Size viewportSize,
    required double imageHeight,
    required double contentHeight,
    required bool alignTop,
  }) {
    return SizedBox(
      width: viewportSize.width,
      height: contentHeight,
      child: Align(
        alignment: alignTop ? Alignment.topCenter : Alignment.center,
        child: SizedBox(
          key: ValueKey('detail.imageSurface.${image.uid}'),
          width: viewportSize.width,
          height: imageHeight,
          child: Semantics(
            key: ValueKey('detail.imageSemantics.${image.uid}'),
            label: _detailImageSemanticLabel(image),
            image: true,
            child: ExcludeSemantics(
              child: StoredImage(
                loader: widget.controller.imageBytes(image.imageKey),
                fit: BoxFit.contain,
                backgroundColor: Colors.black,
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _handlePagePointerDown(PointerDownEvent event) {
    _activePointers.add(event.pointer);
    final canPage = !_isZoomed(widget.images[_index].uid);
    if (_activePointers.length == 1 && canPage && _pageController.hasClients) {
      _pageDragPointer = event.pointer;
      _pageDragStart = event.position;
      _pageDragLast = event.position;
      _pageDragStartPixels = _pageController.position.pixels;
      _pageDragActive = false;
      _pageDragRejected = false;
      return;
    }
    _cancelPageDrag();
  }

  void _handlePagePointerMove(PointerMoveEvent event) {
    final start = _pageDragStart;
    if (event.pointer != _pageDragPointer ||
        start == null ||
        _pageDragRejected ||
        !_pageController.hasClients ||
        _isZoomed(widget.images[_index].uid)) {
      return;
    }
    _pageDragLast = event.position;
    final delta = event.position - start;
    if (!_pageDragActive) {
      if (delta.dy.abs() > 12 && delta.dy.abs() > delta.dx.abs() * 1.2) {
        _pageDragRejected = true;
        return;
      }
      if (delta.dx.abs() < 12 || delta.dx.abs() < delta.dy.abs() * 1.2) {
        return;
      }
      _pageDragActive = true;
    }
    final position = _pageController.position;
    final nextPixels = (_pageDragStartPixels - delta.dx).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    _pageController.jumpTo(nextPixels);
  }

  void _handlePagePointerEnd(PointerEvent event) {
    final shouldSettle = event.pointer == _pageDragPointer && _pageDragActive;
    _activePointers.remove(event.pointer);
    if (shouldSettle) {
      _settlePageDrag();
    }
    if (event.pointer == _pageDragPointer || _activePointers.isEmpty) {
      _cancelPageDrag();
    }
  }

  void _settlePageDrag() {
    if (!_pageController.hasClients) return;
    final start = _pageDragStart;
    final last = _pageDragLast;
    final viewport = _pageController.position.viewportDimension;
    if (start == null || last == null || viewport <= 0) return;
    final delta = last - start;
    final startPage = (_pageDragStartPixels / viewport).round();
    var targetPage = startPage;
    final movedPages =
        (_pageController.position.pixels - _pageDragStartPixels).abs() /
            viewport;
    if (delta.dx.abs() > 96 || movedPages > 0.25) {
      targetPage += delta.dx < 0 ? 1 : -1;
    }
    targetPage = targetPage.clamp(0, widget.images.length - 1);
    _pageController.animateToPage(
      targetPage,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
    );
  }

  void _cancelPageDrag() {
    _pageDragPointer = null;
    _pageDragStart = null;
    _pageDragLast = null;
    _pageDragStartPixels = 0;
    _pageDragActive = false;
    _pageDragRejected = false;
  }

  void _toggleDoubleTapZoom(String uid) {
    final transformation = _transformationFor(uid);
    final currentScale = transformation.value.getMaxScaleOnAxis();
    if (currentScale > _zoomGestureGateScale) {
      transformation.value = Matrix4.identity();
      return;
    }

    final tap = _doubleTapLocalPosition;
    if (tap == null) {
      transformation.value = _matrixForZoom(uid, Offset.zero);
      return;
    }
    transformation.value = _matrixForZoom(uid, tap);
  }

  Matrix4 _matrixForZoom(String uid, Offset tap) {
    const targetScale = 2.5;
    final viewportSize = _viewportSizes[uid];
    final contentSize = _contentSizes[uid];
    if (viewportSize == null || contentSize == null) {
      return Matrix4.identity()..scale(targetScale);
    }
    final minX = math.min(
      0.0,
      viewportSize.width - contentSize.width * targetScale,
    );
    final minY = math.min(
      0.0,
      viewportSize.height - contentSize.height * targetScale,
    );
    final x = (-tap.dx * (targetScale - 1)).clamp(minX, 0.0);
    final y = (-tap.dy * (targetScale - 1)).clamp(minY, 0.0);
    return Matrix4.identity()
      ..translate(x, y)
      ..scale(targetScale);
  }

  double _scaleFor(String uid) {
    return _transformationFor(uid).value.getMaxScaleOnAxis();
  }

  bool _isZoomed(String uid) {
    return _scaleFor(uid) > _zoomGestureGateScale;
  }

  TransformationController _transformationFor(String uid) {
    return _transformations.putIfAbsent(
      uid,
      () {
        final controller = TransformationController();
        controller.addListener(() => _syncZoomState(uid, controller));
        return controller;
      },
    );
  }

  void _syncZoomState(String uid, TransformationController controller) {
    final zoomed = controller.value.getMaxScaleOnAxis() > _zoomGestureGateScale;
    final changed =
        zoomed ? _zoomedImageUids.add(uid) : _zoomedImageUids.remove(uid);
    if (changed && mounted) {
      setState(() {});
    }
  }

  void _showMetadata(PromptImageItem image) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => ImageMetadataPage(
          controller: widget.controller,
          image: image,
          onEditPrompt: () => widget.onEditText(image),
        ),
      ),
    );
  }

  void _showEditHistory(PromptImageItem image) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => ImageEditHistoryPage(
          controller: widget.controller,
          image: image,
          onCopy: widget.onCopy,
          onAppendEdit: widget.onAppendEdit,
          onEditText: widget.onEditText,
          onDelete: widget.onDelete,
          onFilterSamePrompt: widget.onFilterSamePrompt,
        ),
      ),
    );
  }

  void _popWithCurrentImage() {
    Navigator.of(context).pop(widget.images[_index].uid);
  }
}

class _DetailBottomOverlay extends StatelessWidget {
  const _DetailBottomOverlay({
    required this.expanded,
    required this.promptText,
    required this.showEditHistoryAction,
    required this.onExpand,
    required this.onCollapse,
    required this.onCopy,
    required this.onAppendEdit,
    required this.onDetails,
    required this.onRelated,
    required this.onDelete,
    required this.onFilterSamePrompt,
  });

  final bool expanded;
  final String promptText;
  final bool showEditHistoryAction;
  final VoidCallback onExpand;
  final VoidCallback onCollapse;
  final VoidCallback onCopy;
  final VoidCallback onAppendEdit;
  final VoidCallback onDetails;
  final VoidCallback onRelated;
  final VoidCallback onDelete;
  final VoidCallback onFilterSamePrompt;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      minimum: const EdgeInsets.only(bottom: 8),
      child: GestureDetector(
        key: const ValueKey('detail.bottomOverlay'),
        behavior: HitTestBehavior.opaque,
        onVerticalDragUpdate: (details) {
          if (details.primaryDelta == null) return;
          if (details.primaryDelta! < -4) onExpand();
          if (details.primaryDelta! > 4) onCollapse();
        },
        child: DecoratedBox(
          decoration: pixromptSurfaceDecoration(
            color: PixromptPalette.darkSurface.withOpacity(0.80),
            radius: PixromptRadius.xl,
            borderColor: PixromptPalette.darkOutlineStrong,
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 7, 8, 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 34,
                    height: 3,
                    margin: const EdgeInsets.only(bottom: 4),
                    decoration: BoxDecoration(
                      color: Colors.white38,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
                SizedBox(
                  key: const ValueKey('detail.controlsRow'),
                  width: double.infinity,
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final leading = [
                        IconButton(
                          key: const ValueKey('detail.filterSamePrompt'),
                          tooltip: '筛选同 Prompt',
                          color: Colors.white,
                          style: _detailActionStyle(),
                          onPressed: onFilterSamePrompt,
                          icon: const Icon(Icons.filter_alt_outlined),
                        ),
                        IconButton(
                          tooltip: '复制 Prompt',
                          color: Colors.white,
                          style: _detailActionStyle(),
                          onPressed: onCopy,
                          icon: const Icon(Icons.copy),
                        ),
                        IconButton(
                          tooltip: '追加编辑',
                          color: Colors.white,
                          style: _detailActionStyle(),
                          onPressed: onAppendEdit,
                          icon: const Icon(
                            Icons.add_photo_alternate_outlined,
                          ),
                        ),
                        if (showEditHistoryAction)
                          IconButton(
                            key: const ValueKey('detail.relatedAction'),
                            tooltip: '编辑历史',
                            color: Colors.white,
                            style: _detailActionStyle(),
                            onPressed: onRelated,
                            icon: const Icon(Icons.history_outlined),
                          ),
                      ];
                      final trailing = [
                        IconButton(
                          key: const ValueKey('detail.detailsAction'),
                          tooltip: '查看详情',
                          color: Colors.white,
                          style: _detailActionStyle(),
                          onPressed: onDetails,
                          icon: const Icon(Icons.info_outline),
                        ),
                        IconButton(
                          key: const ValueKey('detail.deleteAction'),
                          tooltip: '删除',
                          color: Colors.white,
                          style: _detailActionStyle(destructive: true),
                          onPressed: onDelete,
                          icon: const Icon(Icons.delete_outline),
                        ),
                      ];

                      if (constraints.maxWidth >=
                          _detailControlsWideWidth(showEditHistoryAction)) {
                        return Row(
                          children: [
                            ..._withControlGaps(leading),
                            const Spacer(),
                            ..._withControlGaps(trailing),
                          ],
                        );
                      }
                      return SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: _withControlGaps([
                            ...leading,
                            ...trailing,
                          ]),
                        ),
                      );
                    },
                  ),
                ),
                AnimatedSize(
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOutCubic,
                  alignment: Alignment.topCenter,
                  child: expanded
                      ? Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const Divider(color: Colors.white24, height: 14),
                            ConstrainedBox(
                              constraints: BoxConstraints(
                                maxHeight:
                                    MediaQuery.sizeOf(context).height * 0.42,
                              ),
                              child: SingleChildScrollView(
                                child: SelectableText(
                                  key: const ValueKey('detail.promptText'),
                                  promptText,
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodyMedium
                                      ?.copyWith(
                                        color: Colors.white,
                                        height: 1.45,
                                      ),
                                ),
                              ),
                            ),
                          ],
                        )
                      : const SizedBox.shrink(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

ButtonStyle _detailActionStyle({bool destructive = false}) {
  return pixromptIconButtonStyle(destructive: destructive);
}

double _detailControlsWideWidth(bool showEditHistoryAction) {
  final buttonCount = showEditHistoryAction ? 6 : 5;
  final intraGroupGapCount = showEditHistoryAction ? 4 : 3;
  return buttonCount * 48 + intraGroupGapCount * 8;
}

String _detailImageSemanticLabel(PromptImageItem image) {
  final prompt = image.prompt.trim();
  final fileName = image.originalFileName?.trim();
  return [
    '图片',
    if (prompt.isNotEmpty) 'Prompt：$prompt',
    if (fileName != null && fileName.isNotEmpty) '文件：$fileName',
  ].join('，');
}

List<Widget> _withControlGaps(List<Widget> controls) {
  return [
    for (var index = 0; index < controls.length; index++) ...[
      if (index > 0) const SizedBox(width: 8),
      controls[index],
    ],
  ];
}

class ImageMetadataPage extends StatelessWidget {
  const ImageMetadataPage({
    super.key,
    required this.controller,
    required this.image,
    required this.onEditPrompt,
  });

  final PixromptController controller;
  final PromptImageItem image;
  final VoidCallback onEditPrompt;

  @override
  Widget build(BuildContext context) {
    return PixromptEdgeToEdge(
      child: AnimatedBuilder(
        animation: controller,
        builder: (context, _) {
          final current = _latestImage(controller, image);
          final steps = promptConversationForImage(
            current,
            controller.state.allImages,
          );
          return Scaffold(
            key: const ValueKey('image.metadataPage'),
            backgroundColor: PixromptPalette.darkBackground,
            appBar: AppBar(title: const Text('图片详情')),
            body: ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
              children: [
                Text('分类维度', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                for (final dimension in controller.state.categoryDimensions)
                  ListTile(
                    key: ValueKey('image.categoryAction.${dimension.id}'),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 4,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    tileColor: _mediaSurface,
                    textColor: Colors.white,
                    iconColor: Colors.white70,
                    leading: const Icon(Icons.label_outline),
                    title: Text(dimension.name),
                    subtitle: Text(
                      current.categoryLabel(dimension.id),
                      style: const TextStyle(color: Colors.white60),
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _showCategoryEditor(
                      context,
                      current,
                      dimension,
                    ),
                  ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Text(
                      'Prompt 编辑信息',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const Spacer(),
                    FilledButton.tonalIcon(
                      onPressed: onEditPrompt,
                      icon: const Icon(Icons.edit_outlined),
                      label: const Text('编辑'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                for (var index = 0; index < steps.length; index++)
                  ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 4,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    tileColor: _mediaSurface,
                    textColor: Colors.white,
                    iconColor: Colors.white70,
                    leading: CircleAvatar(
                      backgroundColor: _mediaSurfaceHigh,
                      foregroundColor: Colors.white,
                      child: Text('${index + 1}'),
                    ),
                    title: Text(steps[index].prompt),
                    subtitle: Text(
                      steps[index].imageUid,
                      style: const TextStyle(color: Colors.white60),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _showCategoryEditor(
    BuildContext context,
    PromptImageItem image,
    CategoryDimension dimension,
  ) {
    return showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (context) {
        return _ImageCategoryEditorSheet(
          controller: controller,
          image: image,
          dimension: dimension,
        );
      },
    );
  }
}

class _ImageCategoryEditorSheet extends StatelessWidget {
  const _ImageCategoryEditorSheet({
    required this.controller,
    required this.image,
    required this.dimension,
  });

  final PixromptController controller;
  final PromptImageItem image;
  final CategoryDimension dimension;

  @override
  Widget build(BuildContext context) {
    final current = image.categoryLabel(dimension.id);
    final items = [
      uncategorizedCategory,
      ...dimension.items,
      if (current != uncategorizedCategory &&
          !dimension.items.contains(current))
        current,
    ];
    return Padding(
      key: ValueKey('image.categoryEditor.${dimension.id}'),
      padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(dimension.name, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final item in items)
                ChoiceChip(
                  key: ValueKey('image.categoryChoice.${dimension.id}.$item'),
                  label: Text(item),
                  selected: item == current,
                  onSelected: (_) => _selectCategory(context, item),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _selectCategory(BuildContext context, String item) async {
    final assignments = {...image.categoryAssignments};
    if (item == uncategorizedCategory) {
      assignments.remove(dimension.id);
    } else {
      assignments[dimension.id] = item;
    }
    await controller.updateImage(
      image.uid,
      prompt: image.prompt,
      categoryAssignments: assignments,
    );
    if (context.mounted) Navigator.of(context).pop();
  }
}

class ImageEditHistoryPage extends StatefulWidget {
  const ImageEditHistoryPage({
    super.key,
    required this.controller,
    required this.image,
    required this.onCopy,
    required this.onAppendEdit,
    required this.onEditText,
    required this.onDelete,
    required this.onFilterSamePrompt,
  });

  final PixromptController controller;
  final PromptImageItem image;
  final ValueChanged<PromptImageItem> onCopy;
  final ValueChanged<PromptImageItem> onAppendEdit;
  final ValueChanged<PromptImageItem> onEditText;
  final ValueChanged<PromptImageItem> onDelete;
  final ValueChanged<PromptImageItem> onFilterSamePrompt;

  @override
  State<ImageEditHistoryPage> createState() => _ImageEditHistoryPageState();
}

class _ImageEditHistoryPageState extends State<ImageEditHistoryPage> {
  String? _highlightedImageUid;

  @override
  Widget build(BuildContext context) {
    final tree = promptEditTreeForImage(
      widget.image,
      widget.controller.state.allImages,
    );
    final layout = _EditTreeLayout.compute(tree);
    return PixromptEdgeToEdge(
      child: Scaffold(
        key: const ValueKey('image.editHistoryPage'),
        backgroundColor: PixromptPalette.darkBackground,
        appBar: AppBar(title: const Text('编辑历史')),
        body: InteractiveViewer(
          key: const ValueKey('history.graphCanvas'),
          minScale: 0.35,
          maxScale: 3,
          boundaryMargin: const EdgeInsets.all(480),
          constrained: false,
          child: SizedBox(
            width: layout.size.width,
            height: layout.size.height,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned.fill(
                  child: CustomPaint(
                    painter: _EditTreePainter(layout.edges),
                  ),
                ),
                for (final edge in layout.edges)
                  Positioned(
                    left: edge.labelCenter.dx - 72,
                    top: edge.labelCenter.dy - 22,
                    child: _PromptEdgeChip(
                      edge: edge.edge,
                      onTap: () => _showPromptEdge(context, edge.edge.prompt),
                    ),
                  ),
                for (final entry in layout.nodes.entries)
                  Positioned(
                    left: entry.value.left,
                    top: entry.value.top,
                    width: entry.value.width,
                    height: entry.value.height,
                    child: _EditTreeNodeCard(
                      controller: widget.controller,
                      image: entry.value.node.image,
                      highlighted:
                          _highlightedImageUid == entry.value.node.image.uid,
                      onTap: () => _openTreeDetail(
                        context,
                        tree,
                        entry.value.node.image,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _openTreeDetail(
    BuildContext context,
    PromptEditTree tree,
    PromptImageItem image,
  ) async {
    final images = tree.images;
    final initialIndex = images.indexWhere((item) => item.uid == image.uid);
    if (initialIndex < 0) return;
    final selectedUid = await Navigator.of(context).push<String?>(
      MaterialPageRoute<String?>(
        fullscreenDialog: true,
        builder: (context) {
          return PromptDetailSheet(
            controller: widget.controller,
            images: images,
            initialIndex: initialIndex,
            showEditHistoryAction: false,
            onCopy: widget.onCopy,
            onAppendEdit: widget.onAppendEdit,
            onEditText: widget.onEditText,
            onDelete: widget.onDelete,
            onFilterSamePrompt: widget.onFilterSamePrompt,
          );
        },
      ),
    );
    if (!mounted) return;
    setState(() => _highlightedImageUid = selectedUid ?? image.uid);
  }

  Future<void> _showPromptEdge(BuildContext context, String prompt) {
    return showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (context) {
        return PixromptSheetFrame(
          key: const ValueKey('history.promptSheet'),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('编辑 Prompt', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: PixromptSpace.md),
              SelectableText(
                prompt,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      height: 1.45,
                    ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _EditTreeNodeCard extends StatelessWidget {
  const _EditTreeNodeCard({
    required this.controller,
    required this.image,
    required this.highlighted,
    required this.onTap,
  });

  final PixromptController controller;
  final PromptImageItem image;
  final bool highlighted;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final content = Semantics(
      key: ValueKey('history.node.${image.uid}'),
      label: _historyNodeSemanticLabel(image),
      button: true,
      selected: highlighted ? true : null,
      onTap: onTap,
      child: ExcludeSemantics(
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          decoration: BoxDecoration(
            color: highlighted
                ? Theme.of(context).colorScheme.primary.withOpacity(0.18)
                : _mediaSurface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: highlighted
                  ? Theme.of(context).colorScheme.primary
                  : _mediaBorder,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.26),
                blurRadius: 18,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(18),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              excludeFromSemantics: true,
              borderRadius: BorderRadius.circular(18),
              splashColor: Colors.white.withOpacity(0.16),
              highlightColor: Colors.white.withOpacity(0.10),
              focusColor: Colors.white.withOpacity(0.12),
              hoverColor: Colors.white.withOpacity(0.08),
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.all(7),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: StoredImage(
                          loader: controller.imageBytes(image.imageKey),
                          fit: BoxFit.cover,
                          backgroundColor: _mediaSurfaceHigh,
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      image.prompt,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: Colors.white.withOpacity(0.76),
                            height: 1.2,
                          ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    if (!highlighted) return content;
    return KeyedSubtree(
      key: ValueKey('history.returnHighlight.${image.uid}'),
      child: content,
    );
  }
}

String _historyNodeSemanticLabel(PromptImageItem image) {
  final prompt = image.prompt.trim();
  final fileName = image.originalFileName?.trim();
  return [
    '打开历史图片',
    if (prompt.isNotEmpty) 'Prompt：$prompt',
    if (fileName != null && fileName.isNotEmpty) '文件：$fileName',
  ].join('，');
}

class _PromptEdgeChip extends StatelessWidget {
  const _PromptEdgeChip({
    required this.edge,
    required this.onTap,
  });

  final PromptEditTreeEdge edge;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      key: ValueKey('history.edge.${edge.parentImageUid}.${edge.prompt}'),
      label: '查看编辑 Prompt：${edge.prompt}',
      button: true,
      onTap: onTap,
      child: ExcludeSemantics(
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.28),
                blurRadius: 16,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Material(
            color: PixromptPalette.darkSurfaceHigh.withOpacity(0.92),
            borderRadius: BorderRadius.circular(999),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              excludeFromSemantics: true,
              borderRadius: BorderRadius.circular(999),
              splashColor: Colors.white.withOpacity(0.16),
              highlightColor: Colors.white.withOpacity(0.10),
              focusColor: Colors.white.withOpacity(0.12),
              hoverColor: Colors.white.withOpacity(0.08),
              onTap: onTap,
              child: Container(
                width: 144,
                constraints: const BoxConstraints(minHeight: 44),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.call_split, size: 16),
                    const SizedBox(width: 5),
                    Flexible(
                      child: Text(
                        edge.prompt,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelMedium,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _EditTreeLayout {
  const _EditTreeLayout({
    required this.size,
    required this.nodes,
    required this.edges,
  });

  static const nodeWidth = 132.0;
  static const nodeHeight = 164.0;
  static const xGap = 240.0;
  static const yGap = 190.0;
  static const padding = 36.0;

  final Size size;
  final Map<String, _LaidOutNode> nodes;
  final List<_LaidOutEdge> edges;

  static _EditTreeLayout compute(PromptEditTree tree) {
    final nodeCenters = <String, Offset>{};
    var nextLeafY = padding + nodeHeight / 2;
    var maxDepth = 0;

    double place(PromptEditTreeNode node, int depth) {
      maxDepth = math.max(maxDepth, depth);
      final childYs = <double>[];
      for (final edge in node.edges) {
        for (final child in edge.children) {
          childYs.add(place(child, depth + 1));
        }
      }
      final centerY = childYs.isEmpty
          ? nextLeafY
          : childYs.reduce((a, b) => a + b) / childYs.length;
      if (childYs.isEmpty) nextLeafY += yGap;
      nodeCenters[node.image.uid] = Offset(
        padding + nodeWidth / 2 + depth * xGap,
        centerY,
      );
      return centerY;
    }

    place(tree.root, 0);

    final nodes = <String, _LaidOutNode>{};
    void collectNodes(PromptEditTreeNode node) {
      final center = nodeCenters[node.image.uid]!;
      nodes[node.image.uid] = _LaidOutNode(
        node: node,
        rect: Rect.fromCenter(
          center: center,
          width: nodeWidth,
          height: nodeHeight,
        ),
      );
      for (final edge in node.edges) {
        for (final child in edge.children) {
          collectNodes(child);
        }
      }
    }

    collectNodes(tree.root);

    final edges = <_LaidOutEdge>[];
    void collectEdges(PromptEditTreeNode node) {
      final parentRect = nodes[node.image.uid]!.rect;
      for (final edge in node.edges) {
        final childRects = [
          for (final child in edge.children) nodes[child.image.uid]!.rect,
        ];
        final childCenterY =
            childRects.map((rect) => rect.center.dy).reduce((a, b) => a + b) /
                childRects.length;
        final labelCenter = Offset(
          parentRect.right + (xGap - nodeWidth) / 2,
          childCenterY,
        );
        edges.add(
          _LaidOutEdge(
            edge: edge,
            parentRect: parentRect,
            labelCenter: labelCenter,
            childRects: childRects,
          ),
        );
        for (final child in edge.children) {
          collectEdges(child);
        }
      }
    }

    collectEdges(tree.root);

    final depthWidth = padding * 2 + nodeWidth + maxDepth * xGap;
    final contentHeight = math.max(nextLeafY + padding, 360.0);
    return _EditTreeLayout(
      size: Size(math.max(depthWidth, 420.0), contentHeight),
      nodes: nodes,
      edges: edges,
    );
  }
}

class _LaidOutNode {
  const _LaidOutNode({
    required this.node,
    required this.rect,
  });

  final PromptEditTreeNode node;
  final Rect rect;

  double get left => rect.left;
  double get top => rect.top;
  double get width => rect.width;
  double get height => rect.height;
}

class _LaidOutEdge {
  const _LaidOutEdge({
    required this.edge,
    required this.parentRect,
    required this.labelCenter,
    required this.childRects,
  });

  final PromptEditTreeEdge edge;
  final Rect parentRect;
  final Offset labelCenter;
  final List<Rect> childRects;
}

class _EditTreePainter extends CustomPainter {
  const _EditTreePainter(this.edges);

  final List<_LaidOutEdge> edges;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withOpacity(0.26)
      ..strokeWidth = 1.6
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final arrowPaint = Paint()
      ..color = Colors.white.withOpacity(0.42)
      ..style = PaintingStyle.fill;

    for (final edge in edges) {
      final start = Offset(edge.parentRect.right, edge.labelCenter.dy);
      final label = edge.labelCenter;
      canvas.drawLine(start, Offset(label.dx - 78, label.dy), paint);
      canvas.drawLine(Offset(label.dx + 78, label.dy), label, paint);
      for (final childRect in edge.childRects) {
        final end = Offset(childRect.left, childRect.center.dy);
        canvas.drawLine(Offset(label.dx + 78, label.dy), end, paint);
        _drawArrow(canvas, arrowPaint, end);
      }
    }
  }

  void _drawArrow(Canvas canvas, Paint paint, Offset tip) {
    final path = Path()
      ..moveTo(tip.dx, tip.dy)
      ..lineTo(tip.dx - 8, tip.dy - 5)
      ..lineTo(tip.dx - 8, tip.dy + 5)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _EditTreePainter oldDelegate) {
    return oldDelegate.edges != edges;
  }
}

PromptImageItem _latestImage(
  PixromptController controller,
  PromptImageItem fallback,
) {
  for (final image in controller.state.allImages) {
    if (image.uid == fallback.uid) return image;
  }
  return fallback;
}
