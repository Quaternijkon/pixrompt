import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

import '../data/pixrompt_api_client.dart';
import '../data/sync_state_repository.dart';
import '../domain/prompt_image.dart';
import '../domain/sync_models.dart';
import 'pixrompt_controller.dart';

class PixromptSyncController extends ChangeNotifier {
  PixromptSyncController({
    required PixromptController pixromptController,
    required SyncStateRepository syncStateRepository,
    PixromptApi? api,
    PixromptApi Function(String apiBaseUrl)? apiFactory,
    DateTime Function()? now,
    String Function()? deviceIdFactory,
  })  : _pixromptController = pixromptController,
        _syncStateRepository = syncStateRepository,
        _api = api,
        _apiFactory = apiFactory ??
            ((apiBaseUrl) => PixromptApiClient(apiBaseUrl: apiBaseUrl)),
        _now = now ?? DateTime.now,
        _deviceIdFactory = deviceIdFactory ?? _defaultDeviceId;

  final PixromptController _pixromptController;
  final SyncStateRepository _syncStateRepository;
  final PixromptApi? _api;
  final PixromptApi Function(String apiBaseUrl) _apiFactory;
  final DateTime Function() _now;
  final String Function() _deviceIdFactory;

  SyncStatus _status = const SyncStatus();
  SyncStatus get status => _status;

  Future<void> refreshStatus() async {
    final state = await _syncStateRepository.read();
    _setStatus(
      _status.copyWith(
        accountEmail: state.accountEmail,
        lastSyncAt: state.lastSyncAt,
      ),
    );
  }

  Future<void> login({
    required String email,
    required String password,
    String? apiBaseUrl,
  }) async {
    final current = await _syncStateRepository.read();
    final baseUrl = _normalizedBaseUrl(apiBaseUrl) ?? current.apiBaseUrl;
    final deviceId =
        current.deviceId.isEmpty ? _deviceIdFactory() : current.deviceId;
    final api = _apiFor(baseUrl);
    _setStatus(
      SyncStatus(
        isSyncing: true,
        message: '正在登录。',
        lastSyncAt: current.lastSyncAt,
        accountEmail: current.accountEmail,
      ),
    );
    try {
      final session = await api.login(
        LoginRequest(
          email: email.trim(),
          password: password,
          deviceId: deviceId,
        ),
      );
      final state = current.copyWith(
        apiBaseUrl: baseUrl,
        accountEmail: session.accountEmail,
        token: session.token,
        tokenExpiresAt: session.tokenExpiresAt,
        deviceId: session.deviceId.isEmpty ? deviceId : session.deviceId,
      );
      await _syncStateRepository.write(state);
      _setStatus(
        SyncStatus(
          message: '已登录。',
          lastSyncAt: state.lastSyncAt,
          accountEmail: state.accountEmail,
        ),
      );
    } catch (error) {
      _setStatus(
        SyncStatus(
          message: '登录失败：$error',
          lastSyncAt: current.lastSyncAt,
          accountEmail: current.accountEmail,
        ),
      );
      rethrow;
    }
  }

  Future<void> logout() async {
    final state = await _syncStateRepository.read();
    final token = state.token;
    try {
      if (token != null && token.isNotEmpty) {
        await _apiFor(state.apiBaseUrl).logout(token);
      }
    } finally {
      await _syncStateRepository.clearSession();
      _setStatus(
        SyncStatus(
          message: '已退出登录。',
          lastSyncAt: state.lastSyncAt,
        ),
      );
    }
  }

  Future<void> manualSync() async {
    var state = await _syncStateRepository.read();
    final token = state.token;
    if (token == null || token.isEmpty) {
      _setStatus(
        SyncStatus(
          message: '请先登录。',
          lastSyncAt: state.lastSyncAt,
          accountEmail: state.accountEmail,
        ),
      );
      return;
    }
    if (state.deviceId.isEmpty) {
      state = state.copyWith(deviceId: _deviceIdFactory());
      await _syncStateRepository.write(state);
    }

    _setStatus(
      SyncStatus(
        isSyncing: true,
        message: '正在同步。',
        lastSyncAt: state.lastSyncAt,
        accountEmail: state.accountEmail,
      ),
    );

    try {
      final api = _apiFor(state.apiBaseUrl);
      final local = await _prepareLocalImagesForPush(api, token, state);
      if (local.imagesToPersist.isNotEmpty) {
        await _pixromptController.applySyncUpserts(local.imagesToPersist);
      }

      final pushResponse = await api.push(
        token,
        PushRequest(
          deviceId: state.deviceId,
          baseCursor: state.cursor,
          images: local.pushImages,
          deleted: state.deletedTombstones.values.toList(),
        ),
      );
      state = await _persistPushResult(
        state,
        pushResponse,
        local.pushedRecordsByUid,
      );

      final pullResponse = await api.pull(
        token,
        PullRequest(
          deviceId: state.deviceId,
          cursor: state.cursor,
          knownBlobSha256: local.knownBlobSha256.toList(growable: false),
        ),
      );
      state = await _applyPullResult(api, token, state, pullResponse);

      _setStatus(
        SyncStatus(
          message: '同步完成。',
          lastSyncAt: state.lastSyncAt,
          accountEmail: state.accountEmail,
        ),
      );
    } catch (error) {
      _setStatus(
        SyncStatus(
          message: '同步失败：$error',
          lastSyncAt: state.lastSyncAt,
          accountEmail: state.accountEmail,
        ),
      );
      rethrow;
    }
  }

