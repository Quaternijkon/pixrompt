import 'package:flutter/material.dart';

import '../app/pixrompt_controller.dart';
import '../domain/category_dimension.dart';
import 'pixrompt_design.dart';

class CategoryDrawer extends StatelessWidget {
  const CategoryDrawer({super.key, required this.controller});

  final PixromptController controller;

  @override
  Widget build(BuildContext context) {
    return Drawer(
      key: const ValueKey('category.drawer'),
      backgroundColor: PixromptPalette.darkBackgroundRaised,
      child: SafeArea(
        child: AnimatedBuilder(
          animation: controller,
          builder: (context, _) {
            return ListView(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 18),
              children: [
                Row(
                  children: [
                    Text(
                      '分类',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const Spacer(),
                    IconButton(
                      key: const ValueKey('category.addDimension'),
                      tooltip: '添加维度',
                      onPressed: () => _addDimension(context),
                      icon: const Icon(Icons.add_box_outlined),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                for (final dimension in controller.state.categoryDimensions)
                  _DimensionSection(
                    controller: controller,
                    dimension: dimension,
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  Future<void> _addDimension(BuildContext context) async {
    final name = await _textDialog(context, title: '添加维度', label: '维度名称');
    if (name == null) return;
    await controller.addCategoryDimension(name);
  }
}

class _DimensionSection extends StatelessWidget {
  const _DimensionSection({
    required this.controller,
    required this.dimension,
  });

  final PixromptController controller;
  final CategoryDimension dimension;

  @override
  Widget build(BuildContext context) {
    final active =
        controller.state.searchFilters.categoryDimensionId == dimension.id &&
            controller.state.searchFilters.category != null;
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      color: PixromptPalette.darkSurface.withOpacity(0.92),
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(PixromptRadius.lg),
        side: const BorderSide(color: PixromptPalette.darkOutline),
      ),
      child: ExpansionTile(
        key: ValueKey('category.dimension.${dimension.id}'),
        initiallyExpanded: active || dimension.id == sourceDimensionId,
        title: Text(dimension.name),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: '添加分类',
              onPressed: () => _addItem(context),
              icon: const Icon(Icons.add),
            ),
            if (dimension.id != sourceDimensionId)
              PopupMenuButton<String>(
                tooltip: '维度菜单',
                onSelected: (value) {
                  if (value == 'delete') {
                    controller.deleteCategoryDimension(dimension.id);
                  }
                },
                itemBuilder: (context) => const [
                  PopupMenuItem(
                    value: 'delete',
                    child: Text('删除维度'),
                  ),
                ],
              ),
          ],
        ),
        children: [
          _CategoryItemTile(
            key: ValueKey(
                'category.item.${dimension.id}.$uncategorizedCategory'),
            controller: controller,
            dimension: dimension,
            item: uncategorizedCategory,
            editable: false,
          ),
          for (final item in dimension.items)
            _CategoryItemTile(
              key: ValueKey('category.item.${dimension.id}.$item'),
              controller: controller,
              dimension: dimension,
              item: item,
              editable: true,
            ),
        ],
      ),
    );
  }

  Future<void> _addItem(BuildContext context) async {
    final item = await _textDialog(context, title: '添加分类', label: '分类名称');
    if (item == null) return;
    await controller.addCategoryItem(dimension.id, item);
  }
}

class _CategoryItemTile extends StatelessWidget {
  const _CategoryItemTile({
    super.key,
    required this.controller,
    required this.dimension,
    required this.item,
    required this.editable,
  });

  final PixromptController controller;
  final CategoryDimension dimension;
  final String item;
  final bool editable;

  @override
  Widget build(BuildContext context) {
    final selected =
        controller.state.searchFilters.categoryDimensionId == dimension.id &&
            controller.state.searchFilters.category == item;
    return ListTile(
      selected: selected,
      selectedTileColor: PixromptPalette.darkSurfaceHigh,
      selectedColor: Theme.of(context).colorScheme.primary,
      dense: true,
      title: Text(item),
      leading: Icon(
        item == uncategorizedCategory
            ? Icons.inbox_outlined
            : Icons.label_outline,
      ),
      trailing: editable
          ? PopupMenuButton<String>(
              tooltip: '分类菜单',
              onSelected: (value) async {
                switch (value) {
                  case 'rename':
                    final next = await _textDialog(
                      context,
                      title: '编辑分类',
                      label: '分类名称',
                      initialText: item,
                    );
                    if (next != null) {
                      await controller.renameCategoryItem(
                        dimension.id,
                        item,
                        next,
                      );
                    }
                    break;
                  case 'delete':
                    await controller.deleteCategoryItem(dimension.id, item);
                    break;
                }
              },
              itemBuilder: (context) => const [
                PopupMenuItem(value: 'rename', child: Text('重命名')),
                PopupMenuItem(value: 'delete', child: Text('删除')),
              ],
            )
          : null,
      onTap: () {
        controller.updateSearchFilters(
          controller.state.searchFilters.copyWith(
            categoryDimensionId: dimension.id,
            category: item,
          ),
        );
        Navigator.of(context).pop();
      },
    );
  }
}

Future<String?> _textDialog(
  BuildContext context, {
  required String title,
  required String label,
  String initialText = '',
}) {
  return showDialog<String>(
    context: context,
    builder: (context) => _TextInputDialog(
      title: title,
      label: label,
      initialText: initialText,
    ),
  );
}

class _TextInputDialog extends StatefulWidget {
  const _TextInputDialog({
    required this.title,
    required this.label,
    required this.initialText,
  });

  final String title;
  final String label;
  final String initialText;

  @override
  State<_TextInputDialog> createState() => _TextInputDialogState();
}

class _TextInputDialogState extends State<_TextInputDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialText);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        autofocus: true,
        decoration: InputDecoration(labelText: widget.label),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _submit,
          child: const Text('保存'),
        ),
      ],
    );
  }

  void _submit() {
    final value = _controller.text.trim();
    Navigator.of(context).pop(value.isEmpty ? null : value);
  }
}
