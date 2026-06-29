import 'prompt_image.dart';

class PromptConversationStep {
  const PromptConversationStep({
    required this.imageUid,
    required this.prompt,
    required this.image,
  });

  final String imageUid;
  final String prompt;
  final PromptImageItem? image;
}

class PromptEditTree {
  const PromptEditTree({
    required this.root,
    required this.selectedImageUid,
    required this.nodesByUid,
  });

  final PromptEditTreeNode root;
  final String selectedImageUid;
  final Map<String, PromptEditTreeNode> nodesByUid;

  List<PromptImageItem> get images {
    final result = <PromptImageItem>[];
    void visit(PromptEditTreeNode node) {
      result.add(node.image);
      for (final edge in node.edges) {
        for (final child in edge.children) {
          visit(child);
        }
      }
    }

    visit(root);
    return result;
  }
}

class PromptEditTreeNode {
  const PromptEditTreeNode({
    required this.image,
    required this.edges,
  });

  final PromptImageItem image;
  final List<PromptEditTreeEdge> edges;
}

class PromptEditTreeEdge {
  const PromptEditTreeEdge({
    required this.parentImageUid,
    required this.prompt,
    required this.children,
  });

  final String parentImageUid;
  final String prompt;
  final List<PromptEditTreeNode> children;
}

String buildGenerationPrompt(List<String> promptParts) {
  return promptParts
      .map((part) => part.trim())
      .where((part) => part.isNotEmpty)
      .join('\n\n');
}

String buildInheritedPrompt(List<String> promptParts) {
  return promptParts
      .map((part) => part.trim())
      .where((part) => part.isNotEmpty)
      .join('\n');
}

String appendPromptEdit(
  String promptChain,
  String editPrompt,
) {
  final normalizedChain = promptChain.trim();
  final normalizedEdit = editPrompt.trim();
  if (normalizedEdit.isEmpty) return normalizedChain;
  return [
    if (normalizedChain.isNotEmpty) normalizedChain,
    normalizedEdit,
  ].join('\n');
}

String buildPromptChain(List<String> promptParts) {
  return buildInheritedPrompt(promptParts);
}

List<PromptConversationStep> promptConversationForImage(
  PromptImageItem image,
  Iterable<PromptImageItem> allImages,
) {
  final byUid = {for (final item in allImages) item.uid: item};
  final chain = <PromptImageItem>[];
  var cursor = image;
  while (true) {
    chain.add(cursor);
    final parentUid = cursor.parentImageUid;
    if (parentUid == null ||
        parentUid.isEmpty ||
        !byUid.containsKey(parentUid)) {
      break;
    }
    cursor = byUid[parentUid]!;
  }
  final ordered = chain.reversed.toList();
  final parts = image.promptParts.isNotEmpty
      ? image.promptParts
      : ordered.map((item) => item.prompt).toList();

  return [
    for (var index = 0; index < ordered.length; index++)
      PromptConversationStep(
        imageUid: ordered[index].uid,
        prompt: index < parts.length ? parts[index] : ordered[index].prompt,
        image: ordered[index],
      ),
  ];
}

List<String> promptPartsForImage(
  PromptImageItem image,
  Iterable<PromptImageItem> allImages,
) {
  return promptConversationForImage(image, allImages)
      .map((step) => step.prompt.trim())
      .where((part) => part.isNotEmpty)
      .toList();
}

List<PromptImageItem> imagesWithSamePrompt(
  Iterable<PromptImageItem> images,
  PromptImageItem image,
) {
  final prompt = image.prompt.trim();
  final matches = images.where((candidate) {
    return prompt.isNotEmpty && candidate.prompt.trim() == prompt;
  }).toList();
  if (matches.isEmpty) return [image];
  return _uniqueByUid(matches)
    ..sort((a, b) => _sortTimestamp(b).compareTo(_sortTimestamp(a)));
}

List<PromptImageItem> promptEditBranchesForImage(
  Iterable<PromptImageItem> images,
  PromptImageItem image,
) {
  if (image.uid.trim().isEmpty) return [];
  final branches = images
      .where(
        (candidate) =>
            candidate.uid != image.uid && candidate.parentImageUid == image.uid,
      )
      .toList();
  return _uniqueByUid(branches)
    ..sort((a, b) => _sortTimestamp(b).compareTo(_sortTimestamp(a)));
}

