import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';

import '../app/pixrompt_controller.dart';
import '../app/pixrompt_sync_controller.dart';
import '../domain/prompt_image.dart';
import '../domain/prompt_lineage.dart';
import '../platform/pixrompt_file_actions.dart';
import 'category_assignment_sheet.dart';
import 'category_drawer.dart';
import 'gallery_tile.dart';
import 'prompt_detail_sheet.dart';
import 'prompt_editor_sheet.dart';
import 'search_sheet.dart';
import 'settings_sheet.dart';
import 'sync_center_page.dart';
import 'system_ui.dart';

class GalleryShell extends StatefulWidget {
  const GalleryShell({
    super.key,
    required this.controller,
    required this.syncController,
    required this.fileActions,
  });

  final PixromptController controller;
  final PixromptSyncController syncController;
  final PixromptFileActions fileActions;

  @override
  State<GalleryShell> createState() => _GalleryShellState();
}

class _GalleryShellState extends State<GalleryShell> {
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  final Set<String> _selectedImageUids = {};

  PixromptController get controller => widget.controller;
  bool get _selectionMode => _selectedImageUids.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final state = controller.state;
        _selectedImageUids.removeWhere(
          (uid) => state.allImages.every((image) => image.uid != uid),
        );
        return PixromptEdgeToEdge(
          child: Scaffold(
            key: _scaffoldKey,
            backgroundColor: Colors.black,
            drawer: CategoryDrawer(controller: controller),
            extendBody: true,
            resizeToAvoidBottomInset: false,
            body: Stack(
              children: [
                Positioned.fill(
                  child: _HomeSwipeListener(
                    onSwipeRight: () {
                      if (!_selectionMode) {
                        _scaffoldKey.currentState?.openDrawer();
                      }
                    },
                    onSwipeLeft: () {
                      if (!_selectionMode) _showSearchSheet(context);
                    },
                    child: _ColumnScaleListener(
                      columns: state.settings.columns,
                      onColumnsChanged: controller.setColumns,
                      child: _GalleryWaterfall(
                        controller: controller,
                        selectedImageUids: _selectedImageUids,
                        selectionMode: _selectionMode,
                        onOpenImage: _showImageDetail,
                        onSelectImage: _toggleSelection,
                        onStartSelection: _startSelection,
                      ),
                    ),
                  ),
                ),
                if (_selectionMode)
                  _SelectionToolbar(
                    key: const ValueKey('gallery.selectionToolbar'),
                    count: _selectedImageUids.length,
                    onCancel: _clearSelection,
                    onAssignCategory: _assignSelectedCategory,
                    onDelete: _deleteSelectedImages,
                  )
                else
                  _TopRightActions(
                    key: const ValueKey('gallery.topActions'),
                    activeFilterCount: state.searchFilters.activeFilterCount(),
                    pendingSyncCount:
                        state.allImages.where(_pendingSync).length,
                    onCategory: () => _scaffoldKey.currentState?.openDrawer(),
                    onSearch: () => _showSearchSheet(context),
                    onSync: () => _showSyncCenterPage(context),
                    onSettings: () => _showSettingsSheet(context),
                  ),
                if (!_selectionMode)
                  Positioned(
                    right: 14,
                    bottom: 14,
                    child: _OverlayCluster(
                      children: [
                        _OverlayIconButton(
                          buttonKey: const ValueKey('gallery.addAction'),
                          tooltip: '添加图片',
                          icon: Icons.add_photo_alternate_outlined,
                          onPressed: () => _startAddFlow(context),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _startSelection(PromptImageItem image) {
    setState(() => _selectedImageUids.add(image.uid));
  }

  void _toggleSelection(PromptImageItem image) {
    setState(() {
      if (!_selectedImageUids.add(image.uid)) {
        _selectedImageUids.remove(image.uid);
      }
    });
  }

  void _clearSelection() {
    setState(_selectedImageUids.clear);
  }

  Future<void> _assignSelectedCategory() async {
    final selected = _selectedImageUids.toList(growable: false);
    await showCategoryAssignmentSheet(
      context,
      controller: controller,
      selectedImageUids: selected,
    );
    if (!mounted) return;
    _clearSelection();
  }

  Future<void> _deleteSelectedImages() async {
    final count = _selectedImageUids.length;
    final deleting = _selectedImageUids.toList(growable: false);
    _clearSelection();
    await widget.syncController.deleteImages(deleting);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('已删除 $count 张图片。')),
    );
  }

  Future<void> _startAddFlow(BuildContext context) async {
    final loaders = await widget.fileActions.pickImageLoaders();
    if (!context.mounted || loaders.isEmpty) return;
    final draft = await showPromptEditorSheet(
      context,
      title: '添加 Prompt',
      imageCount: loaders.length,
    );
    if (draft == null || !context.mounted) return;
    final images = await Future.wait(loaders.map((loader) => loader.load()));
    if (!context.mounted) return;
    final result = await controller.addPromptImages(
      images: images,
      prompt: draft.prompt,
    );
    if (!context.mounted) return;
    _showResultMessage(context, result);
  }

  Future<void> _startPromptEdit(PromptImageItem source) async {
    final images = await widget.fileActions.pickImages();
    if (!mounted || images.isEmpty) return;
    final draft = await showPromptEditorSheet(
      context,
      title: '追加编辑',
      imageCount: images.length,
    );
    if (draft == null || !mounted) return;
    final result = await controller.addPromptEdit(
      sourceImageUid: source.uid,
      editPrompt: draft.prompt,
      images: images,
    );
    if (!mounted) return;
    _showResultMessage(context, result);
  }

  void _showImageDetail(PromptImageItem image) {
    final images = controller.state.visibleImages;
    final initialIndex = images.indexWhere((item) => item.uid == image.uid);
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (detailContext) {
          return PromptDetailSheet(
            controller: controller,
            images: images,
            initialIndex: initialIndex < 0 ? 0 : initialIndex,
            onCopy: (current) => _copyPrompt(detailContext, current),
            onAppendEdit: (current) {
              Navigator.of(detailContext).pop();
              _startPromptEdit(current);
            },
            onEditText: (current) async {
              Navigator.of(detailContext).pop();
              final draft = await showPromptEditorSheet(
                context,
                title: '编辑 Prompt',
                initialPrompt: current.prompt,
              );
              if (draft == null) return;
              await controller.updateImage(
                current.uid,
                prompt: draft.prompt,
              );
            },
            onDelete: (current) async {
              Navigator.of(detailContext).pop();
              await widget.syncController.deleteImage(current.uid);
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: const Text('已删除。'),
                  action: SnackBarAction(
                    label: '撤销',
                    onPressed: widget.syncController.undoLastDelete,
                  ),
                ),
              );
            },
            onFilterSamePrompt: (current) {
              controller.updateSearchFilters(
                controller.state.searchFilters.copyWith(
                  query: '',
                  category: null,
                  prompt: current.prompt,
                ),
              );
              Navigator.of(detailContext).pop();
            },
          );
        },
      ),
    );
  }

  void _showSearchSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (context) => SearchSheet(controller: controller),
    );
  }

