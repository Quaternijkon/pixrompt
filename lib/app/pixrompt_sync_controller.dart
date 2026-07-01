import 'dart:async';
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
    Duration autoSyncDebounce = const Duration(seconds: 2),
  })  : _pixromptController = pixromptController,
        _syncStateRepository = syncStateRepository,
        _api = api,
        _apiFactory = apiFactory ??
            ((apiBaseUrl) => PixromptApiClient(apiBaseUrl: apiBaseUrl)),
        _now = now ?? DateTime.now,
        _deviceIdFactory = deviceIdFactory ?? _defaultDeviceId,
        _autoSyncDebounce = autoSyncDebounce {
    _pixromptController.addListener(_handlePixromptChanged);
  }

  final PixromptController _pixromptController;
  final SyncStateRepository _syncStateRepository;
  final PixromptApi? _api;
  final PixromptApi Function(String apiBaseUrl) _apiFactory;
  final DateTime Function() _now;
  final String Function() _deviceIdFactory;
  final Duration _autoSyncDebounce;

  SyncStatus _status = const SyncStatus();
  SyncStatus get status => _status;
  Future<void>? _syncInFlight;
  Timer? _autoSyncTimer;
  var _followUpSyncRequested = false;
  var _suppressPixromptAutoSync = false;
  var _sessionSerial = 0;
  var _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    _sessionSerial += 1;
    _followUpSyncRequested = false;
    _autoSyncTimer?.cancel();
    _pixromptController.removeListener(_handlePixromptChanged);
    super.dispose();
  }

  Future<void> refreshStatus() async {
    final state = await _syncStateRepository.read();
    if (_isTokenExpired(state)) {
      await _clearLocalSessionForRelogin(
        state,
        message: '登录已过期，请重新登录。',
      );
      return;
    }
    _setStatus(
      _status.copyWith(
        accountEmail: state.accountEmail,
        lastSyncAt: state.lastSyncAt,
        pendingDeletionCount: state.deletedTombstones.length,
      ),
    );
  }

  void scheduleSync({String reason = 'local-update'}) {
    if (_disposed) return;
    _autoSyncTimer?.cancel();
    _autoSyncTimer = Timer(_autoSyncDebounce, () {
      _autoSyncTimer = null;
      unawaited(_runScheduledSync(reason));
    });
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
    _setStatus(
      SyncStatus(
        isSyncing: true,
        message: '正在登录。',
        lastSyncAt: current.lastSyncAt,
        accountEmail: current.accountEmail,
        pendingDeletionCount: current.deletedTombstones.length,
      ),
    );
    try {
      final api = _apiFor(baseUrl);
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
      _sessionSerial += 1;
      _setStatus(
        SyncStatus(
          message: '已登录。',
          lastSyncAt: state.lastSyncAt,
          accountEmail: state.accountEmail,
          pendingDeletionCount: state.deletedTombstones.length,
        ),
      );
    } catch (error) {
      _setStatus(
        SyncStatus(
          message: '登录失败：${_displayError(error)}',
          lastSyncAt: current.lastSyncAt,
          accountEmail: current.accountEmail,
          pendingDeletionCount: current.deletedTombstones.length,
        ),
      );
      rethrow;
    }
  }

  Future<void> logout() async {
    final state = await _syncStateRepository.read();
    final token = state.token;
    _sessionSerial += 1;
    _followUpSyncRequested = false;
    _autoSyncTimer?.cancel();
    await _syncStateRepository.clearSession();
    _setStatus(
      SyncStatus(
        message: '已退出登录。',
        lastSyncAt: state.lastSyncAt,
        pendingDeletionCount: state.deletedTombstones.length,
      ),
    );
    try {
      if (token != null && token.isNotEmpty) {
        unawaited(
          _apiFor(state.apiBaseUrl).logout(token).catchError((_) {}),
        );
      }
    } catch (_) {
      // Remote logout is best-effort; local state is already cleared.
    }
  }

  Future<void> manualSync() {
    final inFlight = _syncInFlight;
    if (inFlight != null) {
      _followUpSyncRequested = true;
      return inFlight;
    }
    final run = _runCoalescedSync();
    _syncInFlight = run;
    return run.whenComplete(() {
      if (identical(_syncInFlight, run)) {
        _syncInFlight = null;
      }
    });
  }

  Future<void> _runCoalescedSync() async {
    do {
      _followUpSyncRequested = false;
      await _runSingleSync();
    } while (_followUpSyncRequested);
  }

  Future<void> _runSingleSync() async {
    var state = await _syncStateRepository.read();
    final token = state.token;
    if (token == null || token.isEmpty) {
      _setStatus(
        SyncStatus(
          message: '请先登录。',
          lastSyncAt: state.lastSyncAt,
          accountEmail: state.accountEmail,
          pendingDeletionCount: state.deletedTombstones.length,
        ),
      );
      return;
    }
    if (_isTokenExpired(state)) {
      await _clearLocalSessionForRelogin(
        state,
        message: '登录已过期，请重新登录。',
      );
      return;
    }
    if (state.deviceId.isEmpty) {
      state = state.copyWith(deviceId: _deviceIdFactory());
      await _syncStateRepository.write(state);
    }
    final syncSerial = _sessionSerial;

    _setStatus(
      SyncStatus(
        isSyncing: true,
        message: '正在同步。',
        lastSyncAt: state.lastSyncAt,
        accountEmail: state.accountEmail,
        pendingDeletionCount: state.deletedTombstones.length,
        progress: _newProgress('准备同步'),
      ),
    );

    try {
      final api = _apiFor(state.apiBaseUrl);
      final pullCursor = state.cursor;
      _upsertQueueItem(
        const SyncQueueItem(
          id: 'prepare',
          label: '扫描本地图片',
          detail: '准备上传列表',
          kind: syncQueueKindPrepare,
          state: syncQueueStateActive,
        ),
        phase: '扫描本地图片',
      );
      final local = await _prepareLocalImagesForPush(
        api,
        token,
        state,
        syncSerial,
      );
      if (local == null) return;
      _completeQueueItem(
        'prepare',
        detail: '本地图片已扫描',
        phase: '本地扫描完成',
      );
      if (!await _isCurrentSession(token, syncSerial)) return;
      if (local.imagesToPersist.isNotEmpty) {
        await _applySyncUpsertsSilently(local.imagesToPersist);
      }
      if (!await _isCurrentSession(token, syncSerial)) return;

      _upsertQueueItem(
        SyncQueueItem(
          id: 'push',
          label: '提交记录变更',
          detail:
              '${local.pushImages.length} 张图片，${state.deletedTombstones.length} 个删除',
          kind: syncQueueKindPush,
          state: syncQueueStateActive,
        ),
        phase: '提交记录变更',
      );
      if (!await _isCurrentSession(token, syncSerial)) return;
      final pushResponse = await api.push(
        token,
        PushRequest(
          deviceId: state.deviceId,
          baseCursor: state.cursor,
          images: local.pushImages,
          deleted: state.deletedTombstones.values.toList(),
        ),
      );
      if (!await _isCurrentSession(token, syncSerial)) return;
      _completeQueueItem('push', detail: '记录变更已提交', phase: '记录已提交');
      state = await _persistPushResult(
        state,
        pushResponse,
        local.pushedRecordsByUid,
        api,
        token,
        local.blobUploadsBySha,
        syncSerial,
      );
      if (!await _isCurrentSession(token, syncSerial)) return;

      _upsertQueueItem(
        const SyncQueueItem(
          id: 'pull',
          label: '拉取远端变更',
          detail: '检查其他设备的更新',
          kind: syncQueueKindPull,
          state: syncQueueStateActive,
        ),
        phase: '拉取远端变更',
      );
      if (!await _isCurrentSession(token, syncSerial)) return;
      final pullResponse = await api.pull(
        token,
        PullRequest(
          deviceId: state.deviceId,
          cursor: pullCursor,
          knownBlobSha256: local.knownBlobSha256.toList(growable: false),
        ),
      );
      if (!await _isCurrentSession(token, syncSerial)) return;
      _completeQueueItem(
        'pull',
        detail: '远端变更已拉取',
        phase: '远端变更已拉取',
      );
      state = await _applyPullResult(
        api,
        token,
        syncSerial,
        state,
        pullResponse,
      );
      if (!await _isCurrentSession(token, syncSerial)) return;

      _setStatus(
        SyncStatus(
          message: '同步完成。',
          lastSyncAt: state.lastSyncAt,
          accountEmail: state.accountEmail,
          pendingDeletionCount: state.deletedTombstones.length,
          progress: _completeProgress(phase: '同步完成'),
        ),
      );
    } on PixromptUnauthorizedException {
      await _clearLocalSessionForRelogin(
        state,
        message: '登录状态已失效，请重新登录。',
      );
    } catch (error) {
      if (!await _isCurrentSession(token, syncSerial)) return;
      _setStatus(
        SyncStatus(
          message: '同步失败：${_displayError(error)}',
          lastSyncAt: state.lastSyncAt,
          accountEmail: state.accountEmail,
          pendingDeletionCount: state.deletedTombstones.length,
          progress: _completeProgress(phase: '同步失败', failed: true),
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
    _setStatus(_status.copyWith(pendingDeletionCount: tombstones.length));
    scheduleSync(reason: 'local-tombstone');
  }

  Future<void> deleteImage(String imageUid) async {
    if (imageUid.isEmpty) return;
    await _recordLocalTombstones([imageUid]);
    await _pixromptController.deleteImage(imageUid);
  }

  Future<void> deleteImages(Iterable<String> imageUids) async {
    final uids = imageUids.where((uid) => uid.isNotEmpty).toSet();
    if (uids.isEmpty) return;
    await _recordLocalTombstones(uids);
    await _pixromptController.deleteImages(uids);
  }

  Future<void> undoLastDelete() async {
    final pending = _pixromptController.state.pendingUndo;
    if (pending == null) return;
    await _pixromptController.undoLastDelete();

    var state = await _syncStateRepository.read();
    final tombstones = Map<String, SyncTombstone>.from(state.deletedTombstones)
      ..remove(pending.image.uid);
    state = state.copyWith(deletedTombstones: tombstones);
    await _syncStateRepository.write(state);
    _setStatus(_status.copyWith(pendingDeletionCount: tombstones.length));
    scheduleSync(reason: 'undo-delete');

    if (state.knownServerVersions.containsKey(pending.image.uid)) {
      final restored = _pixromptController.state.allImages
          .where((image) => image.uid == pending.image.uid)
          .firstOrNull;
      if (restored != null) {
        await _pixromptController.applySyncUpserts([
          restored.copyWith(
            updatedAt: _now().millisecondsSinceEpoch,
            lastSyncedAt: null,
          ),
        ]);
      }
    }
  }

  Future<void> _recordLocalTombstones(Iterable<String> imageUids) async {
    final requested = imageUids.toSet();
    if (requested.isEmpty) return;
    final existing = (await _pixromptController.readSyncImages())
        .where((image) => requested.contains(image.uid))
        .map((image) => image.uid)
        .toSet();
    if (existing.isEmpty) return;

    final state = await _syncStateRepository.read();
    final now = _now().millisecondsSinceEpoch;
    final tombstones = Map<String, SyncTombstone>.from(state.deletedTombstones);
    var changed = false;
    for (final uid in existing) {
      final baseServerVersion = state.knownServerVersions[uid];
      if (baseServerVersion == null) continue;
      tombstones[uid] = SyncTombstone(
        imageUid: uid,
        baseServerVersion: baseServerVersion,
        deletedAt: now,
      );
      changed = true;
    }
    if (!changed) return;
    await _syncStateRepository.write(
      state.copyWith(deletedTombstones: tombstones),
    );
    _setStatus(_status.copyWith(pendingDeletionCount: tombstones.length));
    scheduleSync(reason: 'delete');
  }

  Future<_PreparedLocalImages?> _prepareLocalImagesForPush(
    PixromptApi api,
    String token,
    PixromptSyncState state,
    int syncSerial,
  ) async {
    final imagesToPersist = <PromptImageItem>[];
    final pushImages = <PushImage>[];
    final pushedRecordsByUid = <String, PromptImageItem>{};
    final knownBlobSha256 = <String>{};
    final blobUploadsBySha = <String, _BlobUpload>{};

    for (final image in await _pixromptController.readSyncImages()) {
      if (!await _isCurrentSession(token, syncSerial)) return null;
      final knownContentSha256 = _knownContentSha256(image);
      if (_isCleanSyncedRecord(image: image, state: state)) {
        knownBlobSha256.add(knownContentSha256!);
        continue;
      }
      final bytes = await _pixromptController.readSyncImageBytes(image.imageKey);
      BlobRef? blob;
      var record = image;
      var needsMaintenance = false;
      if (bytes != null) {
        final contentSha256 = sha256Hex(bytes);
        final existingMimeType = image.mimeType?.trim();
        final hasMimeType =
            existingMimeType != null && existingMimeType.isNotEmpty;
        final mimeType = hasMimeType
            ? existingMimeType!
            : guessMimeType(image.originalFileName ?? image.imageKey);
        knownBlobSha256.add(contentSha256);
        needsMaintenance = _knownContentSha256(image) != contentSha256 ||
            !hasMimeType ||
            image.importedAt == null ||
            image.fileSizeBytes <= 0;
        blob = BlobRef(
          sha256: contentSha256,
          imageKey: image.imageKey,
          sizeBytes: bytes.length,
          mimeType: mimeType,
        );
        blobUploadsBySha[contentSha256] = _BlobUpload(
          bytes: bytes,
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
        if (shouldPush) {
          if (!await _isCurrentSession(token, syncSerial)) return null;
          final blobExists = await api.headBlob(token, contentSha256);
          if (!await _isCurrentSession(token, syncSerial)) return null;
          if (!blobExists) {
            final queueId = 'upload:$contentSha256';
            _upsertQueueItem(
              SyncQueueItem(
                id: queueId,
                label: _imageProgressLabel(record),
                detail: '上传原图',
                kind: syncQueueKindUpload,
                state: syncQueueStateActive,
                bytesTotal: bytes.length,
              ),
              phase: '上传原图',
            );
            if (!await _isCurrentSession(token, syncSerial)) return null;
            await api.putBlob(
              token,
              contentSha256,
              bytes,
              mimeType: mimeType,
            );
            if (!await _isCurrentSession(token, syncSerial)) return null;
            _completeQueueItem(
              queueId,
              detail: '原图已上传',
              bytesDone: bytes.length,
              bytesTotal: bytes.length,
              phase: '原图上传完成',
            );
          }
        }
      } else if (knownContentSha256 != null) {
        knownBlobSha256.add(knownContentSha256);
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
      blobUploadsBySha: blobUploadsBySha,
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
        image.lastSyncedAt == null ||
        needsMaintenance ||
        state.deletedTombstones.containsKey(record.uid);
  }

  bool _isCleanSyncedRecord({
    required PromptImageItem image,
    required PixromptSyncState state,
  }) {
    return state.knownServerVersions.containsKey(image.uid) &&
        image.lastSyncedAt != null &&
        _hasMaintenanceMetadata(image) &&
        !state.deletedTombstones.containsKey(image.uid);
  }

  bool _hasMaintenanceMetadata(PromptImageItem image) {
    return _knownContentSha256(image) != null &&
        (image.mimeType?.trim().isNotEmpty ?? false) &&
        image.importedAt != null &&
        image.fileSizeBytes > 0;
  }

  String? _knownContentSha256(PromptImageItem image) {
    final value = image.contentSha256?.trim();
    if (value == null || value.isEmpty) return null;
    return value;
  }

  Future<PixromptSyncState> _persistPushResult(
    PixromptSyncState state,
    PushResponse response,
    Map<String, PromptImageItem> pushedRecordsByUid,
    PixromptApi api,
    String token,
    Map<String, _BlobUpload> blobUploadsBySha,
    int syncSerial,
  ) async {
    final uploadedMissing = await _uploadMissingBlobs(
      api,
      token,
      response.missingBlobs,
      blobUploadsBySha,
      syncSerial,
    );
    if (!uploadedMissing || !await _isCurrentSession(token, syncSerial)) {
      return _syncStateRepository.read();
    }

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
      knownServerVersions[rejected.imageUid] = rejected.serverVersion;
    }
    final next = state.copyWith(
      knownServerVersions: knownServerVersions,
      deletedTombstones: deletedTombstones,
    );
    if (acceptedRecords.isNotEmpty) {
      if (!await _isCurrentSession(token, syncSerial)) {
        return _syncStateRepository.read();
      }
      await _applySyncUpsertsSilently(acceptedRecords);
      if (!await _isCurrentSession(token, syncSerial)) {
        return _syncStateRepository.read();
      }
    }
    if (!await _isCurrentSession(token, syncSerial)) {
      return _syncStateRepository.read();
    }
    await _syncStateRepository.write(next);
    return next;
  }

  Future<bool> _uploadMissingBlobs(
    PixromptApi api,
    String token,
    List<String> missingBlobs,
    Map<String, _BlobUpload> blobUploadsBySha,
    int syncSerial,
  ) async {
    for (final sha256 in missingBlobs.toSet()) {
      if (!await _isCurrentSession(token, syncSerial)) return false;
      final upload = blobUploadsBySha[sha256];
      if (upload == null) {
        throw PixromptMalformedResponseException(
          'Pixrompt API requested a missing blob that is not available locally.',
        );
      }
      final queueId = 'upload-missing:$sha256';
      _upsertQueueItem(
        SyncQueueItem(
          id: queueId,
          label: sha256.substring(0, 12),
          detail: '补传后端缺失原图',
          kind: syncQueueKindUpload,
          state: syncQueueStateActive,
          bytesTotal: upload.bytes.length,
        ),
        phase: '补传原图',
      );
      if (!await _isCurrentSession(token, syncSerial)) return false;
      await api.putBlob(
        token,
        sha256,
        upload.bytes,
        mimeType: upload.mimeType,
      );
      if (!await _isCurrentSession(token, syncSerial)) return false;
      _completeQueueItem(
        queueId,
        detail: '缺失原图已补传',
        bytesDone: upload.bytes.length,
        bytesTotal: upload.bytes.length,
        phase: '原图补传完成',
      );
    }
    return true;
  }

  Future<PixromptSyncState> _applyPullResult(
    PixromptApi api,
    String token,
    int syncSerial,
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
      if (!await _isCurrentSession(token, syncSerial)) {
        return _syncStateRepository.read();
      }
      if (change.type != 'upsert') continue;
      final knownVersion = knownServerVersions[change.imageUid];
      if (knownVersion != null && change.serverVersion < knownVersion) {
        continue;
      }
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
          if (!await _isCurrentSession(token, syncSerial)) {
            return _syncStateRepository.read();
          }
          final queueId = 'download:${blob.sha256}';
          _upsertQueueItem(
            SyncQueueItem(
              id: queueId,
              label: _imageProgressLabel(image),
              detail: '下载远端原图',
              kind: syncQueueKindDownload,
              state: syncQueueStateActive,
              bytesTotal: blob.sizeBytes,
            ),
            phase: '下载远端原图',
          );
          if (!await _isCurrentSession(token, syncSerial)) {
            return _syncStateRepository.read();
          }
          final downloaded = await api.getBlob(token, blob.sha256);
          if (!await _isCurrentSession(token, syncSerial)) {
            return _syncStateRepository.read();
          }
          if (sha256Hex(downloaded) != blob.sha256) {
            throw PixromptMalformedResponseException(
              'Pixrompt API returned a blob with a mismatched SHA-256.',
            );
          }
          if (!await _isCurrentSession(token, syncSerial)) {
            return _syncStateRepository.read();
          }
          await _pixromptController.writeSyncImageBytes(
            image.imageKey,
            downloaded,
          );
          if (!await _isCurrentSession(token, syncSerial)) {
            return _syncStateRepository.read();
          }
          _completeQueueItem(
            queueId,
            detail: '远端原图已下载',
            bytesDone: downloaded.length,
            bytesTotal: blob.sizeBytes,
            phase: '远端原图下载完成',
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
      if (!await _isCurrentSession(token, syncSerial)) {
        return _syncStateRepository.read();
      }
      await _applySyncUpsertsSilently(upserts);
      if (!await _isCurrentSession(token, syncSerial)) {
        return _syncStateRepository.read();
      }
    }

    if (response.deleted.isNotEmpty) {
      final deletedTombstones =
          Map<String, SyncTombstone>.from(state.deletedTombstones);
      final freshDeleted = <SyncTombstone>[];
      for (final tombstone in response.deleted) {
        final knownVersion = knownServerVersions[tombstone.imageUid];
        final serverVersion = tombstone.serverVersion;
        if (serverVersion != null &&
            knownVersion != null &&
            serverVersion < knownVersion) {
          continue;
        }
        freshDeleted.add(tombstone);
      }
      if (!await _isCurrentSession(token, syncSerial)) {
        return _syncStateRepository.read();
      }
      await _applySyncTombstonesSilently(
        freshDeleted.map((tombstone) => tombstone.imageUid),
      );
      if (!await _isCurrentSession(token, syncSerial)) {
        return _syncStateRepository.read();
      }
      for (final tombstone in freshDeleted) {
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
    if (!await _isCurrentSession(token, syncSerial)) {
      return _syncStateRepository.read();
    }
    await _syncStateRepository.write(next);
    return next;
  }

  void _handlePixromptChanged() {
    if (_suppressPixromptAutoSync || _disposed) return;
    scheduleSync(reason: 'pixrompt-change');
  }

  Future<void> _runScheduledSync(String _) async {
    try {
      if (!await _hasDirtyLocalWork()) return;
      await manualSync();
    } catch (_) {
      // Manual status already carries the failure; background sync stays quiet.
    }
  }

  Future<bool> _hasDirtyLocalWork() async {
    final state = await _syncStateRepository.read();
    final token = state.token;
    if (token == null || token.isEmpty) return false;
    if (_isTokenExpired(state)) {
      await _clearLocalSessionForRelogin(
        state,
        message: '登录已过期，请重新登录。',
      );
      return false;
    }
    if (state.deletedTombstones.isNotEmpty) return true;
    for (final image in await _pixromptController.readSyncImages()) {
      if (!state.knownServerVersions.containsKey(image.uid) ||
          image.lastSyncedAt == null ||
          !_hasMaintenanceMetadata(image)) {
        return true;
      }
    }
    return false;
  }

  bool _isTokenExpired(PixromptSyncState state) {
    final expiresAt = state.tokenExpiresAt;
    if (expiresAt == null) return false;
    return expiresAt <= _nowMs();
  }

  Future<void> _clearLocalSessionForRelogin(
    PixromptSyncState state, {
    required String message,
  }) async {
    _sessionSerial += 1;
    _autoSyncTimer?.cancel();
    await _syncStateRepository.clearSession();
    _setStatus(
      SyncStatus(
        message: message,
        lastSyncAt: state.lastSyncAt,
        pendingDeletionCount: state.deletedTombstones.length,
        progress: _completeProgress(phase: '需要重新登录', failed: true),
      ),
    );
  }

  Future<bool> _isCurrentSession(String token, int serial) async {
    if (_sessionSerial != serial) return false;
    return _hasCurrentToken(token);
  }

  Future<bool> _hasCurrentToken(String token) async {
    final current = await _syncStateRepository.read();
    return current.token == token;
  }

  Future<void> _applySyncUpsertsSilently(
    Iterable<PromptImageItem> upserts,
  ) async {
    final previous = _suppressPixromptAutoSync;
    _suppressPixromptAutoSync = true;
    try {
      await _pixromptController.applySyncUpserts(upserts);
    } finally {
      _suppressPixromptAutoSync = previous;
    }
  }

  Future<void> _applySyncTombstonesSilently(
    Iterable<String> imageUids,
  ) async {
    final previous = _suppressPixromptAutoSync;
    _suppressPixromptAutoSync = true;
    try {
      await _pixromptController.applySyncTombstones(imageUids);
    } finally {
      _suppressPixromptAutoSync = previous;
    }
  }

  String _displayError(Object error) {
    if (error is PixromptUnauthorizedException) {
      return '登录状态已失效，请重新登录。';
    }
    if (error is PixromptNetworkException) {
      return '网络请求失败，请稍后重试。';
    }
    if (error is PixromptHttpException) {
      final statusCode = error.statusCode;
      if (statusCode != null) return '服务器返回 HTTP $statusCode。';
      return '服务器返回错误。';
    }
    if (error is PixromptMalformedResponseException) {
      return 'API 地址或响应格式异常。';
    }
    return '发生未知错误，请稍后重试。';
  }

  PixromptApi _apiFor(String apiBaseUrl) {
    return _api ?? _apiFactory(apiBaseUrl);
  }

  String? _normalizedBaseUrl(String? value) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) return null;
    return trimmed;
  }

  SyncProgress _newProgress(String phase) {
    final now = _nowMs();
    return SyncProgress(
      isActive: true,
      phase: phase,
      startedAt: now,
      updatedAt: now,
    );
  }

  SyncProgress _completeProgress({
    required String phase,
    bool failed = false,
  }) {
    final queue = failed
        ? _status.progress.queue.map((item) {
            if (item.state != syncQueueStateActive) return item;
            return item.copyWith(state: syncQueueStateFailed);
          }).toList(growable: false)
        : _status.progress.queue;
    return _summarizeProgress(
      _status.progress,
      queue,
      phase: phase,
      isActive: false,
    );
  }

  void _upsertQueueItem(SyncQueueItem item, {String? phase}) {
    final queue = _status.progress.queue.toList(growable: true);
    final index = queue.indexWhere((current) => current.id == item.id);
    if (index < 0) {
      queue.add(item);
    } else {
      queue[index] = item;
    }
    _setProgressQueue(queue, phase: phase);
  }

  void _completeQueueItem(
    String id, {
    String? detail,
    int? bytesDone,
    int? bytesTotal,
    String? phase,
  }) {
    final queue = _status.progress.queue.map((item) {
      if (item.id != id) return item;
      return item.copyWith(
        detail: detail ?? item.detail,
        state: syncQueueStateComplete,
        bytesDone: bytesDone ?? item.bytesDone,
        bytesTotal: bytesTotal ?? item.bytesTotal,
      );
    }).toList(growable: false);
    _setProgressQueue(queue, phase: phase);
  }

  void _setProgressQueue(List<SyncQueueItem> queue, {String? phase}) {
    _setStatus(
      _status.copyWith(
        progress: _summarizeProgress(
          _status.progress,
          queue,
          phase: phase,
          isActive: true,
        ),
      ),
    );
  }

  SyncProgress _summarizeProgress(
    SyncProgress progress,
    List<SyncQueueItem> queue, {
    String? phase,
    bool? isActive,
  }) {
    final completedItems =
        queue.where((item) => item.state == syncQueueStateComplete).length;
    var bytesDone = 0;
    var bytesTotal = 0;
    for (final item in queue) {
      if (item.bytesTotal > 0) {
        bytesTotal += item.bytesTotal;
        bytesDone += item.state == syncQueueStateComplete
            ? item.bytesTotal
            : item.bytesDone.clamp(0, item.bytesTotal).toInt();
      } else {
        bytesDone += item.bytesDone;
      }
    }
    return progress.copyWith(
      isActive: isActive ?? progress.isActive,
      phase: phase ?? progress.phase,
      updatedAt: _nowMs(),
      completedItems: completedItems,
      totalItems: queue.length,
      bytesDone: bytesDone,
      bytesTotal: bytesTotal,
      queue: queue,
    );
  }

  int _nowMs() {
    return _now().millisecondsSinceEpoch;
  }

  void _setStatus(SyncStatus status) {
    if (_disposed) return;
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

String _imageProgressLabel(PromptImageItem image) {
  final name = image.originalFileName?.trim();
  if (name != null && name.isNotEmpty) return name;
  final prompt = image.prompt.trim();
  if (prompt.isNotEmpty) return prompt;
  return image.uid;
}

class _PreparedLocalImages {
  const _PreparedLocalImages({
    required this.imagesToPersist,
    required this.pushImages,
    required this.pushedRecordsByUid,
    required this.knownBlobSha256,
    required this.blobUploadsBySha,
  });

  final List<PromptImageItem> imagesToPersist;
  final List<PushImage> pushImages;
  final Map<String, PromptImageItem> pushedRecordsByUid;
  final Set<String> knownBlobSha256;
  final Map<String, _BlobUpload> blobUploadsBySha;
}

class _BlobUpload {
  const _BlobUpload({
    required this.bytes,
    required this.mimeType,
  });

  final Uint8List bytes;
  final String mimeType;
}
