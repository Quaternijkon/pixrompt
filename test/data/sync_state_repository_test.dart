import 'package:flutter_test/flutter_test.dart';
import 'package:pixrompt/data/sync_state_repository.dart';
import 'package:pixrompt/domain/sync_models.dart';

void main() {
  test('memory sync state persists token, cursor, versions, and tombstones',
      () async {
    final repository = MemorySyncStateRepository(
      initialState: const PixromptSyncState(deviceId: 'device-1'),
    );

    await repository.write(
      const PixromptSyncState(
        apiBaseUrl: 'https://pixrompt.quaternijkon.online/v1',
        accountEmail: 'user@example.com',
        token: 'token-1',
        tokenExpiresAt: 123,
        deviceId: 'device-1',
        cursor: 44,
        knownServerVersions: {'image-1': 3},
        deletedTombstones: {
          'image-2': SyncTombstone(
            imageUid: 'image-2',
            baseServerVersion: 2,
            deletedAt: 99,
          ),
        },
        lastSyncAt: 100,
      ),
    );

    final state = await repository.read();

    expect(state.token, 'token-1');
    expect(state.cursor, 44);
    expect(state.knownServerVersions['image-1'], 3);
    expect(state.deletedTombstones['image-2']?.deletedAt, 99);
    expect(state.lastSyncAt, 100);
  });

  test('clearSession removes account credentials without changing device state',
      () async {
    final repository = MemorySyncStateRepository(
      initialState: const PixromptSyncState(
        accountEmail: 'user@example.com',
        token: 'token-1',
        tokenExpiresAt: 123,
        deviceId: 'device-1',
        cursor: 9,
      ),
    );

    await repository.clearSession();
    final state = await repository.read();

    expect(state.accountEmail, isNull);
    expect(state.token, isNull);
    expect(state.tokenExpiresAt, isNull);
    expect(state.deviceId, 'device-1');
    expect(state.cursor, 9);
  });
}
