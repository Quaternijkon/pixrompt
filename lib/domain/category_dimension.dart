const sourceDimensionId = 'source';
const uncategorizedCategory = '未分类';

class CategoryDimension {
  const CategoryDimension({
    required this.id,
    required this.name,
    required this.items,
  });

  factory CategoryDimension.fromJson(Map<String, dynamic> json) {
    return CategoryDimension(
      id: _normalizeId(json['id'] as String? ?? ''),
      name: normalizeCategoryTerm(json['name'] as String? ?? ''),
      items: normalizeCategoryTerms(
        (json['items'] as List<dynamic>? ?? const []).whereType<String>(),
      ),
    );
  }

  final String id;
  final String name;
  final List<String> items;

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'items': items,
    };
  }

  CategoryDimension copyWith({
    String? id,
    String? name,
    List<String>? items,
  }) {
    return CategoryDimension(
      id: id ?? this.id,
      name: name ?? this.name,
      items: items ?? this.items,
    );
  }
}

const defaultCategoryDimensions = [
  CategoryDimension(
    id: sourceDimensionId,
    name: '来源',
    items: [
      'Gemini',
      'ChatGPT',
      'Grok',
      'Midjourney',
      'Stable Diffusion',
      'Other',
    ],
  ),
  CategoryDimension(
    id: 'subject',
    name: '题材',
    items: [
      '运动',
      '人物',
      '风景',
      '产品',
      '抽象',
    ],
  ),
];

String normalizeCategoryTerm(String value) {
  return value.trim().replaceAll(RegExp(r'\s+'), ' ');
}

List<String> normalizeCategoryTerms(Iterable<String> values) {
  final result = <String>[];
  final seen = <String>{};
  for (final raw in values) {
    final term = normalizeCategoryTerm(raw);
    final key = term.toLowerCase();
    if (term.isEmpty || seen.contains(key)) continue;
    seen.add(key);
    result.add(term);
  }
  return result;
}

List<CategoryDimension> normalizeCategoryDimensions(
  Iterable<CategoryDimension> values,
) {
  final result = <CategoryDimension>[];
  final seen = <String>{};
  for (final raw in values) {
    final id = _normalizeId(raw.id.isEmpty ? raw.name : raw.id);
    final name = normalizeCategoryTerm(raw.name);
    if (id.isEmpty || name.isEmpty || seen.contains(id)) continue;
    seen.add(id);
    result.add(
      raw.copyWith(
        id: id,
        name: name,
        items: normalizeCategoryTerms(raw.items),
      ),
    );
  }
  return result.isEmpty ? defaultCategoryDimensions : result;
}

List<CategoryDimension> dimensionsFromLegacyCategories(
  Iterable<String> categories,
) {
  final legacyItems = normalizeCategoryTerms(categories);
  final defaultSource = defaultCategoryDimensions.first;
  final source = defaultSource.copyWith(
    items: normalizeCategoryTerms([...legacyItems, ...defaultSource.items]),
  );
  return normalizeCategoryDimensions([
    source,
    ...defaultCategoryDimensions.where(
      (dimension) => dimension.id != sourceDimensionId,
    ),
  ]);
}

Map<String, String> normalizeCategoryAssignments(
  Map<String, String> assignments,
) {
  final result = <String, String>{};
  for (final entry in assignments.entries) {
    final id = _normalizeId(entry.key);
    final item = normalizeCategoryTerm(entry.value);
    if (id.isEmpty || item.isEmpty || item == uncategorizedCategory) continue;
    result[id] = item;
  }
  return result;
}

String dimensionIdFromName(String name) => _normalizeId(name);

String _normalizeId(String value) {
  final normalizedTerm = normalizeCategoryTerm(value).toLowerCase();
  final normalized = normalizedTerm
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
  if (normalized == 'source') return sourceDimensionId;
  if (normalized.isNotEmpty) return normalized;
  final encoded = normalizedTerm.runes
      .map((rune) => rune.toRadixString(16))
      .where((part) => part.isNotEmpty)
      .join('-');
  return encoded.isEmpty ? '' : 'dim-$encoded';
}
