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
            'tokenExpiresAt': 123,
            'accountEmail': 'user@example.com',
            'deviceId': 'device-1',
          }),
          200,
        );
      }),
    );

    await api.login(
      const LoginRequest(
        email: 'user@example.com',
        password: 'secret',
        deviceId: 'device-1',
      ),
    );

    expect(requestedUrls.single,
        'https://pixrompt.quaternijkon.online/v1/auth/login');
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
}
