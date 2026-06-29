import 'category_dimension.dart';

class PromptEditHistoryEntry {
  const PromptEditHistoryEntry({
    required this.prompt,
    required this.imageUid,
    required this.createdAt,
    this.referenceImageUids = const [],
  });

  factory PromptEditHistoryEntry.fromJson(Map<String, dynamic> json) {
    return PromptEditHistoryEntry(
      prompt: json['prompt'] as String? ?? '',
      imageUid: json['imageUid'] as String? ?? '',
      createdAt: (json['createdAt'] as num?)?.toInt() ?? 0,
      referenceImageUids:
          (json['referenceImageUids'] as List<dynamic>? ?? const [])
              .whereType<String>()
              .toList(),
    );
  }

  final String prompt;
  final String imageUid;
  final int createdAt;
  final List<String> referenceImageUids;

  Map<String, dynamic> toJson() {
    return {
      'prompt': prompt,
      'imageUid': imageUid,
      'createdAt': createdAt,
      'referenceImageUids': referenceImageUids,
    };
  }

  PromptEditHistoryEntry copyWith({
    String? prompt,
    String? imageUid,
    int? createdAt,
    List<String>? referenceImageUids,
  }) {
    return PromptEditHistoryEntry(
      prompt: prompt ?? this.prompt,
      imageUid: imageUid ?? this.imageUid,
      createdAt: createdAt ?? this.createdAt,
      referenceImageUids: referenceImageUids ?? this.referenceImageUids,
    );
  }
}

class PromptImageItem {
  const PromptImageItem({
    required this.uid,
    required this.imageKey,
    required this.prompt,
    this.category = uncategorizedCategory,
    required this.aspectRatio,
    required this.createdAt,
    required this.updatedAt,
    this.categoryAssignments = const {},
    this.imageWidth = 0,
    this.imageHeight = 0,
    this.fileSizeBytes = 0,
    this.parentImageUid,
    this.promptParts = const [],
    this.editHistory = const [],
    this.originalFileName,
    this.contentSha256,
    this.mimeType,
    this.importedAt,
    this.lastSyncedAt,
  });

  factory PromptImageItem.sample({
    String uid = 'sample',
    String imageKey = 'sample-image',
    String prompt = 'Sample prompt',
    String category = uncategorizedCategory,
    Map<String, String> categoryAssignments = const {},
    double aspectRatio = 1,
    int? createdAt,
    int? updatedAt,
    int imageWidth = 0,
    int imageHeight = 0,
    int fileSizeBytes = 0,
    String? parentImageUid,
    List<String> promptParts = const [],
    List<PromptEditHistoryEntry> editHistory = const [],
    String? originalFileName,
    String? contentSha256,
    String? mimeType,
    int? importedAt,
    int? lastSyncedAt,
  }) {
    final now = DateTime(2026, 1, 1).millisecondsSinceEpoch;
    final normalizedAssignments =
        normalizeCategoryAssignments(categoryAssignments);
    final normalizedCategory = normalizeCategoryTerm(category);
    if (normalizedAssignments.isEmpty &&
        normalizedCategory.isNotEmpty &&
        normalizedCategory != uncategorizedCategory) {
      normalizedAssignments[sourceDimensionId] = normalizedCategory;
    }
    final legacyCategory =
        normalizedAssignments[sourceDimensionId] ?? uncategorizedCategory;
    return PromptImageItem(
      uid: uid,
      imageKey: imageKey,
      prompt: prompt,
      category: legacyCategory,
      categoryAssignments: normalizedAssignments,
      aspectRatio: aspectRatio,
      createdAt: createdAt ?? now,
      updatedAt: updatedAt ?? createdAt ?? now,
      imageWidth: imageWidth,
      imageHeight: imageHeight,
      fileSizeBytes: fileSizeBytes,
      parentImageUid: parentImageUid,
      promptParts: promptParts,
      editHistory: editHistory,
      originalFileName: originalFileName,
      contentSha256: contentSha256,
      mimeType: mimeType,
      importedAt: importedAt,
      lastSyncedAt: lastSyncedAt,
    );
  }

