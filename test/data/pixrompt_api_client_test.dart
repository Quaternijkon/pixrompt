import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pixrompt/data/pixrompt_api_client.dart';
import 'package:pixrompt/domain/sync_models.dart';

void main() {
  test('joins v1 base URL and endpoint paths without duplicate v1 segments',
      () async {
    final requestedUrls = <String>[];
    final api = PixromptApiClient(
      apiBaseUrl: 'https://pixrompt.quaternijkon.online/v1/',
      httpClient: MockClient((request) async {
        requestedUrls.add(request.url.toString());
        return http.Response(
          jsonEncode({
            'token': 'token-1',
            'tokenType': 'bearer',
            'expiresAt': 123,
            'email': 'user@example.com',
          }),
          200,
        );
      }),
    );

    final session = await api.login(
      const LoginRequest(
        email: 'user@example.com',
        password: 'secret',
        deviceId: 'device-1',
      ),
    );

    expect(requestedUrls.single,
        'https://pixrompt.quaternijkon.online/v1/auth/login');
    expect(session.token, 'token-1');
    expect(session.tokenExpiresAt, 123);
    expect(session.accountEmail, 'user@example.com');
    expect(session.deviceId, 'device-1');
  });

  test('throws a typed unauthorized exception for 401 responses', () async {
    final api = PixromptApiClient(
      apiBaseUrl: 'https://pixrompt.quaternijkon.online/v1',
      httpClient: MockClient((request) async {
        return http.Response('{"detail":"invalid token"}', 401);
      }),
    );

    expect(
      () => api.session('bad-token'),
      throwsA(isA<PixromptUnauthorizedException>()),
    );
  });

  test('throws a typed malformed exception for invalid response bodies',
      () async {
    final api = PixromptApiClient(
      apiBaseUrl: 'https://pixrompt.quaternijkon.online/v1',
      httpClient: MockClient((request) async {
        return http.Response('not-json', 200);
      }),
    );

    expect(
      () => api.pull(
        'token-1',
        const PullRequest(deviceId: 'device-1', cursor: 0),
      ),
      throwsA(isA<PixromptMalformedResponseException>()),
    );
  });

  test('throws malformed for successful sync responses missing required fields',
      () async {
    final responses = [
      <String, dynamic>{},
      <String, dynamic>{},
    ];
    final api = PixromptApiClient(
      apiBaseUrl: 'https://pixrompt.quaternijkon.online/v1',
      httpClient: MockClient((request) async {
        return http.Response(jsonEncode(responses.removeAt(0)), 200);
      }),
    );

    expect(
      () => api.push(
        'token-1',
        const PushRequest(deviceId: 'device-1', baseCursor: 0),
      ),
      throwsA(isA<PixromptMalformedResponseException>()),
    );
    expect(
      () => api.pull(
        'token-1',
        const PullRequest(deviceId: 'device-1', cursor: 0),
      ),
      throwsA(isA<PixromptMalformedResponseException>()),
    );
  });

  test('throws malformed for successful sync responses with malformed items',
      () async {
    final responses = [
      {
        'cursor': 1,
        'serverTime': 2,
        'accepted': [
          {'imageUid': 'image-1'}
        ],
        'rejected': [],
        'missingBlobs': [],
      },
      {
        'cursor': 1,
        'serverTime': 2,
        'changes': [
          {
            'type': 'upsert',
            'imageUid': 'image-1',
            'serverVersion': 1,
            'updatedAt': 2,
          }
        ],
        'deleted': [],
        'missingBlobs': [],
      },
      {
        'cursor': 1,
        'serverTime': 2,
        'changes': [],
        'deleted': [
          {'imageUid': 'image-1', 'deletedAt': 2}
        ],
        'missingBlobs': [],
      },
    ];
    final api = PixromptApiClient(
      apiBaseUrl: 'https://pixrompt.quaternijkon.online/v1',
      httpClient: MockClient((request) async {
        return http.Response(jsonEncode(responses.removeAt(0)), 200);
      }),
    );

    expect(
      () => api.push(
        'token-1',
        const PushRequest(deviceId: 'device-1', baseCursor: 0),
      ),
      throwsA(isA<PixromptMalformedResponseException>()),
    );
    expect(
      () => api.pull(
        'token-1',
        const PullRequest(deviceId: 'device-1', cursor: 0),
      ),
      throwsA(isA<PixromptMalformedResponseException>()),
    );
    expect(
      () => api.pull(
        'token-1',
        const PullRequest(deviceId: 'device-1', cursor: 0),
      ),
      throwsA(isA<PixromptMalformedResponseException>()),
    );
  });

  test('throws malformed for successful login responses missing auth fields',
      () async {
    final responses = [
      <String, dynamic>{},
      {
        'token': 123,
        'tokenExpiresAt': 'not-a-timestamp',
        'accountEmail': '',
      },
    ];
    final api = PixromptApiClient(
      apiBaseUrl: 'https://pixrompt.quaternijkon.online/v1',
      httpClient: MockClient((request) async {
        return http.Response(jsonEncode(responses.removeAt(0)), 200);
      }),
    );

    expect(
      () => api.login(
        const LoginRequest(
          email: 'user@example.com',
          password: 'secret',
          deviceId: 'device-1',
        ),
      ),
      throwsA(isA<PixromptMalformedResponseException>()),
    );
    expect(
      () => api.login(
        const LoginRequest(
          email: 'user@example.com',
          password: 'secret',
          deviceId: 'device-1',
        ),
      ),
      throwsA(isA<PixromptMalformedResponseException>()),
    );
  });

  test('session injects token but rejects other malformed auth fields',
      () async {
    final responses = [
      {
        'expiresAt': 123,
        'email': 'user@example.com',
        'deviceId': 'device-1',
      },
      {
        'expiresAt': 123,
        'email': 'user@example.com',
      },
    ];
    final api = PixromptApiClient(
      apiBaseUrl: 'https://pixrompt.quaternijkon.online/v1',
      httpClient: MockClient((request) async {
        return http.Response(jsonEncode(responses.removeAt(0)), 200);
      }),
    );

    final session = await api.session('existing-token');
    expect(session.token, 'existing-token');
    expect(session.tokenExpiresAt, 123);
    expect(session.accountEmail, 'user@example.com');
    expect(session.deviceId, 'device-1');

    expect(
      () => api.session('existing-token'),
      throwsA(isA<PixromptMalformedResponseException>()),
    );
  });

  test('maps request timeouts to network exceptions', () async {
    final pending = Completer<http.Response>();
    final api = PixromptApiClient(
      apiBaseUrl: 'https://pixrompt.quaternijkon.online/v1',
      requestTimeout: const Duration(milliseconds: 1),
      httpClient: MockClient((request) => pending.future),
    );

    await expectLater(
      api.session('token-1'),
      throwsA(isA<PixromptNetworkException>()),
    );
  });

  test('exception text does not include raw response bodies', () async {
    final api = PixromptApiClient(
      apiBaseUrl: 'https://pixrompt.quaternijkon.online/v1',
      httpClient: MockClient((request) async {
        return http.Response('{"debug":"raw-secret-body"}', 500);
      }),
    );

    try {
      await api.session('token-1');
      fail('Expected PixromptHttpException.');
    } catch (error) {
      expect(error, isA<PixromptHttpException>());
      expect(error.toString(), contains('HTTP 500'));
      expect(error.toString(), isNot(contains('raw-secret-body')));
    }
  });
}
