import 'package:flutter_test/flutter_test.dart';
import 'package:pixrompt/domain/category_dimension.dart';
import 'package:pixrompt/domain/prompt_image.dart';
import 'package:pixrompt/domain/prompt_search.dart';
import 'package:pixrompt/domain/search_filters.dart';

void main() {
  final images = [
    PromptImageItem.sample(
      uid: 'new',
      prompt: 'Cyberpunk city portrait',
      categoryAssignments: const {
        sourceDimensionId: 'Gemini',
        'subject': 'Portrait',
      },
      createdAt: DateTime(2026, 1, 3).millisecondsSinceEpoch,
    ),
    PromptImageItem.sample(
      uid: 'old',
      prompt: 'Quiet watercolor landscape',
      categoryAssignments: const {sourceDimensionId: 'ChatGPT'},
      createdAt: DateTime(2026, 1, 1).millisecondsSinceEpoch,
    ),
    PromptImageItem.sample(
      uid: 'edit',
      prompt: 'make it warmer',
      categoryAssignments: const {
        sourceDimensionId: 'Gemini',
        'subject': 'Sports',
      },
      promptParts: const ['A quiet library', 'make it warmer'],
      createdAt: DateTime(2026, 1, 2).millisecondsSinceEpoch,
    ),
    PromptImageItem.sample(
      uid: 'uncategorized',
      prompt: 'No source',
      categoryAssignments: const {},
      createdAt: DateTime(2026, 1, 4).millisecondsSinceEpoch,
    ),
  ];

  test(
      'matches query text against prompt, category dimensions, and prompt chain',
      () {
    final result = filterPromptImages(
      images,
      const SearchFilters(query: 'library sports warmer'),
    );

    expect(result.map((image) => image.uid), ['edit']);
  });

  test('applies a category filter inside the selected dimension', () {
    final result = filterPromptImages(
      images,
      const SearchFilters(
        categoryDimensionId: 'subject',
        category: 'Sports',
      ),
    );

    expect(result.map((image) => image.uid), ['edit']);
  });

  test('applies an unclassified filter inside the selected dimension', () {
    final result = filterPromptImages(
      images,
      const SearchFilters(
        categoryDimensionId: sourceDimensionId,
        category: uncategorizedCategory,
      ),
    );

    expect(result.map((image) => image.uid), ['uncategorized']);
  });

  test('applies exact prompt filter from existing prompt choices', () {
    final result = filterPromptImages(
      images,
      const SearchFilters(prompt: 'make it warmer'),
    );

    expect(result.map((image) => image.uid), ['edit']);
  });

  test('sorts newest, oldest, and category results', () {
    expect(
      sortPromptImages(images, SortMode.newest).map((image) => image.uid),
      ['uncategorized', 'new', 'edit', 'old'],
    );
    expect(
      sortPromptImages(images, SortMode.oldest).map((image) => image.uid),
      ['old', 'edit', 'new', 'uncategorized'],
    );
    expect(
      sortPromptImages(images, SortMode.categoryAZ).map((image) => image.uid),
      ['old', 'new', 'edit', 'uncategorized'],
    );
  });
}
