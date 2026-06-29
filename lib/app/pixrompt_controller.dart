import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../data/pixrompt_repository.dart';
import '../domain/backup.dart';
import '../domain/category_dimension.dart';
import '../domain/pixrompt_settings.dart';
import '../domain/prompt_image.dart';
import '../domain/prompt_lineage.dart';
import '../domain/prompt_search.dart';
import '../domain/prompt_terms.dart';
import '../domain/search_filters.dart';
import 'pixrompt_state.dart';

class PickedImageBytes {
  const PickedImageBytes({
    required this.name,
    required this.bytes,
    this.width = 0,
    this.height = 0,
  });

  final String name;
  final Uint8List bytes;
  final int width;
  final int height;
}

class PixromptActionResult {
  const PixromptActionResult._({required this.success, this.message});

  factory PixromptActionResult.ok([String? message]) {
    return PixromptActionResult._(success: true, message: message);
  }

  factory PixromptActionResult.blocked(String message) {
    return PixromptActionResult._(success: false, message: message);
  }

  final bool success;
  final String? message;
}

int columnCountFromScale({
  required int baseColumns,
  required double scale,
  int minColumns = 1,
  int maxColumns = 6,
}) {
  if (scale <= 0) return baseColumns.clamp(minColumns, maxColumns);
  return (baseColumns / scale).round().clamp(minColumns, maxColumns);
}

class PixromptController extends ChangeNotifier {
  PixromptController(this.repository, {String Function()? uidFactory})
      : _uidFactory = uidFactory ?? const Uuid().v4;

  final PixromptRepository repository;
  final String Function() _uidFactory;

  PixromptState _state = const PixromptState();
  PixromptState get state => _state;

  Future<void> initialize() async {
    final images = await repository.readImages();
    final settings = await repository.readSettings();
    _setLoadedState(images: images, settings: settings);
  }

  Future<PixromptActionResult> addPromptImages({
    required List<PickedImageBytes> images,
    required String prompt,
    String? category,
    Map<String, String> categoryAssignments = const {},
    String? parentImageUid,
    List<String> promptParts = const [],
    List<PromptEditHistoryEntry>? editHistory,
  }) async {
    if (images.isEmpty) {
      return _blocked('请选择图片。');
    }
    final normalizedPrompt = prompt.trim();
    if (normalizedPrompt.isEmpty) {
      return _blocked('请输入 prompt。');
    }

    final assignments = _normalizedAssignments(
      categoryAssignments,
      sourceCategory: category,
    );
    final now = DateTime.now().millisecondsSinceEpoch;
    final normalizedParts = promptParts.isEmpty
        ? [normalizedPrompt]
        : promptParts
            .map((part) => part.trim())
            .where((part) => part.isNotEmpty)
            .toList();
    final newImages = <PromptImageItem>[];

    for (final picked in images) {
      final imageUid = _uidFactory();
      final imageKey = 'image-$imageUid';
      await repository.writeImageBytes(imageKey, picked.bytes);
      final width = picked.width;
      final height = picked.height;
      newImages.add(
        PromptImageItem(
          uid: imageUid,
          imageKey: imageKey,
          prompt: normalizedPrompt,
          category: assignments[sourceDimensionId] ?? uncategorizedCategory,
          categoryAssignments: assignments,
          aspectRatio: width > 0 && height > 0 ? width / height : 1,
          imageWidth: width,
          imageHeight: height,
          fileSizeBytes: picked.bytes.length,
          createdAt: now,
          updatedAt: now,
          parentImageUid: parentImageUid,
          promptParts: normalizedParts,
          editHistory: _historyForImage(
            imageUid: imageUid,
            prompt: normalizedPrompt,
            createdAt: now,
            editHistory: editHistory,
          ),
        ),
      );
    }

    final merged = [...newImages, ..._state.allImages];
    final settings = _settingsWithObservedAssignments(
      _state.settings,
      newImages.expand((image) => image.categoryAssignments.entries),
    );
    await repository.writeImages(merged);
    await repository.writeSettings(settings);
    _setLoadedState(
      images: merged,
      settings: settings,
      message: images.length == 1 ? '已添加图片。' : '已添加 ${images.length} 张图片。',
    );
    return PixromptActionResult.ok();
  }

