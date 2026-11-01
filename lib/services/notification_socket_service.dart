import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform; // deteksi platform android/ios
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:rentalcar/config/api_config.dart';
import 'package:rentalcar/menu/notifikasi.dart'; // halaman tujuan tap notifikasi
import 'package:rentalcar/utils/navigation_service.dart'; // navigatorKey global
import 'package:rentalcar/services/api_client.dart'; // 🟢 FASE 3: refresh token otomatis
import 'package:rentalcar/services/token_storage.dart'; // 🟢 FASE 3: cek sesi

/// Service singleton untuk koneksi real-time ke Reverb.
///
/// Kenapa singleton? Koneksi dibuka SEKALI saat user login (atau app
/// dibuka dengan sesi lama), lalu tetap hidup sepanjang sesi app, dan
/// seluruh halaman tinggal "dengarkan" statusnya tanpa buka koneksi baru.
///
/// Strategi notifikasi:
/// - [_shouldShow] dedupe berdasarkan `notification_id`, dipakai di jalur
///   WS maupun FCM, jadi notifikasi yang sama tidak tampil dua kali.
/// - WS jadi jalur utama SELAMA channel private-nya sudah "subscribed"
///   ([_wsReady] = socket terbuka DAN subscribed).
/// - FCM foreground listener ([handleFcmMessage]) jadi fallback.
/// - Saat app BACKGROUND, WS tetap hidup untuk badge/stream, tapi popup
///   diserahkan ke background handler FCM di main.dart.
///
/// Navigasi saat notifikasi di-tap:
/// - Local notification (WS/FCM foreground) -> onDidReceiveNotificationResponse
/// - FCM background/killed -> main.dart (onMessageOpenedApp & getInitialMessage)
///
/// Multi-device FCM:
/// Token disimpan per-device di tabel `user_fcm_tokens`. `_syncFcmToken()`
/// mengirim `device_id` & `platform`, dan [removeFcmToken] WAJIB dipanggil
/// saat logout.
///
/// 🟢 FASE 3 (refresh token):
/// - Semua request HTTP lewat [ApiClient] (header Authorization + refresh
///   otomatis), tidak ada lagi parameter `token` yang dioper-oper.
/// - Cek sesi lewat [TokenStorage.hasSession], bukan `access_token` di prefs.
/// - Reconnect berhenti kalau sesi sudah berakhir.
class NotificationSocketService {
  NotificationSocketService._internal() {
    _initLocalNotifications();

    // Kalau token FCM device berubah (reinstall, clear data, dst),
    // sinkron ulang ke server supaya push tetap sampai.
    // 🟢 FASE 3: cek sesi lewat TokenStorage, token dipasang ApiClient.
    FirebaseMessaging.instance.onTokenRefresh.listen((newToken) async {
      if (await TokenStorage.hasSession()) {
        await _syncFcmToken();
      }
    });
  }

  static final NotificationSocketService _instance =
      NotificationSocketService._internal();
  factory NotificationSocketService() => _instance;

  WebSocketChannel? _wsChannel;
  StreamSubscription? _wsSubscription;
  String? _socketId;

  // "socket terbuka" dan "channel private siap menerima event" adalah dua
  // hal yang BEDA WAKTU, jadi dipisah jadi dua flag.
  bool _isSocketOpen = false; // WebSocket sudah terbuka (raw connection)
  bool _isSubscribed = false; // channel private sudah confirmed subscribed

  /// WS dianggap "siap" hanya kalau socket terbuka DAN sudah subscribed.
  bool get _wsReady => _isSocketOpen && _isSubscribed;

  String? _connectedUserId;

  Timer? _reconnectTimer;
  int _reconnectAttempt = 0;
  static const List<int> _backoffSeconds = [2, 4, 8, 15, 30, 60];

  final ValueNotifier<bool> hasUnread = ValueNotifier<bool>(false);

  final StreamController<Map<String, dynamic>> _newNotificationController =
      StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get onNewNotification =>
      _newNotificationController.stream;

  /// Dipertahankan untuk kompatibilitas kode lain. Artinya "WS benar-benar
  /// siap terima event", bukan sekadar socket terbuka.
  bool get isConnected => _wsReady;

  /// Dedupe berbasis notification_id (in-memory, per sesi app).
  final Set<String> _shownNotificationIds = {};
  static const int _maxTrackedIds = 200;

