import 'category_dimension.dart';
import 'prompt_terms.dart';

class PixromptSettings {
  const PixromptSettings({
    this.columns = 2,
    this.categories = defaultPromptCategories,
    this.categoryDimensions = defaultCategoryDimensions,
  });

  factory PixromptSettings.fromJson(Map<String, dynamic> json) {
    final categories = (json['categories'] as List<dynamic>? ?? const [])
        .whereType<String>()
        .toList();
    final rawDimensions = json['categoryDimensions'];
    final categoryDimensions = rawDimensions is List<dynamic>
        ? normalizeCategoryDimensions(
            rawDimensions
                .whereType<Map<String, dynamic>>()
                .map(CategoryDimension.fromJson),
          )
        : dimensionsFromLegacyCategories(categories);
    return PixromptSettings(
      columns: (json['columns'] as num?)?.toInt().clamp(1, 6) ?? 2,
      categories: categories.isEmpty
          ? categoryDimensions
              .firstWhere((dimension) => dimension.id == sourceDimensionId)
              .items
          : normalizeTerms(categories),
      categoryDimensions: categoryDimensions,
    );
  }

  final int columns;
  final List<String> categories;
  final List<CategoryDimension> categoryDimensions;

  Map<String, dynamic> toJson() {
    final sourceItems = categoryDimensions
        .firstWhere(
          (dimension) => dimension.id == sourceDimensionId,
          orElse: () => defaultCategoryDimensions.first,
        )
        .items;
    return {
      'columns': columns.clamp(1, 6),
      'categories': normalizeTerms(sourceItems),
      'categoryDimensions':
          categoryDimensions.map((dimension) => dimension.toJson()).toList(),
    };
  }

  PixromptSettings copyWith({
    int? columns,
    List<String>? categories,
    List<CategoryDimension>? categoryDimensions,
  }) {
    final nextDimensions = categoryDimensions ?? this.categoryDimensions;
    return PixromptSettings(
      columns: columns ?? this.columns,
      categories: categories ??
          nextDimensions
              .firstWhere(
                (dimension) => dimension.id == sourceDimensionId,
                orElse: () => defaultCategoryDimensions.first,
              )
              .items,
      categoryDimensions: nextDimensions,
    );
  }
}
