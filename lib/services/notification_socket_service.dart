import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:rentalcar/config/api_config.dart';

/// Service singleton untuk koneksi real-time ke Reverb.
///
/// Kenapa singleton? Karena Navbar dipakai berulang di banyak halaman —
/// kalau tiap halaman/instance Navbar buka koneksi WebSocket sendiri,
/// koneksi akan buka-tutup terus-menerus tiap kali pindah halaman.
/// Dengan singleton, koneksi dibuka SEKALI saat user login, lalu tetap
/// hidup sepanjang sesi app, dan seluruh halaman tinggal "dengarkan"
/// statusnya tanpa perlu buka koneksi baru.
///
/// 🟢 PERBAIKAN DI VERSI INI:
/// 1. Socket yang putus (error/onDone) sekarang otomatis reconnect
///    dengan backoff, bukan mati total sampai app di-restart.
/// 2. `_checkInitialUnreadStatus` (yang menimpa `hasUnread` dari status
///    `is_read` di backend) HANYA dipanggil saat benar-benar koneksi
///    pertama untuk user ini (login / cold start) — bukan setiap kali
///    reconnect di sesi yang sama. Ini mencegah badge "nyala lagi"
///    kalau request read-all sebelumnya sempat gagal/telat sinkron.
/// 3. `markAsSeen()` sekarang juga dipanggil dari `NotifikasiPage`
///    HANYA setelah read-all ke backend benar-benar sukses (lihat
///    notifikasi.dart), supaya state lokal & backend tidak pernah
///    "beda cerita".
class NotificationSocketService {
  NotificationSocketService._internal();
  static final NotificationSocketService _instance =
      NotificationSocketService._internal();
  factory NotificationSocketService() => _instance;

  WebSocketChannel? _wsChannel;
  StreamSubscription? _wsSubscription;
  String? _socketId;
  bool _isConnected = false;
  bool _isConnecting = false; // 🟢 cegah connect() dipanggil dobel bersamaan
  String? _connectedUserId;

  // 🟢 Reconnect dengan backoff, supaya kalau server/jaringan sempat
  // putus, koneksi otomatis pulih tanpa perlu restart app.
  Timer? _reconnectTimer;
  int _reconnectAttempt = 0;
  static const List<int> _backoffSeconds = [2, 4, 8, 15, 30, 60];

  // Status unread yang didengarkan Navbar.
  final ValueNotifier<bool> hasUnread = ValueNotifier<bool>(false);

  // Stream notifikasi baru — didengarkan NotifikasiPage untuk
  // menambahkan item baru ke list tanpa perlu bikin koneksi sendiri lagi.
  final StreamController<Map<String, dynamic>> _newNotificationController =
      StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get onNewNotification =>
      _newNotificationController.stream;

  bool get isConnected => _isConnected;

  /// Panggil ini SEKALI setelah login berhasil (dan idealnya juga saat
  /// app dibuka dengan sesi yang masih aktif). Aman dipanggil berkali-kali
  /// — kalau sudah connect untuk user yang sama, tidak akan connect ulang.
  Future<void> connect() async {
    if (_isConnecting) {
      debugPrint('Reverb Service: sedang proses connect, skip panggilan dobel.');
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('access_token');
    final userId = prefs.getString('user_id');

    if (token == null || userId == null) {
      debugPrint('Reverb Service: token/userId belum tersedia, skip connect.');
      return;
    }

    final isUserSwitch = _connectedUserId != null && _connectedUserId != userId;

    if (isUserSwitch) {
      debugPrint(
          'Reverb Service: user berganti ($_connectedUserId -> $userId), reconnect...');
      _hardDisconnect(resetUnread: true);
    } else if (_isConnected) {
      debugPrint('Reverb Service: sudah terkoneksi untuk user ini, skip.');
      return;
    }

    _isConnecting = true;

    // 🟢 Hanya cek status unread awal dari backend kalau ini memang
    // koneksi pertama untuk user ini (belum pernah connect di sesi
    // app ini, atau baru ganti user). Reconnect biasa (mis. jaringan
    // sempat putus lalu nyambung lagi) TIDAK menimpa `hasUnread` yang
    // sudah kita jaga secara lokal.
    final isFirstConnectForUser = _connectedUserId != userId;
    if (isFirstConnectForUser) {
      await _checkInitialUnreadStatus(token);
    }

    final apiUri = Uri.parse(ApiConfig.baseUrl);
    const reverbPort = 9090;
    const reverbAppKey = '27d6a6d4761caf333da8';
    const useTLS = false;

    final wsUri = Uri(
      scheme: useTLS ? 'wss' : 'ws',
      host: apiUri.host,
      port: reverbPort,
      path: '/app/$reverbAppKey',
      queryParameters: {
        'protocol': '7',
        'client': 'flutter',
        'version': '1.0.0',
        'flash': 'false',
      },
    );

    debugPrint('Reverb Service: connecting ke $wsUri');

    try {
      _wsChannel = WebSocketChannel.connect(wsUri);
      _isConnected = true;
      _connectedUserId = userId;
      _reconnectAttempt = 0; // reset backoff setelah berhasil connect

      _wsSubscription = _wsChannel!.stream.listen(
        (raw) => _handleMessage(raw, userId, token, apiUri),
        onError: (e) {
          debugPrint('Reverb Service: WS error: $e');
          _isConnected = false;
          _scheduleReconnect();
        },
        onDone: () {
          debugPrint('Reverb Service: WS closed.');
          _isConnected = false;
          _scheduleReconnect();
        },
        cancelOnError: true,
      );
    } catch (e) {
      debugPrint('Reverb Service: gagal connect: $e');
      _isConnected = false;
      _scheduleReconnect();
    } finally {
      _isConnecting = false;
    }
  }

  /// 🟢 Reconnect otomatis dengan backoff bertahap (2s, 4s, 8s, ... maks 60s).
  /// Dipanggil setiap kali socket putus tak sengaja (bukan logout manual).
  void _scheduleReconnect() {
    _reconnectTimer?.cancel();

    final idx = _reconnectAttempt.clamp(0, _backoffSeconds.length - 1);
    final delay = Duration(seconds: _backoffSeconds[idx]);
    _reconnectAttempt++;

    debugPrint('Reverb Service: reconnect dalam ${delay.inSeconds}s...');
    _reconnectTimer = Timer(delay, () {
      if (!_isConnected) connect();
    });
  }

  Future<void> _checkInitialUnreadStatus(String token) async {
    try {
      final response = await http.get(
        Uri.parse('${ApiConfig.baseUrl}/notifications'),
        headers: {
          'Authorization': 'Bearer $token',
          'Accept': 'application/json',
        },
      );
      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        final List notifications = decoded['data'] ?? [];
        hasUnread.value =
            notifications.any((notif) => notif['is_read'] == false);
      }
    } catch (_) {
      // Abaikan, badge akan tetap terupdate lewat event realtime nanti
    }
  }