  Future<PixromptActionResult> addPromptEdit({
    required String sourceImageUid,
    required String editPrompt,
    required List<PickedImageBytes> images,
  }) async {
    final source = _state.allImages
        .where((image) => image.uid == sourceImageUid)
        .firstOrNull;
    if (source == null) {
      return _blocked('未找到原始图片。');
    }
    final normalizedEditPrompt = editPrompt.trim();
    if (normalizedEditPrompt.isEmpty) {
      return _blocked('请输入追加编辑 prompt。');
    }
    final promptParts = [
      ...promptPartsForImage(source, _state.allImages),
      normalizedEditPrompt,
    ];
    final inheritedPrompt = buildInheritedPrompt(promptParts);
    final history = [
      if (source.editHistory.isEmpty)
        PromptEditHistoryEntry(
          prompt: source.prompt,
          imageUid: source.uid,
          createdAt: source.createdAt,
        )
      else
        ...source.editHistory,
      PromptEditHistoryEntry(
        prompt: normalizedEditPrompt,
        imageUid: '',
        createdAt: DateTime.now().millisecondsSinceEpoch,
      ),
    ];
    return addPromptImages(
      images: images,
      prompt: inheritedPrompt,
      categoryAssignments: source.categoryAssignments,
      parentImageUid: source.uid,
      promptParts: promptParts,
      editHistory: history,
    );
  }

  Future<void> updateImage(
    String uid, {
    required String prompt,
    String? category,
    Map<String, String>? categoryAssignments,
  }) async {
    final existing =
        _state.allImages.where((image) => image.uid == uid).firstOrNull;
    if (existing == null) return;
    final normalizedPrompt = prompt.trim();
    if (normalizedPrompt.isEmpty) {
      _blocked('请输入 prompt。');
      return;
    }
    final assignments = _normalizedAssignments(
      categoryAssignments ?? existing.categoryAssignments,
      sourceCategory: category,
    );
    final now = DateTime.now().millisecondsSinceEpoch;
    final updatedPromptParts =
        _updatedPromptPartsForImage(existing, normalizedPrompt);
    final updatedPrompt = updatedPromptParts.isEmpty
        ? normalizedPrompt
        : buildInheritedPrompt(updatedPromptParts);
    final images = _state.allImages.map((image) {
      if (image.uid != uid) return image;
      return image.copyWith(
        prompt: updatedPrompt,
        category: assignments[sourceDimensionId] ?? uncategorizedCategory,
        categoryAssignments: assignments,
        promptParts: updatedPromptParts,
        editHistory: _replaceLastHistoryPrompt(
          image.editHistory,
          imageUid: image.uid,
          prompt: updatedPromptParts.isEmpty
              ? updatedPrompt
              : updatedPromptParts.last,
          createdAt: now,
        ),
        updatedAt: now,
      );
    }).toList();
    final settings = _settingsWithObservedAssignments(
      _state.settings,
      assignments.entries,
    );
    await repository.writeImages(images);
    await repository.writeSettings(settings);
    _setLoadedState(images: images, settings: settings, message: '已保存。');
  }

  Future<void> deleteImage(String uid) async {
    final image = _state.allImages.where((item) => item.uid == uid).firstOrNull;
    if (image == null) return;
    final bytes = await repository.readImageBytes(image.imageKey);
    final images = _state.allImages.where((item) => item.uid != uid).toList();
    await repository.writeImages(images);
    await repository.deleteImageBytes(image.imageKey);
    _state = _deriveState(
      _state.copyWith(
        allImages: images,
        pendingUndo: PendingUndo(image: image, bytes: bytes),
        lastMessage: '已删除。',
      ),
    );
    notifyListeners();
  }

  Future<void> deleteImages(Iterable<String> uids) async {
    final uidSet = uids.toSet();
    if (uidSet.isEmpty) return;
    final deleted = _state.allImages
        .where((image) => uidSet.contains(image.uid))
        .toList(growable: false);
    if (deleted.isEmpty) return;
    final images =
        _state.allImages.where((image) => !uidSet.contains(image.uid)).toList();
    await repository.writeImages(images);
    for (final image in deleted) {
      await repository.deleteImageBytes(image.imageKey);
    }
    _state = _deriveState(
      _state.copyWith(
        allImages: images,
        pendingUndo: null,
        lastMessage: '已删除 ${deleted.length} 张图片。',
      ),
    );
    notifyListeners();
  }

