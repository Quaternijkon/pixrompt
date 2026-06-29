import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pixrompt/app/pixrompt_controller.dart';
import 'package:pixrompt/app/pixrompt_sync_controller.dart';
import 'package:pixrompt/data/memory_pixrompt_repository.dart';
import 'package:pixrompt/data/pixrompt_api_client.dart';
import 'package:pixrompt/data/sync_state_repository.dart';
import 'package:pixrompt/domain/sync_models.dart';
import 'package:pixrompt/ui/account_sync_sheet.dart';

void main() {
  testWidgets('account sheet exposes labeled sign-in fields', (tester) async {
    final sync = await _syncController();

    await _pumpAccountSheet(tester, sync);

    final apiBaseUrlField = tester.widget<TextField>(
      find.byKey(const ValueKey('accountSync.apiBaseUrlField')),
    );
    expect(apiBaseUrlField.decoration?.labelText, 'API Base URL');
    expect(apiBaseUrlField.controller?.text, defaultPixromptApiBaseUrl);

    final emailField = tester.widget<TextField>(
      find.byKey(const ValueKey('accountSync.emailField')),
    );
    expect(emailField.decoration?.labelText, 'Email');

    final passwordField = tester.widget<TextField>(
      find.byKey(const ValueKey('accountSync.passwordField')),
    );
    expect(passwordField.decoration?.labelText, 'Password');
    expect(passwordField.obscureText, isTrue);
  });

  testWidgets('login button is disabled while loading', (tester) async {
    final api = _BlockingPixromptApi();
    final sync = await _syncController(api: api);

    await _pumpAccountSheet(tester, sync);
    await tester.enterText(
      find.byKey(const ValueKey('accountSync.emailField')),
      'artist@example.test',
    );
    await tester.enterText(
      find.byKey(const ValueKey('accountSync.passwordField')),
      'not-persisted-test-password',
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('accountSync.loginButton')));
    await tester.pump();

    expect(sync.status.isSyncing, isTrue);
    final loginButton = tester.widget<FilledButton>(
      find.byKey(const ValueKey('accountSync.loginButton')),
    );
    expect(loginButton.onPressed, isNull);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    api.completeLogin('artist@example.test');
    await tester.pump();
  });

  testWidgets('signed-in state shows account, last sync, sync, and logout',
      (tester) async {
    final lastSyncAt = DateTime(2026, 6, 29, 12, 30).millisecondsSinceEpoch;
    final sync = await _syncController(
      initialState: PixromptSyncState(
        accountEmail: 'artist@example.test',
        token: 'test-token-1',
        lastSyncAt: lastSyncAt,
      ),
    );

    await _pumpAccountSheet(tester, sync);

    expect(find.text('artist@example.test'), findsOneWidget);
    expect(find.text('Last sync: 2026-06-29 12:30'), findsOneWidget);
    expect(find.byKey(const ValueKey('accountSync.manualSyncButton')),
        findsOneWidget);
    expect(find.text('Sync Now'), findsOneWidget);
    expect(find.byKey(const ValueKey('accountSync.logoutButton')),
        findsOneWidget);
    expect(find.text('Logout'), findsOneWidget);
  });

  testWidgets('icon-only controls keep tooltips', (tester) async {
    final sync = await _syncController();

    await _pumpAccountSheet(tester, sync);

    expect(find.byTooltip('Show password'), findsOneWidget);
    final iconButtons = tester.widgetList<IconButton>(
      find.descendant(
        of: find.byKey(const ValueKey('accountSync.sheet')),
        matching: find.byType(IconButton),
      ),
    );
    expect(iconButtons, isNotEmpty);
    expect(
      iconButtons.every((button) {
        final tooltip = button.tooltip;
        return tooltip != null && tooltip.trim().isNotEmpty;
      }),
      isTrue,
    );
  });
}

Future<PixromptSyncController> _syncController({
  PixromptSyncState? initialState,
  PixromptApi? api,
}) async {
  final gallery = PixromptController(MemoryPixromptRepository());
  await gallery.initialize();
  final sync = PixromptSyncController(
    pixromptController: gallery,
    syncStateRepository: MemorySyncStateRepository(initialState: initialState),
    api: api ?? _ImmediatePixromptApi(),
  );
  await sync.refreshStatus();
  return sync;
}

Future<void> _pumpAccountSheet(
  WidgetTester tester,
  PixromptSyncController syncController,
) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(useMaterial3: true, brightness: Brightness.dark),
      home: Scaffold(
        body: AccountSyncSheet(syncController: syncController),
      ),
    ),
  );
  await tester.pump();
}

class _ImmediatePixromptApi implements PixromptApi {
  @override
  Future<AuthSession> login(LoginRequest request) async {
    return AuthSession(
      token: 'test-token-1',
      tokenExpiresAt: 123,
      accountEmail: request.email,
      deviceId: request.deviceId,
    );
  }

  @override
  Future<AuthSession> session(String token) async {
    return const AuthSession(
      token: 'test-token-1',
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

class _BlockingPixromptApi extends _ImmediatePixromptApi {
  final _login = Completer<AuthSession>();

  @override
  Future<AuthSession> login(LoginRequest request) {
    return _login.future;
  }

  void completeLogin(String accountEmail) {
    if (_login.isCompleted) return;
    _login.complete(
      AuthSession(
        token: 'test-token-1',
        tokenExpiresAt: 123,
        accountEmail: accountEmail,
        deviceId: 'device-1',
      ),
    );
  }
}