  void _showSettingsSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (context) {
        return SettingsSheet(
          controller: controller,
          syncController: widget.syncController,
          fileActions: widget.fileActions,
        );
      },
    );
  }

  void _showSyncCenterPage(BuildContext context) {
    showSyncCenterPage(
      context,
      controller: controller,
      syncController: widget.syncController,
    );
  }

  void _copyPrompt(BuildContext context, PromptImageItem image) {
    final prompt = buildPromptChain(
      promptPartsForImage(image, controller.state.allImages),
    );
    Clipboard.setData(ClipboardData(text: prompt));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已复制 Prompt。')),
    );
  }
}

class _HomeSwipeListener extends StatefulWidget {
  const _HomeSwipeListener({
    required this.onSwipeRight,
    required this.onSwipeLeft,
    required this.child,
  });

  final VoidCallback onSwipeRight;
  final VoidCallback onSwipeLeft;
  final Widget child;

  @override
  State<_HomeSwipeListener> createState() => _HomeSwipeListenerState();
}

class _HomeSwipeListenerState extends State<_HomeSwipeListener> {
  int _pointerCount = 0;
  int? _trackingPointer;
  Offset? _startPosition;
  bool _triggered = false;

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (event) {
        _pointerCount += 1;
        if (_pointerCount == 1) {
          _trackingPointer = event.pointer;
          _startPosition = event.position;
          _triggered = false;
          return;
        }
        _trackingPointer = null;
        _startPosition = null;
      },
      onPointerMove: (event) {
        final start = _startPosition;
        if (_triggered || start == null || event.pointer != _trackingPointer) {
          return;
        }
        final delta = event.position - start;
        if (delta.dx.abs() < 120 || delta.dx.abs() < delta.dy.abs() * 1.4) {
          return;
        }
        _triggered = true;
        if (delta.dx > 0) {
          widget.onSwipeRight();
        } else {
          widget.onSwipeLeft();
        }
      },
      onPointerUp: _stopTracking,
      onPointerCancel: _stopTracking,
      child: widget.child,
    );
  }

  void _stopTracking(PointerEvent event) {
    _pointerCount = math.max(0, _pointerCount - 1);
    if (event.pointer == _trackingPointer || _pointerCount == 0) {
      _trackingPointer = null;
      _startPosition = null;
      _triggered = false;
    }
  }
}

