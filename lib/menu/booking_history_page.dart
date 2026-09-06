import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:rentalcar/config/api_config.dart';
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

  // ================= WARNA SENADA DENGAN HALAMAN LAIN =================
  static const Color _primaryColor = Color(0xFF2563EB);
  static const Color _accentColor = Color(0xFFF97316);
  static const Color _bgColor = Color(0xFFF4F6F9);

  @override
  void initState() {
    super.initState();
    _loadUserRoleAndBookings();
  }

  // Fungsi helper untuk membersihkan format tanggal (misal: 2026-06-06T00:00:00.000000Z -> 2026-06-06)
  String _formatDate(String? dateStr) {
    if (dateStr == null || dateStr.isEmpty) return '-';
    return dateStr.contains('T') ? dateStr.split('T')[0] : dateStr;
  }

  /// Format angka harga jadi "Rp 1.200.000" biar konsisten dgn halaman lain
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
    setState(() {
      _currentUserId = prefs.getString('user_id') ?? '3';
      _currentUserName = prefs.getString('user_name') ?? AppRole.penyewa.value;
    });
    _fetchBookings();
  }

  // 👇 DIGANTI: dulu manggil /bookings (role-scoped, ikut permission Perental/
  // Driver/Admin). Sekarang manggil /bookings/my-history yang SELALU scoped
  // ke user_id user login, apapun role/permission yang dia punya. Jadi kalau
  // yang login itu Perental yang juga pernah nyewa mobil orang lain, cuma
  // riwayat sewanya sendiri yang muncul di sini — bukan booking untuk mobil
  // yang dia kelola.
  Future<void> _fetchBookings() async {
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
        Uri.parse('${ApiConfig.baseUrl}/bookings/my-history'),
        headers: {
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        setState(() {
          _bookings = decoded['data'] ?? [];
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
      setState(() {
        _errorMessage = 'Terjadi kesalahan koneksi: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _cancelBooking(int bookingId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('access_token');

      final response = await http.patch(
        Uri.parse('${ApiConfig.baseUrl}/bookings/$bookingId/cancel'),
        headers: {
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        if (mounted) {
          _showSnackBar('Booking berhasil dibatalkan.', const Color(0xFF16A34A));
        }
        _fetchBookings();
      } else {
        final decoded = jsonDecode(response.body);
        if (mounted) {
          _showSnackBar(
              decoded['message'] ?? 'Gagal membatalkan pesanan', Colors.red);
        }
      }
    } catch (e) {
      if (mounted) {
        _showSnackBar('Error: $e', Colors.red);
      }
    }
  }

  // 👇 DIGANTI TOTAL: dulu ini "simulasi" yang langsung PATCH payment_status=paid
  // (celah keamanan, Penyewa bisa klaim lunas sendiri). Sekarang cuma NANYA
  // status asli ke backend, yang backend-nya nanya ke Midtrans. Penyewa
  // TIDAK BISA mengubah status ini sendiri.
  Future<void> _checkQrisPaymentStatus(int bookingId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('access_token');

      final response = await http.get(
        Uri.parse('${ApiConfig.baseUrl}/bookings/$bookingId/check-payment'),
        headers: {
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      final decoded = jsonDecode(response.body);

      if (response.statusCode == 200) {
        final updatedBooking = decoded['data'];
        final newPaymentStatus = updatedBooking?['payment_status'] ?? 'unpaid';

        if (mounted) {
          _showSnackBar(
            newPaymentStatus == 'paid'
                ? 'Pembayaran QRIS terkonfirmasi LUNAS!'
                : 'Pembayaran belum diterima. Pastikan sudah scan & bayar QR, lalu coba cek lagi.',
            newPaymentStatus == 'paid' ? const Color(0xFF16A34A) : _accentColor,
          );
        }
      } else {
        if (mounted) {
          _showSnackBar(
              decoded['message'] ?? 'Gagal mengecek status pembayaran',
              Colors.red);
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

 void _openChatWithOwner(dynamic carData) async {
    if (carData == null) {
      _showSnackBar('Informasi kendaraan tidak tersedia.', Colors.red);
      return;
    }

    final ownerMap = carData['user'] ?? carData['owner'];

    final String ownerId = ownerMap != null && ownerMap['id'] != null
        ? ownerMap['id'].toString()
        : (carData['user_id']?.toString() ?? '2');

    final String ownerName = ownerMap != null && ownerMap['name'] != null
        ? ownerMap['name'].toString()
        : 'Perental';

    final String? ownerAvatar =
        ownerMap != null ? ownerMap['avatar']?.toString() : null;

    if (ownerId.isEmpty || ownerId == 'null') {
      _showSnackBar('ID Perental tidak valid.', Colors.red);
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('access_token') ?? '';

    final String uniqueChatId =
        'room_rental_${ownerId}_user_${_currentUserId ?? '3'}';

    if (!mounted) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ChatPage(
          chatId: uniqueChatId,
          currentUserId: _currentUserId ?? '3',
          currentUserName: _currentUserName ?? 'Penyewa',
          receiverId: ownerId,
          receiverName: "Perental: $ownerName",
          receiverAvatarUrl: ownerAvatar,
          authToken: token,
        ),
      ),
    );
  }

  void _showSnackBar(String message, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.all(12),
      ),
    );
  }

  // 👇 DIGANTI: dulu QR-nya dummy (Icon qr_code_2), sekarang pakai qris_url
  // asli dari Midtrans. Tombol "Simulasi Sudah Bayar" dihapus, diganti
  // "Cek Status Pembayaran" yang manggil backend (bukan ubah status sendiri).
  void _showQrisDialog(BuildContext context, dynamic booking) {
    final String? qrisUrl = booking['qris_url'];

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: _primaryColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: const Icon(Icons.qr_code_rounded,
                    size: 18, color: _primaryColor),
              ),
              const SizedBox(width: 10),
              const Text('Pembayaran QRIS',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Silakan scan QR Code di bawah ini:',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
              ),
              const SizedBox(height: 16),
              if (qrisUrl != null)
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: _bgColor,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.grey.shade200),
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
                                  color: _primaryColor)),
                        );
                      },
                      errorBuilder: (context, error, stackTrace) => Container(
                        height: 180,
                        width: 180,
                        color: _bgColor,
                        child: const Center(
                          child: Text('Gagal memuat QR',
                              style: TextStyle(fontSize: 12)),
                        ),
                      ),
                    ),
                  ),
                )
              else
                Container(
                  height: 180,
                  width: 180,
                  decoration: BoxDecoration(
                    color: _bgColor,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Center(
                    child: Padding(
                      padding: EdgeInsets.all(16),
                      child: Text(
                        'QR belum tersedia.\nSilakan hubungi Perental.',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                  ),
                ),
              const SizedBox(height: 14),
              Text(
                'Total: ${_formatPrice(booking['total_price'])}',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: _primaryColor,
                  fontSize: 15,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Setelah scan & bayar, tekan tombol di bawah untuk memeriksa status pembayaran.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
              ),
            ],
          ),
          actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('Tutup',
                  style: TextStyle(color: Colors.grey.shade700)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: _primaryColor,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
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
    return Scaffold(
      backgroundColor: _bgColor,
      appBar: AppBar(
        title: const Text(
          'Riwayat Pemesanan',
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
      bottomNavigationBar: Bottom(
        currentIndex: 2,
        onTap: (index) {},
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
                color: Colors.red.withOpacity(0.08),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.error_outline_rounded,
                  size: 40, color: Colors.red),
            ),
            const SizedBox(height: 16),
            Text(
              _errorMessage!,
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade700, fontSize: 14),
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
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.receipt_long_outlined, size: 48, color: Colors.grey.shade400),
          const SizedBox(height: 12),
          Text(
            'Belum ada riwayat pemesanan.',
            style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _infoRow(IconData icon, String label, String value,
      {Color? valueColor, FontWeight? valueWeight}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 14, color: Colors.grey.shade400),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
          ),
          const Spacer(),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: valueWeight ?? FontWeight.w600,
                color: valueColor ?? const Color(0xFF1E293B),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// ================= KARTU BOOKING =================
  Widget _buildBookingCard(dynamic booking) {
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
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
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
                  style: const TextStyle(
                    fontSize: 15.5,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1E293B),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: statusColor.withOpacity(0.1),
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
          _infoRow(Icons.date_range_outlined, 'Periode Sewa',
              '$startDateFormatted s/d $endDateFormatted'),
          _infoRow(Icons.timelapse_outlined, 'Durasi',
              '${booking['total_days']} Hari'),
          _infoRow(
            Icons.key_outlined,
            'Layanan',
            withDriver ? 'Dengan Driver' : 'Lepas Kunci',
            valueColor: withDriver ? const Color(0xFF4F46E5) : null,
          ),
          if (withDriver && driver != null)
            _infoRow(Icons.badge_outlined, 'Driver Bertugas',
                '${driver['name']}',
                valueColor: const Color(0xFF16A34A)),

          Container(
            margin: const EdgeInsets.symmetric(vertical: 10),
            height: 1,
            color: Colors.grey.shade100,
          ),

          // ===== Pembayaran =====
          _infoRow(Icons.payments_outlined, 'Metode Pembayaran',
              paymentMethod == 'qris' ? 'QRIS' : 'Bayar di Tempat (COD)'),
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
              children: [
                Icon(Icons.verified_outlined, size: 14, color: Colors.grey.shade400),
                const SizedBox(width: 6),
                Text(
                  'Status Pembayaran',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
                const Spacer(),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: isPaid
                        ? const Color(0xFF16A34A).withOpacity(0.1)
                        : _accentColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    isPaid ? 'Lunas' : 'Belum Bayar',
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.bold,
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
                style: TextStyle(fontSize: 12.5, color: Colors.grey.shade600),
              ),
              Text(
                _formatPrice(booking['total_price']),
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: _primaryColor,
                  fontSize: 16,
                ),
              ),
            ],
          ),

          const SizedBox(height: 14),

          // 👇 Tombol di halaman ini murni sudut pandang PENYEWA
          // (halaman ini menampilkan riwayat sewa milik sendiri).
          // Tombol "Konfirmasi Tunai Lunas" khusus Perental/Driver
          // DIHAPUS dari sini — itu action pemilik mobil, bukan
          // penyewa, dan sebaiknya ada di halaman "Kelola Booking"
          // yang memanggil endpoint /bookings (role-scoped).
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
                color: const Color(0xFF0D9488),
                onPressed: () => _openChatWithOwner(car),
              ),
              if (status == 'pending')
                _actionButton(
                  label: 'Batalkan',
                  icon: Icons.cancel_outlined,
                  color: const Color(0xFFDC2626),
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
          foregroundColor: color,
          side: BorderSide(color: color.withOpacity(0.4)),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          minimumSize: Size.zero,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
        onPressed: onPressed,
        icon: Icon(icon, size: 15),
        label: Text(label,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
      );
    }
    return ElevatedButton.icon(
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: Colors.white,
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        minimumSize: Size.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      onPressed: onPressed,
      icon: Icon(icon, size: 15),
      label: Text(label,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
    );
  }
}