  bool _shouldShow(dynamic notificationId) {
    if (notificationId == null) {
      // Tidak ada id untuk dedupe -> tetap tampilkan (fail-open).
      return true;
    }
    final id = notificationId.toString();
    if (_shownNotificationIds.contains(id)) {
      debugPrint('Reverb Service: notifikasi id=$id sudah pernah tampil, skip.');
      return false;
    }
    _shownNotificationIds.add(id);
    if (_shownNotificationIds.length > _maxTrackedIds) {
      _shownNotificationIds.remove(_shownNotificationIds.first);
    }
    return true;
  }

  /// Status foreground/background, di-set dari main.dart lewat
  /// WidgetsBindingObserver. HANYA di-set false untuk paused/hidden/detached,
  /// TIDAK untuk `inactive` (interupsi sesaat).
  bool _isAppInForeground = true;
  set isAppInForeground(bool value) {
    _isAppInForeground = value;
  }

  final FlutterLocalNotificationsPlugin _localNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  /// Inisialisasi local notifications.
  /// PENTING: nama parameternya `settings` (flutter_local_notifications v22).
  Future<void> _initLocalNotifications() async {
    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    const InitializationSettings initializationSettings =
        InitializationSettings(
      android: initializationSettingsAndroid,
    );

    await _localNotificationsPlugin.initialize(
      settings: initializationSettings,
      onDidReceiveNotificationResponse: (NotificationResponse response) {
        debugPrint('Notifikasi di-tap: ${response.payload}');

        // Sengaja TIDAK dibungkus addPostFrameCallback: callback ini
        // terpanggil saat app sudah berjalan normal, jadi tidak ada frame
        // baru yang di-schedule. _navigateToNotifikasi punya retry singkat.
        _navigateToNotifikasi();
      },
    );

    // Android 13+ (API 33) mewajibkan izin runtime untuk notifikasi.
    // Tipe variabel dideklarasikan supaya Dart meng-infer generic-nya.
    final AndroidFlutterLocalNotificationsPlugin? androidImplementation =
        _localNotificationsPlugin.resolvePlatformSpecificImplementation();
    await androidImplementation?.requestNotificationsPermission();
  }

  /// Navigasi ke NotifikasiPage. Kalau `navigatorKey.currentState` masih
  /// null, coba lagi tiap 100ms maksimal 5 kali sebelum menyerah.
  void _navigateToNotifikasi({int attempt = 0}) {
    final state = navigatorKey.currentState;
    if (state != null) {
      state.push(
        MaterialPageRoute(builder: (_) => const NotifikasiPage()),
      );
      return;
    }

    const maxAttempts = 5;
    if (attempt >= maxAttempts) {
      debugPrint(
          'Reverb Service: navigatorKey.currentState tetap null, batal navigasi.');
      return;
    }

    Future.delayed(const Duration(milliseconds: 100), () {
      _navigateToNotifikasi(attempt: attempt + 1);
    });
  }

  /// Menampilkan banner pop-up notifikasi di status bar.
  /// flutter_local_notifications v22: show() memakai NAMED parameter.
  Future<void> _showSystemNotification(String title, String body) async {
    const AndroidNotificationDetails androidPlatformChannelSpecifics =
        AndroidNotificationDetails(
      'rental_car_channel_id',
      'Aktivitas Rental',
      channelDescription:
          'Notifikasi status pesanan dan aktivitas rental mobil',
      importance: Importance.max,
      priority: Priority.high,
    );

    const NotificationDetails platformChannelSpecifics =
        NotificationDetails(android: androidPlatformChannelSpecifics);

    try {
      await _localNotificationsPlugin.show(
        id: DateTime.now().millisecondsSinceEpoch ~/ 1000,
        title: title,
        body: body,
        notificationDetails: platformChannelSpecifics,
      );
    } catch (e) {
      debugPrint('Gagal menampilkan local notification: $e');
    }
  }

  static const String _deviceIdPrefsKey = 'fcm_device_id';

  /// device_id persisten untuk device ini (dibuat sekali, disimpan permanen
  /// di SharedPreferences).
  Future<String> _getOrCreateDeviceId() async {
    final prefs = await SharedPreferences.getInstance();
    String? deviceId = prefs.getString(_deviceIdPrefsKey);

    if (deviceId == null) {
      final random = DateTime.now().microsecondsSinceEpoch;
      deviceId = 'device_$random';
      await prefs.setString(_deviceIdPrefsKey, deviceId);
    }

    return deviceId;
  }