class _ColumnScaleListener extends StatefulWidget {
  const _ColumnScaleListener({
    required this.columns,
    required this.onColumnsChanged,
    required this.child,
  });

  final int columns;
  final ValueChanged<int> onColumnsChanged;
  final Widget child;

  @override
  State<_ColumnScaleListener> createState() => _ColumnScaleListenerState();
}

class _ColumnScaleListenerState extends State<_ColumnScaleListener> {
  final Map<int, Offset> _pointers = {};
  int _baseColumns = 2;
  double? _baseDistance;

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (event) {
        _pointers[event.pointer] = event.position;
        if (_pointers.length == 2) {
          _baseColumns = widget.columns;
          _baseDistance = _currentDistance();
        }
      },
      onPointerMove: (event) {
        if (!_pointers.containsKey(event.pointer)) return;
        _pointers[event.pointer] = event.position;
        final baseDistance = _baseDistance;
        if (_pointers.length < 2 || baseDistance == null || baseDistance <= 0) {
          return;
        }
        final distance = _currentDistance();
        if (distance <= 0) return;
        final next = columnCountFromScale(
          baseColumns: _baseColumns,
          scale: distance / baseDistance,
        );
        if (next != widget.columns) {
          widget.onColumnsChanged(next);
        }
      },
      onPointerUp: _removePointer,
      onPointerCancel: _removePointer,
      child: widget.child,
    );
  }

  void _removePointer(PointerEvent event) {
    _pointers.remove(event.pointer);
    if (_pointers.length < 2) {
      _baseDistance = null;
      return;
    }
    _baseColumns = widget.columns;
    _baseDistance = _currentDistance();
  }

  double _currentDistance() {
    if (_pointers.length < 2) return 0;
    final values = _pointers.values.take(2).toList(growable: false);
    return (values[0] - values[1]).distance;
  }
}

class _GalleryWaterfall extends StatelessWidget {
  const _GalleryWaterfall({
    required this.controller,
    required this.selectedImageUids,
    required this.selectionMode,
    required this.onOpenImage,
    required this.onSelectImage,
    required this.onStartSelection,
  });

  final PixromptController controller;
  final Set<String> selectedImageUids;
  final bool selectionMode;
  final ValueChanged<PromptImageItem> onOpenImage;
  final ValueChanged<PromptImageItem> onSelectImage;
  final ValueChanged<PromptImageItem> onStartSelection;

  @override
  Widget build(BuildContext context) {
    final state = controller.state;
    if (state.allImages.isEmpty) {
      return const _EmptyGallery();
    }
    if (state.visibleImages.isEmpty) {
      return const _NoResults();
    }
    return MasonryGridView.count(
      key: const ValueKey('gallery.waterfall'),
      padding: EdgeInsets.only(top: MediaQuery.paddingOf(context).top),
      crossAxisCount: state.settings.columns,
      mainAxisSpacing: 0,
      crossAxisSpacing: 0,
      itemCount: state.visibleImages.length,
      itemBuilder: (context, index) {
        final image = state.visibleImages[index];
        return GalleryTile(
          controller: controller,
          image: image,
          selected: selectedImageUids.contains(image.uid),
          selectionMode: selectionMode,
          onTap: () {
            if (selectionMode) {
              onSelectImage(image);
              return;
            }
            onOpenImage(image);
          },
          onLongPress: () => onStartSelection(image),
        );
      },
    );
  }
}

class _TopRightActions extends StatelessWidget {
  const _TopRightActions({
    super.key,
    required this.activeFilterCount,
    required this.pendingSyncCount,
    required this.onCategory,
    required this.onSearch,
    required this.onSync,
    required this.onSettings,
  });

