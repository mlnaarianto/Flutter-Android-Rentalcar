import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:rentalcar/config/api_config.dart';
import 'package:rentalcar/services/notification_socket_service.dart'; // 🟢 TAMBAHAN

class NotifikasiPage extends StatefulWidget {
  const NotifikasiPage({super.key});

  @override
  State<NotifikasiPage> createState() => _NotifikasiPageState();
}

class _NotifikasiPageState extends State<NotifikasiPage> {
  List<dynamic> _notifications = [];
  bool _isLoading = true;
  String? _errorMessage;

  // 🟢 TAMBAHAN: koneksi real-time ke Reverb
  WebSocketChannel? _wsChannel;
  StreamSubscription? _wsSubscription;
  String? _socketId;
  bool _isSubscribed = false;

  // ================= WARNA SENADA DENGAN HALAMAN LAIN =================
  static const Color _primaryColor = Color(0xFF2563EB);
  static const Color _accentColor = Color(0xFFF97316);
  static const Color _bgColor = Color(0xFFF4F6F9);
  static const Color _successColor = Color(0xFF16A34A);
  static const Color _dangerColor = Color(0xFFDC2626);
  static const Color _indigoColor = Color(0xFF6366F1);

  @override
  void initState() {
    super.initState();

    // 🟢 TAMBAHAN: begitu halaman ini dibuka, badge merah di Navbar
    // langsung dipadamkan — sinkron dengan _markNotificationsAsRead()
    // di bawah yang menandai read-all ke backend. Tanpa baris ini,
    // badge cuma akan update setelah event WebSocket BARU masuk, bukan
    // langsung padam saat user "melihat" halaman ini.
    NotificationSocketService().markAsSeen();

    _fetchNotifications();
    _markNotificationsAsRead(); // 🟢 Otomatis tandai sudah dibaca saat halaman dibuka
    _connectRealtime(); // 🟢 TAMBAHAN: mulai koneksi websocket Reverb
  }

  @override
  void dispose() {
    // 🟢 TAMBAHAN: tutup koneksi websocket saat halaman ditutup, supaya
    // tidak ada listener yang numpuk / nyala di background sia-sia.
    _wsSubscription?.cancel();
    _wsChannel?.sink.close();
    super.dispose();
  }

  /// ================= AMBIL DATA NOTIFIKASI =================
  Future<void> _fetchNotifications() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('access_token');

      if (token == null) {
        setState(() {
          _errorMessage = 'Sesi habis. Silakan login kembali.';
          _isLoading = false;
        });
        return;
      }

      final response = await http.get(
        Uri.parse('${ApiConfig.baseUrl}/notifications'),
        headers: {
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        setState(() {
          _notifications = decoded['data'] ?? [];
          _isLoading = false;
        });
      } else {
        setState(() {
          _errorMessage = 'Gagal memuat notifikasi (Kode: ${response.statusCode})';
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Terjadi kesalahan koneksi ke server: $e';
        _isLoading = false;
      });
    }
  }

  /// ================= TANDAI SUDAH DIBACA KE BACKEND =================
  Future<void> _markNotificationsAsRead() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('access_token');

      if (token == null) return;

      // Panggil endpoint Laravel untuk mengubah is_read menjadi true di database
      await http.post(
        Uri.parse('${ApiConfig.baseUrl}/notifications/read-all'),
        headers: {
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      // Simpan juga status lokal jika diperlukan
      await prefs.setBool('has_unread_notifications', false);
    } catch (_) {
      // Abaikan jika gagal agar tidak mengganggu UI
    }
  }

  // ================= 🟢 TAMBAHAN: REALTIME VIA REVERB =================