  Future<void> undoLastDelete() async {
    final pending = _state.pendingUndo;
    if (pending == null) return;
    if (pending.bytes != null) {
      await repository.writeImageBytes(
        pending.image.imageKey,
        Uint8List.fromList(pending.bytes!),
      );
    }
    final images = [pending.image, ..._state.allImages];
    await repository.writeImages(images);
    _state = _deriveState(
      _state.copyWith(
        allImages: images,
        pendingUndo: null,
        lastMessage: '已恢复。',
      ),
    );
    notifyListeners();
  }

  Future<void> updateSearchFilters(SearchFilters filters) async {
    _state = _deriveState(_state.copyWith(searchFilters: filters));
    notifyListeners();
  }

  Future<void> updateSettings(PixromptSettings settings) async {
    final normalizedDimensions =
        normalizeCategoryDimensions(settings.categoryDimensions);
    final normalized = settings.copyWith(
      columns: settings.columns.clamp(1, 6),
      categoryDimensions: normalizedDimensions,
      categories: normalizedDimensions
          .firstWhere(
            (dimension) => dimension.id == sourceDimensionId,
            orElse: () => defaultCategoryDimensions.first,
          )
          .items,
    );
    await repository.writeSettings(normalized);
    _setLoadedState(images: _state.allImages, settings: normalized);
  }

  Future<void> setColumns(int columns) {
    return updateSettings(
      _state.settings.copyWith(columns: columns.clamp(1, 6)),
    );
  }

  Future<void> setColumnsFromScale({
    required int baseColumns,
    required double scale,
  }) {
    return setColumns(columnCountFromScale(
      baseColumns: baseColumns,
      scale: scale,
    ));
  }

  Future<void> addCategoryDimension(String name) async {
    final normalizedName = normalizeCategoryTerm(name);
    if (normalizedName.isEmpty) return;
    final id = dimensionIdFromName(normalizedName);
    final exists = _state.settings.categoryDimensions
        .any((dimension) => dimension.id == id);
    if (exists) return;
    await updateSettings(
      _state.settings.copyWith(
        categoryDimensions: [
          ..._state.settings.categoryDimensions,
          CategoryDimension(id: id, name: normalizedName, items: const []),
        ],
      ),
    );
  }

  Future<void> addCategoryItem(String dimensionId, String item) async {
    final normalizedItem = normalizeCategoryTerm(item);
    if (normalizedItem.isEmpty || normalizedItem == uncategorizedCategory) {
      return;
    }
    await _updateDimension(
      dimensionId,
      (dimension) => dimension.copyWith(
        items: normalizeCategoryTerms([...dimension.items, normalizedItem]),
      ),
    );
  }

  Future<void> renameCategoryItem(
    String dimensionId,
    String from,
    String to,
  ) async {
    final fromKey = normalizeCategoryTerm(from).toLowerCase();
    final normalizedTo = normalizeCategoryTerm(to);
    if (fromKey.isEmpty || normalizedTo.isEmpty) return;
    final images = _state.allImages.map((image) {
      if (image.categoryLabel(dimensionId).toLowerCase() != fromKey) {
        return image;
      }
      return image.copyWith(
        categoryAssignments: {
          ...image.categoryAssignments,
          dimensionId: normalizedTo,
        },
        category:
            dimensionId == sourceDimensionId ? normalizedTo : image.category,
      );
    }).toList();
    final dimensions = _state.settings.categoryDimensions.map((dimension) {
      if (dimension.id != dimensionId) return dimension;
      return dimension.copyWith(
        items: normalizeCategoryTerms(
          dimension.items.map(
            (item) => item.toLowerCase() == fromKey ? normalizedTo : item,
          ),
        ),
      );
    }).toList();
    final settings = _state.settings.copyWith(
      categoryDimensions: normalizeCategoryDimensions(dimensions),
    );
    await repository.writeImages(images);
    await repository.writeSettings(settings);
    _setLoadedState(images: images, settings: settings);
  }

