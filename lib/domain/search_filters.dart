import 'category_dimension.dart';

enum SortMode {
  newest,
  oldest,
  categoryAZ,
  categoryZA,
}

class SearchFilters {
  const SearchFilters({
    this.query = '',
    this.categoryDimensionId = sourceDimensionId,
    this.category,
    this.prompt,
    this.sortMode = SortMode.newest,
  });

  final String query;
  final String categoryDimensionId;
  final String? category;
  final String? prompt;
  final SortMode sortMode;

  int activeFilterCount() {
    return [
      query.trim().isNotEmpty,
      category != null,
      prompt != null,
      sortMode != SortMode.newest,
    ].where((active) => active).length;
  }

  SearchFilters clearAll() => const SearchFilters();

  SearchFilters copyWith({
    String? query,
    String? categoryDimensionId,
    Object? category = _sentinel,
    Object? prompt = _sentinel,
    SortMode? sortMode,
  }) {
    return SearchFilters(
      query: query ?? this.query,
      categoryDimensionId: categoryDimensionId ?? this.categoryDimensionId,
      category: category == _sentinel ? this.category : category as String?,
      prompt: prompt == _sentinel ? this.prompt : prompt as String?,
      sortMode: sortMode ?? this.sortMode,
    );
  }
}

const _sentinel = Object();
