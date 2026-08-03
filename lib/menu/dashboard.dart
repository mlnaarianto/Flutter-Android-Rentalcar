import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:rentalcar/config/api_config.dart';
import 'package:rentalcar/layouts/app.dart';
import 'package:rentalcar/menu/car_detail_page.dart';
import 'package:rentalcar/enums/app_enums.dart'; // 👈 Import Enums yang baru dibuat

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

  @override
  void initState() {
    super.initState();
    _loadUserData();
    _fetchDashboardCars();
  }

  /// Mengambil data nama & role asli dari SharedPreferences (Session login)
  Future<void> _loadUserData() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _userName = prefs.getString('user_name') ?? prefs.getString('email')?.split('@')[0] ?? 'Pengguna';
      _userRole = prefs.getString('role') ?? AppRole.penyewa.value;
    });
  }

  /// Mengambil data mobil dari API Laravel
  Future<void> _fetchDashboardCars() async {
    setState(() => _isLoading = true);

    try {
      final prefs = await SharedPreferences.getInstance();
      final String? token = prefs.getString('access_token');

      if (token == null) return;

      final response = await http.get(
        Uri.parse('${ApiConfig.baseUrl}/cars'),
        headers: {
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        final decodedData = jsonDecode(response.body);
        final listCars = decodedData['data'] ?? [];
        setState(() {
          _allCars = listCars;
          _filteredCars = listCars;
          _isLoading = false;
        });
      } else {
        setState(() => _isLoading = false);
      }
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  /// Fungsi untuk filter pencarian dari AppLayout / Navbar search
  void _filterCars(String query) {
    setState(() {
      _searchQuery = query;
      if (query.isEmpty) {
        _filteredCars = _allCars;
      } else {
        _filteredCars = _allCars.where((car) {
          final name = (car['name'] ?? '').toLowerCase();
          final brand = (car['brand'] ?? '').toLowerCase();
          final input = query.toLowerCase();
          return name.contains(input) || brand.contains(input);
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
    return imagePath.startsWith('/') ? '$serverRoot$imagePath' : '$serverRoot/storage/$imagePath';
  }

  @override
  Widget build(BuildContext context) {
    return AppLayout(
      title: 'Dashboard',
      currentIndex: 0,
      onTap: (index) {},
      appBarSearchCallback: _filterCars,
      content: RefreshIndicator(
        onRefresh: _fetchDashboardCars,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 1. Header Banner Selamat Datang dengan Nama Sesi Aktif
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Colors.blue, Colors.blueAccent],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Halo, $_userName! 👋',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      // 👇 Menggunakan AppRole.perental.value agar bersih dari hardcode string
                      _userRole == AppRole.perental.value
                          ? 'Kelola armada rental mobil Anda dengan mudah di sini.'
                          : 'Temukan mobil impian untuk perjalanan nyaman Anda hari ini.',
                      style: const TextStyle(color: Colors.white70, fontSize: 13),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // 2. Label Bagian
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Daftar Mobil Tersedia',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  Text(
                    '${_filteredCars.length} Unit',
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Indikator teks pencarian aktif
              if (_searchQuery.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12.0),
                  child: Text(
                    'Hasil pencarian untuk: "$_searchQuery"',
                    style: const TextStyle(fontStyle: FontStyle.italic, color: Colors.grey, fontSize: 13),
                  ),
                ),

              // 3. List / Grid Konten Mobil
              _isLoading
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(40.0),
                        child: CircularProgressIndicator(),
                      ),
                    )
                  : _filteredCars.isEmpty
                      ? const Center(
                          child: Padding(
                            padding: EdgeInsets.all(40.0),
                            child: Text('Tidak ada mobil yang ditemukan.', style: TextStyle(color: Colors.grey)),
                          ),
                        )
                      : ListView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: _filteredCars.length,
                          itemBuilder: (context, index) {
                            final car = _filteredCars[index];
                            final imageUrl = _getImageUrl(car['image']);

                            return Card(
                              margin: const EdgeInsets.only(bottom: 12),
                              elevation: 2,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(12),
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
                                    children: [
                                      ClipRRect(
                                        borderRadius: BorderRadius.circular(8),
                                        child: imageUrl.isNotEmpty
                                            ? Image.network(
                                                imageUrl,
                                                width: 80,
                                                height: 80,
                                                fit: BoxFit.cover,
                                                errorBuilder: (context, error, stackTrace) =>
                                                    _buildPlaceholder(),
                                              )
                                            : _buildPlaceholder(),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              car['brand']?.toUpperCase() ?? '',
                                              style: const TextStyle(fontSize: 10, color: Colors.grey, fontWeight: FontWeight.bold),
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              car['name'] ?? 'Mobil Rental',
                                              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              'Rp ${car['price_per_day']} / hari',
                                              style: const TextStyle(
                                                fontSize: 13,
                                                color: Colors.blue,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const Icon(Icons.arrow_forward_ios, size: 14, color: Colors.grey),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPlaceholder() {
    return Container(
      width: 80,
      height: 80,
      color: Colors.grey.shade200,
      child: const Icon(Icons.directions_car, color: Colors.grey),
    );
  }
}