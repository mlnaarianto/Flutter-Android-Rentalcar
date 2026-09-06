import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:rentalcar/config/api_config.dart';
import 'package:rentalcar/menu/notifikasi.dart'; // 👈 tambahan: halaman tujuan tap notifikasi
import 'package:rentalcar/utils/navigation_service.dart'; // 👈 tambahan: navigatorKey global

/// Service singleton untuk koneksi real-time ke Reverb.
///
/// Kenapa singleton? Karena Navbar dipakai berulang di banyak halaman —
/// kalau tiap halaman/instance Navbar buka koneksi WebSocket sendiri,
/// koneksi akan buka-tutup terus-menerus tiap kali pindah halaman.
/// Dengan singleton, koneksi dibuka SEKALI saat user login, lalu tetap
/// hidup sepanjang sesi app, dan seluruh halaman tinggal "dengarkan"
/// statusnya tanpa perlu buka koneksi baru.
///
/// 🟢 Strategi notifikasi (REVISI):
/// - Sumber kebenaran untuk "boleh tampil atau tidak" adalah
///   [_shouldShow], yang dedupe berdasarkan `notification_id`. Ini
///   dipakai baik di jalur WS maupun jalur FCM, jadi TIDAK PEDULI
///   keduanya sampai hampir bersamaan (race condition) -- yang kedua
///   akan otomatis di-skip karena id-nya sudah pernah ditampilkan.
///   Ini menggantikan strategi lama yang murni mengandalkan status
///   `_isConnected` sebagai penentu (rawan race & rawan "keduanya
///   sama-sama merasa berhak tampil" ATAU "keduanya sama-sama merasa
///   tidak perlu tampil").
/// - WS dipakai sebagai jalur utama SELAMA channel private-nya benar-benar
///   sudah "subscribed" (bukan sekadar socket terbuka -- lihat perbedaan
///   [_isSocketOpen] vs [_isSubscribed] di bawah).
/// - FCM foreground listener (`handleFcmMessage`) tetap jadi fallback:
///   ditampilkan kalau WS belum/tidak siap, DAN di-skip lewat dedupe id
///   kalau ternyata WS sempat lebih dulu menampilkannya.
/// - Selama app BACKGROUND (proses masih hidup), WS tetap terkoneksi
///   supaya badge/stream tetap update, tapi tidak menampilkan popup --
///   itu diserahkan ke background handler FCM di main.dart.
///
/// 🟢 Navigasi saat notifikasi di-tap:
/// - Local notification (dari WS/FCM foreground) -> ditangani lewat
///   `onDidReceiveNotificationResponse` di `_initLocalNotifications()`.
/// - FCM notification (background/killed) -> ditangani terpisah di
///   `main.dart` lewat `onMessageOpenedApp` & `getInitialMessage`.
/// Dua-duanya pakai `navigatorKey` yang sama supaya konsisten menuju
/// `NotifikasiPage`.
class NotificationSocketService {
  NotificationSocketService._internal() {
    _initLocalNotifications();

    // 🟢 Kalau token FCM device berubah (reinstall, clear data, dst),
    // sinkron ulang ke server supaya push tetap sampai.
    FirebaseMessaging.instance.onTokenRefresh.listen((newToken) async {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('access_token');
      if (token != null) {
        await _syncFcmToken(token);
      }
    });
  }

  static final NotificationSocketService _instance =
      NotificationSocketService._internal();
  factory NotificationSocketService() => _instance;

  WebSocketChannel? _wsChannel;
  StreamSubscription? _wsSubscription;
  String? _socketId;

  // 🟢 REVISI: dipecah jadi dua flag terpisah, karena "socket terbuka"
  // dan "channel private siap menerima event" adalah dua hal yang
  // BEDA WAKTU. Yang lama cuma pakai satu flag (_isConnected) yang
  // di-set true begitu WebSocketChannel.connect() dipanggil -- padahal
  // saat itu proses auth+subscribe ke channel private BELUM selesai,
  // sehingga ada jendela waktu di mana _isConnected sudah true tapi WS
  // belum benar-benar bisa terima event apa pun. Di jendela itu,
  // handleFcmMessage() akan salah mengira WS "aktif" dan membuang FCM,
  // padahal WS juga belum dengar apa-apa -> notifikasi hilang total.
  bool _isSocketOpen = false; // WebSocket sudah terbuka (raw connection)
  bool _isSubscribed = false; // channel private sudah confirmed subscribed