  /// Nama platform untuk dikirim ke backend (kolom `platform`).
  String get _platformName {
    if (Platform.isAndroid) return 'android';
    if (Platform.isIOS) return 'ios';
    return 'unknown';
  }

  /// Kirim/update token FCM device ini ke server (POST /api/fcm-token).
  /// 🟢 FASE 3: pakai ApiClient, tanpa parameter token.
  Future<void> _syncFcmToken() async {
    try {
      final fcmToken = await FirebaseMessaging.instance.getToken();
      if (fcmToken == null) {
        debugPrint('Reverb Service: FCM token belum tersedia, skip sync.');
        return;
      }

      final deviceId = await _getOrCreateDeviceId();

      final response = await ApiClient.instance.post(
        Uri.parse('${ApiConfig.baseUrl}/fcm-token'),
        body: {
          'fcm_token': fcmToken,
          'device_id': deviceId,
          'platform': _platformName,
        },
      );

      if (response.statusCode == 200) {
        debugPrint('Reverb Service: FCM token berhasil disinkron ke server.');
      } else {
        debugPrint(
            'Reverb Service: gagal sync FCM token (${response.statusCode}).');
      }
    } catch (e) {
      debugPrint('Reverb Service: error sync FCM token: $e');
    }
  }

  /// Hapus token FCM device ini dari server. WAJIB dipanggil saat logout,
  /// SEBELUM TokenStorage.clear().
  /// 🟢 FASE 3: pakai ApiClient, tanpa parameter token.
  Future<void> removeFcmToken() async {
    try {
      final fcmToken = await FirebaseMessaging.instance.getToken();
      if (fcmToken == null) {
        debugPrint('Reverb Service: tidak ada FCM token untuk dihapus, skip.');
        return;
      }

      final response = await ApiClient.instance.delete(
        Uri.parse('${ApiConfig.baseUrl}/fcm-token'),
        body: {'fcm_token': fcmToken},
      );

      if (response.statusCode == 200) {
        debugPrint('Reverb Service: FCM token berhasil dihapus dari server.');
      } else {
        debugPrint(
            'Reverb Service: gagal hapus FCM token (${response.statusCode}).');
      }
    } catch (e) {
      debugPrint('Reverb Service: error hapus FCM token: $e');
    }
  }

  bool _isConnecting = false;

  /// 🟢 FIX race: guard dipasang SINKRON di awal, sebelum ada `await`.
  /// Sebelumnya guard baru di-set setelah beberapa await (prefs, hasSession),
  /// jadi dua pemanggil hampir bersamaan (main.dart + Dashboard.initState)
  /// sama-sama lolos dan membuka DUA WebSocket.
  Future<void> connect() async {
    if (_isConnecting) {
      debugPrint('Reverb Service: sedang proses connect, skip panggilan dobel.');
      return;
    }
    _isConnecting = true;
    try {
      await _connectInternal();
    } finally {
      _isConnecting = false;
    }
  }

