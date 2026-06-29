import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../domain/sync_models.dart';

abstract class PixromptApi {
  Future<AuthSession> login(LoginRequest request);
  Future<AuthSession> session(String token);
  Future<void> logout(String token);
  Future<PushResponse> push(String token, PushRequest request);
  Future<PullResponse> pull(String token, PullRequest request);
  Future<bool> headBlob(String token, String sha256);
  Future<void> putBlob(
    String token,
    String sha256,
    Uint8List bytes, {
    String? mimeType,
  });
  Future<Uint8List> getBlob(String token, String sha256);
}

class PixromptApiClient implements PixromptApi {
  PixromptApiClient({
    required String apiBaseUrl,
    http.Client? httpClient,
  })  : apiBaseUrl = _normalizeBaseUrl(apiBaseUrl),
        _httpClient = httpClient ?? http.Client();

  final Uri apiBaseUrl;
  final http.Client _httpClient;

  @override
  Future<AuthSession> login(LoginRequest request) async {
    final response = await _send(
      () => _httpClient.post(
        _uri('/auth/login'),
        headers: _jsonHeaders(),
        body: jsonEncode(request.toJson()),
      ),
    );
    _ensureOk(response);
    final json = _decodeObject(response);
    json['deviceId'] ??= request.deviceId;
    return _parseMap(json, AuthSession.fromJson);
  }

  @override
  Future<AuthSession> session(String token) async {
    final response = await _send(
      () => _httpClient.get(
        _uri('/auth/session'),
        headers: _jsonHeaders(token: token),
      ),
    );
    _ensureOk(response);
    final json = _decodeObject(response);
    json['token'] ??= token;
    return _parseMap(json, AuthSession.fromJson);
  }

  @override
  Future<void> logout(String token) async {
    final response = await _send(
      () => _httpClient.post(
        _uri('/auth/logout'),
        headers: _jsonHeaders(token: token),
      ),
    );
    _ensureOk(response, allowNoContent: true);
  }

  @override
  Future<PushResponse> push(String token, PushRequest request) async {
    final response = await _send(
      () => _httpClient.post(
        _uri('/sync/push'),
        headers: _jsonHeaders(token: token),
        body: jsonEncode(request.toJson()),
      ),
    );
    _ensureOk(response);
    return _parseObject(response, PushResponse.fromJson);
  }

  @override
  Future<PullResponse> pull(String token, PullRequest request) async {
    final response = await _send(
      () => _httpClient.post(
        _uri('/sync/pull'),
        headers: _jsonHeaders(token: token),
        body: jsonEncode(request.toJson()),
      ),
    );
    _ensureOk(response);
    return _parseObject(response, PullResponse.fromJson);
  }

  @override
  Future<bool> headBlob(String token, String sha256) async {
    final response = await _send(
      () => _httpClient.head(
        _uri('/blobs/$sha256'),
        headers: _jsonHeaders(token: token),
      ),
    );
    if (response.statusCode == 404) return false;
    _ensureOk(response, allowNoContent: true);
    return true;
  }

  @override
  Future<void> putBlob(
    String token,
    String sha256,
    Uint8List bytes, {
    String? mimeType,
  }) async {
    final response = await _send(
      () => _httpClient.put(
        _uri('/blobs/$sha256'),
        headers: _binaryHeaders(token: token, mimeType: mimeType),
        body: bytes,
      ),
    );
    _ensureOk(response, allowNoContent: true);
  }

  @override
  Future<Uint8List> getBlob(String token, String sha256) async {
    final response = await _send(
      () => _httpClient.get(
        _uri('/blobs/$sha256'),
        headers: _jsonHeaders(token: token),
      ),
    );
    _ensureOk(response);
    return response.bodyBytes;
  }

  void close() {
    _httpClient.close();
  }

  Uri _uri(String path) {
    final rawSegments = path
        .split('/')
        .where((segment) => segment.trim().isNotEmpty)
        .toList();
    final endpointSegments =
        rawSegments.isNotEmpty && rawSegments.first == 'v1'
            ? rawSegments.skip(1)
            : rawSegments;
    final baseSegments =
        apiBaseUrl.pathSegments.where((segment) => segment.isNotEmpty);
    return apiBaseUrl.replace(
      pathSegments: [...baseSegments, ...endpointSegments],
      query: null,
    );
  }

