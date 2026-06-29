import 'category_dimension.dart';
import 'prompt_image.dart';

const defaultPromptCategories = [
  'Gemini',
  'ChatGPT',
  'Grok',
  'Midjourney',
  'Stable Diffusion',
  'Other',
];

String normalizeTerm(String value) => normalizeCategoryTerm(value);

List<String> normalizeTerms(Iterable<String> values) {
  return normalizeCategoryTerms(values);
}

List<String> categoryOptions(
  Iterable<PromptImageItem> images,
  Iterable<String> customOrder,
) {
  return normalizeTerms([
    ...customOrder,
    ...defaultPromptCategories,
    ...images
        .map((image) => image.categoryAssignments[sourceDimensionId])
        .whereType<String>(),
  ]);
}

List<PromptImageItem> renameCategory(
  Iterable<PromptImageItem> images, {
  required String from,
  required String to,
  String dimensionId = sourceDimensionId,
}) {
  final fromKey = normalizeTerm(from).toLowerCase();
  final normalizedTo = normalizeTerm(to);
  return images.map((image) {
    if (image.categoryLabel(dimensionId).toLowerCase() != fromKey ||
        normalizedTo.isEmpty) {
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
}

List<PromptImageItem> mergeCategory(
  Iterable<PromptImageItem> images, {
  required String from,
  required String to,
  String dimensionId = sourceDimensionId,
}) {
  return renameCategory(
    images,
    from: from,
    to: to,
    dimensionId: dimensionId,
  );
}

List<String> mergeTerm(
  Iterable<String> terms, {
  required String from,
  required String to,
}) {
  final fromKey = normalizeTerm(from).toLowerCase();
  final normalizedTo = normalizeTerm(to);
  if (fromKey.isEmpty || normalizedTo.isEmpty) return normalizeTerms(terms);
  return normalizeTerms(
    terms.map((term) =>
        normalizeTerm(term).toLowerCase() == fromKey ? normalizedTo : term),
  );
}

List<String> moveTerm(
  Iterable<String> terms, {
  required String term,
  required int direction,
}) {
  final normalized = normalizeTerms(terms);
  final termKey = normalizeTerm(term).toLowerCase();
  final currentIndex =
      normalized.indexWhere((candidate) => candidate.toLowerCase() == termKey);
  if (currentIndex < 0) return normalized;
  final nextIndex = (currentIndex + direction).clamp(0, normalized.length - 1);
  if (nextIndex == currentIndex) return normalized;
  final mutable = [...normalized];
  final moving = mutable.removeAt(currentIndex);
  mutable.insert(nextIndex, moving);
  return mutable;
}
