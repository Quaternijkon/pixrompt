import 'category_dimension.dart';
import 'prompt_image.dart';
import 'search_filters.dart';

List<PromptImageItem> filterPromptImages(
  Iterable<PromptImageItem> images,
  SearchFilters filters,
) {
  final queryTokens = filters.query
      .trim()
      .toLowerCase()
      .split(RegExp(r'\s+'))
      .where((token) => token.isNotEmpty)
      .toList();

  final filtered = images.where((image) {
    final category = filters.category;
    if (category != null) {
      final label = image.categoryLabel(filters.categoryDimensionId);
      if (category == uncategorizedCategory) {
        if (label != uncategorizedCategory) return false;
      } else if (label != category) {
        return false;
      }
    }
    if (filters.prompt != null && image.prompt != filters.prompt) {
      return false;
    }
    if (queryTokens.isEmpty) return true;
    final searchable = image.searchableTerms.join(' ').toLowerCase();
    return queryTokens.every(searchable.contains);
  });

  return sortPromptImages(filtered, filters.sortMode);
}

List<PromptImageItem> sortPromptImages(
  Iterable<PromptImageItem> images,
  SortMode mode,
) {
  final result = images.toList();
  int newest(PromptImageItem a, PromptImageItem b) =>
      b.createdAt.compareTo(a.createdAt);
  switch (mode) {
    case SortMode.newest:
      result.sort(newest);
      break;
    case SortMode.oldest:
      result.sort((a, b) => a.createdAt.compareTo(b.createdAt));
      break;
    case SortMode.categoryAZ:
      result.sort((a, b) {
        final category =
            a.category.toLowerCase().compareTo(b.category.toLowerCase());
        return category == 0 ? newest(a, b) : category;
      });
      break;
    case SortMode.categoryZA:
      result.sort((a, b) {
        final category =
            b.category.toLowerCase().compareTo(a.category.toLowerCase());
        return category == 0 ? newest(a, b) : category;
      });
      break;
  }
  return result;
}
