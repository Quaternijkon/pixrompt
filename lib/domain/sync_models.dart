class LoginRequest {
  const LoginRequest({
    required this.email,
    required this.password,
    required this.deviceId,
  });

  factory LoginRequest.fromJson(Map<String, dynamic> json) {
    return LoginRequest(
      email: _string(json, 'email'),
      password: _string(json, 'password'),
      deviceId: _string(json, 'deviceId'),
    );
  }

  final String email;
  final String password;
  final String deviceId;

  Map<String, dynamic> toJson() {
    return {
      'email': email,
      'password': password,
      'deviceId': deviceId,
    };
  }
}

class AuthSession {
  const AuthSession({
    required this.token,
    required this.tokenExpiresAt,
    required this.accountEmail,
    required this.deviceId,
  });

  factory AuthSession.fromJson(Map<String, dynamic> json) {
    final accountEmail =
        _requiredString(json, 'accountEmail', fallbackKey: 'email');
    return AuthSession(
      token: _requiredString(json, 'token'),
      tokenExpiresAt:
          _requiredInt(json, 'tokenExpiresAt', fallbackKey: 'expiresAt'),
      accountEmail: accountEmail.toLowerCase(),
      deviceId: _requiredString(json, 'deviceId'),
    );
  }

  final String token;
  final int tokenExpiresAt;
  final String accountEmail;
  final String deviceId;

  Map<String, dynamic> toJson() {
    return {
      'token': token,
      'tokenExpiresAt': tokenExpiresAt,
      'accountEmail': accountEmail,
      'deviceId': deviceId,
    };
  }
}

class BlobRef {
  const BlobRef({
    required this.sha256,
    required this.imageKey,
    required this.sizeBytes,
    this.mimeType,
  });

  factory BlobRef.fromJson(Map<String, dynamic> json) {
    return BlobRef(
      sha256: _requiredString(json, 'sha256'),
      imageKey: _requiredString(json, 'imageKey'),
      sizeBytes: _requiredInt(json, 'sizeBytes'),
      mimeType: json['mimeType'] as String?,
    );
  }

  final String sha256;
  final String imageKey;
  final int sizeBytes;
  final String? mimeType;

  Map<String, dynamic> toJson() {
    return {
      'sha256': sha256,
      'imageKey': imageKey,
      'sizeBytes': sizeBytes,
      'mimeType': mimeType,
    };
  }
}

class PullRequest {
  const PullRequest({
    required this.deviceId,
    required this.cursor,
    this.knownBlobSha256 = const [],
  });

  factory PullRequest.fromJson(Map<String, dynamic> json) {
    return PullRequest(
      deviceId: _string(json, 'deviceId'),
      cursor: _int(json, 'cursor') ?? 0,
      knownBlobSha256: _stringList(json['knownBlobSha256']),
    );
  }

  final String deviceId;
  final int cursor;
  final List<String> knownBlobSha256;

  Map<String, dynamic> toJson() {
    return {
      'deviceId': deviceId,
      'cursor': cursor,
      'knownBlobSha256': knownBlobSha256,
    };
  }
}

class PullResponse {
  const PullResponse({
    required this.cursor,
    required this.serverTime,
    this.changes = const [],
    this.deleted = const [],
    this.missingBlobs = const [],
  });

  factory PullResponse.fromJson(Map<String, dynamic> json) {
    return PullResponse(
      cursor: _requiredInt(json, 'cursor'),
      serverTime: _requiredInt(json, 'serverTime'),
      changes: _requiredObjectList(json, 'changes')
          .map(PullChange.fromJson)
          .toList(growable: false),
      deleted: _requiredObjectList(json, 'deleted')
          .map(SyncTombstone.fromPullJson)
          .toList(growable: false),
      missingBlobs: _requiredStringList(json, 'missingBlobs'),
    );
  }

  final int cursor;
  final int serverTime;
  final List<PullChange> changes;
  final List<SyncTombstone> deleted;
  final List<String> missingBlobs;

  Map<String, dynamic> toJson() {
    return {
      'cursor': cursor,
      'serverTime': serverTime,
      'changes': changes.map((change) => change.toJson()).toList(),
      'deleted': deleted.map((tombstone) => tombstone.toJson()).toList(),
      'missingBlobs': missingBlobs,
    };
  }
}