  Future<String?> _getCurrentUserId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('user_id');
  }

  Future<void> _connectRealtime() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('access_token');
      final userId = await _getCurrentUserId();

      // 🟢 DEBUG: pastikan token & userId benar-benar ada sebelum lanjut
      debugPrint(
          'Reverb DEBUG -> token: ${token != null ? "ADA" : "NULL ❌"}, userId: ${userId ?? "NULL ❌"}');

      if (token == null || userId == null) {
        debugPrint('Reverb: token atau userId belum tersedia, skip koneksi realtime.');
        return;
      }

      // Ambil host dari ApiConfig.baseUrl (misal http://192.168.x.x:8000/api)
      // supaya host Reverb selalu konsisten dengan host API yang sudah
      // terbukti bisa diakses dari device/emulator ini — tidak hardcode
      // IP terpisah yang bisa beda-beda per environment.
      final apiUri = Uri.parse(ApiConfig.baseUrl);

      // 👉 SESUAIKAN kalau port/scheme Reverb kamu beda dari default ini.
      const reverbPort = 9090;
      const reverbAppKey = '27d6a6d4761caf333da8';
      const useTLS = false; // true kalau REVERB_SCHEME=https di production

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

      // 🟢 DEBUG: tampilkan alamat websocket yang dituju
      debugPrint('Reverb DEBUG -> Mencoba connect ke: $wsUri');

      _wsChannel = WebSocketChannel.connect(wsUri);

      _wsSubscription = _wsChannel!.stream.listen(
        (raw) {
          // 🟢 DEBUG: tampilkan setiap pesan mentah yang masuk dari server
          debugPrint('Reverb DEBUG -> Pesan masuk: $raw');
          _handleSocketMessage(raw, userId, token, apiUri);
        },
        onError: (e) => debugPrint('Reverb WS error: $e'),
        onDone: () {
          debugPrint('Reverb WS closed.');
          _isSubscribed = false;
        },
      );
    } catch (e) {
      debugPrint('Gagal konek realtime Reverb: $e');
    }
  }

  void _handleSocketMessage(
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
        debugPrint('Reverb DEBUG -> Koneksi established, socket_id: $_socketId');
        await _subscribeToChannel(userId, token, apiUri);
        return;
      }

      // 🟢 DEBUG: konfirmasi subscribe channel berhasil di-ack server
      if (event == 'pusher_internal:subscription_succeeded' ||
          event == 'pusher:subscription_succeeded') {
        debugPrint('Reverb DEBUG -> ✅ Berhasil subscribe ke channel privat!');
        return;
      }

      // Nama event broadcastAs() di backend adalah 'notification.created',
      // tapi channel privat mengirimnya dengan titik di depan.
      if (event == '.notification.created' || event == 'notification.created') {
        final payload = jsonDecode(msg['data']);
        final newNotif = payload['data'];

        debugPrint('Reverb DEBUG -> 🔔 Notifikasi baru diterima: ${newNotif['title']}');

        // 🟢 TAMBAHAN: notifikasi masuk SAAT halaman ini terbuka —
        // pastikan badge tetap padam (bukannya nyala lagi gara-gara
        // event baru), karena user memang sedang melihat halaman ini.
        NotificationSocketService().markAsSeen();

        if (!mounted) return;
        setState(() {
          // 🟢 Guard anti-duplikat, sama seperti fix di versi React.
          final alreadyExists =
              _notifications.any((n) => n['id'] == newNotif['id']);
          if (!alreadyExists) {
            _notifications.insert(0, newNotif);
          }
        });
      }
    } catch (e) {
      debugPrint('Gagal parse pesan Reverb: $e');
    }
  }

  Future<void> _subscribeToChannel(
    String userId,
    String token,
    Uri apiUri,
  ) async {
    if (_socketId == null) return;

    final channelName = 'private-notifications.$userId';

    // Endpoint auth broadcasting ada di ROOT domain (bukan di bawah /api),
    // sama persis seperti route default Laravel Broadcast::routes().
    final authUrl = Uri(
      scheme: apiUri.scheme,
      host: apiUri.host,
      port: apiUri.hasPort ? apiUri.port : null,
      path: '/broadcasting/auth',
    );

    // 🟢 DEBUG: tampilkan channel & URL auth yang akan dipanggil
    debugPrint('Reverb DEBUG -> Subscribe channel: $channelName');
    debugPrint('Reverb DEBUG -> Auth URL: $authUrl');

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

      // 🟢 DEBUG: tampilkan hasil response auth apapun hasilnya
      debugPrint(
          'Reverb DEBUG -> Auth response (${authResponse.statusCode}): ${authResponse.body}');

      if (authResponse.statusCode != 200) {
        debugPrint(
            'Broadcasting auth gagal (${authResponse.statusCode}): ${authResponse.body}');
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

      _isSubscribed = true;
    } catch (e) {
      debugPrint('Gagal subscribe channel Reverb: $e');
    }
  }

  // ================= END TAMBAHAN REALTIME =================

  IconData _getNotifIcon(String? type) {
    switch (type) {
      case 'booking':
        return Icons.bookmark_added_rounded;
      case 'payment':
        return Icons.payments_rounded;
      case 'driver_assignment':
        return Icons.person_pin_circle_rounded;
      case 'booking_cancelled':
        return Icons.cancel_rounded;
      default:
        return Icons.notifications_active_rounded;
    }
  }

  Color _getNotifColor(String? type) {
    switch (type) {
      case 'booking':
        return _primaryColor;
      case 'payment':
        return _successColor;
      case 'driver_assignment':
        return _accentColor;
      case 'booking_cancelled':
        return _dangerColor;
      default:
        return _indigoColor;
    }
  }

  /// Format tanggal jadi lebih ramah dibaca, mis. "29 Agu 2026"
  String _formatDate(dynamic rawDate) {
    if (rawDate == null) return '';
    try {
      final date = DateTime.parse(rawDate.toString()).toLocal();
      const months = [
        'Jan', 'Feb', 'Mar', 'Apr', 'Mei', 'Jun',
        'Jul', 'Agu', 'Sep', 'Okt', 'Nov', 'Des'
      ];
      return '${date.day} ${months[date.month - 1]} ${date.year}';
    } catch (_) {
      return rawDate.toString().split('T').first;
    }
  }

  String _formatTime(dynamic rawDate) {
    if (rawDate == null) return '';
    try {
      final date = DateTime.parse(rawDate.toString()).toLocal();
      final hh = date.hour.toString().padLeft(2, '0');
      final mm = date.minute.toString().padLeft(2, '0');
      return '$hh:$mm';
    } catch (_) {
      return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bgColor,
      appBar: AppBar(
        title: const Text(
          'Notifikasi Aktivitas',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
        ),
        centerTitle: false,
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF1E293B),
        elevation: 0,
        surfaceTintColor: Colors.white,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: Colors.grey.shade200),
        ),
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: _primaryColor))
          : _errorMessage != null
              ? _buildErrorState()
              : _notifications.isEmpty
                  ? _buildEmptyState()
                  : RefreshIndicator(
                      color: _primaryColor,
                      onRefresh: _fetchNotifications,
                      child: ListView.builder(
                        physics: const AlwaysScrollableScrollPhysics(),
                        itemCount: _notifications.length,
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                        itemBuilder: (context, index) {
                          final notif = _notifications[index];
                          return _buildNotifCard(notif);
                        },
                      ),
                    ),
    );
  }

  /// ================= STATE: ERROR =================
  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: _dangerColor.withOpacity(0.08),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.error_outline_rounded,
                  size: 40, color: _dangerColor),
            ),
            const SizedBox(height: 16),
            Text(
              _errorMessage!,
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade700, fontSize: 14),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: _fetchNotifications,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Coba Lagi'),
              style: ElevatedButton.styleFrom(
                backgroundColor: _primaryColor,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// ================= STATE: EMPTY =================
  Widget _buildEmptyState() {
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: _primaryColor.withOpacity(0.08),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.notifications_off_outlined,
                        size: 40, color: _primaryColor.withOpacity(0.6)),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'Belum ada notifikasi kejadian.',
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Aktivitas terbaru seputar pesanan Anda akan\nmuncul di sini.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey.shade400, fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  /// ================= KARTU NOTIFIKASI =================
  Widget _buildNotifCard(dynamic notif) {
    final String? type = notif['type'];
    final Color notifColor = _getNotifColor(type);
    final bool isUnread = notif['is_read'] == false;
    final String createdAt = notif['created_at']?.toString() ?? '';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: isUnread ? _primaryColor.withOpacity(0.045) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: isUnread
            ? Border.all(color: _primaryColor.withOpacity(0.15))
            : null,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: notifColor.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(_getNotifIcon(type), color: notifColor, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          notif['title'] ?? 'Informasi',
                          style: TextStyle(
                            fontWeight:
                                isUnread ? FontWeight.bold : FontWeight.w600,
                            fontSize: 13.5,
                            color: const Color(0xFF1E293B),
                          ),
                        ),
                      ),
                      if (isUnread) ...[
                        const SizedBox(width: 8),
                        Container(
                          width: 8,
                          height: 8,
                          margin: const EdgeInsets.only(top: 4),
                          decoration: const BoxDecoration(
                            color: _accentColor,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    notif['message'] ?? '',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade600,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(Icons.schedule_rounded,
                          size: 11.5, color: Colors.grey.shade400),
                      const SizedBox(width: 3),
                      Text(
                        [
                          _formatDate(createdAt),
                          if (_formatTime(createdAt).isNotEmpty)
                            _formatTime(createdAt),
                        ].where((e) => e.isNotEmpty).join(' • '),
                        style: TextStyle(
                            fontSize: 10.5, color: Colors.grey.shade500),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}