  Future<void> deleteCategoryItem(String dimensionId, String item) async {
    final itemKey = normalizeCategoryTerm(item).toLowerCase();
    if (itemKey.isEmpty) return;
    final images = _state.allImages.map((image) {
      if (image.categoryLabel(dimensionId).toLowerCase() != itemKey) {
        return image;
      }
      final assignments = {...image.categoryAssignments}..remove(dimensionId);
      return image.copyWith(
        categoryAssignments: assignments,
        category: dimensionId == sourceDimensionId
            ? uncategorizedCategory
            : image.category,
      );
    }).toList();
    final dimensions = _state.settings.categoryDimensions.map((dimension) {
      if (dimension.id != dimensionId) return dimension;
      return dimension.copyWith(
        items: dimension.items
            .where((candidate) => candidate.toLowerCase() != itemKey)
            .toList(),
      );
    }).toList();
    final settings = _state.settings.copyWith(
      categoryDimensions: normalizeCategoryDimensions(dimensions),
    );
    await repository.writeImages(images);
    await repository.writeSettings(settings);
    _setLoadedState(images: images, settings: settings);
  }

  Future<void> deleteCategoryDimension(String dimensionId) async {
    if (dimensionId == sourceDimensionId) return;
    final dimensions = _state.settings.categoryDimensions
        .where((dimension) => dimension.id != dimensionId)
        .toList();
    final images = _state.allImages.map((image) {
      final assignments = {...image.categoryAssignments}..remove(dimensionId);
      return image.copyWith(categoryAssignments: assignments);
    }).toList();
    final settings = _state.settings.copyWith(
      categoryDimensions: normalizeCategoryDimensions(dimensions),
    );
    await repository.writeImages(images);
    await repository.writeSettings(settings);
    _setLoadedState(images: images, settings: settings);
  }

  Future<void> assignCategoryToImages(
    Iterable<String> uids, {
    required String dimensionId,
    required String item,
  }) async {
    final uidSet = uids.toSet();
    if (uidSet.isEmpty) return;
    final normalizedItem = normalizeCategoryTerm(item);
    final remove =
        normalizedItem.isEmpty || normalizedItem == uncategorizedCategory;
    final images = _state.allImages.map((image) {
      if (!uidSet.contains(image.uid)) return image;
      final assignments = {...image.categoryAssignments};
      if (remove) {
        assignments.remove(dimensionId);
      } else {
        assignments[dimensionId] = normalizedItem;
      }
      return image.copyWith(
        categoryAssignments: assignments,
        category: dimensionId == sourceDimensionId
            ? assignments[sourceDimensionId] ?? uncategorizedCategory
            : image.category,
      );
    }).toList();
    var settings = _state.settings;
    if (!remove) {
      settings = _settingsWithObservedAssignments(
        settings,
        [MapEntry(dimensionId, normalizedItem)],
      );
    }
    await repository.writeImages(images);
    await repository.writeSettings(settings);
    _setLoadedState(
      images: images,
      settings: settings,
      message: '已更新分类。',
    );
  }

  Future<void> addCategory(String name) {
    return addCategoryItem(sourceDimensionId, name);
  }

  Future<void> renameCategoryGlobal(String from, String to) {
    return renameCategoryItem(sourceDimensionId, from, to);
  }

  Future<void> mergeCategoryGlobal(String from, String to) {
    return renameCategoryItem(sourceDimensionId, from, to);
  }

  Future<void> moveCategory(String category, int direction) {
    final source = _state.settings.categoryDimensions.firstWhere(
      (dimension) => dimension.id == sourceDimensionId,
      orElse: () => defaultCategoryDimensions.first,
    );
    final moved = moveTerm(source.items, term: category, direction: direction);
    return _updateDimension(
      sourceDimensionId,
      (dimension) => dimension.copyWith(items: moved),
    );
  }

  Future<void> deleteCategoryGlobal(String category) {
    return deleteCategoryItem(sourceDimensionId, category);
  }

  Future<int> cleanupOrphanedImageBytes() async {
    final referenced = _state.allImages.map((image) => image.imageKey).toSet();
    var deletedCount = 0;
    for (final key in await repository.listImageByteKeys()) {
      if (!referenced.contains(key)) {
        await repository.deleteImageBytes(key);
        deletedCount += 1;
      }
    }
    _state = _state.copyWith(
      lastMessage: deletedCount == 0 ? '未发现孤立图片。' : '已清理 $deletedCount 个孤立图片。',
    );
    notifyListeners();
    return deletedCount;
  }