class PullChange {
  const PullChange({
    required this.type,
    required this.imageUid,
    required this.serverVersion,
    required this.updatedAt,
    required this.record,
    this.blob,
  });

  factory PullChange.fromJson(Map<String, dynamic> json) {
    final type = _requiredString(json, 'type');
    if (type != 'upsert') {
      throw FormatException('Unsupported pull change type: $type.');
    }
    return PullChange(
      type: type,
      imageUid: _requiredString(json, 'imageUid'),
      serverVersion: _requiredInt(json, 'serverVersion'),
      updatedAt: _requiredInt(json, 'updatedAt'),
      record: _requiredObjectMap(json, 'record'),
      blob: json['blob'] is Map
          ? BlobRef.fromJson(_objectMap(json['blob']))
          : null,
    );
  }

  final String type;
  final String imageUid;
  final int serverVersion;
  final int updatedAt;
  final Map<String, dynamic> record;
  final BlobRef? blob;

  Map<String, dynamic> toJson() {
    return {
      'type': type,
      'imageUid': imageUid,
      'serverVersion': serverVersion,
      'updatedAt': updatedAt,
      'record': record,
      'blob': blob?.toJson(),
    };
  }
}

class PushRequest {
  const PushRequest({
    required this.deviceId,
    required this.baseCursor,
    this.images = const [],
    this.deleted = const [],
  });

  factory PushRequest.fromJson(Map<String, dynamic> json) {
    return PushRequest(
      deviceId: _string(json, 'deviceId'),
      baseCursor: _int(json, 'baseCursor') ?? 0,
      images: _objectList(json['images'])
          .map(PushImage.fromJson)
          .toList(growable: false),
      deleted: _objectList(json['deleted'])
          .map(SyncTombstone.fromJson)
          .toList(growable: false),
    );
  }

  final String deviceId;
  final int baseCursor;
  final List<PushImage> images;
  final List<SyncTombstone> deleted;

  Map<String, dynamic> toJson() {
    return {
      'deviceId': deviceId,
      'baseCursor': baseCursor,
      'images': images.map((image) => image.toJson()).toList(),
      'deleted': deleted.map((tombstone) => tombstone.toJson()).toList(),
    };
  }
}

class PushImage {
  const PushImage({
    required this.imageUid,
    required this.baseServerVersion,
    required this.updatedAt,
    required this.record,
    this.blob,
  });

  factory PushImage.fromJson(Map<String, dynamic> json) {
    return PushImage(
      imageUid: _string(json, 'imageUid'),
      baseServerVersion: _int(json, 'baseServerVersion') ?? 0,
      updatedAt: _int(json, 'updatedAt') ?? 0,
      record: _objectMap(json['record']),
      blob: json['blob'] is Map
          ? BlobRef.fromJson(_objectMap(json['blob']))
          : null,
    );
  }

  final String imageUid;
  final int baseServerVersion;
  final int updatedAt;
  final Map<String, dynamic> record;
  final BlobRef? blob;

  Map<String, dynamic> toJson() {
    return {
      'imageUid': imageUid,
      'baseServerVersion': baseServerVersion,
      'updatedAt': updatedAt,
      'record': record,
      'blob': blob?.toJson(),
    };
  }
}

class PushResponse {
  const PushResponse({
    required this.cursor,
    required this.serverTime,
    this.accepted = const [],
    this.rejected = const [],
    this.missingBlobs = const [],
  });

  factory PushResponse.fromJson(Map<String, dynamic> json) {
    return PushResponse(
      cursor: _requiredInt(json, 'cursor'),
      serverTime: _requiredInt(json, 'serverTime'),
      accepted: _requiredObjectList(json, 'accepted')
          .map(AcceptedChange.fromJson)
          .toList(growable: false),
      rejected: _requiredObjectList(json, 'rejected')
          .map(RejectedChange.fromJson)
          .toList(growable: false),
      missingBlobs: _requiredStringList(json, 'missingBlobs'),
    );
  }

  final int cursor;
  final int serverTime;
  final List<AcceptedChange> accepted;
  final List<RejectedChange> rejected;
  final List<String> missingBlobs;

