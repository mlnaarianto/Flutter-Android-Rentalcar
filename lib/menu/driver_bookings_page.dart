import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:rentalcar/config/api_config.dart';
import 'package:rentalcar/services/api_client.dart';
import 'package:rentalcar/menu/chat.dart';
import 'package:rentalcar/enums/app_enums.dart';

class DriverBookingsPage extends StatefulWidget {
  const DriverBookingsPage({super.key});

  @override
  State<DriverBookingsPage> createState() => _DriverBookingsPageState();
}

class _DriverBookingsPageState extends State<DriverBookingsPage> {
  List<dynamic> _assignedBookings = [];
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
    _loadLocalUserData();
    _fetchDriverBookings();
  }

  String _formatDate(String? dateStr) {
    if (dateStr == null || dateStr.isEmpty) return '-';
    return dateStr.contains('T') ? dateStr.split('T')[0] : dateStr;
  }

  Future<void> _loadLocalUserData() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;

    setState(() {
      _currentUserId = prefs.getString('user_id') ?? '';
      _currentUserName = prefs.getString('user_name') ?? AppRole.driver.value;
    });
  }

  Future<void> _fetchDriverBookings() async {
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
          _assignedBookings = decoded['data'] ?? [];
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
              'Gagal memuat data penugasan (Kode: ${response.statusCode})';
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

  void _openChatWithRentalOwner(Map<String, dynamic> rentalOwner) {
    if (_currentUserId == null || _currentUserId!.isEmpty) {
      _showSnackBar(
          'Data akun belum siap, coba lagi sesaat lagi.', Colors.red);
      return;
    }

    final String ownerId = rentalOwner['id']?.toString() ?? '';
    final String ownerName = rentalOwner['name'] ?? 'Perental';
    final String? ownerAvatar = rentalOwner['avatar']?.toString();

    if (ownerId.isEmpty) {
      _showSnackBar('ID Perental tidak valid.', Colors.red);
      return;
    }

    final String uniqueChatId =
        'room_rental_${ownerId}_driver_$_currentUserId';

    if (!mounted) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ChatPage(
          chatId: uniqueChatId,
          currentUserId: _currentUserId!,
          currentUserName: _currentUserName ?? AppRole.driver.value,
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
          'Tugas Penugasan',
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
              : _assignedBookings.isEmpty
                  ? _buildEmptyState()
                  : RefreshIndicator(
                      color: _primaryColor,
                      onRefresh: _fetchDriverBookings,
                      child: ListView.builder(
                        physics: const AlwaysScrollableScrollPhysics(),
                        itemCount: _assignedBookings.length,
                        padding: const EdgeInsets.all(16),
                        itemBuilder: (context, index) {
                          return _buildAssignmentCard(
                              _assignedBookings[index]);
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
                // 🟢 0.08 → 0.15, semantic error
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
              onPressed: _fetchDriverBookings,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Coba Lagi'),
              style: ElevatedButton.styleFrom(
                backgroundColor: _primaryColor, // brand
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
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.directions_car_outlined,
              size: 48,
              // 🟢 Ganti Colors.grey.shade400 → outline
              color: colorScheme.outline,
            ),
            const SizedBox(height: 12),
            Text(
              'Belum ada penugasan rental.',
              style: TextStyle(
                // 🟢 Ganti Colors.grey.shade600 → onSurfaceVariant
                color: colorScheme.onSurfaceVariant,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Perental yang terhubung akan muncul di sini\nsetelah kamu ditugaskan pada sebuah booking.',
              textAlign: TextAlign.center,
              style: TextStyle(
                // 🟢 Ganti Colors.grey.shade400 → outline
                color: colorScheme.outline,
                fontSize: 11.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _infoRow(IconData icon, String label, String value,
      {Color? valueColor, FontWeight? valueWeight}) {
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

  /// ================= KARTU PENUGASAN =================
  Widget _buildAssignmentCard(dynamic booking) {
    final colorScheme = Theme.of(context).colorScheme;

    final car = booking['car'] ?? {};
    final renter = booking['user'] ?? {};
    final rentalOwner = booking['rental_owner'] ??
        booking['perental'] ??
        car['user'] ??
        {};
    final String status = booking['status'] ?? 'pending';
    final statusColor = _getStatusColor(status); // semantic, tetap

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
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
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
                    color: statusColor, // semantic
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // ===== Detail penugasan =====
          _infoRow(Icons.person_outline_rounded, 'Penyewa Mobil',
              renter['name'] ?? '-'),
          _infoRow(Icons.date_range_outlined, 'Jadwal',
              '$startDateFormatted s/d $endDateFormatted'),

          Container(
            margin: const EdgeInsets.symmetric(vertical: 10),
            height: 1,
            // 🟢 Ganti Colors.grey.shade100 → outlineVariant
            color: colorScheme.outlineVariant,
          ),

          // ===== Info perental & tombol chat =====
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              // 🟢 Ganti _bgColor → surfaceContainerHighest
              color: colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          // 🟢 0.1 → 0.15
                          color: _primaryColor.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.storefront_rounded,
                            size: 16, color: _primaryColor),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Pengelola / Perental',
                              style: TextStyle(
                                fontSize: 10.5,
                                // 🟢 Ganti Colors.grey.shade500 → onSurfaceVariant
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(height: 1),
                            Text(
                              rentalOwner['name'] ?? 'Admin Rental',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                                // 🟢 Ganti Color(0xFF1E293B) → onSurface
                                color: colorScheme.onSurface,
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
                  label: 'Chat',
                  icon: Icons.chat_bubble_outline_rounded,
                  color: const Color(0xFF0D9488), // teal brand, tetap
                  onPressed: () => _openChatWithRentalOwner(rentalOwner),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _actionButton({
    required String label,
    required IconData icon,
    required Color color, // brand semantic
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
      icon: Icon(icon, size: 15),
      label: Text(label,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
    );
  }
}