  /// WS dianggap "siap" jadi sumber notifikasi hanya kalau socket terbuka
  /// DAN subscription ke channel private sudah confirmed sukses.
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

  /// Dipertahankan untuk kompatibilitas kode lain yang mungkin sudah
  /// membaca `isConnected` (mis. UI indikator status). Sekarang artinya
  /// "WS benar-benar siap terima event", bukan sekadar socket terbuka.
  bool get isConnected => _wsReady;

  /// 🟢 REVISI: dedupe berbasis notification_id. Ini KUNCI supaya
  /// notifikasi yang sama tidak tampil dua kali walau datang dari dua
  /// jalur berbeda (WS + FCM) hampir bersamaan. Dipakai baik di
  /// `_handleMessage` (jalur WS) maupun `handleFcmMessage` (jalur FCM).
  ///
  /// Disimpan sebagai in-memory Set (bukan persisted) karena tujuannya
  /// cuma mencegah dobel dalam satu sesi app yang sedang berjalan --
  /// bukan riwayat baca/belum-baca (itu sudah ditangani server lewat
  /// field is_read).
  final Set<String> _shownNotificationIds = {};
  static const int _maxTrackedIds = 200;

  bool _shouldShow(dynamic notificationId) {
    if (notificationId == null) {
      // Tidak ada id untuk dedupe -> tetap tampilkan (fail-open), supaya
      // tidak ada notifikasi yang hilang gara-gara payload tidak lengkap.
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

  /// 🟢 Status apakah app sedang di foreground atau tidak.
  /// Di-set dari main.dart lewat WidgetsBindingObserver.
  /// Dipakai supaya WS tidak menampilkan notifikasi sendiri saat app
  /// di background -- biar OS yang otomatis tampilkan dari payload FCM
  /// (hindari dobel notifikasi), sementara WS tetap hidup untuk update
  /// badge/stream data secara real-time.
  ///
  /// CATATAN: sengaja HANYA di-set false untuk AppLifecycleState.paused
  /// / hidden / detached di main.dart, TIDAK untuk `inactive`. State
  /// `inactive` bisa terpicu saat app masih kelihatan tapi sedang
  /// diinterupsi sesaat (notification shade ditarik, dialog sistem,
  /// incoming call overlay) -- kalau ikut dianggap "background" di
  /// situ, notifikasi yang masuk tepat di momen itu bisa tidak
  /// ditampilkan oleh WS maupun FCM foreground listener.
  bool _isAppInForeground = true;
  set isAppInForeground(bool value) {
    _isAppInForeground = value;
  }

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

        // 🟢 Arahkan ke NotifikasiPage saat local notification (dari WS)
        // di-tap.
        //
        // CATATAN: sengaja TIDAK dibungkus addPostFrameCallback di sini.
        // Callback ini terpanggil saat app sudah berjalan normal (bukan
        // saat cold-start seperti kasus FCM getInitialMessage), jadi
        // tidak ada frame baru yang otomatis di-schedule -- akibatnya
        // addPostFrameCallback tidak pernah terpanggil dan push() gagal
        // diam-diam. Push langsung di sini aman karena navigatorKey
        // hampir selalu sudah siap; kalau pun belum, _navigateToNotifikasi
        // akan retry singkat.
        _navigateToNotifikasi();
      },
    );

