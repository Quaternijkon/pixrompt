import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pixrompt/app/pixrompt_controller.dart';
import 'package:pixrompt/app/pixrompt_sync_controller.dart';
import 'package:pixrompt/data/memory_pixrompt_repository.dart';
import 'package:pixrompt/data/pixrompt_api_client.dart';
import 'package:pixrompt/data/sync_state_repository.dart';
import 'package:pixrompt/domain/prompt_image.dart';
import 'package:pixrompt/domain/sync_models.dart';

void main() {
  test('login and logout persist session state without storing passwords',
      () async {
    final gallery = PixromptController(MemoryPixromptRepository());
    await gallery.initialize();
    final stateRepository = MemorySyncStateRepository(
      initialState: const PixromptSyncState(deviceId: 'device-1'),
    );
    final api = _FakePixromptApi();
    final sync = PixromptSyncController(
      pixromptController: gallery,
      syncStateRepository: stateRepository,
      api: api,
    );

    await sync.login(email: 'user@example.com', password: 'secret');

    var state = await stateRepository.read();
    expect(api.loginPasswords, ['secret']);
    expect(state.accountEmail, 'user@example.com');
    expect(state.token, 'token-1');
    expect(state.toJson().containsValue('secret'), isFalse);

    await sync.logout();

    state = await stateRepository.read();
    expect(api.logoutTokens, ['token-1']);
    expect(state.accountEmail, isNull);
    expect(state.token, isNull);
  });

  test('manual sync pushes local records and applies remote upserts and deletes',
      () async {
    final local = PromptImageItem.sample(
      uid: 'local',
      imageKey: 'bytes-local',
      prompt: 'Local prompt',
      updatedAt: 1000,
    );
    final gone = PromptImageItem.sample(
      uid: 'gone',
      imageKey: 'bytes-gone',
      prompt: 'Delete me',
      updatedAt: 11,
    );
    final gallery = PixromptController(
      MemoryPixromptRepository(
        initialImages: [gone, local],
        initialImageBytes: {
          'bytes-local': Uint8List.fromList([1, 2, 3]),
          'bytes-gone': Uint8List.fromList([4]),
        },
      ),
    );
    await gallery.initialize();
    final stateRepository = MemorySyncStateRepository(
      initialState: const PixromptSyncState(
        accountEmail: 'user@example.com',
        token: 'token-1',
        deviceId: 'device-1',
        cursor: 4,
      ),
    );
    final api = _FakePixromptApi()
      ..pullResponse = PullResponse(
        cursor: 8,
        serverTime: 200,
        changes: [
          PullChange(
            type: 'upsert',
            imageUid: 'remote',
            serverVersion: 5,
            updatedAt: 199,
            record: PromptImageItem.sample(
              uid: 'remote',
              imageKey: 'bytes-remote',
              prompt: 'Remote prompt',
              updatedAt: 199,
            ).toJson(),
            blob: BlobRef(
              sha256: sha256Hex(Uint8List.fromList([9, 9])),
              imageKey: 'bytes-remote',
              sizeBytes: 2,
              mimeType: 'image/png',
            ),
          ),
        ],
        deleted: const [
          SyncTombstone(
            imageUid: 'gone',
            serverVersion: 6,
            deletedAt: 201,
          ),
        ],
      )
      ..blobDownloads[sha256Hex(Uint8List.fromList([9, 9]))] =
          Uint8List.fromList([9, 9]);
    final sync = PixromptSyncController(
      pixromptController: gallery,
      syncStateRepository: stateRepository,
      api: api,
    );

    await sync.manualSync();

    final pushedImageUids =
        api.pushedRequests.single.images.map((image) => image.imageUid);
    final pushedLocal = api.pushedRequests.single.images
        .firstWhere((image) => image.imageUid == 'local');
    expect(pushedImageUids, containsAll(['gone', 'local']));
    expect(pushedLocal.blob?.sha256, hasLength(64));
    expect(api.uploadedBlobSha256, contains(pushedLocal.blob?.sha256));
    expect(api.pulledRequests.single.cursor, 4);
    expect(
      gallery.state.allImages.map((image) => image.uid),
      isNot(contains('gone')),
    );
    expect(gallery.state.allImages.map((image) => image.uid), contains('remote'));
    expect(await gallery.readSyncImageBytes('bytes-remote'), [9, 9]);

    final state = await stateRepository.read();
    expect(state.cursor, 8);
    expect(state.knownServerVersions['remote'], 5);
    expect(state.knownServerVersions['gone'], 6);
    expect(state.lastSyncAt, 200);

    api.pullResponse = const PullResponse(
      cursor: 9,
      serverTime: 250,
      changes: [],
      deleted: [],
      missingBlobs: [],
    );

    await sync.manualSync();

    expect(api.pushedRequests.last.images, isEmpty);
    expect(api.pulledRequests.last.cursor, 8);
    expect(gallery.state.allImages.every((image) {
      return image.lastSyncedAt != null;
    }), isTrue);
  });

  test('manual sync pushes locally edited records after prior sync', () async {
    final synced = PromptImageItem.sample(
      uid: 'local',
      imageKey: 'bytes-local',
      prompt: 'Synced prompt',
      updatedAt: 100,
      lastSyncedAt: 150,
    );
    final gallery = PixromptController(
      MemoryPixromptRepository(
        initialImages: [synced],
        initialImageBytes: {
          'bytes-local': Uint8List.fromList([1, 2, 3]),
        },
      ),
    );
    await gallery.initialize();
    final stateRepository = MemorySyncStateRepository(
      initialState: const PixromptSyncState(
        accountEmail: 'user@example.com',
        token: 'token-1',
        deviceId: 'device-1',
        cursor: 4,
        knownServerVersions: {'local': 3},
      ),
    );
    final api = _FakePixromptApi()
      ..pullResponse = const PullResponse(
        cursor: 5,
        serverTime: 200,
        changes: [],
        deleted: [],
        missingBlobs: [],
      );
    final sync = PixromptSyncController(
      pixromptController: gallery,
      syncStateRepository: stateRepository,
      api: api,
    );

    await gallery.updateImage('local', prompt: 'Edited prompt');
    await sync.manualSync();

    expect(api.pushedRequests.single.images, hasLength(1));
    final pushed = api.pushedRequests.single.images.single;
    expect(pushed.imageUid, 'local');
    expect(pushed.baseServerVersion, 3);
    expect(pushed.record['prompt'], 'Edited prompt');
    expect(gallery.state.allImages.single.lastSyncedAt, 150);
  });

  test('delete helpers record and undo local sync tombstones', () async {
    final synced = PromptImageItem.sample(
      uid: 'synced',
      imageKey: 'bytes-synced',
      prompt: 'Synced prompt',
      lastSyncedAt: 150,
    );
    final localOnly = PromptImageItem.sample(
      uid: 'local-only',
      imageKey: 'bytes-local-only',
      prompt: 'Local prompt',
    );
    final gallery = PixromptController(
      MemoryPixromptRepository(
        initialImages: [synced, localOnly],
        initialImageBytes: {
          'bytes-synced': Uint8List.fromList([1]),
          'bytes-local-only': Uint8List.fromList([2]),
        },
      ),
    );
    await gallery.initialize();
    final stateRepository = MemorySyncStateRepository(
      initialState: const PixromptSyncState(
        accountEmail: 'user@example.com',
        token: 'token-1',
        deviceId: 'device-1',
        knownServerVersions: {'synced': 7},
      ),
    );
    final sync = PixromptSyncController(
      pixromptController: gallery,
      syncStateRepository: stateRepository,
      api: _FakePixromptApi(),
      now: () => DateTime.fromMillisecondsSinceEpoch(300),
    );

    await sync.deleteImage('synced');

    var state = await stateRepository.read();
    expect(gallery.state.allImages.map((image) => image.uid), ['local-only']);
    expect(state.deletedTombstones.keys, ['synced']);
    expect(state.deletedTombstones['synced']?.baseServerVersion, 7);
    expect(state.deletedTombstones['synced']?.deletedAt, 300);

    await sync.undoLastDelete();

    state = await stateRepository.read();
    expect(state.deletedTombstones, isEmpty);
    expect(gallery.state.allImages.map((image) => image.uid),
        containsAll(['synced', 'local-only']));

    await sync.deleteImages(['local-only']);

    state = await stateRepository.read();
    expect(state.deletedTombstones, isEmpty);
    expect(gallery.state.allImages.map((image) => image.uid), ['synced']);
  });

  test('manual sync uploads server-reported missing blobs before marking clean',
      () async {
    final local = PromptImageItem.sample(
      uid: 'local',
      imageKey: 'bytes-local',
      prompt: 'Local prompt',
      updatedAt: 100,
    );
    final bytes = Uint8List.fromList([1, 2, 3]);
    final sha = sha256Hex(bytes);
    final gallery = PixromptController(
      MemoryPixromptRepository(
        initialImages: [local],
        initialImageBytes: {'bytes-local': bytes},
      ),
    );
    await gallery.initialize();
    final stateRepository = MemorySyncStateRepository(
      initialState: const PixromptSyncState(
        accountEmail: 'user@example.com',
        token: 'token-1',
        deviceId: 'device-1',
      ),
    );
    final api = _FakePixromptApi()
      ..existingBlobSha256.add(sha)
      ..missingBlobSha256 = [sha];
    final sync = PixromptSyncController(
      pixromptController: gallery,
      syncStateRepository: stateRepository,
      api: api,
    );

    await sync.manualSync();

    expect(api.uploadedBlobSha256, [sha]);
    expect(gallery.state.allImages.single.lastSyncedAt, 150);
  });

  test('manual sync reports queue progress and transfer speed', () async {
    final local = PromptImageItem.sample(
      uid: 'local',
      imageKey: 'bytes-local',
      prompt: 'Local prompt',
      updatedAt: 100,
    );
    final remoteBytes = Uint8List.fromList([9, 9, 9, 9]);
    final remoteSha = sha256Hex(remoteBytes);
    final gallery = PixromptController(
      MemoryPixromptRepository(
        initialImages: [local],
        initialImageBytes: {
          'bytes-local': Uint8List.fromList([1, 2, 3, 4, 5, 6]),
        },
      ),
    );
    await gallery.initialize();
    final stateRepository = MemorySyncStateRepository(
      initialState: const PixromptSyncState(
        accountEmail: 'user@example.com',
        token: 'token-1',
        deviceId: 'device-1',
      ),
    );
    var nowMs = 0;
    final api = _FakePixromptApi()
      ..pullResponse = PullResponse(
        cursor: 3,
        serverTime: 7000,
        changes: [
          PullChange(
            type: 'upsert',
            imageUid: 'remote',
            serverVersion: 4,
            updatedAt: 199,
            record: PromptImageItem.sample(
              uid: 'remote',
              imageKey: 'bytes-remote',
              prompt: 'Remote prompt',
            ).toJson(),
            blob: BlobRef(
              sha256: remoteSha,
              imageKey: 'bytes-remote',
              sizeBytes: remoteBytes.length,
              mimeType: 'image/png',
            ),
          ),
        ],
      )
      ..blobDownloads[remoteSha] = remoteBytes;
    final sync = PixromptSyncController(
      pixromptController: gallery,
      syncStateRepository: stateRepository,
      api: api,
      now: () {
        nowMs += 1000;
        return DateTime.fromMillisecondsSinceEpoch(nowMs);
      },
    );
    final snapshots = <SyncProgress>[];
    sync.addListener(() {
      final progress = sync.status.progress;
      if (progress.queue.isNotEmpty) {
        snapshots.add(progress);
      }
    });

    await sync.manualSync();

    expect(
      snapshots.expand((snapshot) => snapshot.queue).map((item) => item.kind),
      containsAll([
        syncQueueKindUpload,
        syncQueueKindPush,
        syncQueueKindPull,
        syncQueueKindDownload,
      ]),
    );
    expect(
      snapshots.any((snapshot) => snapshot.bytesPerSecond > 0),
      isTrue,
    );
    expect(sync.status.progress.isActive, isFalse);
    expect(sync.status.progress.fraction, 1);
  });

  test('manual sync rejects downloaded blobs with mismatched sha256', () async {
    final expectedSha = sha256Hex(Uint8List.fromList([9, 9]));
    final gallery = PixromptController(MemoryPixromptRepository());
    await gallery.initialize();
    final stateRepository = MemorySyncStateRepository(
      initialState: const PixromptSyncState(
        accountEmail: 'user@example.com',
        token: 'token-1',
        deviceId: 'device-1',
      ),
    );
    final api = _FakePixromptApi()
      ..pullResponse = PullResponse(
        cursor: 1,
        serverTime: 200,
        changes: [
          PullChange(
            type: 'upsert',
            imageUid: 'remote',
            serverVersion: 1,
            updatedAt: 199,
            record: PromptImageItem.sample(
              uid: 'remote',
              imageKey: 'bytes-remote',
              prompt: 'Remote prompt',
            ).toJson(),
            blob: BlobRef(
              sha256: expectedSha,
              imageKey: 'bytes-remote',
              sizeBytes: 2,
              mimeType: 'image/png',
            ),
          ),
        ],
      )
      ..blobDownloads[expectedSha] = Uint8List.fromList([1, 2]);
    final sync = PixromptSyncController(
      pixromptController: gallery,
      syncStateRepository: stateRepository,
      api: api,
    );

    await expectLater(
      sync.manualSync(),
      throwsA(isA<PixromptMalformedResponseException>()),
    );
    expect(gallery.state.allImages, isEmpty);
    expect(await gallery.readSyncImageBytes('bytes-remote'), isNull);
    expect((await stateRepository.read()).cursor, 0);
  });

  test('manual sync ignores stale pulled versions', () async {
    final current = PromptImageItem.sample(
      uid: 'local',
      imageKey: 'bytes-local',
      prompt: 'Current prompt',
      updatedAt: 200,
      lastSyncedAt: 150,
    );
    final gallery = PixromptController(
      MemoryPixromptRepository(initialImages: [current]),
    );
    await gallery.initialize();
    final stateRepository = MemorySyncStateRepository(
      initialState: const PixromptSyncState(
        accountEmail: 'user@example.com',
        token: 'token-1',
        deviceId: 'device-1',
        knownServerVersions: {'local': 5},
      ),
    );
    final api = _FakePixromptApi()
      ..pullResponse = PullResponse(
        cursor: 6,
        serverTime: 250,
        changes: [
          PullChange(
            type: 'upsert',
            imageUid: 'local',
            serverVersion: 4,
            updatedAt: 100,
            record: current.copyWith(prompt: 'Stale prompt').toJson(),
          ),
        ],
        deleted: const [
          SyncTombstone(
            imageUid: 'local',
            serverVersion: 4,
            deletedAt: 260,
          ),
        ],
      );
    final sync = PixromptSyncController(
      pixromptController: gallery,
      syncStateRepository: stateRepository,
      api: api,
    );

    await sync.manualSync();

    expect(gallery.state.allImages.single.prompt, 'Current prompt');
    expect((await stateRepository.read()).knownServerVersions['local'], 5);
  });

  test('manual sync coalesces concurrent requests into one follow-up run',
      () async {
    final local = PromptImageItem.sample(
      uid: 'local',
      imageKey: 'bytes-local',
      prompt: 'Local prompt',
      updatedAt: 100,
    );
    final gallery = PixromptController(
      MemoryPixromptRepository(
        initialImages: [local],
        initialImageBytes: {'bytes-local': Uint8List.fromList([1, 2, 3])},
      ),
    );
    await gallery.initialize();
    final stateRepository = MemorySyncStateRepository(
      initialState: const PixromptSyncState(
        accountEmail: 'user@example.com',
        token: 'token-1',
        deviceId: 'device-1',
      ),
    );
    final api = _FakePixromptApi()
      ..pushGate = Completer<void>()
      ..pullResponse = const PullResponse(
        cursor: 2,
        serverTime: 200,
        changes: [],
        deleted: [],
        missingBlobs: [],
      );
    final sync = PixromptSyncController(
      pixromptController: gallery,
      syncStateRepository: stateRepository,
      api: api,
    );

    final first = sync.manualSync();
    await api.firstPushStarted.future;
    final second = sync.manualSync();
    await Future<void>.delayed(const Duration(milliseconds: 10));

    expect(api.pushedRequests, hasLength(1));
    expect(api.maxConcurrentPushes, 1);

    api.pushGate?.complete();
    await Future.wait([first, second]);

    expect(api.pushedRequests, hasLength(2));
    expect(api.maxConcurrentPushes, 1);
  });

  test('auto sync is scheduled after an authenticated dirty local mutation',
      () async {
    final bytes = Uint8List.fromList([1, 2, 3]);
    final sha = sha256Hex(bytes);
    final synced = PromptImageItem.sample(
      uid: 'local',
      imageKey: 'bytes-local',
      prompt: 'Before',
      updatedAt: 100,
      fileSizeBytes: bytes.length,
      contentSha256: sha,
      mimeType: 'image/png',
      importedAt: 90,
      lastSyncedAt: 150,
    );
    final gallery = PixromptController(
      MemoryPixromptRepository(
        initialImages: [synced],
        initialImageBytes: {'bytes-local': bytes},
      ),
    );
    await gallery.initialize();
    final stateRepository = MemorySyncStateRepository(
      initialState: const PixromptSyncState(
        accountEmail: 'user@example.com',
        token: 'token-1',
        deviceId: 'device-1',
        knownServerVersions: {'local': 3},
      ),
    );
    final api = _FakePixromptApi()
      ..pullResponse = const PullResponse(
        cursor: 4,
        serverTime: 220,
        changes: [],
        deleted: [],
        missingBlobs: [],
      );
    final sync = PixromptSyncController(
      pixromptController: gallery,
      syncStateRepository: stateRepository,
      api: api,
      autoSyncDebounce: Duration.zero,
    );

    await gallery.updateImage('local', prompt: 'After');
    await _waitFor(
      () => api.pushedRequests.isNotEmpty && !sync.status.isSyncing,
    );

    final pushed = api.pushedRequests.single.images.single;
    expect(pushed.imageUid, 'local');
    expect(pushed.record['prompt'], 'After');
  });

  test('manual sync does not read bytes for clean records with sync metadata',
      () async {
    final bytes = Uint8List.fromList([1, 2, 3]);
    final sha = sha256Hex(bytes);
    final synced = PromptImageItem.sample(
      uid: 'clean',
      imageKey: 'bytes-clean',
      prompt: 'Already synced',
      updatedAt: 100,
      fileSizeBytes: bytes.length,
      contentSha256: sha,
      mimeType: 'image/png',
      importedAt: 80,
      lastSyncedAt: 150,
    );
    final repository = _CountingMemoryPixromptRepository(
      initialImages: [synced],
      initialImageBytes: {'bytes-clean': bytes},
    );
    final gallery = PixromptController(repository);
    await gallery.initialize();
    final stateRepository = MemorySyncStateRepository(
      initialState: const PixromptSyncState(
        accountEmail: 'user@example.com',
        token: 'token-1',
        deviceId: 'device-1',
        knownServerVersions: {'clean': 9},
      ),
    );
    final sync = PixromptSyncController(
      pixromptController: gallery,
      syncStateRepository: stateRepository,
      api: _FakePixromptApi(),
    );

    await sync.manualSync();

    expect(repository.readImageBytesCount, 0);
  });

  test('expired local token clears the session and asks for re-login',
      () async {
    final gallery = PixromptController(MemoryPixromptRepository());
    await gallery.initialize();
    final stateRepository = MemorySyncStateRepository(
      initialState: const PixromptSyncState(
        accountEmail: 'user@example.com',
        token: 'expired-token',
        tokenExpiresAt: 999,
        deviceId: 'device-1',
      ),
    );
    final api = _FakePixromptApi();
    final sync = PixromptSyncController(
      pixromptController: gallery,
      syncStateRepository: stateRepository,
      api: api,
      now: () => DateTime.fromMillisecondsSinceEpoch(1000),
    );

    await sync.manualSync();

    final state = await stateRepository.read();
    expect(state.token, isNull);
    expect(state.accountEmail, isNull);
    expect(api.pushedRequests, isEmpty);
    expect(sync.status.accountEmail, isNull);
    expect(sync.status.message, contains('重新登录'));
  });

  test('unauthorized sync response clears session and hides raw body',
      () async {
    final local = PromptImageItem.sample(
      uid: 'local',
      imageKey: 'bytes-local',
      prompt: 'Local prompt',
      updatedAt: 100,
    );
    final gallery = PixromptController(
      MemoryPixromptRepository(
        initialImages: [local],
        initialImageBytes: {'bytes-local': Uint8List.fromList([1])},
      ),
    );
    await gallery.initialize();
    final stateRepository = MemorySyncStateRepository(
      initialState: const PixromptSyncState(
        accountEmail: 'user@example.com',
        token: 'bad-token',
        deviceId: 'device-1',
      ),
    );
    final api = _FakePixromptApi()
      ..pushError = const PixromptUnauthorizedException(
        'Pixrompt API rejected the current session.',
        statusCode: 401,
        body: '{"token":"secret"}',
      );
    final sync = PixromptSyncController(
      pixromptController: gallery,
      syncStateRepository: stateRepository,
      api: api,
    );

    await sync.manualSync();

    final state = await stateRepository.read();
    expect(state.token, isNull);
    expect(state.accountEmail, isNull);
    expect(sync.status.message, contains('重新登录'));
    expect(sync.status.message, isNot(contains('secret')));
  });

  test('failed sync status does not expose raw HTTP response bodies', () async {
    final local = PromptImageItem.sample(
      uid: 'local',
      imageKey: 'bytes-local',
      prompt: 'Local prompt',
      updatedAt: 100,
    );
    final gallery = PixromptController(
      MemoryPixromptRepository(
        initialImages: [local],
        initialImageBytes: {'bytes-local': Uint8List.fromList([1])},
      ),
    );
    await gallery.initialize();
    final stateRepository = MemorySyncStateRepository(
      initialState: const PixromptSyncState(
        accountEmail: 'user@example.com',
        token: 'token-1',
        deviceId: 'device-1',
      ),
    );
    final api = _FakePixromptApi()
      ..pushError = const PixromptHttpException(
        'Pixrompt API returned HTTP 500.',
        statusCode: 500,
        body: '{"debug":"raw-secret-body"}',
      );
    final sync = PixromptSyncController(
      pixromptController: gallery,
      syncStateRepository: stateRepository,
      api: api,
    );

    await expectLater(
      sync.manualSync(),
      throwsA(isA<PixromptHttpException>()),
    );

    expect(sync.status.message, contains('HTTP 500'));
    expect(sync.status.message, isNot(contains('raw-secret-body')));
  });

  test('failed sync status sanitizes unknown errors', () async {
    final local = PromptImageItem.sample(
      uid: 'local',
      imageKey: 'bytes-local',
      prompt: 'Local prompt',
      updatedAt: 100,
    );
    final gallery = PixromptController(
      MemoryPixromptRepository(
        initialImages: [local],
        initialImageBytes: {'bytes-local': Uint8List.fromList([1])},
      ),
    );
    await gallery.initialize();
    final stateRepository = MemorySyncStateRepository(
      initialState: const PixromptSyncState(
        accountEmail: 'user@example.com',
        token: 'token-1',
        deviceId: 'device-1',
      ),
    );
    final api = _FakePixromptApi()
      ..pushError = Exception('raw-secret-token');
    final sync = PixromptSyncController(
      pixromptController: gallery,
      syncStateRepository: stateRepository,
      api: api,
    );

    await expectLater(
      sync.manualSync(),
      throwsA(isA<Exception>()),
    );

    expect(sync.status.message, '同步失败：发生未知错误，请稍后重试。');
    expect(sync.status.message, isNot(contains('raw-secret-token')));
    expect(sync.status.message, isNot(contains('Exception')));
  });

  test('logout during upload prevents later sync network phases', () async {
    final firstBytes = Uint8List.fromList([1]);
    final secondBytes = Uint8List.fromList([2]);
    final firstSha = sha256Hex(firstBytes);
    final first = PromptImageItem.sample(
      uid: 'first',
      imageKey: 'bytes-first',
      prompt: 'First prompt',
      updatedAt: 100,
    );
    final second = PromptImageItem.sample(
      uid: 'second',
      imageKey: 'bytes-second',
      prompt: 'Second prompt',
      updatedAt: 101,
    );
    final gallery = PixromptController(
      MemoryPixromptRepository(
        initialImages: [first, second],
        initialImageBytes: {
          'bytes-first': firstBytes,
          'bytes-second': secondBytes,
        },
      ),
    );
    await gallery.initialize();
    final stateRepository = MemorySyncStateRepository(
      initialState: const PixromptSyncState(
        accountEmail: 'user@example.com',
        token: 'token-1',
        deviceId: 'device-1',
      ),
    );
    final api = _FakePixromptApi()..uploadGate = Completer<void>();
    final sync = PixromptSyncController(
      pixromptController: gallery,
      syncStateRepository: stateRepository,
      api: api,
    );

    final run = sync.manualSync();
    await api.firstUploadStarted.future;
    await sync.logout();
    api.uploadGate?.complete();
    await run;

    expect(api.headBlobSha256, [firstSha]);
    expect(api.uploadedBlobSha256, [firstSha]);
    expect(api.pushedRequests, isEmpty);
    expect(api.pulledRequests, isEmpty);
    expect((await stateRepository.read()).token, isNull);
    expect(
      gallery.state.allImages.every((image) => image.lastSyncedAt == null),
      isTrue,
    );
  });

  test('logout during push prevents pull and local clean marking', () async {
    final local = PromptImageItem.sample(
      uid: 'local',
      imageKey: 'bytes-local',
      prompt: 'Local prompt',
      updatedAt: 100,
    );
    final bytes = Uint8List.fromList([1]);
    final gallery = PixromptController(
      MemoryPixromptRepository(
        initialImages: [local],
        initialImageBytes: {'bytes-local': bytes},
      ),
    );
    await gallery.initialize();
    final stateRepository = MemorySyncStateRepository(
      initialState: const PixromptSyncState(
        accountEmail: 'user@example.com',
        token: 'token-1',
        deviceId: 'device-1',
      ),
    );
    final api = _FakePixromptApi()
      ..existingBlobSha256.add(sha256Hex(bytes))
      ..pushGate = Completer<void>();
    final sync = PixromptSyncController(
      pixromptController: gallery,
      syncStateRepository: stateRepository,
      api: api,
    );

    final run = sync.manualSync();
    await api.firstPushStarted.future;
    await sync.logout();
    api.pushGate?.complete();
    await run;

    expect(api.pushedRequests, hasLength(1));
    expect(api.pulledRequests, isEmpty);
    expect(gallery.state.allImages.single.lastSyncedAt, isNull);
    expect((await stateRepository.read()).knownServerVersions, isEmpty);
    expect((await stateRepository.read()).token, isNull);
  });

  test('dispose invalidates in-flight sync and prevents later notifications',
      () async {
    final local = PromptImageItem.sample(
      uid: 'local',
      imageKey: 'bytes-local',
      prompt: 'Local prompt',
      updatedAt: 100,
    );
    final bytes = Uint8List.fromList([1]);
    final gallery = PixromptController(
      MemoryPixromptRepository(
        initialImages: [local],
        initialImageBytes: {'bytes-local': bytes},
      ),
    );
    await gallery.initialize();
    final stateRepository = MemorySyncStateRepository(
      initialState: const PixromptSyncState(
        accountEmail: 'user@example.com',
        token: 'token-1',
        deviceId: 'device-1',
      ),
    );
    final api = _FakePixromptApi()
      ..existingBlobSha256.add(sha256Hex(bytes))
      ..pushGate = Completer<void>();
    final sync = PixromptSyncController(
      pixromptController: gallery,
      syncStateRepository: stateRepository,
      api: api,
    );
    var notifications = 0;
    sync.addListener(() {
      notifications += 1;
    });

    final run = sync.manualSync();
    await api.firstPushStarted.future;
    final notificationsBeforeDispose = notifications;
    sync.dispose();
    api.pushGate?.complete();
    await run;

    expect(api.pushedRequests, hasLength(1));
    expect(api.pulledRequests, isEmpty);
    expect(notifications, notificationsBeforeDispose);
    expect(gallery.state.allImages.single.lastSyncedAt, isNull);
  });

  test('logout during download prevents local remote application', () async {
    final firstBytes = Uint8List.fromList([9, 1]);
    final secondBytes = Uint8List.fromList([9, 2]);
    final firstSha = sha256Hex(firstBytes);
    final secondSha = sha256Hex(secondBytes);
    final gallery = PixromptController(MemoryPixromptRepository());
    await gallery.initialize();
    final stateRepository = MemorySyncStateRepository(
      initialState: const PixromptSyncState(
        accountEmail: 'user@example.com',
        token: 'token-1',
        deviceId: 'device-1',
      ),
    );
    final api = _FakePixromptApi()
      ..downloadGate = Completer<void>()
      ..pullResponse = PullResponse(
        cursor: 2,
        serverTime: 300,
        changes: [
          PullChange(
            type: 'upsert',
            imageUid: 'remote-first',
            serverVersion: 1,
            updatedAt: 200,
            record: PromptImageItem.sample(
              uid: 'remote-first',
              imageKey: 'bytes-remote-first',
              prompt: 'Remote first',
              updatedAt: 200,
            ).toJson(),
            blob: BlobRef(
              sha256: firstSha,
              imageKey: 'bytes-remote-first',
              sizeBytes: firstBytes.length,
              mimeType: 'image/png',
            ),
          ),
          PullChange(
            type: 'upsert',
            imageUid: 'remote-second',
            serverVersion: 1,
            updatedAt: 201,
            record: PromptImageItem.sample(
              uid: 'remote-second',
              imageKey: 'bytes-remote-second',
              prompt: 'Remote second',
              updatedAt: 201,
            ).toJson(),
            blob: BlobRef(
              sha256: secondSha,
              imageKey: 'bytes-remote-second',
              sizeBytes: secondBytes.length,
              mimeType: 'image/png',
            ),
          ),
        ],
      )
      ..blobDownloads[firstSha] = firstBytes
      ..blobDownloads[secondSha] = secondBytes;
    final sync = PixromptSyncController(
      pixromptController: gallery,
      syncStateRepository: stateRepository,
      api: api,
    );

    final run = sync.manualSync();
    await api.firstDownloadStarted.future;
    await sync.logout();
    api.downloadGate?.complete();
    await run;

    expect(api.downloadedBlobSha256, [firstSha]);
    expect(gallery.state.allImages, isEmpty);
    expect(await gallery.readSyncImageBytes('bytes-remote-first'), isNull);
    expect(await gallery.readSyncImageBytes('bytes-remote-second'), isNull);
    expect((await stateRepository.read()).token, isNull);
  });

  test('scheduled auto sync catches dirty-check failures quietly', () async {
    final errors = <Object>[];
    await runZonedGuarded(() async {
      final gallery = PixromptController(MemoryPixromptRepository());
      await gallery.initialize();
      final sync = PixromptSyncController(
        pixromptController: gallery,
        syncStateRepository: _ThrowingReadSyncStateRepository(),
        api: _FakePixromptApi(),
        autoSyncDebounce: Duration.zero,
      );

      sync.scheduleSync();
      await Future<void>.delayed(const Duration(milliseconds: 10));
      sync.dispose();
    }, (error, _) {
      errors.add(error);
    });

    expect(errors, isEmpty);
  });

  test('logout clears local session without waiting for remote logout',
      () async {
    final gallery = PixromptController(MemoryPixromptRepository());
    await gallery.initialize();
    final stateRepository = MemorySyncStateRepository(
      initialState: const PixromptSyncState(
        accountEmail: 'user@example.com',
        token: 'token-1',
        deviceId: 'device-1',
      ),
    );
    final api = _FakePixromptApi()..logoutGate = Completer<void>();
    final sync = PixromptSyncController(
      pixromptController: gallery,
      syncStateRepository: stateRepository,
      api: api,
    );

    await sync.logout().timeout(const Duration(milliseconds: 50));

    final state = await stateRepository.read();
    expect(api.logoutTokens, ['token-1']);
    expect(state.token, isNull);
    expect(state.accountEmail, isNull);
    expect(sync.status.isSyncing, isFalse);
    expect(sync.status.message, '已退出登录。');
  });
}