  void _handleMessage(
    dynamic raw,
    String userId,
    String token,
    Uri apiUri,
  ) async {
    try {
      final msg = jsonDecode(raw as String);
      final event = msg['event'];

      if (event == 'pusher:connection_established') {
        final connData = jsonDecode(msg['data']);
        _socketId = connData['socket_id'];
        await _subscribeToChannel(userId, token, apiUri);
        return;
      }

      if (event == '.notification.created' || event == 'notification.created') {
        final payload = jsonDecode(msg['data']);
        final newNotif = payload['data'];

        // Badge langsung nyala
        hasUnread.value = true;

        // Teruskan ke halaman manapun yang sedang mendengarkan
        // (misal NotifikasiPage kalau sedang terbuka)
        _newNotificationController.add(newNotif);
      }
    } catch (e) {
      debugPrint('Reverb Service: gagal parse pesan: $e');
    }
  }

  Future<void> _subscribeToChannel(
    String userId,
    String token,
    Uri apiUri,
  ) async {
    if (_socketId == null) return;

    final channelName = 'private-notifications.$userId';
    final authUrl = Uri(
      scheme: apiUri.scheme,
      host: apiUri.host,
      port: apiUri.hasPort ? apiUri.port : null,
      path: '/broadcasting/auth',
    );

    try {
      final authResponse = await http.post(
        authUrl,
        headers: {
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: {
          'socket_id': _socketId,
          'channel_name': channelName,
        },
      );

      if (authResponse.statusCode != 200) {
        debugPrint(
            'Reverb Service: broadcasting auth gagal (${authResponse.statusCode})');
        return;
      }

      final authData = jsonDecode(authResponse.body);

      _wsChannel?.sink.add(jsonEncode({
        'event': 'pusher:subscribe',
        'data': {
          'channel': channelName,
          'auth': authData['auth'],
        },
      }));
    } catch (e) {
      debugPrint('Reverb Service: gagal subscribe: $e');
    }
  }

  /// Tutup koneksi tanpa mereset status login (dipakai internal saat
  /// ganti user). `resetUnread` opsional supaya badge langsung 0 saat
  /// benar-benar ganti akun.
  void _hardDisconnect({bool resetUnread = false}) {
    _reconnectTimer?.cancel();
    _wsSubscription?.cancel();
    _wsChannel?.sink.close();
    _isConnected = false;
    _connectedUserId = null;
    _reconnectAttempt = 0;
    if (resetUnread) hasUnread.value = false;
  }

  /// Panggil ini saat user LOGOUT — supaya koneksi lama ditutup dan
  /// tidak "menempel" ke sesi user berikutnya kalau ganti akun.
  void disconnect() {
    _hardDisconnect(resetUnread: true);
    debugPrint('Reverb Service: disconnected.');
  }

  /// Panggil ini HANYA setelah backend benar-benar mengonfirmasi
  /// notifikasi sudah ditandai read (lihat `NotifikasiPage`). Jangan
  /// panggil ini secara optimis sebelum tahu hasil request ke server,
  /// supaya badge lokal tidak pernah "berbohong" dibanding backend.
  void markAsSeen() {
    hasUnread.value = false;
  }
}