  Map<String, dynamic> toJson() {
    return {
      'cursor': cursor,
      'serverTime': serverTime,
      'accepted': accepted.map((change) => change.toJson()).toList(),
      'rejected': rejected.map((change) => change.toJson()).toList(),
      'missingBlobs': missingBlobs,
    };
  }
}

class AcceptedChange {
  const AcceptedChange({
    required this.imageUid,
    required this.serverVersion,
  });

  factory AcceptedChange.fromJson(Map<String, dynamic> json) {
    return AcceptedChange(
      imageUid: _requiredString(json, 'imageUid'),
      serverVersion: _requiredInt(json, 'serverVersion'),
    );
  }

  final String imageUid;
  final int serverVersion;

  Map<String, dynamic> toJson() {
    return {
      'imageUid': imageUid,
      'serverVersion': serverVersion,
    };
  }
}

class RejectedChange {
  const RejectedChange({
    required this.imageUid,
    required this.reason,
    required this.serverVersion,
  });

  factory RejectedChange.fromJson(Map<String, dynamic> json) {
    return RejectedChange(
      imageUid: _requiredString(json, 'imageUid'),
      reason: _requiredString(json, 'reason'),
      serverVersion: _requiredInt(json, 'serverVersion'),
    );
  }

  final String imageUid;
  final String reason;
  final int serverVersion;

  Map<String, dynamic> toJson() {
    return {
      'imageUid': imageUid,
      'reason': reason,
      'serverVersion': serverVersion,
    };
  }
}

class SyncTombstone {
  const SyncTombstone({
    required this.imageUid,
    required this.deletedAt,
    this.baseServerVersion,
    this.serverVersion,
  });

  factory SyncTombstone.fromJson(Map<String, dynamic> json) {
    return SyncTombstone(
      imageUid: _requiredString(json, 'imageUid'),
      deletedAt: _requiredInt(json, 'deletedAt'),
      baseServerVersion: _int(json, 'baseServerVersion'),
      serverVersion: _int(json, 'serverVersion'),
    );
  }

  factory SyncTombstone.fromPullJson(Map<String, dynamic> json) {
    return SyncTombstone(
      imageUid: _requiredString(json, 'imageUid'),
      deletedAt: _requiredInt(json, 'deletedAt'),
      baseServerVersion: _int(json, 'baseServerVersion'),
      serverVersion: _requiredInt(json, 'serverVersion'),
    );
  }

  final String imageUid;
  final int deletedAt;
  final int? baseServerVersion;
  final int? serverVersion;

  Map<String, dynamic> toJson() {
    return {
      'imageUid': imageUid,
      'baseServerVersion': baseServerVersion,
      'serverVersion': serverVersion,
      'deletedAt': deletedAt,
    };
  }
}

const syncQueueKindPrepare = 'prepare';
const syncQueueKindUpload = 'upload';
const syncQueueKindPush = 'push';
const syncQueueKindPull = 'pull';
const syncQueueKindDownload = 'download';
const syncQueueKindDelete = 'delete';

const syncQueueStateWaiting = 'waiting';
const syncQueueStateActive = 'active';
const syncQueueStateComplete = 'complete';
const syncQueueStateFailed = 'failed';

class SyncQueueItem {
  const SyncQueueItem({
    required this.id,
    required this.label,
    this.detail,
    this.kind = syncQueueKindPrepare,
    this.state = syncQueueStateWaiting,
    this.bytesDone = 0,
    this.bytesTotal = 0,
  });

  factory SyncQueueItem.fromJson(Map<String, dynamic> json) {
    return SyncQueueItem(
      id: _requiredString(json, 'id'),
      label: _requiredString(json, 'label'),
      detail: _string(json, 'detail').isEmpty ? null : _string(json, 'detail'),
      kind: _string(json, 'kind').isEmpty
          ? syncQueueKindPrepare
          : _string(json, 'kind'),
      state: _string(json, 'state').isEmpty
          ? syncQueueStateWaiting
          : _string(json, 'state'),
      bytesDone: _int(json, 'bytesDone') ?? 0,
      bytesTotal: _int(json, 'bytesTotal') ?? 0,
    );
  }

  final String id;
  final String label;
  final String? detail;
  final String kind;
  final String state;
  final int bytesDone;
  final int bytesTotal;

