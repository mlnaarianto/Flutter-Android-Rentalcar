import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:rentalcar/config/api_config.dart';
import 'package:rentalcar/services/api_client.dart';
import 'package:rentalcar/menu/chat.dart';
import 'package:rentalcar/enums/app_enums.dart';

class RentalsBookingPage extends StatefulWidget {
  const RentalsBookingPage({super.key});

  @override
  State<RentalsBookingPage> createState() => _RentalsBookingPageState();
}

class _RentalsBookingPageState extends State<RentalsBookingPage> {
  List<dynamic> _bookings = [];
  bool _isLoading = true;
  String? _errorMessage;
  String? _currentUserId;
  String? _currentUserName;

  // 👇 Menyimpan booking id mana saja yang sedang proses cek pembayaran,
  // supaya cuma tombol yang ditekan itu yang menampilkan loading.
  final Set<int> _checkingPaymentIds = {};

  // 👇 DITAMBAHKAN: menyimpan booking id mana saja yang sedang proses
  // konfirmasi pembayaran tunai (COD), supaya cuma tombol yang ditekan
  // itu yang menampilkan loading (pola sama seperti _checkingPaymentIds).
  final Set<int> _confirmingCashIds = {};

  static const List<String> _statusOptions = [
    'pending',
    'confirmed',
    'active',
    'completed',
    'cancelled',
  ];

  // ================= WARNA SENADA DENGAN HALAMAN LAIN =================
  static const Color _primaryColor = Color(0xFF2563EB);
  static const Color _accentColor = Color(0xFFF97316);
  static const Color _bgColor = Color(0xFFF4F6F9);
  static const Color _successColor = Color(0xFF16A34A);

  @override
  void initState() {
    super.initState();
    _loadLocalUserData();
    _fetchBookings();
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

  // Ambil data user aktif (Perental) dari SharedPreferences.
  // SENGAJA tidak diberi fallback hardcode (mis. '3') untuk user_id -- kalau
  // belum sempat ke-load, _currentUserId tetap null dan setiap aksi yang
  // butuh identitas user (buka chat) akan di-guard secara eksplisit, bukan
  // diam-diam memakai identitas user lain.
  Future<void> _loadLocalUserData() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;

    setState(() {
      _currentUserId = prefs.getString('user_id');
      _currentUserName = prefs.getString('user_name') ?? AppRole.perental.value;
    });
  }

  // 1. Ambil daftar booking khusus perental dari API backend.
  // Token dipasang dan di-refresh otomatis oleh ApiClient. Kalau sesi
  // benar-benar mati, onSessionExpired di main.dart yang mengarahkan ke login.
  Future<void> _fetchBookings() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final response = await ApiClient.instance.get(
        Uri.parse('${ApiConfig.baseUrl}/bookings'),
      );