  Map<String, String> _jsonHeaders({String? token}) {
    return {
      'Accept': 'application/json',
      'Content-Type': 'application/json',
      if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
    };
  }

  Map<String, String> _binaryHeaders({
    required String token,
    String? mimeType,
  }) {
    return {
      'Accept': 'application/json',
      'Content-Type': mimeType ?? 'application/octet-stream',
      if (token.isNotEmpty) 'Authorization': 'Bearer $token',
    };
  }

  Future<http.Response> _send(
    Future<http.Response> Function() request,
  ) async {
    try {
      return await request();
    } on PixromptApiException {
      rethrow;
    } on http.ClientException catch (error) {
      throw PixromptNetworkException('Network request failed.', error);
    } catch (error) {
      throw PixromptNetworkException('Network request failed.', error);
    }
  }

  void _ensureOk(http.Response response, {bool allowNoContent = false}) {
    if (response.statusCode == 401 || response.statusCode == 403) {
      throw PixromptUnauthorizedException(
        'Pixrompt API rejected the current session.',
        statusCode: response.statusCode,
      );
    }
    final success = response.statusCode >= 200 && response.statusCode < 300;
    if (!success) {
      throw PixromptHttpException(
        'Pixrompt API returned HTTP ${response.statusCode}.',
        statusCode: response.statusCode,
        body: response.body,
      );
    }
    if (!allowNoContent && response.bodyBytes.isEmpty) {
      throw PixromptMalformedResponseException(
        'Pixrompt API returned an empty response body.',
      );
    }
  }

  T _parseObject<T>(
    http.Response response,
    T Function(Map<String, dynamic> json) parse,
  ) {
    return _parseMap(_decodeObject(response), parse);
  }

  T _parseMap<T>(
    Map<String, dynamic> json,
    T Function(Map<String, dynamic> json) parse,
  ) {
    try {
      return parse(json);
    } catch (error) {
      throw PixromptMalformedResponseException(
        'Pixrompt API response did not match the expected schema.',
        cause: error,
      );
    }
  }

  Map<String, dynamic> _decodeObject(http.Response response) {
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) return decoded.cast<String, dynamic>();
    } catch (error) {
      throw PixromptMalformedResponseException(
        'Pixrompt API returned malformed JSON.',
        cause: error,
      );
    }
    throw PixromptMalformedResponseException(
      'Pixrompt API returned JSON that was not an object.',
    );
  }

  static Uri _normalizeBaseUrl(String value) {
    final trimmed = value.trim().isEmpty
        ? defaultPixromptApiBaseUrl
        : value.trim();
    final uri = Uri.parse(trimmed);
    if (!uri.hasScheme || uri.host.isEmpty) {
      throw PixromptMalformedResponseException(
        'Pixrompt API base URL must include scheme and host.',
      );
    }
    final segments = uri.pathSegments.where((segment) => segment.isNotEmpty);
    final normalizedSegments = segments.isNotEmpty && segments.last == 'v1'
        ? segments
        : [...segments, 'v1'];
    return uri.replace(pathSegments: normalizedSegments, query: null);
  }
}

class PixromptApiException implements Exception {
  const PixromptApiException(
    this.message, {
    this.statusCode,
    this.body,
    this.cause,
  });

  final String message;
  final int? statusCode;
  final String? body;
  final Object? cause;

  @override
  String toString() {
    final status = statusCode == null ? '' : ' HTTP $statusCode.';
    final detail = body == null || body!.isEmpty ? '' : ' $body';
    return '$runtimeType: $message$status$detail';
  }
}

class PixromptUnauthorizedException extends PixromptApiException {
  const PixromptUnauthorizedException(
    super.message, {
    super.statusCode,
    super.body,
    super.cause,
  });
}

class PixromptNetworkException extends PixromptApiException {
  const PixromptNetworkException(String message, Object cause)
      : super(message, cause: cause);
}

class PixromptMalformedResponseException extends PixromptApiException {
  const PixromptMalformedResponseException(
    super.message, {
    super.statusCode,
    super.body,
    super.cause,
  });
}

class PixromptHttpException extends PixromptApiException {
  const PixromptHttpException(
    super.message, {
    super.statusCode,
    super.body,
    super.cause,
  });
}

const defaultPixromptApiBaseUrl = 'https://pixrompt.quaternijkon.online/v1';
