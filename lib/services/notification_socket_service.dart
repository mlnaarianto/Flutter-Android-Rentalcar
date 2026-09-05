import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:rentalcar/config/api_config.dart';

/// Service singleton untuk koneksi real-time ke Reverb.
///
/// Kenapa singleton? Karena Navbar dipakai berulang di banyak halaman —
/// kalau tiap halaman/instance Navbar buka koneksi WebSocket sendiri,
/// koneksi akan buka-tutup terus-menerus tiap kali pindah halaman.
/// Dengan singleton, koneksi dibuka SEKALI saat user login, lalu tetap
/// hidup sepanjang sesi app, dan seluruh halaman tinggal "dengarkan"
/// statusnya tanpa perlu buka koneksi baru.
class NotificationSocketService {
  NotificationSocketService._internal() {
    _initLocalNotifications();
  }

  static final NotificationSocketService _instance =
      NotificationSocketService._internal();
  factory NotificationSocketService() => _instance;

  WebSocketChannel? _wsChannel;
  StreamSubscription? _wsSubscription;
  String? _socketId;
  bool _isConnected = false;
  bool _isConnecting = false;
  String? _connectedUserId;

  Timer? _reconnectTimer;
  int _reconnectAttempt = 0;
  static const List<int> _backoffSeconds = [2, 4, 8, 15, 30, 60];

  final ValueNotifier<bool> hasUnread = ValueNotifier<bool>(false);

  final StreamController<Map<String, dynamic>> _newNotificationController =
      StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get onNewNotification =>
      _newNotificationController.stream;

  bool get isConnected => _isConnected;

  final FlutterLocalNotificationsPlugin _localNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  /// Inisialisasi setting local notifications untuk Android & iOS.
  ///
  /// PENTING: nama parameternya adalah `settings` (dikonfirmasi dari source
  /// code resmi paket ini), bukan `initSettings` maupun `initializationSettings`.
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
      },
    );

    // Android 13+ (API 33) mewajibkan izin runtime untuk menampilkan
    // notifikasi sistem. Tanpa ini, show() akan gagal diam-diam
    // (tidak ada error, tapi notifikasi tidak pernah muncul).
    await _localNotificationsPlugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
  }

  /// Menampilkan banner pop-up notifikasi di luar aplikasi (Status Bar).
  ///
  /// PENTING: mulai flutter_local_notifications v22, show() memakai
  /// NAMED parameter untuk id, title, body, dan notificationDetails.
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
      _reconnectAttempt = 0;

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
    } catch (_) {}
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

        // Badge navbar langsung menyala
        hasUnread.value = true;

        // Tampilkan sistem pop-up notifikasi di luar aplikasi (Status Bar)
        final title = newNotif['title'] ?? 'Informasi Rental';
        final message = newNotif['message'] ?? 'Anda memiliki aktivitas baru.';
        _showSystemNotification(title, message);

        // Teruskan ke halaman yang sedang aktif mendengarkan (NotifikasiPage)
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

  void _hardDisconnect({bool resetUnread = false}) {
    _reconnectTimer?.cancel();
    _wsSubscription?.cancel();
    _wsChannel?.sink.close();
    _isConnected = false;
    _connectedUserId = null;
    _reconnectAttempt = 0;
    if (resetUnread) hasUnread.value = false;
  }

  void disconnect() {
    _hardDisconnect(resetUnread: true);
    debugPrint('Reverb Service: disconnected.');
  }

  void markAsSeen() {
    hasUnread.value = false;
  }
}