import 'package:flutter_test/flutter_test.dart';
import 'package:pixrompt/domain/prompt_image.dart';
import 'package:pixrompt/domain/prompt_terms.dart';

void main() {
  test(
      'normalizes terms by trimming, removing blanks, and collapsing duplicates',
      () {
    expect(
      normalizeTerms([' Gemini ', '', 'portrait', 'Gemini', ' portrait ']),
      ['Gemini', 'portrait'],
    );
  });

  test('renames a category across images', () {
    final images = [
      PromptImageItem.sample(uid: 'a', category: 'Gemini'),
      PromptImageItem.sample(uid: 'b', category: 'ChatGPT'),
    ];

    final renamed = renameCategory(images, from: 'Gemini', to: 'Imagen');

    expect(renamed[0].category, 'Imagen');
    expect(renamed[1].category, 'ChatGPT');
  });

  test('merges categories across images and saved taxonomy order', () {
    final images = [
      PromptImageItem.sample(uid: 'a', category: 'Gemini'),
      PromptImageItem.sample(uid: 'b', category: 'Imagen'),
      PromptImageItem.sample(uid: 'c', category: 'ChatGPT'),
    ];

    final merged = mergeCategory(images, from: 'Gemini', to: 'Imagen');
    final terms = mergeTerm(['Gemini', 'Imagen', 'ChatGPT'],
        from: 'Gemini', to: 'Imagen');

    expect(
        merged.map((image) => image.category), ['Imagen', 'Imagen', 'ChatGPT']);
    expect(terms, ['Imagen', 'ChatGPT']);
  });

  test('moves a category within the saved order without losing defaults', () {
    expect(
      moveTerm(['Gemini', 'Imagen', 'ChatGPT'], term: 'ChatGPT', direction: -1),
      ['Gemini', 'ChatGPT', 'Imagen'],
    );
    expect(
      moveTerm(['Gemini', 'Imagen', 'ChatGPT'], term: 'Gemini', direction: -1),
      ['Gemini', 'Imagen', 'ChatGPT'],
    );
  });
}