class _FakePixromptApi implements PixromptApi {
  final loginPasswords = <String>[];
  final logoutTokens = <String>[];
  final pushedRequests = <PushRequest>[];
  final pulledRequests = <PullRequest>[];
  final headBlobSha256 = <String>[];
  final uploadedBlobSha256 = <String>[];
  final downloadedBlobSha256 = <String>[];
  final existingBlobSha256 = <String>{};
  final blobDownloads = <String, Uint8List>{};
  final firstPushStarted = Completer<void>();
  final firstUploadStarted = Completer<void>();
  final firstDownloadStarted = Completer<void>();
  Completer<void>? pushGate;
  Completer<void>? uploadGate;
  Completer<void>? downloadGate;
  Completer<void>? logoutGate;
  Object? pushError;
  PullResponse pullResponse = const PullResponse(cursor: 0, serverTime: 0);
  List<String> missingBlobSha256 = const [];
  var activePushes = 0;
  var maxConcurrentPushes = 0;

  @override
  Future<AuthSession> login(LoginRequest request) async {
    loginPasswords.add(request.password);
    return AuthSession(
      token: 'token-1',
      tokenExpiresAt: 123,
      accountEmail: request.email,
      deviceId: request.deviceId,
    );
  }

  @override
  Future<AuthSession> session(String token) async {
    return const AuthSession(
      token: 'token-1',
      tokenExpiresAt: 123,
      accountEmail: 'user@example.com',
      deviceId: 'device-1',
    );
  }

