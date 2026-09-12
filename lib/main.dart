import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:rentalcar/menu/dashboard.dart';
import 'package:rentalcar/pages/login.dart';
import 'package:rentalcar/menu/notifikasi.dart';
import 'package:rentalcar/services/notification_socket_service.dart';
import 'package:rentalcar/utils/navigation_service.dart'; // 👈 satu-satunya sumber navigatorKey
import 'firebase_options.dart';
// 🟢 DIHAPUS: import app_notifier.dart tidak diperlukan di sini lagi.
// scaffoldMessengerKey sudah tidak dipakai karena AppNotifier sekarang
// pakai QuickAlert (butuh BuildContext lewat navigatorKey), bukan SnackBar.

// 🟢 Top-level function wajib untuk menangkap pesan FCM saat app di background/killed
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  debugPrint("Handling a background message: ${message.messageId}");

  // 🟢 DIPERBAIKI: sebelumnya di sini kosong (mengandalkan Android
  // auto-tampilkan dari payload "notification"). Sekarang backend
  // mengirim FCM data-only (lihat SendPushNotification.php di Laravel),
  // jadi Android TIDAK akan menampilkan apa pun secara otomatis lagi --
  // kita WAJIB tampilkan sendiri secara manual di sini.
  //
  // Ini penting untuk MENGHILANGKAN NOTIFIKASI DOBEL: sebelumnya Android
  // auto-tampilkan dari payload "notification" DAN kode kita juga
  // menampilkan lewat WebSocket -- makanya muncul 2x. Sekarang hanya
  // satu jalur yang aktif per kondisi app (lihat tabel di penjelasan).
  //
  // Catatan: fungsi ini berjalan di ISOLATE TERPISAH dari main.dart,
  // jadi instance FlutterLocalNotificationsPlugin harus dibuat baru di
  // sini, tidak bisa memakai instance dari NotificationSocketService.
  //
  // Catatan tambahan: isolate ini TIDAK bisa mengakses Set dedupe
  // in-memory milik NotificationSocketService (beda isolate = beda
  // memori). Jadi kalau ke depannya ingin dedupe id notifikasi juga di
  // jalur background-killed ini (mis. mencegah dobel dengan popup yang
  // sempat tampil dari WS tepat sebelum app di-kill), perlu disimpan
  // ke SharedPreferences, bukan variabel in-memory biasa.
  try {
    final title = message.data['title'] ?? 'Informasi Rental';
    final body = message.data['message'] ?? 'Anda memiliki aktivitas baru.';

    final plugin = FlutterLocalNotificationsPlugin();

    const AndroidInitializationSettings androidInit =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const InitializationSettings initSettings =
        InitializationSettings(android: androidInit);

    await plugin.initialize(settings: initSettings);

    const AndroidNotificationDetails androidDetails =
        AndroidNotificationDetails(
      'rental_car_channel_id',
      'Aktivitas Rental',
      channelDescription:
          'Notifikasi status pesanan dan aktivitas rental mobil',
      importance: Importance.max,
      priority: Priority.high,
    );

    const NotificationDetails notifDetails =
        NotificationDetails(android: androidDetails);

    await plugin.show(
      id: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title: title,
      body: body,
      notificationDetails: notifDetails,
    );
  } catch (e) {
    debugPrint("Gagal tampilkan notifikasi background: $e");
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 1. Inisialisasi Firebase
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } catch (e) {
    debugPrint("Firebase init error: $e");
  }

  // Daftarkan background handler FCM
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  // 🟢 Matikan banner native OS saat foreground (utamanya berefek di iOS).
  // Kita yang kontrol tampilan sendiri lewat listener onMessage di bawah,
  // supaya bisa dicek dulu status WebSocket-nya (hindari notifikasi dobel).
  try {
    await FirebaseMessaging.instance.setForegroundNotificationPresentationOptions(
      alert: false,
      badge: true,
      sound: false,
    );
  } catch (e) {
    debugPrint("Foreground presentation options error: $e");
  }

  // 🟢 Fallback FCM saat app foreground.
  // handleFcmMessage() sendiri yang memutuskan tampil/tidak berdasarkan
  // status WebSocket (WS ready + dedupe berdasarkan notification_id --
  // lihat NotificationSocketService.handleFcmMessage()).
  // Sejak backend kirim data-only message, field message.notification
  // akan selalu null -- handleFcmMessage() sudah punya fallback ke
  // message.data untuk kasus ini, jadi tidak perlu diubah.
  FirebaseMessaging.onMessage.listen((RemoteMessage message) {
    NotificationSocketService().handleFcmMessage(message);
  });

  // 2. Cek apakah token login sudah ada di SharedPreferences
  final prefs = await SharedPreferences.getInstance();
  final String? token = prefs.getString('access_token');

  // 3. Tentukan halaman awal berdasarkan status token
  final Widget initialScreen = (token != null && token.isNotEmpty)
      ? const Dashboard()
      : const LoginPage();

  // 🟢 Kalau sesi lama masih ada (app dibuka ulang tanpa login baru),
  // langsung sambungkan WebSocket dari sini.
  if (token != null && token.isNotEmpty) {
    NotificationSocketService().connect();
  }

  // Kalau app dibuka dari kondisi tertutup total dengan cara men-tap notifikasi FCM
  final RemoteMessage? initialMessage =
      await FirebaseMessaging.instance.getInitialMessage();

  if (initialMessage != null) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      navigatorKey.currentState?.push(
        MaterialPageRoute(builder: (_) => const NotifikasiPage()),
      );
    });
  }

  // Kalau app sedang berjalan di background lalu user men-tap notifikasi FCM
  //
  // 🟡 FIX: dibungkus addPostFrameCallback supaya navigasi ditunda sampai
  // frame build Flutter yang sedang berjalan selesai. Tanpa ini, kalau
  // event ini tiba persis saat Flutter lagi di tengah proses build
  // (misalnya saat app baru resume dari background), push() bisa memicu
  // "setState() or markNeedsBuild() called during build" exception.
  // Pola ini disamakan dengan handler initialMessage di atas.
  FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
    debugPrint('FCM: notifikasi di-tap, app dibuka dari background.');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      navigatorKey.currentState?.push(
        MaterialPageRoute(builder: (_) => const NotifikasiPage()),
      );
    });
  });

  runApp(MyApp(initialScreen: initialScreen));
}

