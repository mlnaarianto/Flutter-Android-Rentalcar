import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:rentalcar/services/api_client.dart'; // 🟢 refresh token otomatis
import 'package:shared_preferences/shared_preferences.dart';

import 'package:rentalcar/config/api_config.dart';
import 'package:rentalcar/layouts/app.dart';
import 'package:rentalcar/menu/car_detail_page.dart';
import 'package:rentalcar/enums/app_enums.dart';
import 'package:rentalcar/services/notification_socket_service.dart'; // 🟢 TAMBAHAN

class Dashboard extends StatefulWidget {
  const Dashboard({super.key});

  @override
  State<Dashboard> createState() => _DashboardState();
}

class _DashboardState extends State<Dashboard> {
  List<dynamic> _allCars = [];
  List<dynamic> _filteredCars = [];
  bool _isLoading = true;
  String _userName = '';
  String _userRole = '';
  String _searchQuery = '';
  int?
  _currentUserId; // 👈 Tambahkan variabel ini untuk ngecek kepemilikan mobil

  // ================= WARNA TEMA =================
  static const Color _primaryColor = Color(0xFF2563EB);
  static const Color _accentColor = Color(0xFFF97316);
  static const Color _bgColor = Color(0xFFF4F6F9);

  @override
  void initState() {
    super.initState();
    _loadUserData();
    _fetchDashboardCars();

    // 🟢 TAMBAHAN: penting untuk kasus user SUDAH LOGIN SEBELUMNYA (buka
    // app lagi dengan token yang masih tersimpan, tanpa lewat LoginPage
    // sama sekali). Tanpa baris ini, koneksi WebSocket cuma akan hidup
    // kalau user baru saja login lewat Google — padahal Dashboard bisa
    // jadi halaman PERTAMA yang dibuka kalau sesi lama masih valid.
    //
    // Aman dipanggil di sini walau LoginPage juga memanggilnya — ada
    // guard _isConnected di dalam service, jadi tidak akan connect dobel.
    NotificationSocketService().connect();
  }

  /// Mengambil data nama, role, dan user_id dari SharedPreferences
  Future<void> _loadUserData() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _userName =
          prefs.getString('user_name') ??
          prefs.getString('email')?.split('@')[0] ??
          'Pengguna';
      _userRole = prefs.getString('role') ?? AppRole.penyewa.value;