  @override
  Future<void> logout(String token) async {
    logoutTokens.add(token);
    final gate = logoutGate;
    if (gate != null) {
      await gate.future;
    }
  }

  @override
  Future<PushResponse> push(String token, PushRequest request) async {
    activePushes += 1;
    if (activePushes > maxConcurrentPushes) {
      maxConcurrentPushes = activePushes;
    }
    if (!firstPushStarted.isCompleted) {
      firstPushStarted.complete();
    }
    try {
      pushedRequests.add(request);
      final error = pushError;
      if (error != null) throw error;
      final gate = pushGate;
      if (gate != null) {
        await gate.future;
      }
      return PushResponse(
        cursor: 6,
        serverTime: 150,
        accepted: [
          ...request.images.map(
            (image) => AcceptedChange(
              imageUid: image.imageUid,
              serverVersion: image.imageUid == 'local' ? 3 : 2,
            ),
          ),
          ...request.deleted.map(
            (tombstone) => AcceptedChange(
              imageUid: tombstone.imageUid,
              serverVersion: tombstone.imageUid == 'local' ? 3 : 2,
            ),
          ),
        ],
        missingBlobs: missingBlobSha256,
      );
    } finally {
      activePushes -= 1;
    }
  }

  @override
  Future<PullResponse> pull(String token, PullRequest request) async {
    pulledRequests.add(request);
    return pullResponse;
  }