  Future<String> exportBackupJson() async {
    final bytes = <String, Uint8List>{};
    for (final image in _state.allImages) {
      final payload = await repository.readImageBytes(image.imageKey);
      if (payload != null) bytes[image.imageKey] = payload;
    }
    return PromptBackupCodec.encode(
      images: _state.allImages,
      imageBytesByKey: bytes,
    );
  }

  Future<void> importBackupJson(String jsonText) async {
    final backup = PromptBackupCodec.decode(jsonText);
    final imageMap = {for (final image in _state.allImages) image.uid: image};
    for (final image in backup.images) {
      imageMap[image.uid] = image;
    }
    for (final entry in backup.imageBytesByKey.entries) {
      await repository.writeImageBytes(entry.key, entry.value);
    }
    final images = imageMap.values.toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final settings = _settingsWithObservedAssignments(
      _state.settings,
      images.expand((image) => image.categoryAssignments.entries),
    );
    await repository.writeImages(images);
    await repository.writeSettings(settings);
    _setLoadedState(
      images: images,
      settings: settings,
      message: '已导入备份。',
    );
  }

  Future<List<PromptImageItem>> readSyncImages() async {
    return List.unmodifiable(_state.allImages);
  }

  Future<void> applySyncUpserts(
    Iterable<PromptImageItem> upserts, {
    String? message,
  }) async {
    final incoming = upserts.where((image) => image.uid.isNotEmpty).toList();
    if (incoming.isEmpty) return;
    final imageMap = {for (final image in _state.allImages) image.uid: image};
    for (final image in incoming) {
      imageMap[image.uid] = image;
    }
    final images = imageMap.values.toList()
      ..sort((a, b) {
        final created = b.createdAt.compareTo(a.createdAt);
        if (created != 0) return created;
        return b.updatedAt.compareTo(a.updatedAt);
      });
    final settings = _settingsWithObservedAssignments(
      _state.settings,
      images.expand((image) => image.categoryAssignments.entries),
    );
    await repository.writeImages(images);
    await repository.writeSettings(settings);
    _setLoadedState(images: images, settings: settings, message: message);
  }

  Future<void> applySyncTombstones(
    Iterable<String> imageUids, {
    String? message,
  }) async {
    final uidSet = imageUids.where((uid) => uid.isNotEmpty).toSet();
    if (uidSet.isEmpty) return;
    final deleted = _state.allImages
        .where((image) => uidSet.contains(image.uid))
        .toList(growable: false);
    if (deleted.isEmpty) return;
    final images =
        _state.allImages.where((image) => !uidSet.contains(image.uid)).toList();
    await repository.writeImages(images);
    for (final image in deleted) {
      await repository.deleteImageBytes(image.imageKey);
    }
    _setLoadedState(
      images: images,
      settings: _state.settings,
      message: message,
    );
  }

  Future<Uint8List?> imageBytes(String imageKey) {
    return repository.readImageBytes(imageKey);
  }

  Future<Uint8List?> readSyncImageBytes(String imageKey) {
    return repository.readImageBytes(imageKey);
  }

  Future<void> writeSyncImageBytes(String imageKey, Uint8List bytes) {
    return repository.writeImageBytes(imageKey, bytes);
  }

  Future<void> deleteSyncImageBytes(String imageKey) {
    return repository.deleteImageBytes(imageKey);
  }

  PixromptActionResult _blocked(String message) {
    _state = _state.copyWith(lastMessage: message);
    notifyListeners();
    return PixromptActionResult.blocked(message);
  }

  void _setLoadedState({
    required List<PromptImageItem> images,
    required PixromptSettings settings,
    String? message,
  }) {
    _state = _deriveState(
      _state.copyWith(
        allImages: images,
        settings: settings,
        lastMessage: message,
      ),
    );
    notifyListeners();
  }

  PixromptState _deriveState(PixromptState base) {
    final dimensions = normalizeCategoryDimensions(
      base.settings.categoryDimensions,
    );
    final visible = filterPromptImages(base.allImages, base.searchFilters);
    return base.copyWith(
      visibleImages: visible,
      categories: dimensions
          .firstWhere(
            (dimension) => dimension.id == sourceDimensionId,
            orElse: () => defaultCategoryDimensions.first,
          )
          .items,
      categoryDimensions: dimensions,
      prompts: _promptOptions(base.allImages),
    );
  }