      // 👇 Ambil ID user yang sedang login
      final storedId = prefs.get('user_id');
      if (storedId is int) {
        _currentUserId = storedId;
      } else if (storedId is String) {
        _currentUserId = int.tryParse(storedId);
      }
    });
  }

  /// Mengambil data mobil dari API Laravel
  Future<void> _fetchDashboardCars() async {
    if (mounted) setState(() => _isLoading = true);

    try {
      // Token, header Accept/Authorization, dan refresh otomatis
      // ditangani ApiClient.
      final response = await ApiClient.instance
          .get(Uri.parse('${ApiConfig.baseUrl}/cars'))
          .timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final decodedData = jsonDecode(response.body);
        final listCars = decodedData['data'] ?? [];
        if (!mounted) return;
        setState(() {
          _allCars = listCars;
          _filteredCars = listCars;
        });
      } else {
        debugPrint('Dashboard: gagal ambil mobil (${response.statusCode})');
      }
    } catch (e) {
      debugPrint('Dashboard: error ambil mobil: $e');
    } finally {
      // Selalu matikan spinner, apa pun hasilnya.
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// Fungsi untuk filter pencarian
  void _filterCars(String query) {
    setState(() {
      _searchQuery = query;
      if (query.isEmpty) {
        _filteredCars = _allCars;
      } else {
        _filteredCars = _allCars.where((car) {
          final name = (car['name'] ?? '').toString().toLowerCase();
          final brand = (car['brand'] ?? '').toString().toLowerCase();

          // 👇 Tambahkan pencarian berdasarkan nama pemilik
          String ownerStr = '';
          if (car['user'] != null && car['user']['name'] != null) {
            ownerStr = car['user']['name'].toString().toLowerCase();
          } else if (car['owner_name'] != null) {
            ownerStr = car['owner_name'].toString().toLowerCase();
          }

          final input = query.toLowerCase();
          return name.contains(input) ||
              brand.contains(input) ||
              ownerStr.contains(input);
        }).toList();
      }
    });
  }

  String _getImageUrl(String? imagePath) {
    if (imagePath == null || imagePath.isEmpty) return '';
    if (imagePath.startsWith('http://') || imagePath.startsWith('https://')) {
      return imagePath;
    }
    final serverRoot = ApiConfig.baseUrl.replaceAll('/api', '');
    return imagePath.startsWith('/')
        ? '$serverRoot$imagePath'
        : '$serverRoot/storage/$imagePath';
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

  Color _statusColor(String status) {
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

  String _statusLabel(String status) {
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
    return AppLayout(
      title: 'Dashboard',
      currentIndex: 0,
      onTap: (index) {},
      appBarSearchCallback: _filterCars,
      showNotification:
          true, // 🟢 TAMBAHAN: supaya icon notif muncul di Dashboard
      content: RefreshIndicator(
        color: _primaryColor,
        onRefresh: _fetchDashboardCars,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildWelcomeBanner(),
              const SizedBox(height: 22),
              _buildSectionHeader(),
              const SizedBox(height: 14),
              if (_searchQuery.isNotEmpty) _buildSearchIndicator(),
              _buildCarList(),
            ],
          ),
        ),
      ),
    );
  }

  /// ================= BANNER SELAMAT DATANG =================
  Widget _buildWelcomeBanner() {
    final bool isOwner = _userRole == AppRole.perental.value;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [_primaryColor, Color(0xFF3B82F6)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: _primaryColor.withOpacity(0.25),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Halo, $_userName! 👋',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 19,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  isOwner
                      ? 'Kelola armada rental mobil Anda dengan mudah di sini.'
                      : 'Temukan mobil impian untuk perjalanan nyaman Anda hari ini.',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.85),
                    fontSize: 12.5,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(
              isOwner
                  ? Icons.directions_car_filled_rounded
                  : Icons.travel_explore_rounded,
              color: Colors.white,
              size: 26,
            ),
          ),
        ],
      ),
    );
  }

  /// ================= LABEL BAGIAN + JUMLAH UNIT =================
  Widget _buildSectionHeader() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        const Text(
          'Daftar Mobil Tersedia',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Color(0xFF1E293B),
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: _primaryColor.withOpacity(0.08),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            '${_filteredCars.length} Unit',
            style: const TextStyle(
              fontSize: 12,
              color: _primaryColor,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSearchIndicator() {
    return Padding(
      padding: const EdgeInsets.only(top: 10, bottom: 4),
      child: Row(
        children: [
          Icon(Icons.search_rounded, size: 14, color: Colors.grey.shade500),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              'Hasil pencarian untuk: "$_searchQuery"',
              style: TextStyle(
                fontStyle: FontStyle.italic,
                color: Colors.grey.shade600,
                fontSize: 12.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// ================= LIST MOBIL =================
  Widget _buildCarList() {
    if (_isLoading) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(48.0),
          child: CircularProgressIndicator(color: _primaryColor),
        ),
      );
    }

    if (_filteredCars.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(40.0),
          child: Column(
            children: [
              Icon(
                Icons.search_off_rounded,
                size: 44,
                color: Colors.grey.shade400,
              ),
              const SizedBox(height: 12),
              Text(
                _searchQuery.isNotEmpty
                    ? 'Tidak ada mobil yang cocok dengan pencarianmu.'
                    : 'Belum ada mobil yang tersedia.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _filteredCars.length,
      itemBuilder: (context, index) {
        final car = _filteredCars[index];
        return _buildCarCard(car);
      },
    );
  }

  /// ================= KARTU MOBIL =================
  Widget _buildCarCard(dynamic car) {
    final imageUrl = _getImageUrl(car['image']);
    final String status = car['status'] ?? '';
    final statusColor = _statusColor(status);

    // 👇 Cek kepemilikan
    final int carUserId = int.tryParse(car['user_id'].toString()) ?? 0;
    final bool isOwnerCar =
        _currentUserId != null && carUserId == _currentUserId;

    // 👇 Ambil nama pemilik
    String ownerName = 'Pemilik Tidak Diketahui';
    if (car['user'] != null && car['user']['name'] != null) {
      ownerName = car['user']['name'];
    } else if (car['owner_name'] != null) {
      ownerName = car['owner_name'];
    }

    // 👇 Setel warna sesuai kepemilikan
    final Color ownerColor = isOwnerCar ? _accentColor : _primaryColor;

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
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => CarDetailPage(carId: car['id']),
              ),
            );
          },
          child: Padding(
            padding: const EdgeInsets.all(12.0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Stack(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: imageUrl.isNotEmpty
                          ? Image.network(
                              imageUrl,
                              width: 84,
                              height:
                                  94, // 👈 Ditinggikan sedikit agar seimbang dengan tambahan teks
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) =>
                                  _buildPlaceholder(),
                            )
                          : _buildPlaceholder(),
                    ),
                    if (status.isNotEmpty)
                      Positioned(
                        left: 4,
                        bottom: 4,
                        child: Container(
                          width: 9,
                          height: 9,
                          decoration: BoxDecoration(
                            color: statusColor,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 1.6),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
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
                          if (status.isNotEmpty)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: statusColor.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                _statusLabel(status),
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: statusColor,
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        car['name'] ?? 'Mobil Rental',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF1E293B),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Icon(
                            Icons.event_seat_outlined,
                            size: 13,
                            color: Colors.grey.shade400,
                          ),
                          const SizedBox(width: 3),
                          Text(
                            '${car['seats'] ?? '-'} Kursi',
                            style: TextStyle(
                              fontSize: 11.5,
                              color: Colors.grey.shade600,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Icon(
                            Icons.calendar_today_outlined,
                            size: 12,
                            color: Colors.grey.shade400,
                          ),
                          const SizedBox(width: 3),
                          Text(
                            '${car['year'] ?? '-'}',
                            style: TextStyle(
                              fontSize: 11.5,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),

                      // 👇 Tambahan Label Pemilik
                      Row(
                        children: [
                          Icon(
                            Icons.person_pin_rounded,
                            size: 13,
                            color: ownerColor,
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              isOwnerCar
                                  ? 'Milik Anda ($ownerName)'
                                  : 'Milik $ownerName',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w600,
                                color: ownerColor,
                              ),
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 8),
                      Text(
                        '${_formatPrice(car['price_per_day'])} / hari',
                        style: const TextStyle(
                          fontSize: 13.5,
                          color: _primaryColor,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 4),
                Icon(
                  Icons.arrow_forward_ios_rounded,
                  size: 13,
                  color: Colors.grey.shade400,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPlaceholder() {
    return Container(
      width: 84,
      height: 94, // 👈 Samakan dengan tinggi network image
      color: _bgColor,
      child: Icon(
        Icons.directions_car_rounded,
        color: Colors.grey.shade400,
        size: 30,
      ),
    );
  }
}