class MyApp extends StatefulWidget {
  final Widget initialScreen;
  const MyApp({super.key, required this.initialScreen});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        // 🟢 App kembali ke foreground. Tandai foreground, dan pastikan
        // WS konek (kalau memang sempat putus, connect() reconnect di
        // sini; kalau masih hidup, otomatis skip).
        NotificationSocketService().isAppInForeground = true;
        NotificationSocketService().connect();
        break;

      case AppLifecycleState.inactive:
        // 🟢 REVISI: `inactive` SENGAJA dipisah dari paused/hidden dan
        // TIDAK ikut mematikan flag foreground.
        //
        // `inactive` bisa terpicu saat app masih kelihatan di layar tapi
        // sedang diinterupsi SESAAT -- notification shade ditarik turun,
        // dialog izin sistem muncul, incoming call overlay, app switcher
        // di-buka sekilas, dll (terutama sering di iOS, tapi juga bisa
        // di Android). App belum benar-benar pindah ke background.
        //
        // Sebelumnya `inactive` disatukan dengan `paused`/`hidden`,
        // sehingga kalau ada notifikasi masuk PERSIS saat interupsi
        // sesaat ini terjadi, WS mengira app sedang di background dan
        // sengaja TIDAK menampilkan popup (diserahkan ke FCM) -- padahal
        // FCM foreground listener sendiri belum tentu ikut ter-skip
        // dengan rapi di momen transisi seperti ini. Hasilnya notifikasi
        // bisa hilang tanpa muncul dari jalur manapun.
        //
        // Dengan `inactive` dibiarkan tidak mengubah apa-apa, flag
        // foreground tetap seperti kondisi sebelumnya (biasanya masih
        // `true`), sehingga WS tetap berhak menampilkan popup seperti
        // biasa selama interupsi sesaat itu.
        debugPrint('App inactive (interupsi sesaat) - status foreground tidak diubah.');
        break;

      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
        // 🟢 App ke background (proses masih hidup, cuma menggantung di
        // recent apps). WS TETAP dibiarkan jalan (tidak di-pause) supaya
        // badge/stream tetap real-time. Tapi ditandai "bukan foreground"
        // supaya WS berhenti menampilkan pop-up-nya sendiri -- biar FCM
        // (yang otomatis tampil dari OS) jadi satu-satunya yang muncul,
        // hindari notifikasi dobel.
        NotificationSocketService().isAppInForeground = false;
        debugPrint(
            'App ke background (proses masih hidup) - WS tetap jalan, tampilan diserahkan ke FCM.');
        break;

      case AppLifecycleState.detached:
        // App benar-benar di-swipe/ditutup dari recent apps. Callback
        // ini kadang tidak sempat terpicu reliable (proses bisa langsung
        // mati duluan), tapi kalau sempat, aman untuk bersih-bersih WS
        // di sini. Kalau tidak sempat pun tidak masalah -- WS otomatis
        // mati sendiri begitu proses hilang, dan FCM background handler
        // yang berjalan independen di level OS yang ambil alih.
        NotificationSocketService().isAppInForeground = false;
        NotificationSocketService().pause();
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey, // 🟢 satu-satunya key, dari navigation_service.dart
      // 🟢 DIHAPUS: scaffoldMessengerKey — sudah tidak dipakai karena
      // AppNotifier sekarang pakai QuickAlert (dialog, butuh BuildContext
      // via navigatorKey), bukan SnackBar (yang butuh ScaffoldMessengerKey).
      debugShowCheckedModeBanner: false,
      title: 'Rental Car',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
      ),
      home: widget.initialScreen,
    );
  }
}