List<PromptConversationStep> promptTimelineForImage(
  PromptImageItem image,
  Iterable<PromptImageItem> allImages,
) {
  final byUid = {for (final item in allImages) item.uid: item};
  var root = image;
  while (root.parentImageUid != null &&
      root.parentImageUid!.isNotEmpty &&
      byUid.containsKey(root.parentImageUid)) {
    root = byUid[root.parentImageUid]!;
  }

  final childrenByParent = <String, List<PromptImageItem>>{};
  for (final item in allImages) {
    final parentUid = item.parentImageUid;
    if (parentUid == null || parentUid.isEmpty) continue;
    childrenByParent.putIfAbsent(parentUid, () => []).add(item);
  }
  for (final children in childrenByParent.values) {
    children.sort((a, b) => _sortTimestamp(a).compareTo(_sortTimestamp(b)));
  }

  final timeline = <PromptConversationStep>[];
  final seen = <String>{};

  void visit(PromptImageItem item) {
    if (!seen.add(item.uid)) return;
    timeline.add(
      PromptConversationStep(
        imageUid: item.uid,
        prompt: _timelinePromptForImage(item),
        image: item,
      ),
    );
    for (final child
        in childrenByParent[item.uid] ?? const <PromptImageItem>[]) {
      visit(child);
    }
  }

  visit(root);
  return timeline;
}

PromptEditTree promptEditTreeForImage(
  PromptImageItem image,
  Iterable<PromptImageItem> allImages,
) {
  final byUid = {for (final item in allImages) item.uid: item};
  var root = image;
  while (root.parentImageUid != null &&
      root.parentImageUid!.isNotEmpty &&
      byUid.containsKey(root.parentImageUid)) {
    root = byUid[root.parentImageUid]!;
  }

  final childrenByParent = <String, List<PromptImageItem>>{};
  for (final item in allImages) {
    final parentUid = item.parentImageUid;
    if (parentUid == null || parentUid.isEmpty) continue;
    childrenByParent.putIfAbsent(parentUid, () => []).add(item);
  }
  for (final children in childrenByParent.values) {
    children.sort((a, b) => _sortTimestamp(a).compareTo(_sortTimestamp(b)));
  }

  final nodesByUid = <String, PromptEditTreeNode>{};
  final visiting = <String>{};

  PromptEditTreeNode buildNode(PromptImageItem item) {
    final existing = nodesByUid[item.uid];
    if (existing != null) return existing;
    if (!visiting.add(item.uid)) {
      final cycleNode = PromptEditTreeNode(image: item, edges: const []);
      nodesByUid[item.uid] = cycleNode;
      return cycleNode;
    }

    final groupedChildren = <String, List<PromptImageItem>>{};
    for (final child
        in childrenByParent[item.uid] ?? const <PromptImageItem>[]) {
      final prompt = editPromptForImage(child, parent: item);
      groupedChildren.putIfAbsent(prompt, () => []).add(child);
    }

    final edges = <PromptEditTreeEdge>[];
    for (final entry in groupedChildren.entries) {
      edges.add(
        PromptEditTreeEdge(
          parentImageUid: item.uid,
          prompt: entry.key,
          children: entry.value.map(buildNode).toList(growable: false),
        ),
      );
    }
    visiting.remove(item.uid);
    final node = PromptEditTreeNode(
      image: item,
      edges: List.unmodifiable(edges),
    );
    nodesByUid[item.uid] = node;
    return node;
  }

  final rootNode = buildNode(root);
  return PromptEditTree(
    root: rootNode,
    selectedImageUid: image.uid,
    nodesByUid: Map.unmodifiable(nodesByUid),
  );
}

String editPromptForImage(
  PromptImageItem image, {
  PromptImageItem? parent,
}) {
  if (image.promptParts.isNotEmpty) {
    if (parent != null &&
        parent.promptParts.isNotEmpty &&
        image.promptParts.length > parent.promptParts.length) {
      return buildInheritedPrompt(
        image.promptParts.skip(parent.promptParts.length).toList(),
      );
    }
    if (image.parentImageUid != null && image.promptParts.length > 1) {
      return image.promptParts.last.trim();
    }
    return image.promptParts.last.trim();
  }

  final prompt = image.prompt.trim();
  final parentPrompt = parent?.prompt.trim() ?? '';
  if (parentPrompt.isNotEmpty && prompt.startsWith(parentPrompt)) {
    final suffix = prompt.substring(parentPrompt.length).trim();
    if (suffix.isNotEmpty) return suffix;
  }
  return prompt;
}

String _timelinePromptForImage(PromptImageItem image) {
  if (image.promptParts.isNotEmpty) return image.promptParts.last;
  return image.prompt;
}

List<PromptImageItem> _uniqueByUid(List<PromptImageItem> images) {
  final result = <PromptImageItem>[];
  final seen = <String>{};
  for (final image in images) {
    if (seen.add(image.uid)) result.add(image);
  }
  return result;
}

int _sortTimestamp(PromptImageItem image) {
  return image.createdAt > 0 ? image.createdAt : image.updatedAt;
}
