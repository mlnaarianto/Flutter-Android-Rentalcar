import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:rentalcar/config/api_config.dart';
import 'package:rentalcar/widgets/bottom.dart';
import 'package:rentalcar/menu/car_add.dart';
import 'package:rentalcar/menu/car_detail_page.dart';
import 'package:rentalcar/enums/app_enums.dart'; // 👈 Import Enums yang baru dibuat

class CarPage extends StatefulWidget {
  const CarPage({super.key});

  @override
  State<CarPage> createState() => _CarPageState();
}

class _CarPageState extends State<CarPage> {
  List<dynamic> _cars = [];
  bool _isLoading = true;
  String? _errorMessage;
  String _userRole = ''; // 👈 role user, diambil sekali di initState

  // ================= WARNA SENADA DENGAN HALAMAN LAIN =================
  static const Color _primaryColor = Color(0xFF2563EB);
  static const Color _accentColor = Color(0xFFF97316);
  static const Color _bgColor = Color(0xFFF4F6F9);

  @override
  void initState() {
    super.initState();
    _loadRole();
    _fetchCars();
  }

  /// Mengambil role user dari SharedPreferences sekali di awal,
  /// dipakai untuk menentukan tombol Tambah & menu Edit/Hapus.
  Future<void> _loadRole() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _userRole = prefs.getString('role') ?? '';
    });
  }

  bool get _canManageCars =>
      _userRole != AppRole.penyewa.value && _userRole != AppRole.driver.value;

  /// Mengambil data mobil langsung dari backend Laravel /api/cars
  Future<void> _fetchCars() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      final String? token = prefs.getString('access_token');

      if (token == null) {
        setState(() {
          _errorMessage =
              'Sesi habis atau token tidak ditemukan. Silakan login kembali.';
          _isLoading = false;
        });
        return;
      }

      final response = await http.get(
        Uri.parse('${ApiConfig.baseUrl}/cars'),
        headers: {
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        final decodedData = jsonDecode(response.body);
        setState(() {
          _cars = decodedData['data'] ?? [];
          _isLoading = false;
        });
      } else {
        setState(() {
          _errorMessage =
              'Gagal memuat data mobil (Kode: ${response.statusCode})';
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

  Future<void> _openEditCar(dynamic car) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => CarAddPage(carData: car)),
    );
    if (result == true) {
      _fetchCars();
    }
  }

  /// Tampilkan dialog konfirmasi sebelum menghapus mobil
  Future<void> _confirmDeleteCar(int carId, String carName) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Hapus Mobil',
            style: TextStyle(fontWeight: FontWeight.bold)),
        content: Text(
          'Yakin ingin menghapus "$carName"? Tindakan ini tidak dapat dibatalkan.',
          style: TextStyle(color: Colors.grey.shade700, fontSize: 13.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Batal',
                style: TextStyle(color: Colors.grey.shade700)),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFDC2626),
              shape:
                  RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('Hapus'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      _deleteCar(carId);
    }
  }

  /// Hapus mobil lewat endpoint DELETE /api/cars/{id}
  Future<void> _deleteCar(int carId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String? token = prefs.getString('access_token');

      if (token == null) {
        if (!mounted) return;
        _showSnackBar('Sesi habis, silakan login kembali.', _accentColor);
        return;
      }

      final response = await http.delete(
        Uri.parse('${ApiConfig.baseUrl}/cars/$carId'),
        headers: {
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        setState(() {
          _cars.removeWhere((car) => car['id'] == carId);
        });
        if (!mounted) return;
        _showSnackBar('Mobil berhasil dihapus', const Color(0xFF16A34A));
      } else {
        String message = 'Gagal menghapus mobil (Kode: ${response.statusCode})';
        try {
          final decoded = jsonDecode(response.body);
          message = decoded['message'] ?? message;
        } catch (_) {
          // biarkan pakai default message kalau body bukan JSON
        }
        if (!mounted) return;
        _showSnackBar(message, Colors.red);
      }
    } catch (e) {
      if (!mounted) return;
      _showSnackBar('Terjadi kesalahan koneksi: $e', Colors.red);
    }
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

  /// Helper untuk mendapatkan URL gambar dengan benar tanpa double /storage/
  String _getImageUrl(String? imagePath) {
    if (imagePath == null || imagePath.isEmpty) return '';

    if (imagePath.startsWith('http://') || imagePath.startsWith('https://')) {
      return imagePath;
    }

    final serverRoot = ApiConfig.baseUrl.replaceAll('/api', '');

    if (imagePath.startsWith('/')) {
      return '$serverRoot$imagePath';
    } else {
      return '$serverRoot/storage/$imagePath';
    }
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

  Color _getStatusColor(String status) {
    switch (status) {
      case 'tersedia':
        return const Color(0xFF16A34A);
      case 'disewa':
        return _accentColor;
      case 'perbaikan':
        return const Color(0xFFDC2626);
      default:
        return Colors.grey;
    }
  }

  String _getStatusLabel(String status) {
    switch (status) {
      case 'tersedia':
        return 'Tersedia';
      case 'disewa':
        return 'Disewa';
      case 'perbaikan':
        return 'Perbaikan';
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
          'Daftar Mobil Rental',
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
      floatingActionButton: _canManageCars
          ? FloatingActionButton.extended(
              backgroundColor: _primaryColor,
              foregroundColor: Colors.white,
              elevation: 2,
              icon: const Icon(Icons.add_rounded),
              label: const Text(
                'Tambah Mobil',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              onPressed: () async {
                final result = await Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const CarAddPage()),
                );
                if (result == true) {
                  _fetchCars();
                }
              },
            )
          : null,
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: _primaryColor))
          : _errorMessage != null
              ? _buildErrorState()
              : _cars.isEmpty
                  ? _buildEmptyState()
                  : RefreshIndicator(
                      color: _primaryColor,
                      onRefresh: _fetchCars,
                      child: ListView.builder(
                        physics: const AlwaysScrollableScrollPhysics(),
                        itemCount: _cars.length,
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
                        itemBuilder: (context, index) {
                          final car = _cars[index];
                          return _buildCarCard(car);
                        },
                      ),
                    ),
      bottomNavigationBar: Bottom(
        currentIndex: 1,
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
              onPressed: _fetchCars,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Coba Lagi'),
              style: ElevatedButton.styleFrom(
                backgroundColor: _primaryColor,
                foregroundColor: Colors.white,
                shape:
                    RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
          Icon(Icons.directions_car_outlined,
              size: 48, color: Colors.grey.shade400),
          const SizedBox(height: 12),
          Text(
            'Belum ada data mobil yang terdaftar.',
            style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
          ),
          if (_canManageCars) ...[
            const SizedBox(height: 6),
            Text(
              'Ketuk tombol "Tambah Mobil" untuk mulai menambahkan armada.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade400, fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }

  /// ================= KARTU MOBIL =================
  Widget _buildCarCard(dynamic car) {
    final String status = car['status'] ?? 'tersedia';
    final statusColor = _getStatusColor(status);
    final bool hasImage =
        car['image'] != null && car['image'].toString().isNotEmpty;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () async {
            final carId = car['id'];

            if (_userRole == AppRole.penyewa.value ||
                _userRole == AppRole.driver.value) {
              // Jika Penyewa/Driver, arahkan ke halaman Detail Mobil
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => CarDetailPage(carId: carId),
                ),
              );
            } else {
              // Jika Admin/Perental, tap kartu tetap langsung ke Edit
              _openEditCar(car);
            }
          },
          child: Padding(
            padding: const EdgeInsets.all(12.0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: hasImage
                      ? Image.network(
                          _getImageUrl(car['image']),
                          width: 92,
                          height: 92,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) =>
                              _buildPlaceholderImage(),
                        )
                      : _buildPlaceholderImage(),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Expanded(
                            child: Text(
                              (car['brand'] ?? '').toString().toUpperCase(),
                              style: TextStyle(
                                fontSize: 10.5,
                                color: Colors.grey.shade500,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.4,
                              ),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: statusColor.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              _getStatusLabel(status),
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: statusColor,
                              ),
                            ),
                          ),
                          // 👇 Menu titik-tiga: Edit & Hapus, hanya untuk yang berhak kelola
                          if (_canManageCars)
                            SizedBox(
                              height: 28,
                              width: 28,
                              child: PopupMenuButton<String>(
                                padding: EdgeInsets.zero,
                                icon: Icon(Icons.more_vert,
                                    size: 18, color: Colors.grey.shade500),
                                tooltip: 'Opsi mobil',
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12)),
                                onSelected: (value) {
                                  if (value == 'edit') {
                                    _openEditCar(car);
                                  } else if (value == 'delete') {
                                    _confirmDeleteCar(
                                      car['id'],
                                      car['name'] ?? 'mobil ini',
                                    );
                                  }
                                },
                                itemBuilder: (context) => [
                                  const PopupMenuItem(
                                    value: 'edit',
                                    child: Row(
                                      children: [
                                        Icon(Icons.edit_outlined,
                                            size: 18, color: Colors.black87),
                                        SizedBox(width: 10),
                                        Text('Edit Mobil'),
                                      ],
                                    ),
                                  ),
                                  const PopupMenuItem(
                                    value: 'delete',
                                    child: Row(
                                      children: [
                                        Icon(Icons.delete_outline,
                                            size: 18, color: Colors.red),
                                        SizedBox(width: 10),
                                        Text('Hapus Mobil',
                                            style:
                                                TextStyle(color: Colors.red)),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        car['name'] ?? 'Tanpa Nama',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 15.5,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF1E293B),
                        ),
                      ),
                      const SizedBox(height: 5),
                      Row(
                        children: [
                          Icon(Icons.confirmation_number_outlined,
                              size: 12.5, color: Colors.grey.shade400),
                          const SizedBox(width: 3),
                          Text(
                            '${car['plate_number'] ?? '-'}',
                            style: TextStyle(
                                fontSize: 11.5, color: Colors.grey.shade600),
                          ),
                          const SizedBox(width: 10),
                          Icon(Icons.calendar_today_outlined,
                              size: 11.5, color: Colors.grey.shade400),
                          const SizedBox(width: 3),
                          Text(
                            '${car['year'] ?? '-'}',
                            style: TextStyle(
                                fontSize: 11.5, color: Colors.grey.shade600),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Icon(Icons.settings_outlined,
                              size: 12.5, color: Colors.grey.shade400),
                          const SizedBox(width: 3),
                          Expanded(
                            child: Text(
                              '${car['engine_type'] ?? '-'}${car['fuel_spec'] != null && car['fuel_spec'].toString().isNotEmpty ? ' (${car['fuel_spec']})' : ''}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontSize: 11.5, color: Colors.grey.shade600),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            '${_formatPrice(car['price_per_day'])} / hari',
                            style: const TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.bold,
                              color: _primaryColor,
                            ),
                          ),
                          Row(
                            children: [
                              Icon(Icons.event_seat_outlined,
                                  size: 13, color: Colors.grey.shade500),
                              const SizedBox(width: 3),
                              Text(
                                '${car['seats'] ?? '-'} Kursi',
                                style: TextStyle(
                                    fontSize: 11.5,
                                    color: Colors.grey.shade600),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPlaceholderImage() {
    return Container(
      width: 92,
      height: 92,
      color: _bgColor,
      child: Icon(Icons.directions_car_rounded,
          size: 34, color: Colors.grey.shade400),
    );
  }
}