    // Android 13+ (API 33) mewajibkan izin runtime untuk menampilkan
    // notifikasi sistem. Tanpa ini, show() akan gagal diam-diam
    // (tidak ada error, tapi notifikasi tidak pernah muncul).
    //
    // CATATAN: sengaja TIDAK ditulis pakai syntax generic eksplisit
    // resolvePlatformSpecificImplementation<Tipe>() — karena tipe di
    // dalam kurung siku itu berulang kali hilang saat disalin.
    // Solusinya: deklarasikan tipe variabelnya, biar Dart infer sendiri
    // argumen generic-nya dari situ, tanpa perlu menulis tanda < >.
    final AndroidFlutterLocalNotificationsPlugin? androidImplementation =
        _localNotificationsPlugin.resolvePlatformSpecificImplementation();
    await androidImplementation?.requestNotificationsPermission();
  }

  /// 🟢 Navigasi ke NotifikasiPage, dipanggil saat local notification
  /// (dari WS) di-tap.
  ///
  /// Kalau `navigatorKey.currentState` masih null (jarang terjadi,
  /// misalnya app baru saja resume dari background dan widget tree
  /// belum sempat ter-attach), coba lagi tiap 100ms sampai maksimal
  /// 5 kali (~500ms) sebelum menyerah.
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

  /// 🟢 Kirim/update token FCM device ini ke server, supaya backend
  /// bisa kirim push notification lewat Firebase saat WS tidak aktif.
  /// Endpoint disesuaikan dengan routes/api.php: POST /api/fcm-token.
  Future<void> _syncFcmToken(String token) async {
    try {
      final fcmToken = await FirebaseMessaging.instance.getToken();
      if (fcmToken == null) {
        debugPrint('Reverb Service: FCM token belum tersedia, skip sync.');
        return;
      }

      final response = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/fcm-token'),
        headers: {
          'Authorization': 'Bearer $token',
          'Accept': 'application/json',
        },
        body: {'fcm_token': fcmToken},
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

  Future<void> connect() async {
    // 🟢 Guard: kalau sudah siap penuh (socket terbuka + subscribed)
    // untuk user yang sama, tidak perlu connect ulang. Sebelumnya
    // pengecekan ini pakai _isConnected yang di-set optimistik di awal
    // proses connect -- sekarang pakai _wsReady supaya lebih akurat.
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
    } else if (_wsReady) {
      debugPrint('Reverb Service: sudah terkoneksi & subscribed untuk user ini, skip.');
      return;
    } else if (_isSocketOpen && !isUserSwitch) {
      // Socket masih terbuka tapi belum subscribed (mis. proses auth
      // masih berjalan) -- jangan buka koneksi baru, biarkan proses
      // subscribe yang sedang berjalan menyelesaikan dirinya sendiri.
      debugPrint('Reverb Service: socket masih terbuka & menunggu subscribe, skip.');
      return;
    }

    _isConnecting = true;

    final isFirstConnectForUser = _connectedUserId != userId;
    if (isFirstConnectForUser) {
      await _checkInitialUnreadStatus(token);
    }

    // 🟢 Pastikan server selalu punya FCM token terbaru device ini,
    // supaya fallback push bisa jalan kapan pun WS putus/app background.
    await _syncFcmToken(token);

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
      _isSocketOpen = true;
      _isSubscribed = false; // 👈 penting: belum subscribed sampai confirmed
      _connectedUserId = userId;
      _reconnectAttempt = 0;

      _wsSubscription = _wsChannel!.stream.listen(
        (raw) => _handleMessage(raw, userId, token, apiUri),
        onError: (e) {
          debugPrint('Reverb Service: WS error: $e');
          _isSocketOpen = false;
          _isSubscribed = false;
          _scheduleReconnect();
        },
        onDone: () {
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
    } finally {
      _isConnecting = false;
    }
  }

  bool _isConnecting = false;

  void _scheduleReconnect() {
    _reconnectTimer?.cancel();

    final idx = _reconnectAttempt.clamp(0, _backoffSeconds.length - 1);
    final delay = Duration(seconds: _backoffSeconds[idx]);
    _reconnectAttempt++;

    debugPrint('Reverb Service: reconnect dalam ${delay.inSeconds}s...');
    _reconnectTimer = Timer(delay, () {
      if (!_wsReady) connect();
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

      // 🟢 BARU: konfirmasi subscribe sukses. Baru dari titik ini WS
      // benar-benar dianggap siap jadi sumber notifikasi (_wsReady).
      // Nama event bisa "pusher:subscription_succeeded" (protokol umum)
      // -- dijaga longgar dengan endsWith supaya tidak pecah kalau
      // Reverb mengirim varian namespace-nya.
      if (event != null &&
          event.toString().contains('subscription_succeeded')) {
        _isSubscribed = true;
        debugPrint('Reverb Service: subscribed ke channel notifications.$userId');
        return;
      }

      // 🟢 BARU: kalau subscribe gagal, jangan biarkan _isSubscribed
      // tetap false diam-diam tanpa penjelasan -- log & coba reconnect,
      // supaya tidak ada sesi yang "kelihatan konek" padahal channel-nya
      // tidak pernah aktif.
      if (event != null && event.toString().contains('subscription_error')) {
        debugPrint('Reverb Service: subscribe GAGAL: ${msg['data']}');
        _isSubscribed = false;
        _scheduleReconnect();
        return;
      }

      if (event == '.notification.created' || event == 'notification.created') {
        final payload = jsonDecode(msg['data']);
        final newNotif = payload['data'];

        // Badge navbar langsung menyala -- ini tetap jalan baik
        // foreground maupun background, karena cuma update state,
        // bukan menampilkan sesuatu ke user.
        hasUnread.value = true;

        // 🟢 REVISI: dedupe dulu berdasarkan notification_id SEBELUM
        // memutuskan tampil atau tidak. Ini independen dari status
        // foreground/background & independen dari FCM -- jadi walau
        // FCM juga mencoba menampilkan notifikasi yang sama, salah
        // satu (siapa pun yang lebih dulu) akan menang dan yang kedua
        // otomatis di-skip.
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

        // Teruskan ke halaman yang sedang aktif mendengarkan (NotifikasiPage)
        _newNotificationController.add(newNotif);
      }
    } catch (e) {
      debugPrint('Reverb Service: gagal parse pesan: $e');
    }
  }

  /// 🟢 Dipanggil dari main.dart (FirebaseMessaging.onMessage) tiap ada
  /// pesan FCM masuk selagi app foreground.
  ///
  /// REVISI: sebelumnya cuma dicek `_isConnected` (yang di-set optimistik
  /// begitu socket dibuka, walau channel private belum tentu subscribed).
  /// Sekarang dicek `_wsReady` (socket terbuka DAN subscribed), DAN tetap
  /// di-dedupe lewat `_shouldShow` berdasarkan notification_id -- supaya
  /// walau kondisi timing pas-pasan (mis. WS baru saja subscribed detik
  /// itu juga dan sempat menampilkan notifikasi yang sama), FCM tidak
  /// ikut menampilkannya dobel.
  void handleFcmMessage(RemoteMessage message) {
    final data = message.data;
    final notifId = data['notification_id'];

    if (_wsReady) {
      debugPrint('Reverb Service: WS siap & subscribed, abaikan FCM (hindari duplikat).');
      return;
    }

    if (!_shouldShow(notifId)) {
      // Sudah pernah ditampilkan (kemungkinan besar oleh WS tepat
      // sebelum ini, atau oleh panggilan FCM lain yang duplikat).
      return;
    }

    final title = message.notification?.title ??
        data['title'] ??
        'Informasi Rental';
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
        // 🟢 BARU: sebelumnya di sini diam saja, dan _isConnected (lama)
        // sudah kadung true -- jadi sesi ini akan tampak "konek" padahal
        // channel-nya tidak akan pernah aktif sampai reconnect manual.
        // Sekarang dipicu reconnect supaya percobaan berikutnya bisa
        // memperbaiki dirinya sendiri.
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

      // Catatan: _isSubscribed baru di-set true saat menerima event
      // "pusher:subscription_succeeded" balik dari server (lihat
      // _handleMessage), BUKAN di sini -- supaya benar-benar
      // dikonfirmasi server, bukan diasumsikan sepihak dari klien.
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

  /// 🟢 Dipanggil saat app benar-benar ditutup/di-swipe (bukan sekadar
  /// diminimize). WebSocket ditutup untuk hemat resource, tapi
  /// `_connectedUserId` TIDAK direset — supaya reconnect saat app dibuka
  /// lagi bisa lebih cepat.
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