  Future<void> _updateDimension(
    String dimensionId,
    CategoryDimension Function(CategoryDimension dimension) update,
  ) async {
    final dimensions = _state.settings.categoryDimensions.map((dimension) {
      if (dimension.id != dimensionId) return dimension;
      return update(dimension);
    }).toList();
    await updateSettings(
      _state.settings.copyWith(
        categoryDimensions: normalizeCategoryDimensions(dimensions),
      ),
    );
  }

  PixromptSettings _settingsWithObservedAssignments(
    PixromptSettings settings,
    Iterable<MapEntry<String, String>> assignments,
  ) {
    var dimensions = normalizeCategoryDimensions(settings.categoryDimensions);
    for (final assignment in assignments) {
      final dimensionId = assignment.key;
      final item = normalizeCategoryTerm(assignment.value);
      if (item.isEmpty || item == uncategorizedCategory) continue;
      final index =
          dimensions.indexWhere((dimension) => dimension.id == dimensionId);
      if (index < 0) continue;
      final dimension = dimensions[index];
      dimensions[index] = dimension.copyWith(
        items: normalizeCategoryTerms([...dimension.items, item]),
      );
    }
    return settings.copyWith(
      categoryDimensions: normalizeCategoryDimensions(dimensions),
    );
  }

  Map<String, String> _normalizedAssignments(
    Map<String, String> assignments, {
    String? sourceCategory,
  }) {
    final result = normalizeCategoryAssignments(assignments);
    final normalizedSource = normalizeCategoryTerm(sourceCategory ?? '');
    if (normalizedSource.isNotEmpty &&
        normalizedSource != uncategorizedCategory) {
      result[sourceDimensionId] = normalizedSource;
    }
    return result;
  }

  List<String> _promptOptions(Iterable<PromptImageItem> images) {
    final result = <String>[];
    final seen = <String>{};
    for (final image in images) {
      final prompt = image.prompt.trim();
      if (prompt.isEmpty || !seen.add(prompt)) continue;
      result.add(prompt);
    }
    return result;
  }

  List<PromptEditHistoryEntry> _historyForImage({
    required String imageUid,
    required String prompt,
    required int createdAt,
    List<PromptEditHistoryEntry>? editHistory,
  }) {
    final source = editHistory ??
        [
          PromptEditHistoryEntry(
            prompt: prompt,
            imageUid: imageUid,
            createdAt: createdAt,
          ),
        ];
    return source.map((entry) {
      if (entry.imageUid.isNotEmpty) return entry;
      return entry.copyWith(imageUid: imageUid);
    }).toList();
  }

  List<String> _replaceLastPromptPart(List<String> parts, String prompt) {
    if (parts.isEmpty) return [prompt];
    final updated = [...parts];
    updated[updated.length - 1] = prompt;
    return updated;
  }

  List<String> _updatedPromptPartsForImage(
    PromptImageItem image,
    String prompt,
  ) {
    if (image.promptParts.isEmpty) return [prompt];
    if (image.parentImageUid == null || image.promptParts.length <= 1) {
      return [prompt];
    }
    final inheritedParts =
        image.promptParts.take(image.promptParts.length - 1).toList();
    final inheritedPrompt = buildInheritedPrompt(inheritedParts);
    if (inheritedPrompt.isNotEmpty && prompt.startsWith(inheritedPrompt)) {
      final suffix = prompt.substring(inheritedPrompt.length).trim();
      if (suffix.isNotEmpty) return [...inheritedParts, suffix];
    }
    return _replaceLastPromptPart(image.promptParts, prompt);
  }

  List<PromptEditHistoryEntry> _replaceLastHistoryPrompt(
    List<PromptEditHistoryEntry> history, {
    required String imageUid,
    required String prompt,
    required int createdAt,
  }) {
    if (history.isEmpty) {
      return [
        PromptEditHistoryEntry(
          prompt: prompt,
          imageUid: imageUid,
          createdAt: createdAt,
        ),
      ];
    }
    final updated = [...history];
    updated[updated.length - 1] = updated.last.copyWith(
      prompt: prompt,
      imageUid:
          updated.last.imageUid.isEmpty ? imageUid : updated.last.imageUid,
    );
    return updated;
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull {
    for (final item in this) {
      return item;
    }
    return null;
  }
}
