import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart'; // DEBUG-LOG: untuk debugPrint
import 'package:http/http.dart' as http;

import '../config/api_config.dart';
import 'token_storage.dart';

enum _RefreshResult { success, sessionExpired, temporaryFailure }

/// Wrapper http yang otomatis memasang header, me-refresh token
/// (proaktif dan saat 401), dan memastikan hanya satu refresh berjalan.
///
/// Pemakaian: ApiClient.instance.get(Uri.parse(...))
/// Untuk upload multipart: ApiClient.instance.sendMultipart(() async { ... })
///
/// Semua baris bertanda "DEBUG-LOG" bersifat sementara dan tidak mencetak
/// nilai token (hanya panjang, nama key, status). Hapus setelah bug beres.
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
    // DEBUG-LOG
    debugPrint('SEND ${request.method} ${request.url.path} '
        'expiresAt=$expiresAt now=${DateTime.now()}');

    if (expiresAt != null &&
        DateTime.now().isAfter(expiresAt.subtract(_refreshMargin))) {
      debugPrint('SEND proaktif refresh dipicu'); // DEBUG-LOG
      final r = await _refreshOnce();
      debugPrint('SEND proaktif refresh hasil=$r'); // DEBUG-LOG
    }

    // Salin dulu: request hanya bisa dikirim sekali, dan kita butuh
    // salinan bersih untuk retry kalau nanti 401.
    final retryCopy = _copyIfRetryable(request);

    final response = await _sendWithAuth(request);
    // DEBUG-LOG
    debugPrint('RESP ${request.url.path} status=${response.statusCode} '
        'retryable=${retryCopy != null}');

    if (response.statusCode != 401 || retryCopy == null) {
      return response; // bukan 401, atau multipart/streamed (tidak bisa diulang)
    }

    debugPrint('RESP 401 -> coba refresh lalu retry'); // DEBUG-LOG
    final result = await _refreshOnce();
    debugPrint('RESP 401 refresh hasil=$result'); // DEBUG-LOG
    if (result != _RefreshResult.success) {
      return response; // kembalikan 401 asli, jangan logout dari sini
    }

    await response.stream.drain<void>(); // buang body 401 sebelumnya
    final retried = await _sendWithAuth(retryCopy);
    // DEBUG-LOG
    debugPrint('RETRY ${request.url.path} status=${retried.statusCode}');
    return retried;
  }

  /// Kirim request multipart dengan retry setelah 401.
  ///
  /// [build] dipanggil ulang saat retry karena MultipartRequest hanya bisa
  /// dikirim sekali (file harus dibaca ulang dari disk). Pemanggil TIDAK
  /// perlu memasang header Authorization; ApiClient yang memasangnya.
  ///
  /// Alur: kirim -> kalau 401, refresh sekali (dibagi dengan request lain
  /// yang sedang refresh) -> bangun ulang request -> kirim lagi.
  /// Kalau refresh gagal, 401 pertama dikembalikan apa adanya (kalau sesi
  /// mati, onSessionExpired sudah dipanggil oleh _doRefresh).
  Future<http.StreamedResponse> sendMultipart(
    Future<http.MultipartRequest> Function() build,
  ) async {
    // Percobaan 1 (send() sudah melakukan refresh proaktif)
    final first = await send(await build());
    if (first.statusCode != 401) return first;

    // 401: refresh sekali, lalu bangun ulang request dan kirim lagi
    debugPrint('MULTIPART 401 -> refresh lalu kirim ulang'); // DEBUG-LOG
    final result = await _refreshOnce();
    if (result != _RefreshResult.success) return first;

    await first.stream.drain<void>(); // buang body 401 sebelumnya
    return send(await build());
  }

  Future<http.StreamedResponse> _sendWithAuth(http.BaseRequest request) async {
    final token = await TokenStorage.readAccess();
    // DEBUG-LOG: hanya panjang token, bukan nilainya
    debugPrint('AUTH ${request.url.path} accessToken='
        '${token == null ? "NULL" : "len=${token.length}"}');

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
    // DEBUG-LOG
    debugPrint('REFRESH start: refreshToken='
        '${refreshToken == null ? "NULL" : "len=${refreshToken.length}"}');

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

      // DEBUG-LOG
      debugPrint('REFRESH url=${ApiConfig.refresh} status=${res.statusCode}');

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        // DEBUG-LOG: hanya nama key, bukan nilai
        debugPrint('REFRESH keys=${data.keys.toList()}');

        await TokenStorage.save(
          accessToken: data['access_token'] as String,
          refreshToken: data['refresh_token'] as String,
          expiresIn: (data['expires_in'] as num).toInt(),
        );
        debugPrint('REFRESH saved OK'); // DEBUG-LOG
        return _RefreshResult.success;
      }

      if (res.statusCode == 401) {
        debugPrint('REFRESH 401 -> sesi berakhir'); // DEBUG-LOG
        await onSessionExpired?.call();
        return _RefreshResult.sessionExpired;
      }

      // DEBUG-LOG: body error (bukan 200) tidak berisi token, aman dicetak
      final b = res.body;
      debugPrint('REFRESH non-200 body='
          '${b.length > 300 ? b.substring(0, 300) : b}');
      return _RefreshResult.temporaryFailure; // 5xx dll: jangan logout
    } catch (e, st) {
      // Jaringan putus, timeout, respons rusak: jangan logout.
      debugPrint('REFRESH exception: $e\n$st'); // DEBUG-LOG
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