  factory PromptImageItem.fromJson(Map<String, dynamic> json) {
    final prompt = json['prompt'] as String? ?? '';
    final promptParts = (json['promptParts'] as List<dynamic>? ?? const [])
        .whereType<String>()
        .toList();
    final rawAssignments = json['categoryAssignments'];
    final assignments = <String, String>{};
    if (rawAssignments is Map<String, dynamic>) {
      for (final entry in rawAssignments.entries) {
        final value = entry.value;
        if (value is String) assignments[entry.key] = value;
      }
    }
    final legacyCategory = json['category'] as String?;
    if (assignments.isEmpty &&
        legacyCategory != null &&
        legacyCategory.trim().isNotEmpty &&
        legacyCategory != uncategorizedCategory) {
      assignments[sourceDimensionId] = legacyCategory;
    }
    final normalizedAssignments = normalizeCategoryAssignments(assignments);
    final category =
        normalizedAssignments[sourceDimensionId] ?? uncategorizedCategory;
    return PromptImageItem(
      uid: json['uid'] as String? ?? '',
      imageKey: json['imageKey'] as String? ?? '',
      prompt: prompt,
      category: category,
      categoryAssignments: normalizedAssignments,
      aspectRatio: (json['aspectRatio'] as num?)?.toDouble() ?? 1,
      createdAt: (json['createdAt'] as num?)?.toInt() ?? 0,
      updatedAt: (json['updatedAt'] as num?)?.toInt() ?? 0,
      imageWidth: (json['imageWidth'] as num?)?.toInt() ?? 0,
      imageHeight: (json['imageHeight'] as num?)?.toInt() ?? 0,
      fileSizeBytes: (json['fileSizeBytes'] as num?)?.toInt() ?? 0,
      parentImageUid: json['parentImageUid'] as String?,
      promptParts: promptParts.isEmpty && prompt.trim().isNotEmpty
          ? [prompt]
          : promptParts,
      editHistory: (json['editHistory'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(PromptEditHistoryEntry.fromJson)
          .toList(),
      originalFileName: json['originalFileName'] as String?,
      contentSha256: json['contentSha256'] as String?,
      mimeType: json['mimeType'] as String?,
      importedAt: (json['importedAt'] as num?)?.toInt(),
      lastSyncedAt: (json['lastSyncedAt'] as num?)?.toInt(),
    );
  }

  final String uid;
  final String imageKey;
  final String prompt;
  final String category;
  final Map<String, String> categoryAssignments;
  final double aspectRatio;
  final int createdAt;
  final int updatedAt;
  final int imageWidth;
  final int imageHeight;
  final int fileSizeBytes;
  final String? parentImageUid;
  final List<String> promptParts;
  final List<PromptEditHistoryEntry> editHistory;
  final String? originalFileName;
  final String? contentSha256;
  final String? mimeType;
  final int? importedAt;
  final int? lastSyncedAt;

  List<String> get searchableTerms => [
        prompt,
        category,
        ...categoryAssignments.values,
        ...promptParts,
      ];

  String categoryLabel(String dimensionId) {
    return categoryAssignments[dimensionId] ?? uncategorizedCategory;
  }

  PromptImageItem copyWith({
    String? uid,
    String? imageKey,
    String? prompt,
    String? category,
    Map<String, String>? categoryAssignments,
    double? aspectRatio,
    int? createdAt,
    int? updatedAt,
    int? imageWidth,
    int? imageHeight,
    int? fileSizeBytes,
    Object? parentImageUid = _sentinel,
    List<String>? promptParts,
    List<PromptEditHistoryEntry>? editHistory,
    Object? originalFileName = _sentinel,
    Object? contentSha256 = _sentinel,
    Object? mimeType = _sentinel,
    Object? importedAt = _sentinel,
    Object? lastSyncedAt = _sentinel,
  }) {
    final assignments = categoryAssignments == null
        ? this.categoryAssignments
        : normalizeCategoryAssignments(categoryAssignments);
    return PromptImageItem(
      uid: uid ?? this.uid,
      imageKey: imageKey ?? this.imageKey,
      prompt: prompt ?? this.prompt,
      category:
          category ?? assignments[sourceDimensionId] ?? uncategorizedCategory,
      categoryAssignments: assignments,
      aspectRatio: aspectRatio ?? this.aspectRatio,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      imageWidth: imageWidth ?? this.imageWidth,
      imageHeight: imageHeight ?? this.imageHeight,
      fileSizeBytes: fileSizeBytes ?? this.fileSizeBytes,
      parentImageUid: parentImageUid == _sentinel
          ? this.parentImageUid
          : parentImageUid as String?,
      promptParts: promptParts ?? this.promptParts,
      editHistory: editHistory ?? this.editHistory,
      originalFileName: originalFileName == _sentinel
          ? this.originalFileName
          : originalFileName as String?,
      contentSha256: contentSha256 == _sentinel
          ? this.contentSha256
          : contentSha256 as String?,
      mimeType: mimeType == _sentinel ? this.mimeType : mimeType as String?,
      importedAt:
          importedAt == _sentinel ? this.importedAt : importedAt as int?,
      lastSyncedAt: lastSyncedAt == _sentinel
          ? this.lastSyncedAt
          : lastSyncedAt as int?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'uid': uid,
      'imageKey': imageKey,
      'prompt': prompt,
      'category': category,
      'categoryAssignments': categoryAssignments,
      'aspectRatio': aspectRatio,
      'createdAt': createdAt,
      'updatedAt': updatedAt,
      'imageWidth': imageWidth,
      'imageHeight': imageHeight,
      'fileSizeBytes': fileSizeBytes,
      'parentImageUid': parentImageUid,
      'promptParts': promptParts,
      'editHistory': editHistory.map((entry) => entry.toJson()).toList(),
      'originalFileName': originalFileName,
      'contentSha256': contentSha256,
      'mimeType': mimeType,
      'importedAt': importedAt,
      'lastSyncedAt': lastSyncedAt,
    };
  }
}

const _sentinel = Object();
