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

  final Set<int> _checkingPaymentIds = {};
  final Set<int> _confirmingCashIds = {};

  static const List<String> _statusOptions = [
    'pending',
    'confirmed',
    'active',
    'completed',
    'cancelled',
  ];

  // ================= BRAND & SEMANTIC COLORS (tetap) =================
  static const Color _primaryColor = Color(0xFF2563EB);
  static const Color _accentColor = Color(0xFFF97316);
  static const Color _successColor = Color(0xFF16A34A);
  // 🟢 DIHAPUS: _bgColor

  @override
  void initState() {
    super.initState();
    _loadLocalUserData();
    _fetchBookings();
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

  Future<void> _loadLocalUserData() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;

    setState(() {
      _currentUserId = prefs.getString('user_id');
      _currentUserName =
          prefs.getString('user_name') ?? AppRole.perental.value;
    });
  }

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
              'Gagal memuat data pesanan (Kode: ${response.statusCode})';
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

  Future<List<dynamic>> _fetchAvailableDrivers() async {
    try {
      final response = await ApiClient.instance.get(
        Uri.parse('${ApiConfig.baseUrl}/drivers-list'),
      );

      if (response.statusCode == 200) {
        final decoded = _tryDecodeMap(response.body);
        final data = decoded?['data'];
        return data is List ? data : [];
      }
      return [];
    } catch (e) {
      return [];
    }
  }

  Future<void> _showAssignDriverDialog(int bookingId) async {
    List<dynamic> drivers = await _fetchAvailableDrivers();
    int? selectedDriverId;

    if (!mounted) return;

    if (drivers.isEmpty) {
      _showSnackBar(
          'Tidak ada driver yang tersedia di sistem saat ini.', Colors.red);
      return;
    }

    showDialog(
      context: context,
      builder: (context) {
        // 🟢 Ambil colorScheme dari context dialog
        final colorScheme = Theme.of(context).colorScheme;

        return AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  // 🟢 0.1 → 0.12
                  color: _primaryColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: const Icon(Icons.person_add_alt_rounded,
                    size: 18, color: _primaryColor),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Text('Tugaskan Driver',
                    style:
                        TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
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
                  // 🟢 Ganti _bgColor → surfaceContainerHighest
                  fillColor: colorScheme.surfaceContainerHighest,
                  labelStyle: TextStyle(
                    color: colorScheme.onSurfaceVariant,
                    fontSize: 13,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: colorScheme.outlineVariant),
                  ),
                ),
                // 🟢 Dropdown menu juga ikut tema supaya tidak putih di dark
                dropdownColor: colorScheme.surface,
                style: TextStyle(
                  fontSize: 14,
                  color: colorScheme.onSurface,
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
              child: Text(
                'Batal',
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
                    borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: () async {
                if (selectedDriverId == null) {
                  _showSnackBar(
                      'Silakan pilih driver terlebih dahulu!', Colors.red);
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

  Future<void> _submitAssignDriver(int bookingId, int driverId) async {
    try {
      final response = await ApiClient.instance.patch(
        Uri.parse('${ApiConfig.baseUrl}/bookings/$bookingId/assign-driver'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'driver_id': driverId}),
      );

      final decoded = _tryDecodeMap(response.body);

      if (response.statusCode == 200) {
        if (mounted) {
          _showSnackBar(
              'Driver berhasil ditugaskan!', const Color(0xFF16A34A));
        }
        _fetchBookings();
      } else {
        if (mounted) {
          _showSnackBar(
            decoded?['message']?.toString() ??
                'Gagal menugaskan driver (Kode: ${response.statusCode})',
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

  Future<void> _updateBookingStatus(int bookingId, String newStatus) async {
    try {
      final response = await ApiClient.instance.patch(
        Uri.parse('${ApiConfig.baseUrl}/bookings/$bookingId/status'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'status': newStatus}),
      );

      final decoded = _tryDecodeMap(response.body);

      if (response.statusCode == 200) {
        if (mounted) {
          _showSnackBar(
              'Status booking berhasil diperbarui!', const Color(0xFF16A34A));
        }
        _fetchBookings();
      } else {
        if (mounted) {
          _showSnackBar(
            decoded?['message']?.toString() ??
                'Gagal memperbarui status (Kode: ${response.statusCode})',
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

  Future<void> _checkPaymentStatus(int bookingId) async {
    setState(() => _checkingPaymentIds.add(bookingId));

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
                ? 'Pembayaran penyewa terkonfirmasi LUNAS!'
                : 'Penyewa belum menyelesaikan pembayaran QRIS.',
            newPaymentStatus == 'paid'
                ? const Color(0xFF16A34A)
                : _accentColor,
          );
        }
        _fetchBookings();
      } else {
        if (mounted) {
          _showSnackBar(
            decoded?['message']?.toString() ??
                'Gagal mengecek status pembayaran (Kode: ${response.statusCode})',
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
        setState(() => _checkingPaymentIds.remove(bookingId));
      }
    }
  }

  Future<void> _confirmCashPayment(int bookingId) async {
    setState(() => _confirmingCashIds.add(bookingId));

    try {
      final response = await ApiClient.instance.patch(
        Uri.parse('${ApiConfig.baseUrl}/bookings/$bookingId/status'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'payment_status': 'paid'}),
      );

      final decoded = _tryDecodeMap(response.body);

      if (response.statusCode == 200) {
        if (mounted) {
          _showSnackBar(
              'Pembayaran tunai berhasil dikonfirmasi LUNAS!', _successColor);
        }
        _fetchBookings();
      } else {
        if (mounted) {
          _showSnackBar(
            decoded?['message']?.toString() ??
                'Gagal mengonfirmasi pembayaran tunai (Kode: ${response.statusCode})',
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

  void _openChatWithRenter(Map<String, dynamic> renter) {
    if (_currentUserId == null || _currentUserId!.isEmpty) {
      _showSnackBar(
          'Data akun belum siap, coba lagi sesaat lagi.', Colors.red);
      return;
    }

    final String renterId = renter['id']?.toString() ?? '';
    final String renterName = renter['name'] ?? 'Penyewa';
    final String? renterAvatar = renter['avatar']?.toString();

    if (renterId.isEmpty) {
      _showSnackBar('ID Penyewa tidak valid.', Colors.red);
      return;
    }

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

  void _openChatWithDriver(Map<String, dynamic> driver) {
    if (_currentUserId == null || _currentUserId!.isEmpty) {
      _showSnackBar(
          'Data akun belum siap, coba lagi sesaat lagi.', Colors.red);
      return;
    }

    final String driverId = driver['id']?.toString() ?? '';
    final String driverName = driver['name'] ?? 'Driver';
    final String? driverAvatar = driver['avatar']?.toString();

    if (driverId.isEmpty) {
      _showSnackBar('ID Driver tidak valid.', Colors.red);
      return;
    }

    final String uniqueChatId =
        'room_rental_${_currentUserId}_driver_$driverId';

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
        backgroundColor: color, // 🟢 semantic, tetap
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.all(12),
      ),
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
          'Kelola Pesanan & Driver',
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
                // 🟢 0.08 → 0.15
                color: colorScheme.error.withOpacity(0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.error_outline_rounded,
                  size: 40, color: colorScheme.error),
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

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.inbox_outlined,
            size: 48,
            // 🟢 Ganti Colors.grey.shade400 → outline
            color: colorScheme.outline,
          ),
          const SizedBox(height: 12),
          Text(
            'Belum ada pesanan masuk.',
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

  Widget _infoRow(IconData icon, String label, String value,
      {Color? valueColor}) {
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 14, color: colorScheme.outline),
          const SizedBox(width: 6),
          Text(label,
              style: TextStyle(
                fontSize: 12,
                color: colorScheme.onSurfaceVariant,
              )),
          const Spacer(),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                // 🟢 Ganti Color(0xFF1E293B) → onSurface
                color: valueColor ?? colorScheme.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// ================= SELECTOR STATUS (Dropdown Berwarna) =================
  Widget _statusSelector(int bookingId, String currentStatus) {
    final colorScheme = Theme.of(context).colorScheme;
    final String safeStatus =
        _statusOptions.contains(currentStatus) ? currentStatus : 'pending';
    final Color color = _getStatusColor(safeStatus); // semantic, tetap

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      decoration: BoxDecoration(
        // 🟢 0.1 → 0.15, 0.3 → 0.4 (border) biar tetap kelihatan di dark
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: safeStatus,
          isDense: true,
          icon: Icon(Icons.keyboard_arrow_down_rounded,
              size: 16, color: color),
          style: TextStyle(
              fontSize: 11.5, fontWeight: FontWeight.bold, color: color),
          // 🟢 DIPERBAIKI: sebelumnya hardcode Colors.white — dropdown
          // menu akan putih menyilaukan di dark mode. Sekarang ikut tema.
          dropdownColor: colorScheme.surface,
          borderRadius: BorderRadius.circular(12),
          items: _statusOptions
              .map((st) => DropdownMenuItem(
                    value: st,
                    child: Text(
                      _getStatusLabel(st),
                      // 🟢 Teks item dropdown ikut tema (sebelumnya
                      // style diwarisi dari tombol berwarna → tidak
                      // terbaca di atas bg putih saat dropdown terbuka)
                      style: TextStyle(
                        color: colorScheme.onSurface,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
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
    final colorScheme = Theme.of(context).colorScheme;

    final int bookingId = booking['id'];
    final car = booking['car'] ?? {};
    final renter = booking['user'] ?? {};
    final driver = booking['driver'];
    final bool withDriver =
        booking['with_driver'] == 1 || booking['with_driver'] == true;
    final String currentStatus = booking['status'] ?? 'pending';
    final String paymentStatus = booking['payment_status'] ?? 'unpaid';
    final String paymentMethod = booking['payment_method'] ?? 'cod';
    final bool isPaid = paymentStatus == 'paid';
    final bool isCheckingThisPayment =
        _checkingPaymentIds.contains(bookingId);
    final bool isConfirmingThisCash = _confirmingCashIds.contains(bookingId);

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
          // ===== Header: nama mobil + chat + status =====
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
              const SizedBox(width: 4),
              _circleIconButton(
                icon: Icons.chat_bubble_outline_rounded,
                color: const Color(0xFF0D9488), // teal brand
                tooltip: 'Chat Penyewa',
                onTap: () => _openChatWithRenter(renter),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            renter['name'] ?? 'Penyewa tidak diketahui',
            style: TextStyle(
              fontSize: 12.5,
              // 🟢 Ganti Colors.grey.shade600 → onSurfaceVariant
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 14),

          _infoRow(Icons.date_range_outlined, 'Periode Sewa',
              '$startDateFormatted s/d $endDateFormatted'),
          _infoRow(Icons.timelapse_outlined, 'Durasi',
              '${booking['total_days']} Hari'),
          _infoRow(
            Icons.key_outlined,
            'Layanan',
            withDriver ? 'Dengan Driver' : 'Lepas Kunci',
            // 🟢 Indigo brand — tetap
            valueColor: withDriver ? const Color(0xFF4F46E5) : null,
          ),

          Container(
            margin: const EdgeInsets.symmetric(vertical: 10),
            height: 1,
            // 🟢 Ganti Colors.grey.shade100 → outlineVariant
            color: colorScheme.outlineVariant,
          ),

          // ===== Status pesanan =====
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Status Pesanan',
                  style: TextStyle(
                    fontSize: 12,
                    color: colorScheme.onSurfaceVariant,
                  )),
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
                Icon(Icons.verified_outlined,
                    size: 14, color: colorScheme.outline),
                const SizedBox(width: 6),
                Text('Status Pembayaran',
                    style: TextStyle(
                      fontSize: 12,
                      color: colorScheme.onSurfaceVariant,
                    )),
                const Spacer(),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    // 🟢 0.1 → 0.15, semantic hijau/oranye
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
                      // 🟢 Semantic — tetap
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
                // 🟢 0.06 → 0.12, biar tetap kelihatan di dark
                color: _primaryColor.withOpacity(0.12),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.hourglass_bottom_rounded,
                          size: 15, color: _primaryColor),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Menunggu penyewa menyelesaikan pembayaran QRIS',
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 11.5,
                            // 🟢 Brand biru — tetap
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
                        foregroundColor: _primaryColor, // brand
                        side: BorderSide(
                            color: _primaryColor.withOpacity(0.4)),
                        padding: const EdgeInsets.symmetric(vertical: 9),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                      ),
                      icon: isCheckingThisPayment
                          ? const SizedBox(
                              width: 15,
                              height: 15,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.refresh_rounded, size: 17),
                      label: Text(
                        isCheckingThisPayment
                            ? 'Memeriksa...'
                            : 'Cek Status Pembayaran',
                        style: const TextStyle(
                            fontSize: 12.5, fontWeight: FontWeight.w600),
                      ),
                      onPressed: isCheckingThisPayment
                          ? null
                          : () => _checkPaymentStatus(bookingId),
                    ),
                  ),
                ],
              ),
            ),
          ],

          // ===== Konfirmasi pembayaran TUNAI (COD) =====
          if (paymentMethod == 'cod' && !isPaid) ...[
            const SizedBox(height: 6),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                // 🟢 0.06 → 0.12
                color: _successColor.withOpacity(0.12),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.payments_rounded,
                          size: 15, color: _successColor),
                      const SizedBox(width: 6),
                      const Expanded(
                        child: Text(
                          'Belum ada konfirmasi penerimaan tunai dari Anda',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 11.5,
                            // 🟢 Hijau semantic — tetap
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
                        backgroundColor: _successColor, // semantic
                        foregroundColor: Colors.white,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(vertical: 9),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
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
                          : const Icon(Icons.check_circle_outline_rounded,
                              size: 17),
                      label: Text(
                        isConfirmingThisCash
                            ? 'Menyimpan...'
                            : 'Konfirmasi Tunai Diterima',
                        style: const TextStyle(
                            fontSize: 12.5, fontWeight: FontWeight.w600),
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
                // 🟢 Ganti _bgColor → surfaceContainerHighest
                color: colorScheme.surfaceContainerHighest,
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
                                // 🟢 Semantic hijau/merah, opacity 0.1 → 0.15
                                color: (driver != null
                                        ? const Color(0xFF16A34A)
                                        : const Color(0xFFDC2626))
                                    .withOpacity(0.15),
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
                                      style: TextStyle(
                                        fontSize: 10.5,
                                        // 🟢 Ganti grey.shade500 → onSurfaceVariant
                                        color:
                                            colorScheme.onSurfaceVariant,
                                      )),
                                  const SizedBox(height: 1),
                                  Text(
                                    driver != null
                                        ? driver['name']
                                        : 'Belum Ditugaskan',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 13,
                                      // 🟢 Semantic hijau/merah — tetap
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
                        color: _accentColor, // brand oranye
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
                          foregroundColor: const Color(0xFF0D9488), // teal
                          side: const BorderSide(color: Color(0xFF0D9488)),
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10)),
                        ),
                        icon: const Icon(
                            Icons.chat_bubble_outline_rounded,
                            size: 15),
                        label: const Text('Chat Driver',
                            style: TextStyle(fontSize: 12)),
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
              Text('Total Biaya',
                  style: TextStyle(
                    fontSize: 12.5,
                    color: colorScheme.onSurfaceVariant,
                  )),
              Text(
                _formatPrice(booking['total_price']),
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: _primaryColor, // brand
                  fontSize: 16,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// ================= DIALOG KONFIRMASI TUNAI =================
  void _showConfirmCashDialog(int bookingId) {
    showDialog(
      context: context,
      builder: (context) {
        final colorScheme = Theme.of(context).colorScheme;

        return AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text(
            'Konfirmasi Pembayaran Tunai',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          content: Text(
            'Pastikan Anda sudah benar-benar menerima uang tunai dari penyewa '
            'sebelum menandai pesanan ini sebagai LUNAS.',
            style: TextStyle(
              // 🟢 Ganti Colors.grey.shade700 → onSurfaceVariant
              color: colorScheme.onSurfaceVariant,
              fontSize: 13.5,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(
                'Batal',
                style: TextStyle(
                  // 🟢 Ganti Colors.grey.shade700 → onSurfaceVariant
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(context);
                _confirmCashPayment(bookingId);
              },
              style: FilledButton.styleFrom(
                backgroundColor: _successColor, // semantic hijau
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
              child: const Text('Ya, Sudah Diterima'),
            ),
          ],
        );
      },
    );
  }

  Widget _circleIconButton({
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
    String? tooltip,
  }) {
    return Material(
      // 🟢 0.1 → 0.15, biar tetap kelihatan di dark
      color: color.withOpacity(0.15),
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
        backgroundColor: color, // brand/semantic
        foregroundColor: Colors.white,
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        minimumSize: Size.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      onPressed: onPressed,
      icon: Icon(icon, size: 14),
      label: Text(label,
          style: const TextStyle(
              fontSize: 11.5, fontWeight: FontWeight.w600)),
    );
  }
}