  double? get fraction {
    if (bytesTotal > 0) {
      return (bytesDone / bytesTotal).clamp(0, 1).toDouble();
    }
    if (state == syncQueueStateComplete) return 1;
    if (state == syncQueueStateActive) return null;
    return 0;
  }

  SyncQueueItem copyWith({
    String? id,
    String? label,
    Object? detail = _sentinel,
    String? kind,
    String? state,
    int? bytesDone,
    int? bytesTotal,
  }) {
    return SyncQueueItem(
      id: id ?? this.id,
      label: label ?? this.label,
      detail: detail == _sentinel ? this.detail : detail as String?,
      kind: kind ?? this.kind,
      state: state ?? this.state,
      bytesDone: bytesDone ?? this.bytesDone,
      bytesTotal: bytesTotal ?? this.bytesTotal,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'label': label,
      'detail': detail,
      'kind': kind,
      'state': state,
      'bytesDone': bytesDone,
      'bytesTotal': bytesTotal,
    };
  }
}

class SyncProgress {
  const SyncProgress({
    this.isActive = false,
    this.phase = '',
    this.startedAt,
    this.updatedAt,
    this.completedItems = 0,
    this.totalItems = 0,
    this.bytesDone = 0,
    this.bytesTotal = 0,
    this.queue = const [],
  });

  factory SyncProgress.fromJson(Map<String, dynamic> json) {
    return SyncProgress(
      isActive: json['isActive'] as bool? ?? false,
      phase: _string(json, 'phase'),
      startedAt: _int(json, 'startedAt'),
      updatedAt: _int(json, 'updatedAt'),
      completedItems: _int(json, 'completedItems') ?? 0,
      totalItems: _int(json, 'totalItems') ?? 0,
      bytesDone: _int(json, 'bytesDone') ?? 0,
      bytesTotal: _int(json, 'bytesTotal') ?? 0,
      queue: _objectList(json['queue'])
          .map(SyncQueueItem.fromJson)
          .toList(growable: false),
    );
  }

  final bool isActive;
  final String phase;
  final int? startedAt;
  final int? updatedAt;
  final int completedItems;
  final int totalItems;
  final int bytesDone;
  final int bytesTotal;
  final List<SyncQueueItem> queue;

  double? get fraction {
    if (totalItems > 0) {
      return (completedItems / totalItems).clamp(0, 1).toDouble();
    }
    if (bytesTotal > 0) {
      return (bytesDone / bytesTotal).clamp(0, 1).toDouble();
    }
    if (!isActive && queue.isNotEmpty) return 1;
    return null;
  }

  double get bytesPerSecond {
    final start = startedAt;
    final updated = updatedAt;
    if (start == null || updated == null || bytesDone <= 0) return 0;
    final elapsedMs = updated - start;
    if (elapsedMs <= 0) return 0;
    return bytesDone / (elapsedMs / 1000);
  }

  SyncProgress copyWith({
    bool? isActive,
    String? phase,
    Object? startedAt = _sentinel,
    Object? updatedAt = _sentinel,
    int? completedItems,
    int? totalItems,
    int? bytesDone,
    int? bytesTotal,
    List<SyncQueueItem>? queue,
  }) {
    return SyncProgress(
      isActive: isActive ?? this.isActive,
      phase: phase ?? this.phase,
      startedAt: startedAt == _sentinel ? this.startedAt : startedAt as int?,
      updatedAt: updatedAt == _sentinel ? this.updatedAt : updatedAt as int?,
      completedItems: completedItems ?? this.completedItems,
      totalItems: totalItems ?? this.totalItems,
      bytesDone: bytesDone ?? this.bytesDone,
      bytesTotal: bytesTotal ?? this.bytesTotal,
      queue: queue ?? this.queue,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'isActive': isActive,
      'phase': phase,
      'startedAt': startedAt,
      'updatedAt': updatedAt,
      'completedItems': completedItems,
      'totalItems': totalItems,
      'bytesDone': bytesDone,
      'bytesTotal': bytesTotal,
      'queue': queue.map((item) => item.toJson()).toList(),
    };
  }
}

class SyncStatus {
  const SyncStatus({
    this.isSyncing = false,
    this.message,
    this.lastSyncAt,
    this.accountEmail,
    this.progress = const SyncProgress(),
  });