      if (!mounted) return;

      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        setState(() {
          _bookings = decoded['data'] ?? [];
          _isLoading = false;
        });
      } else if (response.statusCode == 401) {
        setState(() {
          _errorMessage = 'Sesi habis. Silakan login kembali.';
          _isLoading = false;
        });
      } else {
        setState(() {
          _errorMessage = 'Gagal memuat data pesanan (Kode: ${response.statusCode})';
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

  // 2. Ambil daftar user ber-role 'Driver' dari backend
  Future<List<dynamic>> _fetchAvailableDrivers() async {
    try {
      final response = await ApiClient.instance.get(
        Uri.parse('${ApiConfig.baseUrl}/drivers-list'),
      );

      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        return decoded['data'] ?? [];
      }
      return [];
    } catch (e) {
      return [];
    }
  }

  // 3. Dialog untuk Memilih & Menugaskan Driver
  Future<void> _showAssignDriverDialog(int bookingId) async {
    List<dynamic> drivers = await _fetchAvailableDrivers();
    int? selectedDriverId;

    if (!mounted) return;

    if (drivers.isEmpty) {
      _showSnackBar('Tidak ada driver yang tersedia di sistem saat ini.', Colors.red);
      return;
    }

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
                child: const Icon(Icons.person_add_alt_rounded, size: 18, color: _primaryColor),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Text('Tugaskan Driver',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              ),
            ],
          ),
          content: StatefulBuilder(
            builder: (context, setStateDialog) {
              return DropdownButtonFormField<int>(
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: 'Pilih Nama Driver',
                  filled: true,
                  fillColor: _bgColor,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
                items: drivers.map<DropdownMenuItem<int>>((driver) {
                  return DropdownMenuItem<int>(
                    value: driver['id'],
                    child: Text(
                      '${driver['name']} (${driver['email']})',
                      overflow: TextOverflow.ellipsis,
                    ),
                  );
                }).toList(),
                onChanged: (value) {
                  setStateDialog(() {
                    selectedDriverId = value;
                  });
                },
              );
            },
          ),
          actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('Batal', style: TextStyle(color: Colors.grey.shade700)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: _primaryColor,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: () async {
                if (selectedDriverId == null) {
                  _showSnackBar('Silakan pilih driver terlebih dahulu!', Colors.red);
                  return;
                }
                Navigator.pop(context);
                await _submitAssignDriver(bookingId, selectedDriverId!);
              },
              child: const Text('Simpan & Tugaskan'),
            ),
          ],
        );
      },
    );
  }

  // 4. Kirim request API penugasan driver ke backend
  Future<void> _submitAssignDriver(int bookingId, int driverId) async {
    try {
      final response = await ApiClient.instance.patch(
        Uri.parse('${ApiConfig.baseUrl}/bookings/$bookingId/assign-driver'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'driver_id': driverId}),
      );

      final decoded = jsonDecode(response.body);

      if (response.statusCode == 200) {
        if (mounted) {
          _showSnackBar('Driver berhasil ditugaskan!', const Color(0xFF16A34A));
        }
        _fetchBookings();
      } else {
        if (mounted) {
          _showSnackBar(decoded['message'] ?? 'Gagal menugaskan driver', Colors.red);
        }
      }
    } catch (e) {
      if (mounted) {
        _showSnackBar('Error: $e', Colors.red);
      }
    }
  }

  // 5. Kirim request API pembaruan status booking ke backend
  Future<void> _updateBookingStatus(int bookingId, String newStatus) async {
    try {
      final response = await ApiClient.instance.patch(
        Uri.parse('${ApiConfig.baseUrl}/bookings/$bookingId/status'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'status': newStatus}),
      );

      final decoded = jsonDecode(response.body);

      if (response.statusCode == 200) {
        if (mounted) {
          _showSnackBar('Status booking berhasil diperbarui!', const Color(0xFF16A34A));
        }
        _fetchBookings();
      } else {
        if (mounted) {
          _showSnackBar(decoded['message'] ?? 'Gagal memperbarui status', Colors.red);
        }
      }
    } catch (e) {
      if (mounted) {
        _showSnackBar('Error: $e', Colors.red);
      }
    }
  }

  // 6. Cek status pembayaran QRIS ke backend (yang backend-nya nanya ke Midtrans).
  // Perental cuma butuh TAHU status pembayaran, bukan bayar — jadi di halaman
  // ini tidak ada gambar QR sama sekali, cuma tombol cek + badge status.
  Future<void> _checkPaymentStatus(int bookingId) async {
    setState(() => _checkingPaymentIds.add(bookingId));

    try {
      final response = await ApiClient.instance.get(
        Uri.parse('${ApiConfig.baseUrl}/bookings/$bookingId/check-payment'),
      );

      final decoded = jsonDecode(response.body);

      if (response.statusCode == 200) {
        final updatedBooking = decoded['data'];
        final newPaymentStatus = updatedBooking?['payment_status'] ?? 'unpaid';

        if (mounted) {
          _showSnackBar(
            newPaymentStatus == 'paid'
                ? 'Pembayaran penyewa terkonfirmasi LUNAS!'
                : 'Penyewa belum menyelesaikan pembayaran QRIS.',
            newPaymentStatus == 'paid' ? const Color(0xFF16A34A) : _accentColor,
          );
        }
        _fetchBookings(); // Refresh daftar biar badge status ikut update
      } else {
        if (mounted) {
          _showSnackBar(decoded['message'] ?? 'Gagal mengecek status pembayaran', Colors.red);
        }
      }
    } catch (e) {
      if (mounted) {
        _showSnackBar('Error: $e', Colors.red);
      }
    } finally {
      if (mounted) {
        setState(() => _checkingPaymentIds.remove(bookingId));
      }
    }
  }

  // 👇 DITAMBAHKAN: Konfirmasi pembayaran TUNAI (COD) oleh Perental.
  //
  // Beda dengan QRIS (yang statusnya diverifikasi otomatis lewat Midtrans),
  // COD dibayar langsung secara fisik saat serah-terima mobil, jadi tidak
  // ada gateway pihak ketiga yang bisa dicek. Satu-satunya pihak yang tahu
  // uang tunai itu benar-benar diterima adalah Perental sendiri, jadi
  // konfirmasi ini murni aksi manual dari sisi Perental.
  //
  // Aman dari sisi keamanan: request ini lewat endpoint
  // PATCH /bookings/{id}/status yang di backend selalu melewati
  // $this->authorize('updateStatus', $booking) -- jadi Penyewa TIDAK BISA
  // memicu endpoint ini sendiri untuk klaim lunas sendiri (beda dengan versi
  // lama tombol "Simulasi Sudah Bayar" di sisi Penyewa yang sudah dihapus).
  Future<void> _confirmCashPayment(int bookingId) async {
    setState(() => _confirmingCashIds.add(bookingId));

    try {
      final response = await ApiClient.instance.patch(
        Uri.parse('${ApiConfig.baseUrl}/bookings/$bookingId/status'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'payment_status': 'paid'}),
      );

      final decoded = jsonDecode(response.body);

      if (response.statusCode == 200) {
        if (mounted) {
          _showSnackBar('Pembayaran tunai berhasil dikonfirmasi LUNAS!', _successColor);
        }
        _fetchBookings();
      } else {
        if (mounted) {
          _showSnackBar(
            decoded['message'] ?? 'Gagal mengonfirmasi pembayaran tunai',
            Colors.red,
          );
        }
      }
    } catch (e) {
      if (mounted) {
        _showSnackBar('Error: $e', Colors.red);
      }
    } finally {
      if (mounted) {
        setState(() => _confirmingCashIds.remove(bookingId));
      }
    }
  }

  // Navigasi ke Halaman Chat Perental <-> Penyewa.
  // Di-guard: kalau _currentUserId belum ke-load, JANGAN buka ChatPage --
  // sebelumnya kode ini fallback diam-diam ke '3' dan bisa menghasilkan
  // uniqueChatId berisi literal "null" kalau _currentUserId null.
  void _openChatWithRenter(Map<String, dynamic> renter) {
    if (_currentUserId == null || _currentUserId!.isEmpty) {
      _showSnackBar('Data akun belum siap, coba lagi sesaat lagi.', Colors.red);
      return;
    }

    final String renterId = renter['id']?.toString() ?? '';
    final String renterName = renter['name'] ?? 'Penyewa';
    final String? renterAvatar = renter['avatar']?.toString();

    if (renterId.isEmpty) {
      _showSnackBar('ID Penyewa tidak valid.', Colors.red);
      return;
    }

    // PENTING: skema "room_rental_{perentalId}_user_{renterId}" ini harus
    // PERSIS SAMA dengan yang dipakai halaman chat milik Penyewa untuk room
    // yang sama (backend mencocokkan chatId ke room_identifier apa adanya,
    // lihat ChatController::sendMessage). Kalau sisi Penyewa membangun
    // chatId dengan urutan/format berbeda, keduanya akan dianggap dua room
    // terpisah oleh backend.
    final String uniqueChatId = 'room_rental_${_currentUserId}_user_$renterId';

    if (!mounted) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ChatPage(
          chatId: uniqueChatId,
          currentUserId: _currentUserId!,
          currentUserName: _currentUserName ?? AppRole.perental.value,
          receiverId: renterId,
          receiverName: "Penyewa: $renterName",
          receiverAvatarUrl: renterAvatar,
        ),
      ),
    );
  }

  // Navigasi ke Halaman Chat Perental <-> Driver.
  // Guard yang sama seperti _openChatWithRenter di atas.
  void _openChatWithDriver(Map<String, dynamic> driver) {
    if (_currentUserId == null || _currentUserId!.isEmpty) {
      _showSnackBar('Data akun belum siap, coba lagi sesaat lagi.', Colors.red);
      return;
    }

    final String driverId = driver['id']?.toString() ?? '';
    final String driverName = driver['name'] ?? 'Driver';
    final String? driverAvatar = driver['avatar']?.toString();

    if (driverId.isEmpty) {
      _showSnackBar('ID Driver tidak valid.', Colors.red);
      return;
    }

    // Catatan skema chatId sama seperti di _openChatWithRenter -- pastikan
    // sisi Driver (kalau punya halaman chat sendiri ke Perental) memakai
    // format yang identik untuk room yang sama.
    final String uniqueChatId = 'room_rental_${_currentUserId}_driver_$driverId';

    if (!mounted) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ChatPage(
          chatId: uniqueChatId,
          currentUserId: _currentUserId!,
          currentUserName: _currentUserName ?? AppRole.perental.value,
          receiverId: driverId,
          receiverName: "Driver: $driverName",
          receiverAvatarUrl: driverAvatar,
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
          'Kelola Pesanan & Driver',
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
          ? const Center(child: CircularProgressIndicator(color: _primaryColor))
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
              child: const Icon(Icons.error_outline_rounded, size: 40, color: Colors.red),
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
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
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
          Icon(Icons.inbox_outlined, size: 48, color: Colors.grey.shade400),
          const SizedBox(height: 12),
          Text(
            'Belum ada pesanan masuk.',
            style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _infoRow(IconData icon, String label, String value, {Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 14, color: Colors.grey.shade400),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
          const Spacer(),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: valueColor ?? const Color(0xFF1E293B),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// ================= SELECTOR STATUS (Dropdown Berwarna) =================
  Widget _statusSelector(int bookingId, String currentStatus) {
    final String safeStatus = _statusOptions.contains(currentStatus) ? currentStatus : 'pending';
    final Color color = _getStatusColor(safeStatus);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: safeStatus,
          isDense: true,
          icon: Icon(Icons.keyboard_arrow_down_rounded, size: 16, color: color),
          style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: color),
          dropdownColor: Colors.white,
          borderRadius: BorderRadius.circular(12),
          items: _statusOptions
              .map((st) => DropdownMenuItem(
                    value: st,
                    child: Text(_getStatusLabel(st)),
                  ))
              .toList(),
          onChanged: (newStatus) {
            if (newStatus != null) {
              _updateBookingStatus(bookingId, newStatus);
            }
          },
        ),
      ),
    );
  }

  /// ================= KARTU BOOKING =================
  Widget _buildBookingCard(dynamic booking) {
    final int bookingId = booking['id'];
    final car = booking['car'] ?? {};
    final renter = booking['user'] ?? {};
    final driver = booking['driver'];
    final bool withDriver = booking['with_driver'] == 1 || booking['with_driver'] == true;
    final String currentStatus = booking['status'] ?? 'pending';
    final String paymentStatus = booking['payment_status'] ?? 'unpaid';
    final String paymentMethod = booking['payment_method'] ?? 'cod';
    final bool isPaid = paymentStatus == 'paid';
    final bool isCheckingThisPayment = _checkingPaymentIds.contains(bookingId);
    final bool isConfirmingThisCash = _confirmingCashIds.contains(bookingId);

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
          // ===== Header: nama mobil + chat + status =====
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
              const SizedBox(width: 4),
              _circleIconButton(
                icon: Icons.chat_bubble_outline_rounded,
                color: const Color(0xFF0D9488),
                tooltip: 'Chat Penyewa',
                onTap: () => _openChatWithRenter(renter),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            renter['name'] ?? 'Penyewa tidak diketahui',
            style: TextStyle(fontSize: 12.5, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 14),

          _infoRow(Icons.date_range_outlined, 'Periode Sewa',
              '$startDateFormatted s/d $endDateFormatted'),
          _infoRow(Icons.timelapse_outlined, 'Durasi', '${booking['total_days']} Hari'),
          _infoRow(
            Icons.key_outlined,
            'Layanan',
            withDriver ? 'Dengan Driver' : 'Lepas Kunci',
            valueColor: withDriver ? const Color(0xFF4F46E5) : null,
          ),

          Container(
            margin: const EdgeInsets.symmetric(vertical: 10),
            height: 1,
            color: Colors.grey.shade100,
          ),

          // ===== Status pesanan =====
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Status Pesanan',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
              _statusSelector(bookingId, currentStatus),
            ],
          ),
          const SizedBox(height: 10),

          _infoRow(Icons.payments_outlined, 'Metode Pembayaran',
              paymentMethod == 'qris' ? 'QRIS' : 'Bayar di Tempat (COD)'),
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
              children: [
                Icon(Icons.verified_outlined, size: 14, color: Colors.grey.shade400),
                const SizedBox(width: 6),
                Text('Status Pembayaran',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
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

          // ===== Menunggu pembayaran QRIS =====
          if (paymentMethod == 'qris' && !isPaid) ...[
            const SizedBox(height: 6),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _primaryColor.withOpacity(0.06),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.hourglass_bottom_rounded, size: 15, color: _primaryColor),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Menunggu penyewa menyelesaikan pembayaran QRIS',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 11.5,
                            color: _primaryColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: _primaryColor,
                        side: BorderSide(color: _primaryColor.withOpacity(0.4)),
                        padding: const EdgeInsets.symmetric(vertical: 9),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      icon: isCheckingThisPayment
                          ? const SizedBox(
                              width: 15,
                              height: 15,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.refresh_rounded, size: 17),
                      label: Text(
                        isCheckingThisPayment ? 'Memeriksa...' : 'Cek Status Pembayaran',
                        style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
                      ),
                      onPressed: isCheckingThisPayment ? null : () => _checkPaymentStatus(bookingId),
                    ),
                  ),
                ],
              ),
            ),
          ],

          // 👇 DITAMBAHKAN: Konfirmasi pembayaran TUNAI (COD).
          // Muncul hanya untuk booking dengan metode COD yang belum lunas.
          // Ini satu-satunya cara payment_status COD bisa berubah jadi
          // 'paid' -- murni aksi manual Perental setelah benar-benar
          // menerima uang tunai dari penyewa (biasanya saat serah-terima
          // mobil), karena tidak ada gateway otomatis seperti Midtrans
          // untuk metode tunai.
          if (paymentMethod == 'cod' && !isPaid) ...[
            const SizedBox(height: 6),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _successColor.withOpacity(0.06),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.payments_rounded, size: 15, color: _successColor),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Belum ada konfirmasi penerimaan tunai dari Anda',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 11.5,
                            color: _successColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _successColor,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(vertical: 9),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      icon: isConfirmingThisCash
                          ? const SizedBox(
                              width: 15,
                              height: 15,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.check_circle_outline_rounded, size: 17),
                      label: Text(
                        isConfirmingThisCash ? 'Menyimpan...' : 'Konfirmasi Tunai Diterima',
                        style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
                      ),
                      onPressed: isConfirmingThisCash
                          ? null
                          : () => _showConfirmCashDialog(bookingId),
                    ),
                  ),
                ],
              ),
            ),
          ],

          // ===== Info driver (kalau layanan dengan driver) =====
          if (withDriver) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _bgColor,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: (driver != null
                                        ? const Color(0xFF16A34A)
                                        : const Color(0xFFDC2626))
                                    .withOpacity(0.1),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Icon(
                                Icons.badge_outlined,
                                size: 16,
                                color: driver != null
                                    ? const Color(0xFF16A34A)
                                    : const Color(0xFFDC2626),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Driver Bertugas',
                                      style: TextStyle(fontSize: 10.5, color: Colors.grey.shade500)),
                                  const SizedBox(height: 1),
                                  Text(
                                    driver != null ? driver['name'] : 'Belum Ditugaskan',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 13,
                                      color: driver != null
                                          ? const Color(0xFF16A34A)
                                          : const Color(0xFFDC2626),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      _actionButton(
                        label: driver != null ? 'Ganti' : 'Tugaskan',
                        icon: Icons.person_add_alt_rounded,
                        color: _accentColor,
                        onPressed: () => _showAssignDriverDialog(bookingId),
                      ),
                    ],
                  ),
                  if (driver != null) ...[
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFF0D9488),
                          side: const BorderSide(color: Color(0xFF0D9488)),
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        icon: const Icon(Icons.chat_bubble_outline_rounded, size: 15),
                        label: const Text('Chat Driver', style: TextStyle(fontSize: 12)),
                        onPressed: () => _openChatWithDriver(driver),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],

          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Total Biaya', style: TextStyle(fontSize: 12.5, color: Colors.grey.shade600)),
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
        ],
      ),
    );
  }

  // 👇 DITAMBAHKAN: dialog konfirmasi sebelum menandai tunai sebagai lunas,
  // supaya Perental tidak salah tekan (aksi ini tidak ada "undo" otomatis
  // di UI, meskipun secara teknis bisa diubah lagi lewat status pesanan).
  void _showConfirmCashDialog(int bookingId) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Konfirmasi Pembayaran Tunai',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        content: Text(
          'Pastikan Anda sudah benar-benar menerima uang tunai dari penyewa '
          'sebelum menandai pesanan ini sebagai LUNAS.',
          style: TextStyle(color: Colors.grey.shade700, fontSize: 13.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Batal', style: TextStyle(color: Colors.grey.shade700)),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(context);
              _confirmCashPayment(bookingId);
            },
            style: FilledButton.styleFrom(
              backgroundColor: _successColor,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('Ya, Sudah Diterima'),
          ),
        ],
      ),
    );
  }

  Widget _circleIconButton({
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
    String? tooltip,
  }) {
    return Material(
      color: color.withOpacity(0.1),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Tooltip(
          message: tooltip ?? '',
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Icon(icon, size: 17, color: color),
          ),
        ),
      ),
    );
  }

  Widget _actionButton({
    required String label,
    required IconData icon,
    required Color color,
    required VoidCallback onPressed,
  }) {
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
      icon: Icon(icon, size: 14),
      label: Text(label, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600)),
    );
  }
}