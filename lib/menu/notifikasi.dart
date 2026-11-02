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

  StreamSubscription<Map<String, dynamic>>? _notifSubscription;

  // ================= BRAND & SEMANTIC COLORS (tetap) =================
  static const Color _primaryColor = Color(0xFF2563EB);
  static const Color _accentColor = Color(0xFFF97316);
  static const Color _successColor = Color(0xFF16A34A);
  static const Color _dangerColor = Color(0xFFDC2626);
  static const Color _indigoColor = Color(0xFF6366F1);
  // 🟢 DIHAPUS: _bgColor

  @override
  void initState() {
    super.initState();

    NotificationSocketService().markAsSeen();

    _fetchNotifications();
    _markNotificationsAsRead();

    _notifSubscription =
        NotificationSocketService().onNewNotification.listen((newNotif) {
      debugPrint(
          'NotifikasiPage: 🔔 notifikasi baru diterima: ${newNotif['title']}');

      NotificationSocketService().markAsSeen();

      if (!mounted) return;
      setState(() {
        final alreadyExists =
            _notifications.any((n) => n['id'] == newNotif['id']);
        if (!alreadyExists) {
          _notifications.insert(0, newNotif);
        }
      });

      _markNotificationsAsRead();
    });
  }

  @override
  void dispose() {
    _notifSubscription?.cancel();
    super.dispose();
  }

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

  Future<void> _markNotificationsAsRead({int attempt = 0}) async {
    try {
      final response = await ApiClient.instance.post(
        Uri.parse('${ApiConfig.baseUrl}/notifications/read-all'),
      );

      if (response.statusCode == 200) {
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
        debugPrint(
            'NotifikasiPage: read-all 401, sesi berakhir, tidak di-retry.');
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
    final delay = Duration(seconds: 2 * (attempt + 1));
    Timer(delay, () {
      if (mounted) _markNotificationsAsRead(attempt: attempt + 1);
    });
  }

  Future<void> _deleteSingleNotification(int index) async {
    final deletedNotif = _notifications[index];
    final notifId = deletedNotif['id'];

    setState(() {
      _notifications.removeAt(index);
    });

    try {
      final response = await ApiClient.instance.delete(
        Uri.parse('${ApiConfig.baseUrl}/notifications/$notifId'),
      );

      if (response.statusCode != 200) {
        if (!mounted) return;
        setState(() {
          _notifications.insert(index, deletedNotif);
        });
        _showSnackBar('Gagal menghapus notifikasi.');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _notifications.insert(index, deletedNotif);
      });
      _showSnackBar('Terjadi kesalahan koneksi.');
    }
  }

  Future<void> _clearAllNotifications() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) {
        // 🟢 Ambil token tema dari context dialog
        final colorScheme = Theme.of(context).colorScheme;

        return AlertDialog(
          title: const Text('Hapus Semua Notifikasi?',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
          content: const Text('Tindakan ini tidak dapat dibatalkan.'),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(
                'Batal',
                style: TextStyle(
                  // 🟢 Ganti Colors.grey.shade600 → onSurfaceVariant
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text(
                'Hapus',
                style: TextStyle(
                  color: _dangerColor, // semantic error
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        );
      },
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
        _showSnackBar(
            'Gagal menghapus notifikasi (Kode: ${response.statusCode})');
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

  // 🟢 Warna semantic per jenis notifikasi — tetap di kedua mode
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
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      // 🟢 DIHAPUS: backgroundColor: _bgColor
      appBar: AppBar(
        title: const Text(
          'Notifikasi Aktivitas',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
        ),
        centerTitle: false,
        // 🟢 AppBar pakai token tema
        backgroundColor: colorScheme.surface,
        foregroundColor: colorScheme.onSurface,
        elevation: 0,
        surfaceTintColor: colorScheme.surface,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: colorScheme.outlineVariant),
        ),
        actions: [
          if (_notifications.isNotEmpty && !_isLoading)
            IconButton(
              icon: const Icon(Icons.delete_sweep_rounded,
                  color: _dangerColor), // semantic, tetap
              tooltip: 'Bersihkan Semua',
              onPressed: _clearAllNotifications,
            ),
        ],
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

                          return Dismissible(
                            key: Key('notif_${notif['id']}'),
                            direction: DismissDirection.endToStart,
                            onDismissed: (direction) {
                              _deleteSingleNotification(index);
                            },
                            background: Container(
                              margin: const EdgeInsets.only(bottom: 10),
                              decoration: BoxDecoration(
                                // 🟢 Merah semantic (destruktif) — tetap
                                color: _dangerColor,
                                borderRadius: BorderRadius.circular(16),
                              ),
                              alignment: Alignment.centerRight,
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 24),
                              child: const Icon(
                                Icons.delete_outline_rounded,
                                color: Colors.white, // di atas merah, tetap
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
    final colorScheme = Theme.of(context).colorScheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                // 🟢 0.08 → 0.15, biar tetap kelihatan di dark
                color: _dangerColor.withOpacity(0.15),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.error_outline_rounded,
                  size: 40, color: _dangerColor),
            ),
            const SizedBox(height: 16),
            Text(
              _errorMessage!,
              textAlign: TextAlign.center,
              style: TextStyle(
                // 🟢 Ganti Colors.grey.shade700 → onSurfaceVariant
                color: colorScheme.onSurfaceVariant,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: _fetchNotifications,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Coba Lagi'),
              style: ElevatedButton.styleFrom(
                backgroundColor: _primaryColor, // brand
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
    final colorScheme = Theme.of(context).colorScheme;

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
                      // 🟢 0.08 → 0.15
                      color: _primaryColor.withOpacity(0.15),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.notifications_off_outlined,
                      size: 40,
                      // 🟢 _primaryColor.withOpacity(0.6) tetap — brand
                      color: _primaryColor.withOpacity(0.6),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'Belum ada notifikasi kejadian.',
                    style: TextStyle(
                      // 🟢 Ganti Colors.grey.shade600 → onSurfaceVariant
                      color: colorScheme.onSurfaceVariant,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Aktivitas terbaru seputar pesanan Anda akan\nmuncul di sini.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      // 🟢 Ganti Colors.grey.shade400 → outline
                      color: colorScheme.outline,
                      fontSize: 12,
                    ),
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
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final bool isDark = theme.brightness == Brightness.dark;

    final String? type = notif['type'];
    final Color notifColor = _getNotifColor(type);
    final bool isUnread = notif['is_read'] == false;
    final String createdAt = notif['created_at']?.toString() ?? '';

    // 🟢 Unread bg: light 0.045 (asli), dark 0.15 (biar kelihatan tint biru)
    final Color cardBg = isUnread
        ? _primaryColor.withOpacity(isDark ? 0.15 : 0.045)
        : colorScheme.surface;

    // 🟢 Unread border: light 0.15, dark 0.30
    final Color unreadBorder = _primaryColor.withOpacity(isDark ? 0.30 : 0.15);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
        border: isUnread ? Border.all(color: unreadBorder) : null,
        boxShadow: [
          BoxShadow(
            // 🟢 Shadow dari tema
            color: colorScheme.shadow.withOpacity(0.06),
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
                // 🟢 0.1 → 0.15, tetap kelihatan di dark
                color: notifColor.withOpacity(0.15),
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
                            // 🟢 Ganti Color(0xFF1E293B) → onSurface
                            color: colorScheme.onSurface,
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
                            // 🟢 Oranye brand — tetap di kedua mode
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
                      // 🟢 Ganti Colors.grey.shade600 → onSurfaceVariant
                      color: colorScheme.onSurfaceVariant,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(
                        Icons.schedule_rounded,
                        size: 11.5,
                        // 🟢 Ganti Colors.grey.shade400 → outline
                        color: colorScheme.outline,
                      ),
                      const SizedBox(width: 3),
                      Text(
                        [
                          _formatDate(createdAt),
                          if (_formatTime(createdAt).isNotEmpty)
                            _formatTime(createdAt),
                        ].where((e) => e.isNotEmpty).join(' • '),
                        style: TextStyle(
                          fontSize: 10.5,
                          // 🟢 Ganti Colors.grey.shade500 → outline
                          color: colorScheme.outline,
                        ),
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