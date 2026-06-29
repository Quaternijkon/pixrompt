import 'package:flutter_test/flutter_test.dart';
import 'package:pixrompt/domain/sync_models.dart';

void main() {
  test('parses and serializes auth session payloads', () {
    final session = AuthSession.fromJson({
      'token': 'token-1',
      'tokenExpiresAt': 1234,
      'accountEmail': 'user@example.com',
      'deviceId': 'device-1',
    });

    expect(session.token, 'token-1');
    expect(session.tokenExpiresAt, 1234);
    expect(session.accountEmail, 'user@example.com');
    expect(session.toJson(), {
      'token': 'token-1',
      'tokenExpiresAt': 1234,
      'accountEmail': 'user@example.com',
      'deviceId': 'device-1',
    });
  });

  test('parses and serializes pull responses with upserts and tombstones', () {
    final response = PullResponse.fromJson({
      'cursor': 12,
      'serverTime': 1700000000000,
      'changes': [
        {
          'type': 'upsert',
          'imageUid': 'image-1',
          'serverVersion': 3,
          'updatedAt': 1700000000000,
          'record': {'uid': 'image-1', 'prompt': 'Remote'},
          'blob': {
            'sha256': _repeat('b', 64),
            'imageKey': 'bytes-1',
            'sizeBytes': 3,
            'mimeType': 'image/png',
          },
        }
      ],
      'deleted': [
        {
          'imageUid': 'image-2',
          'serverVersion': 4,
          'deletedAt': 1700000000100,
        }
      ],
      'missingBlobs': [_repeat('c', 64)],
    });

    expect(response.cursor, 12);
    expect(response.changes.single.imageUid, 'image-1');
    expect(response.changes.single.blob?.mimeType, 'image/png');
    expect(response.deleted.single.imageUid, 'image-2');
    expect(response.toJson()['missingBlobs'], [_repeat('c', 64)]);
  });

  test('parses and serializes push requests and accepted or rejected results',
      () {
    final request = PushRequest(
      deviceId: 'device-1',
      baseCursor: 10,
      images: [
        PushImage(
          imageUid: 'image-1',
          baseServerVersion: 2,
          updatedAt: 99,
          record: const {'uid': 'image-1', 'prompt': 'Local'},
          blob: BlobRef(
            sha256: _repeat('d', 64),
            imageKey: 'bytes-1',
            sizeBytes: 4,
            mimeType: 'image/jpeg',
          ),
        ),
      ],
      deleted: const [
        SyncTombstone(
          imageUid: 'image-2',
          baseServerVersion: 1,
          deletedAt: 100,
        ),
      ],
    );

    expect(PushRequest.fromJson(request.toJson()).images.single.imageUid,
        'image-1');

    final response = PushResponse.fromJson({
      'cursor': 13,
      'serverTime': 101,
      'accepted': [
        {'imageUid': 'image-1', 'serverVersion': 3}
      ],
      'rejected': [
        {'imageUid': 'image-2', 'serverVersion': 2, 'reason': 'stale'}
      ],
      'missingBlobs': [_repeat('d', 64)],
    });

    expect(response.accepted.single.serverVersion, 3);
    expect(response.rejected.single.reason, 'stale');
    expect(response.toJson()['cursor'], 13);
  });

  test('serializes sync status messages', () {
    final status = SyncStatus.fromJson({
      'isSyncing': true,
      'message': 'Syncing',
      'lastSyncAt': 123,
      'accountEmail': 'user@example.com',
    });

    expect(status.isSyncing, isTrue);
    expect(status.toJson(), {
      'isSyncing': true,
      'message': 'Syncing',
      'lastSyncAt': 123,
      'accountEmail': 'user@example.com',
    });
  });
}

String _repeat(String value, int count) {
  return List.filled(count, value).join();
}
