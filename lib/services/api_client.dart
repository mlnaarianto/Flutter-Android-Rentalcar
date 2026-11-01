import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/api_config.dart';
import 'token_storage.dart';

enum _RefreshResult { success, sessionExpired, temporaryFailure }

/// Wrapper http yang otomatis memasang header, me-refresh token
/// (proaktif dan saat 401), dan memastikan hanya satu refresh berjalan.
///
/// Pemakaian: ApiClient.instance.get(Uri.parse(...))
class ApiClient extends http.BaseClient {
  ApiClient._();
  static final ApiClient instance = ApiClient._();

  /// Dipanggil HANYA saat /auth/refresh membalas 401 (sesi benar-benar mati).
  /// Diisi dari main.dart (Fase 2): disconnect WS, bersihkan data, ke LoginPage.
  static Future<void> Function()? onSessionExpired;

  final http.Client _inner = http.Client();
  Future<_RefreshResult>? _refreshing;

  /// Refresh lebih awal kalau sisa umur access token kurang dari ini.
  static const Duration _refreshMargin = Duration(seconds: 30);
  static const Duration _refreshTimeout = Duration(seconds: 15);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    // Panggilan ke /auth/refresh tidak boleh lewat logika refresh (cegah loop).
    if (_isRefreshCall(request.url)) {
      return _inner.send(request);
    }

    // Refresh proaktif. Kalau gagal sementara, tetap kirim dengan token lama.
    final expiresAt = await TokenStorage.readExpiresAt();
    if (expiresAt != null &&
        DateTime.now().isAfter(expiresAt.subtract(_refreshMargin))) {
      await _refreshOnce();
    }

    // Salin dulu: request hanya bisa dikirim sekali, dan kita butuh
    // salinan bersih untuk retry kalau nanti 401.
    final retryCopy = _copyIfRetryable(request);

    final response = await _sendWithAuth(request);
    if (response.statusCode != 401 || retryCopy == null) {
      return response; // bukan 401, atau multipart/streamed (tidak bisa diulang)
    }

    final result = await _refreshOnce();
    if (result != _RefreshResult.success) {
      return response; // kembalikan 401 asli, jangan logout dari sini
    }

    await response.stream.drain<void>(); // buang body 401 sebelumnya
    return _sendWithAuth(retryCopy);
  }

  Future<http.StreamedResponse> _sendWithAuth(http.BaseRequest request) async {
    final token = await TokenStorage.readAccess();
    request.headers['Accept'] = 'application/json';
    if (token != null && token.isNotEmpty) {
      request.headers['Authorization'] = 'Bearer $token';
    }
    // Content-Type sengaja tidak diset: biar pemanggil / multipart yang atur.
    return _inner.send(request);
  }

  /// Satu refresh bersama: request paralel menunggu Future yang sama.
  Future<_RefreshResult> _refreshOnce() {
    return _refreshing ??=
        _doRefresh().whenComplete(() => _refreshing = null);
  }

  Future<_RefreshResult> _doRefresh() async {
    final refreshToken = await TokenStorage.readRefresh();
    if (refreshToken == null || refreshToken.isEmpty) {
      // Tidak ada sesi (mis. sudah logout). Tidak perlu memicu callback lagi.
      return _RefreshResult.sessionExpired;
    }

    try {
      final res = await _inner.post(
        Uri.parse(ApiConfig.refresh),
        headers: {
          'Accept': 'application/json',
          'Authorization': 'Bearer $refreshToken',
        },
      ).timeout(_refreshTimeout);

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        await TokenStorage.save(
          accessToken: data['access_token'] as String,
          refreshToken: data['refresh_token'] as String,
          expiresIn: (data['expires_in'] as num).toInt(),
        );
        return _RefreshResult.success;
      }

      if (res.statusCode == 401) {
        await onSessionExpired?.call();
        return _RefreshResult.sessionExpired;
      }

      return _RefreshResult.temporaryFailure; // 5xx dll: jangan logout
    } catch (_) {
      // Jaringan putus, timeout, respons rusak: jangan logout.
      return _RefreshResult.temporaryFailure;
    }
  }

  bool _isRefreshCall(Uri url) => url.path.endsWith('/auth/refresh');

  /// Hanya http.Request biasa yang bisa diulang. Multipart/streamed -> null.
  http.Request? _copyIfRetryable(http.BaseRequest request) {
    if (request is! http.Request) return null;
    return http.Request(request.method, request.url)
      ..headers.addAll(request.headers)
      ..encoding = request.encoding
      ..bodyBytes = request.bodyBytes
      ..followRedirects = request.followRedirects
      ..maxRedirects = request.maxRedirects
      ..persistentConnection = request.persistentConnection;
  }
}