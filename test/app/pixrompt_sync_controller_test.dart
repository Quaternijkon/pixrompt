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
      updatedAt: 10,
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
              sha256: 'remote-sha',
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
      ..blobDownloads['remote-sha'] = Uint8List.fromList([9, 9]);
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
  });
}

class _FakePixromptApi implements PixromptApi {
  final loginPasswords = <String>[];
  final logoutTokens = <String>[];
  final pushedRequests = <PushRequest>[];
  final uploadedBlobSha256 = <String>[];
  final blobDownloads = <String, Uint8List>{};
  PullResponse pullResponse = const PullResponse(cursor: 0, serverTime: 0);

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
      accepted: request.images
          .map(
            (image) => AcceptedChange(
              imageUid: image.imageUid,
              serverVersion: image.imageUid == 'local' ? 3 : 2,
            ),
          )
          .toList(),
    );
  }

  @override
  Future<PullResponse> pull(String token, PullRequest request) async {
    return pullResponse;
  }

  @override
  Future<bool> headBlob(String token, String sha256) async => false;

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