  factory SyncStatus.fromJson(Map<String, dynamic> json) {
    return SyncStatus(
      isSyncing: json['isSyncing'] as bool? ?? false,
      message: json['message'] as String?,
      lastSyncAt: _int(json, 'lastSyncAt'),
      accountEmail: json['accountEmail'] as String?,
      progress: json['progress'] is Map
          ? SyncProgress.fromJson(_objectMap(json['progress']))
          : const SyncProgress(),
    );
  }

  final bool isSyncing;
  final String? message;
  final int? lastSyncAt;
  final String? accountEmail;
  final SyncProgress progress;

  SyncStatus copyWith({
    bool? isSyncing,
    Object? message = _sentinel,
    Object? lastSyncAt = _sentinel,
    Object? accountEmail = _sentinel,
    SyncProgress? progress,
  }) {
    return SyncStatus(
      isSyncing: isSyncing ?? this.isSyncing,
      message: message == _sentinel ? this.message : message as String?,
      lastSyncAt:
          lastSyncAt == _sentinel ? this.lastSyncAt : lastSyncAt as int?,
      accountEmail: accountEmail == _sentinel
          ? this.accountEmail
          : accountEmail as String?,
      progress: progress ?? this.progress,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'isSyncing': isSyncing,
      'message': message,
      'lastSyncAt': lastSyncAt,
      'accountEmail': accountEmail,
      'progress': progress.toJson(),
    };
  }
}

String _string(
  Map<String, dynamic> json,
  String key, {
  String? fallbackKey,
}) {
  final value = json[key] ?? (fallbackKey == null ? null : json[fallbackKey]);
  return value is String ? value : '';
}

String _requiredString(
  Map<String, dynamic> json,
  String key, {
  String? fallbackKey,
}) {
  final value = json[key] ?? (fallbackKey == null ? null : json[fallbackKey]);
  if (value is String && value.trim().isNotEmpty) {
    return value.trim();
  }
  throw FormatException('Missing or invalid required string field: $key.');
}

int? _int(
  Map<String, dynamic> json,
  String key, {
  String? fallbackKey,
}) {
  final value = json[key] ?? (fallbackKey == null ? null : json[fallbackKey]);
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value);
  return null;
}

int _requiredInt(
  Map<String, dynamic> json,
  String key, {
  String? fallbackKey,
}) {
  final value = _int(json, key, fallbackKey: fallbackKey);
  if (value != null) return value;
  throw FormatException('Missing or invalid required integer field: $key.');
}

List<String> _stringList(Object? value) {
  return (value as List<dynamic>? ?? const []).whereType<String>().toList();
}

List<String> _requiredStringList(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! List) {
    throw FormatException('Missing or invalid required list field: $key.');
  }
  final result = <String>[];
  for (final item in value) {
    if (item is! String) {
      throw FormatException('Invalid string value in required list: $key.');
    }
    result.add(item);
  }
  return result;
}

List<Map<String, dynamic>> _objectList(Object? value) {
  return (value as List<dynamic>? ?? const [])
      .whereType<Map>()
      .map((entry) => entry.cast<String, dynamic>())
      .toList();
}

List<Map<String, dynamic>> _requiredObjectList(
  Map<String, dynamic> json,
  String key,
) {
  final value = json[key];
  if (value is! List) {
    throw FormatException('Missing or invalid required list field: $key.');
  }
  return value.map((item) {
    if (item is Map<String, dynamic>) return item;
    if (item is Map) return item.cast<String, dynamic>();
    throw FormatException('Invalid object value in required list: $key.');
  }).toList();
}

Map<String, dynamic> _objectMap(Object? value) {
  if (value is Map<String, dynamic>) return Map<String, dynamic>.from(value);
  if (value is Map) return value.cast<String, dynamic>();
  return <String, dynamic>{};
}

Map<String, dynamic> _requiredObjectMap(
  Map<String, dynamic> json,
  String key,
) {
  final value = json[key];
  if (value is Map<String, dynamic>) return Map<String, dynamic>.from(value);
  if (value is Map) return value.cast<String, dynamic>();
  throw FormatException('Missing or invalid required object field: $key.');
}

const _sentinel = Object();
