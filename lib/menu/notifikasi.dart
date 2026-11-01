import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:rentalcar/config/api_config.dart';
import 'package:rentalcar/services/api_client.dart';
import 'package:rentalcar/services/notification_socket_service.dart';

class NotifikasiPage extends StatefulWidget {
  const NotifikasiPage({super.key});

  @override
  State<NotifikasiPage> createState() => _NotifikasiPageState();
}

class _NotifikasiPageState extends State<NotifikasiPage> {
  List<dynamic> _notifications = [];
  bool _isLoading = true;
  String? _errorMessage;

  // Tidak lagi bikin WebSocketChannel sendiri. Cukup dengarkan stream
  // dari service singleton yang sudah hidup sejak login — jadi cuma
  // ADA SATU koneksi WebSocket untuk seluruh app.
  StreamSubscription<Map<String, dynamic>>? _notifSubscription;

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

    // Begitu halaman ini dibuka, badge merah di Navbar langsung padam
    // secara visual. Ini terpisah dari status "is_read" di backend —
    // yang itu ditangani & dikonfirmasi lewat _markNotificationsAsRead().
    NotificationSocketService().markAsSeen();

    _fetchNotifications();
    _markNotificationsAsRead(); // Tandai sudah dibaca ke backend (dengan retry)

    // Dengarkan notifikasi baru dari service singleton, bukan bikin
    // koneksi WebSocket baru.
    _notifSubscription =
        NotificationSocketService().onNewNotification.listen((newNotif) {
      debugPrint(
          'NotifikasiPage: 🔔 notifikasi baru diterima: ${newNotif['title']}');

      // Notifikasi masuk SAAT halaman ini terbuka — badge tetap padam
      // karena user memang sedang melihat halaman ini secara langsung.
      NotificationSocketService().markAsSeen();

      if (!mounted) return;
      setState(() {
        final alreadyExists =
            _notifications.any((n) => n['id'] == newNotif['id']);
        if (!alreadyExists) {
          _notifications.insert(0, newNotif);
        }
      });

      // 🟢 Notifikasi baru yang masuk saat halaman ini terbuka juga
      // perlu ditandai read ke backend, supaya tidak numpuk jadi unread
      // lagi saat halaman dibuka ulang nanti.
      _markNotificationsAsRead();
    });
  }

  @override
  void dispose() {
    // Cukup batalkan LANGGANAN ke stream — tidak menutup koneksi
    // WebSocket apapun, karena koneksinya memang bukan milik halaman
    // ini. Koneksi service tetap hidup di background seperti biasa.
    _notifSubscription?.cancel();
    super.dispose();
  }

  /// ================= AMBIL DATA NOTIFIKASI =================
  /// Token dipasang dan di-refresh otomatis oleh ApiClient. Kalau sesi
  /// benar-benar mati, onSessionExpired di main.dart yang mengarahkan ke login.
  Future<void> _fetchNotifications() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final response = await ApiClient.instance.get(
        Uri.parse('${ApiConfig.baseUrl}/notifications'),
      );

      if (!mounted) return;

      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        setState(() {
          _notifications = decoded['data'] ?? [];
          _isLoading = false;
        });
      } else if (response.statusCode == 401) {
        setState(() {
          _errorMessage = 'Sesi habis. Silakan login kembali.';
          _isLoading = false;
        });
      } else {
        setState(() {
          _errorMessage =
              'Gagal memuat notifikasi (Kode: ${response.statusCode})';
          _isLoading = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Terjadi kesalahan koneksi ke server: $e';
        _isLoading = false;
      });
    }
  }

  /// ================= TANDAI SUDAH DIBACA KE BACKEND =================
  Future<void> _markNotificationsAsRead({int attempt = 0}) async {
    try {
      final response = await ApiClient.instance.post(
        Uri.parse('${ApiConfig.baseUrl}/notifications/read-all'),
      );

      if (response.statusCode == 200) {
        // prefs tetap dipakai di sini untuk flag non-sensitif (bukan token).
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('has_unread_notifications', false);

        if (mounted) {
          setState(() {
            for (final n in _notifications) {
              if (n is Map) n['is_read'] = true;
            }
          });
        }
      } else if (response.statusCode == 401) {
        // Sesi sudah mati (refresh juga ditolak). onSessionExpired yang
        // mengurus pindah ke login, jadi tidak perlu di-retry.
        debugPrint('NotifikasiPage: read-all 401, sesi berakhir, tidak di-retry.');
      } else {
        debugPrint(
            'NotifikasiPage: read-all gagal (${response.statusCode}), attempt=$attempt');
        _retryMarkAsRead(attempt);
      }
    } catch (e) {
      debugPrint('NotifikasiPage: read-all error: $e, attempt=$attempt');
      _retryMarkAsRead(attempt);
    }
  }

  void _retryMarkAsRead(int attempt) {
    const maxAttempts = 3;
    if (attempt >= maxAttempts) {
      debugPrint(
          'NotifikasiPage: read-all menyerah setelah $maxAttempts percobaan.');
      return;
    }
    final delay = Duration(seconds: 2 * (attempt + 1)); // 2s, 4s, 6s
    Timer(delay, () {
      if (mounted) _markNotificationsAsRead(attempt: attempt + 1);
    });
  }

  /// ================= 🟢 HAPUS SATU NOTIFIKASI =================
  Future<void> _deleteSingleNotification(int index) async {
    final deletedNotif = _notifications[index];
    final notifId = deletedNotif['id'];

    // 1. Optimistic UI update: Hapus dulu dari tampilan agar terasa cepat
    setState(() {
      _notifications.removeAt(index);
    });

    try {
      final response = await ApiClient.instance.delete(
        Uri.parse('${ApiConfig.baseUrl}/notifications/$notifId'),
      );

      if (response.statusCode != 200) {
        // Jika gagal, kembalikan data ke dalam list
        if (!mounted) return;
        setState(() {
          _notifications.insert(index, deletedNotif);
        });
        _showSnackBar('Gagal menghapus notifikasi.');
      }
    } catch (e) {
      // Jika error koneksi, kembalikan data ke dalam list
      if (!mounted) return;
      setState(() {
        _notifications.insert(index, deletedNotif);
      });
      _showSnackBar('Terjadi kesalahan koneksi.');
    }
  }

  /// ================= 🟢 HAPUS SEMUA NOTIFIKASI =================
  Future<void> _clearAllNotifications() async {
    // Tampilkan dialog konfirmasi
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Hapus Semua Notifikasi?', 
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        content: const Text('Tindakan ini tidak dapat dibatalkan.'),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Batal', style: TextStyle(color: Colors.grey.shade600)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Hapus', style: TextStyle(color: _dangerColor, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirm != true) return;
    if (!mounted) return;

    setState(() {
      _isLoading = true;
    });

    try {
      final response = await ApiClient.instance.delete(
        Uri.parse('${ApiConfig.baseUrl}/notifications'),
      );

      if (!mounted) return;

      if (response.statusCode == 200) {
        setState(() {
          _notifications.clear();
          _isLoading = false;
        });
        _showSnackBar('Semua notifikasi berhasil dibersihkan.');
      } else {
        setState(() => _isLoading = false);
        _showSnackBar('Gagal menghapus notifikasi (Kode: ${response.statusCode})');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      _showSnackBar('Terjadi kesalahan koneksi.');
    }
  }

  void _showSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

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
        // 🟢 TAMBAHAN: Tombol Hapus Semua di pojok kanan atas
        actions: [
          if (_notifications.isNotEmpty && !_isLoading)
            IconButton(
              icon: const Icon(Icons.delete_sweep_rounded, color: _dangerColor),
              tooltip: 'Bersihkan Semua',
              onPressed: _clearAllNotifications,
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: _primaryColor))
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
                          
                          // 🟢 TAMBAHAN: Dibungkus Dismissible agar bisa di-swipe untuk hapus
                          return Dismissible(
                            key: Key('notif_${notif['id']}'),
                            direction: DismissDirection.endToStart,
                            onDismissed: (direction) {
                              _deleteSingleNotification(index);
                            },
                            background: Container(
                              margin: const EdgeInsets.only(bottom: 10),
                              decoration: BoxDecoration(
                                color: _dangerColor,
                                borderRadius: BorderRadius.circular(16),
                              ),
                              alignment: Alignment.centerRight,
                              padding: const EdgeInsets.symmetric(horizontal: 24),
                              child: const Icon(
                                Icons.delete_outline_rounded,
                                color: Colors.white,
                                size: 28,
                              ),
                            ),
                            child: _buildNotifCard(notif),
                          );
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