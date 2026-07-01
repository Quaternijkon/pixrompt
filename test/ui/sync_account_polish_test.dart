import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pixrompt/app/pixrompt_controller.dart';
import 'package:pixrompt/app/pixrompt_sync_controller.dart';
import 'package:pixrompt/data/memory_pixrompt_repository.dart';
import 'package:pixrompt/data/pixrompt_api_client.dart';
import 'package:pixrompt/data/sync_state_repository.dart';
import 'package:pixrompt/domain/prompt_image.dart';
import 'package:pixrompt/domain/sync_models.dart';
import 'package:pixrompt/platform/pixrompt_file_actions.dart';
import 'package:pixrompt/ui/settings_sheet.dart';
import 'package:pixrompt/ui/sync_center_page.dart';

void main() {
  testWidgets('settings uses Chinese account and sync copy', (tester) async {
    final controller = PixromptController(MemoryPixromptRepository());
    await controller.initialize();
    final sync = PixromptSyncController(
      pixromptController: controller,
      syncStateRepository: MemorySyncStateRepository(),
      api: _NoopApi(),
    );
    addTearDown(sync.dispose);
    await sync.refreshStatus();

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(useMaterial3: true, brightness: Brightness.dark),
        home: Scaffold(
          body: SettingsSheet(
            controller: controller,
            syncController: sync,
            fileActions: const PixromptFileActions(),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('账号'), findsOneWidget);
    expect(find.text('账号与同步'), findsOneWidget);
    expect(find.text('同步中心'), findsOneWidget);
  });

  testWidgets('sync center exposes progress semantics and pending deletions',
      (tester) async {
    final controller = PixromptController(
      MemoryPixromptRepository(
        initialImages: [
          PromptImageItem.sample(
            uid: 'pending',
            imageKey: 'missing-pending',
            prompt: 'Pending image',
          ),
        ],
      ),
    );
    await controller.initialize();
    final sync = PixromptSyncController(
      pixromptController: controller,
      syncStateRepository: MemorySyncStateRepository(
        initialState: const PixromptSyncState(
          accountEmail: 'artist@example.test',
          token: 'token-1',
          deviceId: 'device-1',
          deletedTombstones: {
            'deleted': SyncTombstone(
              imageUid: 'deleted',
              baseServerVersion: 3,
              deletedAt: 200,
            ),
          },
        ),
      ),
      api: _NoopApi(),
    );
    addTearDown(sync.dispose);
    await sync.refreshStatus();

    final semantics = SemanticsTester(tester);
    addTearDown(semantics.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(useMaterial3: true, brightness: Brightness.dark),
        home: SyncCenterPage(controller: controller, syncController: sync),
      ),
    );
    await tester.pump();

    expect(find.text('待删除'), findsOneWidget);
    expect(find.text('1'), findsWidgets);
    expect(
      semantics,
      includesNodeWith(
        label: '同步进度',
        value: '空闲，0/0，0 B / 0 B',
      ),
    );
  });

  testWidgets('sync center summary wraps metrics at 320px width',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 640));
    addTearDown(() async => tester.binding.setSurfaceSize(null));
    final images = [
      for (var index = 0; index < 45; index++)
        PromptImageItem.sample(
          uid: 'synced-$index',
          imageKey: 'missing-synced-$index',
          prompt: 'Synced $index',
          updatedAt: index,
          lastSyncedAt: DateTime(2026, 6, 30).millisecondsSinceEpoch + index,
        ),
      for (var index = 0; index < 83; index++)
        PromptImageItem.sample(
          uid: 'pending-$index',
          imageKey: 'missing-pending-$index',
          prompt: 'Pending $index',
          updatedAt: 100 + index,
        ),
    ];
    final controller = PixromptController(
      MemoryPixromptRepository(initialImages: images),
    );
    await controller.initialize();
    final sync = PixromptSyncController(
      pixromptController: controller,
      syncStateRepository: MemorySyncStateRepository(
        initialState: PixromptSyncState(
          accountEmail: 'artist@example.test',
          token: 'token-1',
          deviceId: 'device-1',
          deletedTombstones: {
            for (var index = 0; index < 17; index++)
              'deleted-$index': SyncTombstone(
                imageUid: 'deleted-$index',
                baseServerVersion: index,
                deletedAt: 200 + index,
              ),
          },
        ),
      ),
      api: _NoopApi(),
    );
    addTearDown(sync.dispose);
    await sync.refreshStatus();

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(useMaterial3: true, brightness: Brightness.dark),
        home: SyncCenterPage(controller: controller, syncController: sync),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('128'), findsWidgets);
    expect(find.text('45'), findsWidgets);
    expect(find.text('83'), findsWidgets);
    expect(find.text('17'), findsWidgets);

    final totalTopLeft = tester.getTopLeft(
      find.byKey(const ValueKey('syncCenter.metric.total')),
    );
    final syncedTopLeft = tester.getTopLeft(
      find.byKey(const ValueKey('syncCenter.metric.synced')),
    );
    final pendingTopLeft = tester.getTopLeft(
      find.byKey(const ValueKey('syncCenter.metric.pending')),
    );
    final deletionsTopLeft = tester.getTopLeft(
      find.byKey(const ValueKey('syncCenter.metric.pendingDeletions')),
    );
    expect(syncedTopLeft.dy, totalTopLeft.dy);
    expect(pendingTopLeft.dy, greaterThan(totalTopLeft.dy));
    expect(pendingTopLeft.dx, totalTopLeft.dx);
    expect(deletionsTopLeft.dy, pendingTopLeft.dy);
    expect(deletionsTopLeft.dx, syncedTopLeft.dx);
  });
}

class _NoopApi implements PixromptApi {
  @override
  Future<AuthSession> login(LoginRequest request) async {
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
      accountEmail: 'artist@example.test',
      deviceId: 'device-1',
    );
  }

  @override
  Future<void> logout(String token) async {}

  @override
  Future<PushResponse> push(String token, PushRequest request) async {
    return const PushResponse(cursor: 0, serverTime: 0);
  }

  @override
  Future<PullResponse> pull(String token, PullRequest request) async {
    return const PullResponse(cursor: 0, serverTime: 0);
  }

  @override
  Future<bool> headBlob(String token, String sha256) async => true;

  @override
  Future<void> putBlob(
    String token,
    String sha256,
    Uint8List bytes, {
    String? mimeType,
  }) async {}

  @override
  Future<Uint8List> getBlob(String token, String sha256) async {
    return Uint8List(0);
  }
}
