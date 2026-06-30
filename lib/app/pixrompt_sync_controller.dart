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
    _setStatus(
      SyncStatus(
        isSyncing: true,
        message: '正在登录。',
        lastSyncAt: current.lastSyncAt,
        accountEmail: current.accountEmail,
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
    _setStatus(
      SyncStatus(
        isSyncing: true,
        message: '正在退出登录。',
        lastSyncAt: state.lastSyncAt,
        accountEmail: state.accountEmail,
      ),
    );
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
      final local = await _prepareLocalImagesForPush(api, token, state);
      _completeQueueItem(
        'prepare',
        detail: '本地图片已扫描',
        phase: '本地扫描完成',
      );
      if (local.imagesToPersist.isNotEmpty) {
        await _pixromptController.applySyncUpserts(local.imagesToPersist);
      }

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
      final pushResponse = await api.push(
        token,
        PushRequest(
          deviceId: state.deviceId,
          baseCursor: state.cursor,
          images: local.pushImages,
          deleted: state.deletedTombstones.values.toList(),
        ),
      );
      _completeQueueItem('push', detail: '记录变更已提交', phase: '记录已提交');
      state = await _persistPushResult(
        state,
        pushResponse,
        local.pushedRecordsByUid,
        api,
        token,
        local.blobUploadsBySha,
      );

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
      final pullResponse = await api.pull(
        token,
        PullRequest(
          deviceId: state.deviceId,
          cursor: pullCursor,
          knownBlobSha256: local.knownBlobSha256.toList(growable: false),
        ),
      );
      _completeQueueItem(
        'pull',
        detail: '远端变更已拉取',
        phase: '远端变更已拉取',
      );
      state = await _applyPullResult(api, token, state, pullResponse);

      _setStatus(
        SyncStatus(
          message: '同步完成。',
          lastSyncAt: state.lastSyncAt,
          accountEmail: state.accountEmail,
          progress: _completeProgress(phase: '同步完成'),
        ),
      );
    } catch (error) {
      _setStatus(
        SyncStatus(
          message: '同步失败：$error',
          lastSyncAt: state.lastSyncAt,
          accountEmail: state.accountEmail,
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
    final blobUploadsBySha = <String, _BlobUpload>{};

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
        if (shouldPush && !await api.headBlob(token, contentSha256)) {
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
          await api.putBlob(
            token,
            contentSha256,
            bytes,
            mimeType: mimeType,
          );
          _completeQueueItem(
            queueId,
            detail: '原图已上传',
            bytesDone: bytes.length,
            bytesTotal: bytes.length,
            phase: '原图上传完成',
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

  Future<PixromptSyncState> _persistPushResult(
    PixromptSyncState state,
    PushResponse response,
    Map<String, PromptImageItem> pushedRecordsByUid,
    PixromptApi api,
    String token,
    Map<String, _BlobUpload> blobUploadsBySha,
  ) async {
    await _uploadMissingBlobs(
      api,
      token,
      response.missingBlobs,
      blobUploadsBySha,
    );

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
      await _pixromptController.applySyncUpserts(acceptedRecords);
    }
    await _syncStateRepository.write(next);
    return next;
  }

  Future<void> _uploadMissingBlobs(
    PixromptApi api,
    String token,
    List<String> missingBlobs,
    Map<String, _BlobUpload> blobUploadsBySha,
  ) async {
    for (final sha256 in missingBlobs.toSet()) {
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
      await api.putBlob(
        token,
        sha256,
        upload.bytes,
        mimeType: upload.mimeType,
      );
      _completeQueueItem(
        queueId,
        detail: '缺失原图已补传',
        bytesDone: upload.bytes.length,
        bytesTotal: upload.bytes.length,
        phase: '原图补传完成',
      );
    }
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
          final downloaded = await api.getBlob(token, blob.sha256);
          if (sha256Hex(downloaded) != blob.sha256) {
            throw PixromptMalformedResponseException(
              'Pixrompt API returned a blob with a mismatched SHA-256.',
            );
          }
          await _pixromptController.writeSyncImageBytes(
            image.imageKey,
            downloaded,
          );
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
      await _pixromptController.applySyncUpserts(upserts);
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
      await _pixromptController.applySyncTombstones(
        freshDeleted.map((tombstone) => tombstone.imageUid),
      );
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
