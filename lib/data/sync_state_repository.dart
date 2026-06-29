import 'dart:convert';

import 'package:hive/hive.dart';
import 'package:uuid/uuid.dart';

import '../domain/sync_models.dart';
import 'pixrompt_api_client.dart';

abstract class SyncStateRepository {
  Future<PixromptSyncState> read();
  Future<void> write(PixromptSyncState state);
  Future<void> clearSession();
}

class PixromptSyncState {
  const PixromptSyncState({
    this.apiBaseUrl = defaultPixromptApiBaseUrl,
    this.accountEmail,
    this.token,
    this.tokenExpiresAt,
    this.deviceId = '',
    this.cursor = 0,
    this.knownServerVersions = const {},
    this.deletedTombstones = const {},
    this.lastSyncAt,
  });

  factory PixromptSyncState.fromJson(Map<String, dynamic> json) {
    return PixromptSyncState(
      apiBaseUrl: json['apiBaseUrl'] as String? ?? defaultPixromptApiBaseUrl,
      accountEmail: json['accountEmail'] as String?,
      token: json['token'] as String?,
      tokenExpiresAt: _int(json['tokenExpiresAt']),
      deviceId: json['deviceId'] as String? ?? '',
      cursor: _int(json['cursor']) ?? 0,
      knownServerVersions: _intMap(json['knownServerVersions']),
      deletedTombstones: _tombstoneMap(json['deletedTombstones']),
      lastSyncAt: _int(json['lastSyncAt']),
    );
  }

  final String apiBaseUrl;
  final String? accountEmail;
  final String? token;
  final int? tokenExpiresAt;
  final String deviceId;
  final int cursor;
  final Map<String, int> knownServerVersions;
  final Map<String, SyncTombstone> deletedTombstones;
  final int? lastSyncAt;

  bool get isAuthenticated => token != null && token!.isNotEmpty;

  PixromptSyncState copyWith({
    String? apiBaseUrl,
    Object? accountEmail = _sentinel,
    Object? token = _sentinel,
    Object? tokenExpiresAt = _sentinel,
    String? deviceId,
    int? cursor,
    Map<String, int>? knownServerVersions,
    Map<String, SyncTombstone>? deletedTombstones,
    Object? lastSyncAt = _sentinel,
  }) {
    return PixromptSyncState(
      apiBaseUrl: apiBaseUrl ?? this.apiBaseUrl,
      accountEmail:
          accountEmail == _sentinel ? this.accountEmail : accountEmail as String?,
      token: token == _sentinel ? this.token : token as String?,
      tokenExpiresAt: tokenExpiresAt == _sentinel
          ? this.tokenExpiresAt
          : tokenExpiresAt as int?,
      deviceId: deviceId ?? this.deviceId,
      cursor: cursor ?? this.cursor,
      knownServerVersions:
          knownServerVersions ?? Map<String, int>.from(this.knownServerVersions),
      deletedTombstones: deletedTombstones ??
          Map<String, SyncTombstone>.from(this.deletedTombstones),
      lastSyncAt:
          lastSyncAt == _sentinel ? this.lastSyncAt : lastSyncAt as int?,
    );
  }

  PixromptSyncState withoutSession() {
    return copyWith(
      accountEmail: null,
      token: null,
      tokenExpiresAt: null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'apiBaseUrl': apiBaseUrl,
      'accountEmail': accountEmail,
      'token': token,
      'tokenExpiresAt': tokenExpiresAt,
      'deviceId': deviceId,
      'cursor': cursor,
      'knownServerVersions': knownServerVersions,
      'deletedTombstones': deletedTombstones.map(
        (uid, tombstone) => MapEntry(uid, tombstone.toJson()),
      ),
      'lastSyncAt': lastSyncAt,
    };
  }
}

class HiveSyncStateRepository implements SyncStateRepository {
  HiveSyncStateRepository._(this._box);

  static Future<HiveSyncStateRepository> open({
    String prefix = 'pixrompt',
  }) async {
    final box = await Hive.openBox<dynamic>('${prefix}_sync_state');
    final repository = HiveSyncStateRepository._(box);
    final state = await repository.read();
    if (state.deviceId.isEmpty) {
      await repository.write(state.copyWith(deviceId: _newDeviceId()));
    }
    return repository;
  }

  final Box<dynamic> _box;

  @override
  Future<PixromptSyncState> read() async {
    final raw = _box.get(_stateKey);
    final decoded = _decodeState(raw);
    return PixromptSyncState.fromJson(decoded);
  }

  @override
  Future<void> write(PixromptSyncState state) {
    return _box.put(_stateKey, jsonEncode(state.toJson()));
  }

  @override
  Future<void> clearSession() async {
    await write((await read()).withoutSession());
  }
}

class MemorySyncStateRepository implements SyncStateRepository {
  MemorySyncStateRepository({PixromptSyncState? initialState})
      : _state = _withDeviceId(initialState ?? const PixromptSyncState());

  PixromptSyncState _state;

  @override
  Future<PixromptSyncState> read() async => _state;

  @override
  Future<void> write(PixromptSyncState state) async {
    _state = _withDeviceId(state);
  }

  @override
  Future<void> clearSession() async {
    _state = _state.withoutSession();
  }
}

Map<String, dynamic> _decodeState(Object? raw) {
  if (raw is String && raw.isNotEmpty) {
    final decoded = jsonDecode(raw);
    if (decoded is Map<String, dynamic>) return decoded;
    if (decoded is Map) return decoded.cast<String, dynamic>();
  }
  if (raw is Map<String, dynamic>) return raw;
  if (raw is Map) return raw.cast<String, dynamic>();
  return <String, dynamic>{};
}

Map<String, int> _intMap(Object? value) {
  final result = <String, int>{};
  if (value is! Map) return result;
  for (final entry in value.entries) {
    final key = entry.key;
    final version = _int(entry.value);
    if (key is String && version != null) {
      result[key] = version;
    }
  }
  return result;
}

Map<String, SyncTombstone> _tombstoneMap(Object? value) {
  final result = <String, SyncTombstone>{};
  if (value is! Map) return result;
  for (final entry in value.entries) {
    final key = entry.key;
    final payload = entry.value;
    if (key is String && payload is Map) {
      result[key] = SyncTombstone.fromJson(payload.cast<String, dynamic>());
    }
  }
  return result;
}

int? _int(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value);
  return null;
}

PixromptSyncState _withDeviceId(PixromptSyncState state) {
  if (state.deviceId.isNotEmpty) return state;
  return state.copyWith(deviceId: _newDeviceId());
}

String _newDeviceId() {
  return const Uuid().v4();
}

const _stateKey = 'state';
const _sentinel = Object();