  Future<void> _connectInternal() async {

    // 🟢 FASE 3: cek sesi lewat TokenStorage (refresh token), bukan
    // access_token di prefs. Access token boleh sudah kedaluwarsa;
    // ApiClient yang akan me-refresh saat request pertama.
    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getString('user_id');

    if (!await TokenStorage.hasSession() || userId == null) {
      debugPrint('Reverb Service: sesi/userId belum tersedia, skip connect.');
      return;
    }

    final isUserSwitch = _connectedUserId != null && _connectedUserId != userId;

    if (isUserSwitch) {
      debugPrint(
          'Reverb Service: user berganti ($_connectedUserId -> $userId), reconnect...');
      _hardDisconnect(resetUnread: true);
    } else if (_wsReady) {
      debugPrint(
          'Reverb Service: sudah terkoneksi & subscribed untuk user ini, skip.');
      return;
    } else if (_isSocketOpen && !isUserSwitch) {
      // Socket terbuka tapi belum subscribed (proses auth masih berjalan).
      debugPrint(
          'Reverb Service: socket masih terbuka & menunggu subscribe, skip.');
      return;
    }

    final isFirstConnectForUser = _connectedUserId != userId;
    if (isFirstConnectForUser) {
      await _checkInitialUnreadStatus();
    }

    // Pastikan server selalu punya FCM token terbaru device ini.
    await _syncFcmToken();

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
      // Tutup koneksi lama (kalau ada) supaya tidak ada socket yatim.
      _wsSubscription?.cancel();
      _wsChannel?.sink.close();

      final channel = WebSocketChannel.connect(wsUri);
      _wsChannel = channel;
      _isSocketOpen = true;
      _isSubscribed = false; // belum subscribed sampai confirmed
      _connectedUserId = userId;
      _reconnectAttempt = 0;

      _wsSubscription = channel.stream.listen(
        (raw) => _handleMessage(raw, userId, apiUri),
        onError: (e) {
          // Abaikan event dari channel lama (sudah diganti koneksi baru).
          if (!identical(channel, _wsChannel)) return;
          debugPrint('Reverb Service: WS error: $e');
          _isSocketOpen = false;
          _isSubscribed = false;
          _scheduleReconnect();
        },
        onDone: () {
          if (!identical(channel, _wsChannel)) return;
          debugPrint('Reverb Service: WS closed.');
          _isSocketOpen = false;
          _isSubscribed = false;
          _scheduleReconnect();
        },
        cancelOnError: true,
      );
    } catch (e) {
      debugPrint('Reverb Service: gagal connect: $e');
      _isSocketOpen = false;
      _isSubscribed = false;
      _scheduleReconnect();
    }
  }

  /// 🟢 FASE 3: pengecekan sesi ditaruh DI DALAM timer, bukan di awal.
  /// Ada race: saat /auth/refresh membalas 401, onSessionExpired memanggil
  /// disconnect() (membatalkan timer), lalu request /broadcasting/auth yang
  /// gagal kembali ke _subscribeToChannel dan memanggil _scheduleReconnect()
  /// lagi -> timer baru terbentuk SETELAH disconnect(). Cek di dalam timer
  /// memastikan reconnect batal kalau sesi sudah dibersihkan.
  void _scheduleReconnect() {
    _reconnectTimer?.cancel();

    final idx = _reconnectAttempt.clamp(0, _backoffSeconds.length - 1);
    final delay = Duration(seconds: _backoffSeconds[idx]);
    _reconnectAttempt++;

    debugPrint('Reverb Service: reconnect dalam ${delay.inSeconds}s...');
    _reconnectTimer = Timer(delay, () async {
      if (!await TokenStorage.hasSession()) {
        debugPrint('Reverb Service: sesi berakhir, reconnect dibatalkan.');
        _reconnectAttempt = 0;
        return;
      }
      if (!_wsReady) connect();
    });
  }

  /// 🟢 FASE 3: pakai ApiClient, tanpa parameter token.
  Future<void> _checkInitialUnreadStatus() async {
    try {
      final response = await ApiClient.instance.get(
        Uri.parse('${ApiConfig.baseUrl}/notifications'),
      );
      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        final List notifications = decoded['data'] ?? [];
        hasUnread.value =
            notifications.any((notif) => notif['is_read'] == false);
      }
    } catch (_) {}
  }

  /// 🟢 FASE 3: parameter token dihapus.
  void _handleMessage(
    dynamic raw,
    String userId,
    Uri apiUri,
  ) async {
    try {
      final msg = jsonDecode(raw as String);
      final event = msg['event'];

      // Reverb mengirim ping berkala dan menutup koneksi kalau tidak dibalas
      // pong. Klien mentah (tanpa pusher-js) harus membalasnya sendiri.
      if (event == 'pusher:ping') {
        _wsChannel?.sink.add(jsonEncode({'event': 'pusher:pong', 'data': {}}));
        return;
      }

      if (event == 'pusher:connection_established') {
        final connData = jsonDecode(msg['data']);
        _socketId = connData['socket_id'];
        await _subscribeToChannel(userId, apiUri);
        return;
      }

      // Konfirmasi subscribe sukses. Baru dari titik ini WS dianggap siap.
      if (event != null &&
          event.toString().contains('subscription_succeeded')) {
        _isSubscribed = true;
        debugPrint('Reverb Service: subscribed ke channel notifications.$userId');
        return;
      }

      // Subscribe gagal: log & coba reconnect.
      if (event != null && event.toString().contains('subscription_error')) {
        debugPrint('Reverb Service: subscribe GAGAL: ${msg['data']}');
        _isSubscribed = false;
        _scheduleReconnect();
        return;
      }

      if (event == '.notification.created' || event == 'notification.created') {
        final payload = jsonDecode(msg['data']);
        final newNotif = payload['data'];

        // Badge langsung menyala (foreground maupun background).
        hasUnread.value = true;

        // Dedupe dulu berdasarkan notification_id sebelum memutuskan tampil.
        final notifId = newNotif is Map ? newNotif['id'] : null;

        if (_isAppInForeground && _shouldShow(notifId)) {
          final title = newNotif['title'] ?? 'Informasi Rental';
          final message =
              newNotif['message'] ?? 'Anda memiliki aktivitas baru.';
          _showSystemNotification(title, message);
        } else if (!_isAppInForeground) {
          debugPrint(
              'Reverb Service: app di background, notifikasi diserahkan ke FCM (tidak tampil dari WS).');
        }

        // Teruskan ke halaman yang sedang mendengarkan (NotifikasiPage)
        _newNotificationController.add(newNotif);
      }
    } catch (e) {
      debugPrint('Reverb Service: gagal parse pesan: $e');
    }
  }

  /// Dipanggil dari main.dart (FirebaseMessaging.onMessage) tiap ada pesan
  /// FCM masuk selagi app foreground. Dicek `_wsReady` + dedupe id.
  void handleFcmMessage(RemoteMessage message) {
    final data = message.data;
    final notifId = data['notification_id'];

    if (_wsReady) {
      debugPrint(
          'Reverb Service: WS siap & subscribed, abaikan FCM (hindari duplikat).');
      return;
    }

    if (!_shouldShow(notifId)) {
      return;
    }

    final title =
        message.notification?.title ?? data['title'] ?? 'Informasi Rental';
    final body = message.notification?.body ??
        data['message'] ??
        'Anda memiliki aktivitas baru.';

    debugPrint('Reverb Service: WS belum siap, tampilkan notifikasi via FCM.');

    hasUnread.value = true;
    _showSystemNotification(title, body);

    _newNotificationController.add(<String, dynamic>{
      'title': title,
      'message': body,
      ...data,
    });
  }

  /// 🟢 FASE 3: parameter token dihapus, pakai ApiClient.
  Future<void> _subscribeToChannel(
    String userId,
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
      final authResponse = await ApiClient.instance.post(
        authUrl,
        body: {
          'socket_id': _socketId,
          'channel_name': channelName,
        },
      );

      if (authResponse.statusCode != 200) {
        debugPrint(
            'Reverb Service: broadcasting auth gagal (${authResponse.statusCode})');
        // Picu reconnect supaya percobaan berikutnya bisa memperbaiki diri
        // (dibatalkan otomatis di _scheduleReconnect kalau sesi sudah mati).
        _isSubscribed = false;
        _scheduleReconnect();
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

      // _isSubscribed baru di-set true saat menerima
      // "pusher:subscription_succeeded" dari server (lihat _handleMessage).
    } catch (e) {
      debugPrint('Reverb Service: gagal subscribe: $e');
      _isSubscribed = false;
      _scheduleReconnect();
    }
  }

  void _hardDisconnect({bool resetUnread = false}) {
    _reconnectTimer?.cancel();
    _wsSubscription?.cancel();
    _wsChannel?.sink.close();
    _isSocketOpen = false;
    _isSubscribed = false;
    _connectedUserId = null;
    _reconnectAttempt = 0;
    if (resetUnread) hasUnread.value = false;
  }

  /// Dipanggil saat app benar-benar ditutup/di-swipe. WebSocket ditutup
  /// untuk hemat resource, `_connectedUserId` TIDAK direset.
  void pause() {
    _reconnectTimer?.cancel();
    _wsSubscription?.cancel();
    _wsChannel?.sink.close();
    _isSocketOpen = false;
    _isSubscribed = false;
    debugPrint('Reverb Service: paused.');
  }

  void disconnect() {
    _hardDisconnect(resetUnread: true);
    debugPrint('Reverb Service: disconnected.');
  }

  void markAsSeen() {
    hasUnread.value = false;
  }
}