  Future<void> recordLocalTombstone(String imageUid) async {
    final state = await _syncStateRepository.read();
    final now = _now().millisecondsSinceEpoch;
    final tombstones = Map<String, SyncTombstone>.from(state.deletedTombstones);
    tombstones[imageUid] = SyncTombstone(
      imageUid: imageUid,
      baseServerVersion: state.knownServerVersions[imageUid] ?? 0,
      deletedAt: now,
    );
    await _syncStateRepository.write(
      state.copyWith(deletedTombstones: tombstones),
    );
  }

  Future<_PreparedLocalImages> _prepareLocalImagesForPush(
    PixromptApi api,
    String token,
    PixromptSyncState state,
  ) async {
    final imagesToPersist = <PromptImageItem>[];
    final pushImages = <PushImage>[];
    final pushedRecordsByUid = <String, PromptImageItem>{};
    final knownBlobSha256 = <String>{};

    for (final image in await _pixromptController.readSyncImages()) {
      final bytes = await _pixromptController.readSyncImageBytes(image.imageKey);
      BlobRef? blob;
      var record = image;
      var needsMaintenance = false;
      if (bytes != null) {
        final contentSha256 = sha256Hex(bytes);
        final mimeType = image.mimeType ??
            guessMimeType(image.originalFileName ?? image.imageKey);
        knownBlobSha256.add(contentSha256);
        needsMaintenance = image.contentSha256 != contentSha256 ||
            image.mimeType == null ||
            image.importedAt == null;
        blob = BlobRef(
          sha256: contentSha256,
          imageKey: image.imageKey,
          sizeBytes: bytes.length,
          mimeType: mimeType,
        );
        record = image.copyWith(
          contentSha256: contentSha256,
          mimeType: mimeType,
          importedAt: image.importedAt ?? image.createdAt,
          fileSizeBytes: image.fileSizeBytes > 0
              ? image.fileSizeBytes
              : bytes.length,
        );
        final shouldPush = _shouldPushLocalRecord(
          image: image,
          record: record,
          state: state,
          needsMaintenance: needsMaintenance,
        );
        if (needsMaintenance) {
          imagesToPersist.add(record);
        }
        if (shouldPush && !await api.headBlob(token, contentSha256)) {
          await api.putBlob(
            token,
            contentSha256,
            bytes,
            mimeType: mimeType,
          );
        }
      } else if (image.contentSha256 != null &&
          image.contentSha256!.isNotEmpty) {
        knownBlobSha256.add(image.contentSha256!);
      }

      final shouldPush = _shouldPushLocalRecord(
        image: image,
        record: record,
        state: state,
        needsMaintenance: needsMaintenance,
      );
      if (shouldPush) {
        pushedRecordsByUid[record.uid] = record;
        pushImages.add(
          PushImage(
            imageUid: record.uid,
            baseServerVersion: state.knownServerVersions[record.uid] ?? 0,
            updatedAt: record.updatedAt,
            record: record.toJson(),
            blob: blob,
          ),
        );
      }
    }

    return _PreparedLocalImages(
      imagesToPersist: imagesToPersist,
      pushImages: pushImages,
      pushedRecordsByUid: pushedRecordsByUid,
      knownBlobSha256: knownBlobSha256,
    );
  }

  bool _shouldPushLocalRecord({
    required PromptImageItem image,
    required PromptImageItem record,
    required PixromptSyncState state,
    required bool needsMaintenance,
  }) {
    final knownServerVersion = state.knownServerVersions[record.uid];
    return knownServerVersion == null ||
        image.updatedAt > (image.lastSyncedAt ?? 0) ||
        needsMaintenance;
  }

