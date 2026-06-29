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

class SyncStatus {
  const SyncStatus({
    this.isSyncing = false,
    this.message,
    this.lastSyncAt,
    this.accountEmail,
  });

  factory SyncStatus.fromJson(Map<String, dynamic> json) {
    return SyncStatus(
      isSyncing: json['isSyncing'] as bool? ?? false,
      message: json['message'] as String?,
      lastSyncAt: _int(json, 'lastSyncAt'),
      accountEmail: json['accountEmail'] as String?,
    );
  }

  final bool isSyncing;
  final String? message;
  final int? lastSyncAt;
  final String? accountEmail;

  SyncStatus copyWith({
    bool? isSyncing,
    Object? message = _sentinel,
    Object? lastSyncAt = _sentinel,
    Object? accountEmail = _sentinel,
  }) {
    return SyncStatus(
      isSyncing: isSyncing ?? this.isSyncing,
      message: message == _sentinel ? this.message : message as String?,
      lastSyncAt:
          lastSyncAt == _sentinel ? this.lastSyncAt : lastSyncAt as int?,
      accountEmail: accountEmail == _sentinel
          ? this.accountEmail
          : accountEmail as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'isSyncing': isSyncing,
      'message': message,
      'lastSyncAt': lastSyncAt,
      'accountEmail': accountEmail,
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