  final int activeFilterCount;
  final int pendingSyncCount;
  final VoidCallback onCategory;
  final VoidCallback onSearch;
  final VoidCallback onSync;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Align(
        alignment: Alignment.topRight,
        child: Padding(
          padding: const EdgeInsets.only(top: 10, right: 12),
          child: _OverlayCluster(
            children: [
              _OverlayIconButton(
                buttonKey: const ValueKey('gallery.categoryAction'),
                tooltip: '分类',
                icon: Icons.view_sidebar_outlined,
                onPressed: onCategory,
              ),
              _OverlayIconButton(
                buttonKey: const ValueKey('gallery.searchAction'),
                tooltip: '搜索',
                icon: Icons.search,
                badgeCount: activeFilterCount,
                onPressed: onSearch,
              ),
              _OverlayIconButton(
                buttonKey: const ValueKey('gallery.syncStatusAction'),
                tooltip: '同步中心',
                icon: Icons.cloud_done_outlined,
                badgeCount: pendingSyncCount,
                onPressed: onSync,
              ),
              _OverlayIconButton(
                buttonKey: const ValueKey('gallery.settingsAction'),
                tooltip: '设置',
                icon: Icons.tune,
                onPressed: onSettings,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

bool _pendingSync(PromptImageItem image) {
  return image.lastSyncedAt == null;
}

class _SelectionToolbar extends StatelessWidget {
  const _SelectionToolbar({
    super.key,
    required this.count,
    required this.onCancel,
    required this.onAssignCategory,
    required this.onDelete,
  });

  final int count;
  final VoidCallback onCancel;
  final VoidCallback onAssignCategory;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 12,
      right: 12,
      bottom: 12,
      child: SafeArea(
        top: false,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.72),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.white.withOpacity(0.16)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.28),
                blurRadius: 24,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: Row(
              children: [
                IconButton(
                  key: const ValueKey('selection.cancel'),
                  tooltip: '取消选择',
                  color: Colors.white,
                  style: IconButton.styleFrom(
                    fixedSize: const Size.square(48),
                    minimumSize: const Size.square(48),
                    backgroundColor: Colors.white.withOpacity(0.08),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  onPressed: onCancel,
                  icon: const Icon(Icons.close),
                ),
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.10),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                    child: Text(
                      '$count',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                const Spacer(),
                IconButton.filledTonal(
                  key: const ValueKey('selection.assignCategory'),
                  tooltip: '分类',
                  style: IconButton.styleFrom(
                    fixedSize: const Size.square(48),
                    minimumSize: const Size.square(48),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  onPressed: onAssignCategory,
                  icon: const Icon(Icons.label_outline),
                ),
                const SizedBox(width: 8),
                IconButton.filledTonal(
                  key: const ValueKey('selection.delete'),
                  tooltip: '删除',
                  style: IconButton.styleFrom(
                    fixedSize: const Size.square(48),
                    minimumSize: const Size.square(48),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  onPressed: onDelete,
                  icon: const Icon(Icons.delete_outline),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _OverlayCluster extends StatelessWidget {
  const _OverlayCluster({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.46),
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: Colors.white.withOpacity(0.16)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.20),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: children,
        ),
      ),
    );
  }
}

class _OverlayIconButton extends StatelessWidget {
  const _OverlayIconButton({
    this.buttonKey,
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.badgeCount = 0,
  });

  final Key? buttonKey;
  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;
  final int badgeCount;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        IconButton(
          key: buttonKey,
          tooltip: tooltip,
          color: Colors.white,
          style: IconButton.styleFrom(
            backgroundColor: Colors.white.withOpacity(0.12),
            fixedSize: const Size.square(48),
            minimumSize: const Size.square(48),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          icon: Icon(icon),
          onPressed: onPressed,
        ),
        if (badgeCount > 0)
          Positioned(
            right: 2,
            top: 2,
            child: Badge.count(count: badgeCount),
          ),
      ],
    );
  }
}

class _EmptyGallery extends StatelessWidget {
  const _EmptyGallery();

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      color: Colors.black,
      child: Center(
        child: Text(
          '暂无图片',
          style: TextStyle(color: Colors.white70),
        ),
      ),
    );
  }
}

class _NoResults extends StatelessWidget {
  const _NoResults();

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      color: Colors.black,
      child: Center(
        child: Text(
          '没有匹配结果',
          style: TextStyle(color: Colors.white70),
        ),
      ),
    );
  }
}

void _showResultMessage(BuildContext context, PixromptActionResult result) {
  final message = result.message;
  if (result.success || message == null || message.isEmpty) return;
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}