  @override
  Future<bool> headBlob(String token, String sha256) async {
    headBlobSha256.add(sha256);
    return existingBlobSha256.contains(sha256);
  }

  @override
  Future<void> putBlob(
    String token,
    String sha256,
    Uint8List bytes, {
    String? mimeType,
  }) async {
    if (!firstUploadStarted.isCompleted) {
      firstUploadStarted.complete();
    }
    final gate = uploadGate;
    if (gate != null) {
      await gate.future;
    }
    uploadedBlobSha256.add(sha256);
  }

  @override
  Future<Uint8List> getBlob(String token, String sha256) async {
    if (!firstDownloadStarted.isCompleted) {
      firstDownloadStarted.complete();
    }
    final gate = downloadGate;
    if (gate != null) {
      await gate.future;
    }
    downloadedBlobSha256.add(sha256);
    return blobDownloads[sha256]!;
  }
}

class _ThrowingReadSyncStateRepository implements SyncStateRepository {
  @override
  Future<PixromptSyncState> read() async {
    throw StateError('dirty-check failed');
  }

  @override
  Future<void> write(PixromptSyncState state) async {}

  @override
  Future<void> clearSession() async {}
}

class _CountingMemoryPixromptRepository extends MemoryPixromptRepository {
  _CountingMemoryPixromptRepository({
    super.initialImages,
    super.initialSettings,
    super.initialImageBytes,
  });

  int readImageBytesCount = 0;

  @override
  Future<Uint8List?> readImageBytes(String imageKey) async {
    readImageBytesCount += 1;
    return super.readImageBytes(imageKey);
  }
}

Future<void> _waitFor(
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 1),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      throw TimeoutException('Timed out waiting for test condition.');
    }
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}
