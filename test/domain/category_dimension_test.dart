import 'package:flutter_test/flutter_test.dart';
import 'package:pixrompt/domain/category_dimension.dart';

void main() {
  test('default dimensions separate source from subject style categories', () {
    expect(defaultCategoryDimensions.map((dimension) => dimension.id), [
      sourceDimensionId,
      'subject',
    ]);
    expect(defaultCategoryDimensions.first.items, contains('Gemini'));
    expect(defaultCategoryDimensions.first.items, contains('ChatGPT'));
    expect(defaultCategoryDimensions.first.items, contains('Grok'));
    expect(
      defaultCategoryDimensions
          .firstWhere((dimension) => dimension.id == 'subject')
          .items,
      contains('运动'),
    );
  });

  test('normalizes dimensions and collapses duplicate items', () {
    final dimensions = normalizeCategoryDimensions([
      const CategoryDimension(
        id: ' source ',
        name: ' Source ',
        items: ['Gemini', 'gemini', '', ' ChatGPT '],
      ),
    ]);

    expect(dimensions.single.id, sourceDimensionId);
    expect(dimensions.single.name, 'Source');
    expect(dimensions.single.items, ['Gemini', 'ChatGPT']);
  });

  test('migrates legacy category lists into the source dimension', () {
    final dimensions = dimensionsFromLegacyCategories(['Imagen', 'Gemini']);

    final source = dimensions.firstWhere(
      (dimension) => dimension.id == sourceDimensionId,
    );
    expect(source.items.take(2), ['Imagen', 'Gemini']);
  });

  test('creates stable ids for non-latin dimension names', () {
    final id = dimensionIdFromName('情绪');

    expect(id, isNotEmpty);
    expect(id, isNot(sourceDimensionId));
    expect(id, dimensionIdFromName(' 情绪 '));
    expect(
      normalizeCategoryDimensions([
        CategoryDimension(id: id, name: '情绪', items: const []),
      ]).single.name,
      '情绪',
    );
  });
}
