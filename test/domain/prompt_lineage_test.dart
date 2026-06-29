import 'package:flutter_test/flutter_test.dart';
import 'package:pixrompt/domain/prompt_image.dart';
import 'package:pixrompt/domain/prompt_lineage.dart';

void main() {
  test('builds generation prompt from prompt parts and meta prompt', () {
    expect(
      buildGenerationPrompt(['A quiet library', 'warmer light']),
      'A quiet library\n\nwarmer light',
    );
  });

  test('builds inherited display prompt with simple newline composition', () {
    expect(
      buildInheritedPrompt(['A quiet library', 'warmer light', 'add fog']),
      'A quiet library\nwarmer light\nadd fog',
    );
  });

  test('returns conversation steps for an edited image', () {
    final root = PromptImageItem.sample(uid: 'root', prompt: 'A quiet library');
    final edit = PromptImageItem.sample(
      uid: 'edit',
      prompt: 'warmer light',
      parentImageUid: 'root',
      promptParts: ['A quiet library', 'warmer light'],
    );

    final steps = promptConversationForImage(edit, [root, edit]);

    expect(steps.length, 2);
    expect(steps[0].prompt, 'A quiet library');
    expect(steps[1].prompt, 'warmer light');
    expect(steps[1].imageUid, 'edit');
  });

  test('builds simple inherited prompt chains from multiple edits', () {
    expect(
      buildPromptChain(['Base prompt', 'make it warmer', 'add fog']),
      'Base prompt\nmake it warmer\nadd fog',
    );
    expect(
      appendPromptEdit('Base prompt\nmake it warmer', 'add fog'),
      'Base prompt\nmake it warmer\nadd fog',
    );
  });

  test('finds same-prompt siblings and direct prompt-edit branches', () {
    final root = PromptImageItem.sample(
      uid: 'root',
      prompt: 'A quiet library',
      createdAt: 10,
    );
    final sibling = PromptImageItem.sample(
      uid: 'sibling',
      prompt: 'A quiet library',
      createdAt: 20,
    );
    final branch = PromptImageItem.sample(
      uid: 'branch',
      prompt: 'warmer light',
      parentImageUid: 'root',
      createdAt: 30,
    );
    final other = PromptImageItem.sample(
      uid: 'other',
      prompt: 'A lake',
      createdAt: 40,
    );

    final images = [root, sibling, branch, other];

    expect(imagesWithSamePrompt(images, root).map((image) => image.uid),
        ['sibling', 'root']);
    expect(promptEditBranchesForImage(images, root).map((image) => image.uid),
        ['branch']);
  });

  test('builds a linear prompt timeline across related gallery images', () {
    final root = PromptImageItem.sample(
      uid: 'root',
      prompt: 'A quiet library',
      createdAt: 10,
    );
    final edit = PromptImageItem.sample(
      uid: 'edit',
      prompt: 'warmer light',
      parentImageUid: 'root',
      promptParts: ['A quiet library', 'warmer light'],
      createdAt: 20,
    );
    final secondEdit = PromptImageItem.sample(
      uid: 'second',
      prompt: 'add fog',
      parentImageUid: 'edit',
      promptParts: ['A quiet library', 'warmer light', 'add fog'],
      createdAt: 30,
    );
    final unrelated = PromptImageItem.sample(
      uid: 'other',
      prompt: 'A lake',
      createdAt: 40,
    );

    final timeline = promptTimelineForImage(edit, [
      root,
      edit,
      secondEdit,
      unrelated,
    ]);

    expect(timeline.map((step) => step.imageUid), ['root', 'edit', 'second']);
    expect(timeline.map((step) => step.prompt),
        ['A quiet library', 'warmer light', 'add fog']);
  });

  test('groups prompt edit descendants into a tree by parent and edit prompt',
      () {
    final root = PromptImageItem.sample(
      uid: 'root',
      prompt: 'Base prompt',
      createdAt: 10,
    );
    final warmerA = PromptImageItem.sample(
      uid: 'warm-a',
      prompt: 'Base prompt\nmake it warmer',
      parentImageUid: 'root',
      promptParts: ['Base prompt', 'make it warmer'],
      createdAt: 20,
    );
    final warmerB = PromptImageItem.sample(
      uid: 'warm-b',
      prompt: 'Base prompt\nmake it warmer',
      parentImageUid: 'root',
      promptParts: ['Base prompt', 'make it warmer'],
      createdAt: 30,
    );
    final cooler = PromptImageItem.sample(
      uid: 'cool',
      prompt: 'Base prompt\nmake it cooler',
      parentImageUid: 'root',
      promptParts: ['Base prompt', 'make it cooler'],
      createdAt: 40,
    );
    final fog = PromptImageItem.sample(
      uid: 'fog',
      prompt: 'Base prompt\nmake it warmer\nadd fog',
      parentImageUid: 'warm-a',
      promptParts: ['Base prompt', 'make it warmer', 'add fog'],
      createdAt: 50,
    );

    final tree = promptEditTreeForImage(
      warmerA,
      [root, warmerA, warmerB, cooler, fog],
    );

    expect(tree.root.image.uid, 'root');
    expect(tree.selectedImageUid, 'warm-a');
    expect(tree.nodesByUid.keys,
        containsAll(['root', 'warm-a', 'warm-b', 'cool', 'fog']));
    expect(tree.root.edges.map((edge) => edge.prompt),
        ['make it warmer', 'make it cooler']);
    expect(tree.root.edges.first.children.map((node) => node.image.uid),
        ['warm-a', 'warm-b']);
    expect(tree.root.edges.first.children.first.edges.single.prompt, 'add fog');
    expect(
      tree.root.edges.first.children.first.edges.single.children.single.image
          .uid,
      'fog',
    );
  });
}
