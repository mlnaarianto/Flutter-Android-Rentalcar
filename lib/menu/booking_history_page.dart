import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:rentalcar/config/api_config.dart';
import 'package:rentalcar/services/api_client.dart';
import 'package:rentalcar/widgets/bottom.dart';
import 'package:rentalcar/menu/chat.dart';
import 'package:rentalcar/enums/app_enums.dart';

class BookingHistoryPage extends StatefulWidget {
  const BookingHistoryPage({super.key});

  @override
  State<BookingHistoryPage> createState() => _BookingHistoryPageState();
}

class _BookingHistoryPageState extends State<BookingHistoryPage> {
  List<dynamic> _bookings = [];
  bool _isLoading = true;
  String? _errorMessage;
  String? _currentUserId;
  String? _currentUserName;

  // ================= BRAND COLORS (tetap di light & dark) =================
  static const Color _primaryColor = Color(0xFF2563EB);
  static const Color _accentColor = Color(0xFFF97316);
  // 🟢 DIHAPUS: _bgColor

  @override
  void initState() {
    super.initState();
    _loadUserRoleAndBookings();
  }

  Map<String, dynamic>? _tryDecodeMap(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) return decoded;
    } catch (_) {}
    return null;
  }

  String _formatDate(String? dateStr) {
    if (dateStr == null || dateStr.isEmpty) return '-';
    return dateStr.contains('T') ? dateStr.split('T')[0] : dateStr;
  }

  String _formatPrice(dynamic raw) {
    if (raw == null) return 'Rp 0';
    final numValue = num.tryParse(raw.toString()) ?? 0;
    final intValue = numValue.round();
    final str = intValue.toString();
    final buffer = StringBuffer();
    for (int i = 0; i < str.length; i++) {
      final posFromRight = str.length - i;
      buffer.write(str[i]);
      if (posFromRight > 1 && posFromRight % 3 == 1) {
        buffer.write('.');
      }
    }
    return 'Rp $buffer';
  }

  Future<void> _loadUserRoleAndBookings() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;

    setState(() {
      _currentUserId = prefs.getString('user_id');
      _currentUserName = prefs.getString('user_name') ?? AppRole.penyewa.value;
    });
    _fetchBookings();
  }

  Future<void> _fetchBookings() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final response = await ApiClient.instance.get(
        Uri.parse('${ApiConfig.baseUrl}/bookings/my-history'),
      );

      if (!mounted) return;

      if (response.statusCode == 200) {
        final decoded = _tryDecodeMap(response.body);
        if (decoded == null) {
          setState(() {
            _errorMessage = 'Respons server tidak valid. Coba lagi nanti.';
            _isLoading = false;
          });
          return;
        }

        final data = decoded['data'];
        setState(() {
          _bookings = data is List ? data : [];
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
              'Gagal memuat riwayat booking (Kode: ${response.statusCode})';
          _isLoading = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Terjadi kesalahan koneksi: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _cancelBooking(int bookingId) async {
    try {
      final response = await ApiClient.instance.patch(
        Uri.parse('${ApiConfig.baseUrl}/bookings/$bookingId/cancel'),
      );

      if (response.statusCode == 200) {
        if (mounted) {
          _showSnackBar(
            'Booking berhasil dibatalkan.',
            const Color(0xFF16A34A),
          );
        }
        _fetchBookings();
      } else {
        final decoded = _tryDecodeMap(response.body);
        if (mounted) {
          _showSnackBar(
            decoded?['message']?.toString() ??
                'Gagal membatalkan pesanan (Kode: ${response.statusCode})',
            Colors.red,
          );
        }
      }
    } catch (e) {
      if (mounted) {
        _showSnackBar('Error: $e', Colors.red);
      }
    }
  }

  Future<void> _checkQrisPaymentStatus(int bookingId) async {
    try {
      final response = await ApiClient.instance.get(
        Uri.parse('${ApiConfig.baseUrl}/bookings/$bookingId/check-payment'),
      );

      final decoded = _tryDecodeMap(response.body);

      if (response.statusCode == 200 && decoded != null) {
        final updatedBooking = decoded['data'];
        final newPaymentStatus = updatedBooking?['payment_status'] ?? 'unpaid';

        if (mounted) {
          _showSnackBar(
            newPaymentStatus == 'paid'
                ? 'Pembayaran QRIS terkonfirmasi LUNAS!'
                : 'Pembayaran belum diterima. Pastikan sudah scan & bayar QR, lalu coba cek lagi.',
            newPaymentStatus == 'paid'
                ? const Color(0xFF16A34A)
                : _accentColor,
          );
        }
      } else {
        if (mounted) {
          _showSnackBar(
            decoded?['message']?.toString() ??
                'Gagal mengecek status pembayaran (Kode: ${response.statusCode})',
            Colors.red,
          );
        }
      }
      _fetchBookings();
    } catch (e) {
      if (mounted) {
        _showSnackBar('Error: $e', Colors.red);
      }
      _fetchBookings();
    }
  }

  void _openChatWithOwner(dynamic carData) {
    if (carData == null) {
      _showSnackBar('Informasi kendaraan tidak tersedia.', Colors.red);
      return;
    }

    if (_currentUserId == null || _currentUserId!.isEmpty) {
      _showSnackBar('Data akun belum siap, coba lagi sesaat lagi.', Colors.red);
      return;
    }

    final ownerMap = carData['user'] ?? carData['owner'];

    final String ownerId = ownerMap != null && ownerMap['id'] != null
        ? ownerMap['id'].toString()
        : (carData['user_id']?.toString() ?? '');

    if (ownerId.isEmpty || ownerId == 'null') {
      _showSnackBar('ID Perental tidak valid.', Colors.red);
      return;
    }

    final String ownerName = ownerMap != null && ownerMap['name'] != null
        ? ownerMap['name'].toString()
        : 'Perental';

    final String? ownerAvatar =
        ownerMap != null ? ownerMap['avatar']?.toString() : null;

    final String uniqueChatId = 'room_rental_${ownerId}_user_$_currentUserId';

    if (!mounted) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ChatPage(
          chatId: uniqueChatId,
          currentUserId: _currentUserId!,
          currentUserName: _currentUserName ?? AppRole.penyewa.value,
          receiverId: ownerId,
          receiverName: "Perental: $ownerName",
          receiverAvatarUrl: ownerAvatar,
        ),
      ),
    );
  }

  void _showSnackBar(String message, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: color, // 🟢 semantic, tetap
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.all(12),
      ),
    );
  }

  /// ================= DIALOG QRIS =================
  /// ⚠️ ATURAN KHUSUS: kotak QR tetap **putih** di kedua mode —
  /// bukan sekadar preferensi visual, tapi kebutuhan fungsional
  /// (QR harus punya kontras tinggi agar bisa discan kamera HP lain).
  /// Ini juga standar UX e-wallet (GoPay, OVO, Dana).
  void _showQrisDialog(BuildContext context, dynamic booking) {
    final String? qrisUrl = booking['qris_url'];

    showDialog(
      context: context,
      builder: (context) {
        final colorScheme = Theme.of(context).colorScheme;

        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  // 🟢 0.1 → 0.12, tetap terlihat di dark
                  color: _primaryColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: const Icon(
                  Icons.qr_code_rounded,
                  size: 18,
                  color: _primaryColor,
                ),
              ),
              const SizedBox(width: 10),
              const Text(
                'Pembayaran QRIS',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Silakan scan QR Code di bawah ini:',
                textAlign: TextAlign.center,
                style: TextStyle(
                  // 🟢 Ganti Colors.grey.shade600 → onSurfaceVariant
                  color: colorScheme.onSurfaceVariant,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 16),
              if (qrisUrl != null)
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    // 🟢 SENGAJA tetap putih — QR butuh latar putih
                    // untuk bisa discan. Tidak diubah per mode.
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Image.network(
                      qrisUrl,
                      height: 180,
                      width: 180,
                      fit: BoxFit.contain,
                      loadingBuilder: (context, child, progress) {
                        if (progress == null) return child;
                        return const SizedBox(
                          height: 180,
                          width: 180,
                          child: Center(
                            child: CircularProgressIndicator(
                              color: _primaryColor,
                            ),
                          ),
                        );
                      },
                      errorBuilder: (context, error, stackTrace) => Container(
                        height: 180,
                        width: 180,
                        // 🟢 Tetap putih — konsisten dengan latar QR
                        color: Colors.white,
                        child: const Center(
                          child: Text(
                            'Gagal memuat QR',
                            style: TextStyle(
                              fontSize: 12,
                              // 🟢 Teks gelap karena bg putih — tetap
                              color: Colors.black54,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                )
              else
                // Placeholder "QR belum tersedia" — ini BUKAN QR asli,
                // jadi pakai token tema seperti widget biasa
                Container(
                  height: 180,
                  width: 180,
                  decoration: BoxDecoration(
                    // 🟢 Ganti _bgColor → surfaceContainerHighest
                    color: colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        'QR belum tersedia.\nSilakan hubungi Perental.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 12,
                          // 🟢 Teks placeholder pakai onSurfaceVariant
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ),
                ),
              const SizedBox(height: 14),
              Text(
                'Total: ${_formatPrice(booking['total_price'])}',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: _primaryColor, // brand biru
                  fontSize: 15,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Setelah scan & bayar, tekan tombol di bawah untuk memeriksa status pembayaran.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 11,
                  // 🟢 Ganti Colors.grey.shade500 → onSurfaceVariant
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(
                'Tutup',
                style: TextStyle(
                  // 🟢 Ganti Colors.grey.shade700 → onSurfaceVariant
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: _primaryColor,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              onPressed: () {
                Navigator.pop(context);
                _checkQrisPaymentStatus(booking['id']);
              },
              child: const Text('Cek Status Pembayaran'),
            ),
          ],
        );
      },
    );
  }

  // 🟢 Warna status semantic — tetap di kedua mode
  Color _getStatusColor(String status) {
    switch (status) {
      case 'confirmed':
      case 'active':
        return _primaryColor;
      case 'completed':
        return const Color(0xFF16A34A);
      case 'cancelled':
        return const Color(0xFFDC2626);
      default:
        return _accentColor;
    }
  }

  String _getStatusLabel(String status) {
    switch (status) {
      case 'confirmed':
        return 'Dikonfirmasi';
      case 'active':
        return 'Berlangsung';
      case 'completed':
        return 'Selesai';
      case 'cancelled':
        return 'Dibatalkan';
      case 'pending':
        return 'Menunggu';
      default:
        return status.isEmpty ? '-' : status;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      // 🟢 DIHAPUS: backgroundColor: _bgColor
      appBar: AppBar(
        title: const Text(
          'Riwayat Pemesanan',
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
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: _primaryColor))
          : _errorMessage != null
              ? _buildErrorState()
              : _bookings.isEmpty
                  ? _buildEmptyState()
                  : RefreshIndicator(
                      color: _primaryColor,
                      onRefresh: _fetchBookings,
                      child: ListView.builder(
                        physics: const AlwaysScrollableScrollPhysics(),
                        itemCount: _bookings.length,
                        padding: const EdgeInsets.all(16),
                        itemBuilder: (context, index) {
                          return _buildBookingCard(_bookings[index]);
                        },
                      ),
                    ),
      bottomNavigationBar: Bottom(currentIndex: 2, onTap: (index) {}),
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
                // 🟢 0.08 → 0.15, error semantic
                color: colorScheme.error.withOpacity(0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.error_outline_rounded,
                size: 40,
                color: colorScheme.error,
              ),
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
              onPressed: _fetchBookings,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Coba Lagi'),
              style: ElevatedButton.styleFrom(
                backgroundColor: _primaryColor,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 12,
                ),
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

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.receipt_long_outlined,
            size: 48,
            // 🟢 Ganti Colors.grey.shade400 → outline
            color: colorScheme.outline,
          ),
          const SizedBox(height: 12),
          Text(
            'Belum ada riwayat pemesanan.',
            style: TextStyle(
              // 🟢 Ganti Colors.grey.shade600 → onSurfaceVariant
              color: colorScheme.onSurfaceVariant,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoRow(
    IconData icon,
    String label,
    String value, {
    Color? valueColor,
    FontWeight? valueWeight,
  }) {
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            icon,
            size: 14,
            // 🟢 Ganti Colors.grey.shade400 → outline
            color: colorScheme.outline,
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              // 🟢 Ganti Colors.grey.shade600 → onSurfaceVariant
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const Spacer(),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: valueWeight ?? FontWeight.w600,
                // 🟢 Ganti Color(0xFF1E293B) → onSurface
                color: valueColor ?? colorScheme.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// ================= KARTU BOOKING =================
  Widget _buildBookingCard(dynamic booking) {
    final colorScheme = Theme.of(context).colorScheme;

    final car = booking['car'] ?? {};
    final driver = booking['driver'];
    final status = booking['status'] ?? 'pending';
    final paymentStatus = booking['payment_status'] ?? 'unpaid';
    final paymentMethod = booking['payment_method'] ?? 'cod';
    final bool withDriver =
        booking['with_driver'] == 1 || booking['with_driver'] == true;
    final bool isPaid = paymentStatus == 'paid';
    final statusColor = _getStatusColor(status);

    final String startDateFormatted = _formatDate(booking['start_date']);
    final String endDateFormatted = _formatDate(booking['end_date']);

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        // 🟢 Ganti Colors.white → colorScheme.surface
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            // 🟢 Shadow dari tema
            color: colorScheme.shadow.withOpacity(0.06),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ===== Header: nama mobil + status =====
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  car['name'] ?? 'Mobil Rental',
                  style: TextStyle(
                    fontSize: 15.5,
                    fontWeight: FontWeight.bold,
                    // 🟢 Ganti Color(0xFF1E293B) → onSurface
                    color: colorScheme.onSurface,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  // 🟢 0.1 → 0.15, tetap kelihatan di dark
                  color: statusColor.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  _getStatusLabel(status),
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.bold,
                    color: statusColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // ===== Detail sewa =====
          _infoRow(
            Icons.date_range_outlined,
            'Periode Sewa',
            '$startDateFormatted s/d $endDateFormatted',
          ),
          _infoRow(
            Icons.timelapse_outlined,
            'Durasi',
            '${booking['total_days']} Hari',
          ),
          _infoRow(
            Icons.key_outlined,
            'Layanan',
            withDriver ? 'Dengan Driver' : 'Lepas Kunci',
            // 🟢 Indigo brand — tetap
            valueColor: withDriver ? const Color(0xFF4F46E5) : null,
          ),
          if (withDriver && driver != null)
            _infoRow(
              Icons.badge_outlined,
              'Driver Bertugas',
              '${driver['name']}',
              // 🟢 Hijau semantic — tetap
              valueColor: const Color(0xFF16A34A),
            ),

          Container(
            margin: const EdgeInsets.symmetric(vertical: 10),
            height: 1,
            // 🟢 Ganti Colors.grey.shade100 → outlineVariant
            color: colorScheme.outlineVariant,
          ),

          // ===== Pembayaran =====
          _infoRow(
            Icons.payments_outlined,
            'Metode Pembayaran',
            paymentMethod == 'qris' ? 'QRIS' : 'Bayar di Tempat (COD)',
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
              children: [
                Icon(
                  Icons.verified_outlined,
                  size: 14,
                  // 🟢 Ganti Colors.grey.shade400 → outline
                  color: colorScheme.outline,
                ),
                const SizedBox(width: 6),
                Text(
                  'Status Pembayaran',
                  style: TextStyle(
                    fontSize: 12,
                    // 🟢 Ganti Colors.grey.shade600 → onSurfaceVariant
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    // 🟢 0.1 → 0.15 untuk kedua kemungkinan (paid & unpaid)
                    color: isPaid
                        ? const Color(0xFF16A34A).withOpacity(0.15)
                        : _accentColor.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    isPaid ? 'Lunas' : 'Belum Bayar',
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.bold,
                      // 🟢 Semantic color — tetap
                      color: isPaid ? const Color(0xFF16A34A) : _accentColor,
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Total Biaya',
                style: TextStyle(
                  fontSize: 12.5,
                  // 🟢 Ganti Colors.grey.shade600 → onSurfaceVariant
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              Text(
                _formatPrice(booking['total_price']),
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: _primaryColor, // brand biru
                  fontSize: 16,
                ),
              ),
            ],
          ),

          const SizedBox(height: 14),

          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (!isPaid && paymentMethod == 'qris' && status != 'cancelled')
                _actionButton(
                  label: 'Bayar via QRIS',
                  icon: Icons.qr_code_rounded,
                  color: _primaryColor,
                  onPressed: () => _showQrisDialog(context, booking),
                ),
              _actionButton(
                label: 'Chat Perental',
                icon: Icons.chat_bubble_outline_rounded,
                color: const Color(0xFF0D9488), // teal brand
                onPressed: () => _openChatWithOwner(car),
              ),
              if (status == 'pending')
                _actionButton(
                  label: 'Batalkan',
                  icon: Icons.cancel_outlined,
                  color: const Color(0xFFDC2626), // merah semantic
                  outlined: true,
                  onPressed: () => _cancelBooking(booking['id']),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _actionButton({
    required String label,
    required IconData icon,
    required Color color,
    required VoidCallback onPressed,
    bool outlined = false,
  }) {
    if (outlined) {
      return OutlinedButton.icon(
        style: OutlinedButton.styleFrom(
          foregroundColor: color, // 🟢 semantic, tetap
          side: BorderSide(color: color.withOpacity(0.4)),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          minimumSize: Size.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
        onPressed: onPressed,
        icon: Icon(icon, size: 15),
        label: Text(
          label,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
        ),
      );
    }
    return ElevatedButton.icon(
      style: ElevatedButton.styleFrom(
        backgroundColor: color, // 🟢 brand/semantic, tetap
        foregroundColor: Colors.white,
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        minimumSize: Size.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      onPressed: onPressed,
      icon: Icon(icon, size: 15),
      label: Text(
        label,
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
      ),
    );
  }
}