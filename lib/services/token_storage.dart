import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Penyimpanan token di secure storage (Keystore Android).
/// Semua method static supaya bisa dipanggil dari mana saja
/// tanpa perlu menyimpan instance.
class TokenStorage {
  TokenStorage._();

  static const FlutterSecureStorage _storage = FlutterSecureStorage();

  static const String _kAccess = 'access_token';
  static const String _kRefresh = 'refresh_token';
  static const String _kExpiresAt = 'expires_at';

  /// Simpan pasangan token. [expiresIn] dalam detik (sesuai respons backend).
  /// expires_at disimpan sebagai epoch milidetik.
  static Future<void> save({
    required String accessToken,
    required String refreshToken,
    required int expiresIn,
  }) async {
    final expiresAt =
        DateTime.now().add(Duration(seconds: expiresIn)).millisecondsSinceEpoch;

    await _storage.write(key: _kAccess, value: accessToken);
    await _storage.write(key: _kRefresh, value: refreshToken);
    await _storage.write(key: _kExpiresAt, value: expiresAt.toString());
  }

  static Future<String?> readAccess() => _storage.read(key: _kAccess);

  static Future<String?> readRefresh() => _storage.read(key: _kRefresh);

  /// Waktu kedaluwarsa access token, atau null kalau belum tersimpan.
  static Future<DateTime?> readExpiresAt() async {
    final raw = await _storage.read(key: _kExpiresAt);
    if (raw == null) return null;
    final ms = int.tryParse(raw);
    if (ms == null) return null;
    return DateTime.fromMillisecondsSinceEpoch(ms);
  }

  /// Ada sesi kalau refresh token tersimpan.
  static Future<bool> hasSession() async {
    final refresh = await _storage.read(key: _kRefresh);
    return refresh != null && refresh.isNotEmpty;
  }

  /// Hapus ketiga nilai (dipakai saat logout / sesi berakhir).
  static Future<void> clear() async {
    await _storage.delete(key: _kAccess);
    await _storage.delete(key: _kRefresh);
    await _storage.delete(key: _kExpiresAt);
  }
}