  Future<PixromptSyncState> _persistPushResult(
    PixromptSyncState state,
    PushResponse response,
    Map<String, PromptImageItem> pushedRecordsByUid,
  ) async {
    final knownServerVersions =
        Map<String, int>.from(state.knownServerVersions);
    final deletedTombstones =
        Map<String, SyncTombstone>.from(state.deletedTombstones);
    final acceptedRecords = <PromptImageItem>[];
    for (final accepted in response.accepted) {
      knownServerVersions[accepted.imageUid] = accepted.serverVersion;
      deletedTombstones.remove(accepted.imageUid);
      final record = pushedRecordsByUid[accepted.imageUid];
      if (record != null) {
        acceptedRecords.add(
          record.copyWith(lastSyncedAt: response.serverTime),
        );
      }
    }
    for (final rejected in response.rejected) {
      final serverVersion = rejected.serverVersion;
      if (serverVersion != null) {
        knownServerVersions[rejected.imageUid] = serverVersion;
      }
    }
    final next = state.copyWith(
      cursor: response.cursor > state.cursor ? response.cursor : state.cursor,
      knownServerVersions: knownServerVersions,
      deletedTombstones: deletedTombstones,
      lastSyncAt: response.serverTime > 0 ? response.serverTime : state.lastSyncAt,
    );
    if (acceptedRecords.isNotEmpty) {
      await _pixromptController.applySyncUpserts(acceptedRecords);
    }
    await _syncStateRepository.write(next);
    return next;
  }

  Future<PixromptSyncState> _applyPullResult(
    PixromptApi api,
    String token,
    PixromptSyncState state,
    PullResponse response,
  ) async {
    final knownServerVersions =
        Map<String, int>.from(state.knownServerVersions);
    final upserts = <PromptImageItem>[];
    final syncTime = response.serverTime > 0
        ? response.serverTime
        : _now().millisecondsSinceEpoch;

    for (final change in response.changes) {
      if (change.type != 'upsert') continue;
      var image = PromptImageItem.fromJson(change.record);
      if (image.uid.isEmpty) {
        image = image.copyWith(uid: change.imageUid);
      }
      final blob = change.blob;
      if (blob != null) {
        if (image.imageKey.isEmpty) {
          image = image.copyWith(imageKey: blob.imageKey);
        }
        final existingBytes =
            await _pixromptController.readSyncImageBytes(image.imageKey);
        final existingSha =
            existingBytes == null ? null : sha256Hex(existingBytes);
        if (existingSha != blob.sha256) {
          final downloaded = await api.getBlob(token, blob.sha256);
          await _pixromptController.writeSyncImageBytes(
            image.imageKey,
            downloaded,
          );
        }
        image = image.copyWith(
          contentSha256: blob.sha256,
          mimeType: blob.mimeType ?? image.mimeType,
          importedAt: image.importedAt ?? image.createdAt,
          fileSizeBytes: blob.sizeBytes,
          lastSyncedAt: syncTime,
        );
      } else {
        image = image.copyWith(
          importedAt: image.importedAt ?? image.createdAt,
          lastSyncedAt: syncTime,
        );
      }
      upserts.add(image);
      knownServerVersions[change.imageUid] = change.serverVersion;
    }

    if (upserts.isNotEmpty) {
      await _pixromptController.applySyncUpserts(upserts);
    }

    if (response.deleted.isNotEmpty) {
      final deletedTombstones =
          Map<String, SyncTombstone>.from(state.deletedTombstones);
      await _pixromptController.applySyncTombstones(
        response.deleted.map((tombstone) => tombstone.imageUid),
      );
      for (final tombstone in response.deleted) {
        deletedTombstones.remove(tombstone.imageUid);
        final serverVersion = tombstone.serverVersion;
        if (serverVersion != null) {
          knownServerVersions[tombstone.imageUid] = serverVersion;
        }
      }
      state = state.copyWith(deletedTombstones: deletedTombstones);
    }

    final next = state.copyWith(
      cursor: response.cursor > state.cursor ? response.cursor : state.cursor,
      knownServerVersions: knownServerVersions,
      lastSyncAt: syncTime,
    );
    await _syncStateRepository.write(next);
    return next;
  }

  PixromptApi _apiFor(String apiBaseUrl) {
    return _api ?? _apiFactory(apiBaseUrl);
  }

  String? _normalizedBaseUrl(String? value) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) return null;
    return trimmed;
  }

  void _setStatus(SyncStatus status) {
    _status = status;
    notifyListeners();
  }
}

String sha256Hex(Uint8List bytes) {
  return sha256.convert(bytes).toString();
}

String guessMimeType(String name) {
  final lower = name.toLowerCase();
  if (lower.endsWith('.png')) return 'image/png';
  if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'image/jpeg';
  if (lower.endsWith('.webp')) return 'image/webp';
  if (lower.endsWith('.gif')) return 'image/gif';
  return 'application/octet-stream';
}

String _defaultDeviceId() {
  return DateTime.now().microsecondsSinceEpoch.toString();
}

class _PreparedLocalImages {
  const _PreparedLocalImages({
    required this.imagesToPersist,
    required this.pushImages,
    required this.pushedRecordsByUid,
    required this.knownBlobSha256,
  });

  final List<PromptImageItem> imagesToPersist;
  final List<PushImage> pushImages;
  final Map<String, PromptImageItem> pushedRecordsByUid;
  final Set<String> knownBlobSha256;
}
