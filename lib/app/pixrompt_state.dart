import '../domain/pixrompt_settings.dart';
import '../domain/category_dimension.dart';
import '../domain/prompt_image.dart';
import '../domain/search_filters.dart';

class PendingUndo {
  const PendingUndo({required this.image, required this.bytes});

  final PromptImageItem image;
  final List<int>? bytes;
}

class PixromptState {
  const PixromptState({
    this.allImages = const [],
    this.visibleImages = const [],
    this.searchFilters = const SearchFilters(),
    this.settings = const PixromptSettings(),
    this.categories = const [],
    this.categoryDimensions = defaultCategoryDimensions,
    this.prompts = const [],
    this.pendingUndo,
    this.lastMessage,
    this.isBusy = false,
  });

  final List<PromptImageItem> allImages;
  final List<PromptImageItem> visibleImages;
  final SearchFilters searchFilters;
  final PixromptSettings settings;
  final List<String> categories;
  final List<CategoryDimension> categoryDimensions;
  final List<String> prompts;
  final PendingUndo? pendingUndo;
  final String? lastMessage;
  final bool isBusy;

  PixromptState copyWith({
    List<PromptImageItem>? allImages,
    List<PromptImageItem>? visibleImages,
    SearchFilters? searchFilters,
    PixromptSettings? settings,
    List<String>? categories,
    List<CategoryDimension>? categoryDimensions,
    List<String>? prompts,
    Object? pendingUndo = _sentinel,
    Object? lastMessage = _sentinel,
    bool? isBusy,
  }) {
    return PixromptState(
      allImages: allImages ?? this.allImages,
      visibleImages: visibleImages ?? this.visibleImages,
      searchFilters: searchFilters ?? this.searchFilters,
      settings: settings ?? this.settings,
      categories: categories ?? this.categories,
      categoryDimensions: categoryDimensions ?? this.categoryDimensions,
      prompts: prompts ?? this.prompts,
      pendingUndo: pendingUndo == _sentinel
          ? this.pendingUndo
          : pendingUndo as PendingUndo?,
      lastMessage:
          lastMessage == _sentinel ? this.lastMessage : lastMessage as String?,
      isBusy: isBusy ?? this.isBusy,
    );
  }
}

const _sentinel = Object();
