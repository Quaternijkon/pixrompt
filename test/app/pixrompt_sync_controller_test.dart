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
}

class _FakePixromptApi implements PixromptApi {
  final loginPasswords = <String>[];
  final logoutTokens = <String>[];
  final pushedRequests = <PushRequest>[];
  final pulledRequests = <PullRequest>[];
  final uploadedBlobSha256 = <String>[];
  final existingBlobSha256 = <String>{};
  final blobDownloads = <String, Uint8List>{};
  PullResponse pullResponse = const PullResponse(cursor: 0, serverTime: 0);
  List<String> missingBlobSha256 = const [];

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
  }

  @override
  Future<PushResponse> push(String token, PushRequest request) async {
    pushedRequests.add(request);
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
  }

  @override
  Future<PullResponse> pull(String token, PullRequest request) async {
    pulledRequests.add(request);
    return pullResponse;
  }

  @override
  Future<bool> headBlob(String token, String sha256) async {
    return existingBlobSha256.contains(sha256);
  }

  @override
  Future<void> putBlob(
    String token,
    String sha256,
    Uint8List bytes, {
    String? mimeType,
  }) async {
    uploadedBlobSha256.add(sha256);
  }

  @override
  Future<Uint8List> getBlob(String token, String sha256) async {
    return blobDownloads[sha256]!;
  }
}
