import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:rentalcar/config/api_config.dart';
import 'package:rentalcar/widgets/bottom.dart';
import 'package:rentalcar/menu/car_add.dart';
import 'package:rentalcar/menu/car_detail_page.dart'; // 👈 Import halaman detail mobil

class CarPage extends StatefulWidget {
  const CarPage({super.key});

  @override
  State<CarPage> createState() => _CarPageState();
}

class _CarPageState extends State<CarPage> {
  List<dynamic> _cars = [];
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _fetchCars();
  }

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
          _errorMessage = 'Sesi habis atau token tidak ditemukan. Silakan login kembali.';
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
          _errorMessage = 'Gagal memuat data mobil (Kode: ${response.statusCode})';
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

  /// Helper untuk mendapatkan URL gambar dengan benar tanpa double /storage/
  String _getImageUrl(String? imagePath) {
    if (imagePath == null || imagePath.isEmpty) return '';
    
    // Jika dari backend sudah berupa URL lengkap (mengandung http:// atau https://), gunakan langsung
    if (imagePath.startsWith('http://') || imagePath.startsWith('https://')) {
      return imagePath;
    }
    
    // Jika path relatif, gabungkan dengan domain server & /storage/
    final serverRoot = ApiConfig.baseUrl.replaceAll('/api', '');
    
    // Bersihkan slash ganda jika ada
    if (imagePath.startsWith('/')) {
      return '$serverRoot$imagePath';
    } else {
      return '$serverRoot/storage/$imagePath';
    }
  }

  // Helper untuk warna badge status mobil (tersedia, disewa, perbaikan)
  Color _getStatusColor(String status) {
    switch (status) {
      case 'tersedia':
        return Colors.green;
      case 'disewa':
        return Colors.orange;
      case 'perbaikan':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Daftar Mobil Rental'),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
        actions: [
          // 👇 Batasi Tombol Tambah Mobil berdasarkan Role dari SharedPreferences
          FutureBuilder<SharedPreferences>(
            future: SharedPreferences.getInstance(),
            builder: (context, snapshot) {
              if (!snapshot.hasData) return const SizedBox.shrink();
              
              final prefs = snapshot.data!;
              final role = prefs.getString('role') ?? '';
              
              // Sembunyikan tombol tambah jika role adalah Penyewa atau Driver
              if (role == 'Penyewa' || role == 'Driver') {
                return const SizedBox.shrink();
              }

              return IconButton(
                icon: const Icon(Icons.add),
                tooltip: 'Tambah Mobil',
                onPressed: () async {
                  final result = await Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const CarAddPage()),
                  );
                  if (result == true) {
                    _fetchCars();
                  }
                },
              );
            },
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.error_outline, size: 48, color: Colors.red),
                        const SizedBox(height: 12),
                        Text(_errorMessage!, textAlign: TextAlign.center),
                        const SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: _fetchCars,
                          child: const Text('Coba Lagi'),
                        ),
                      ],
                    ),
                  ),
                )
              : _cars.isEmpty
                  ? const Center(
                      child: Text('Belum ada data mobil yang terdaftar.'),
                    )
                  : ListView.builder(
                      itemCount: _cars.length,
                      padding: const EdgeInsets.all(12),
                      itemBuilder: (context, index) {
                        final car = _cars[index];
                        final status = car['status'] ?? 'tersedia';

                        return Card(
                          margin: const EdgeInsets.only(bottom: 12),
                          elevation: 3,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(12),
                            onTap: () async {
                              // Cek role saat card diklik untuk navigasi dinamis
                              final prefs = await SharedPreferences.getInstance();
                              final role = prefs.getString('role') ?? '';
                              final carId = car['id'];

                              if (role == 'Penyewa' || role == 'Driver') {
                                // Jika Penyewa/Driver, arahkan ke halaman Detail Mobil
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => CarDetailPage(carId: carId),
                                  ),
                                );
                              } else {
                                // Jika Admin/Perental, arahkan ke halaman Edit Mobil
                                final result = await Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => CarAddPage(carData: car),
                                  ),
                                );
                                if (result == true) {
                                  _fetchCars();
                                }
                              }
                            },
                            child: Padding(
                              padding: const EdgeInsets.all(12.0),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(8),
                                    child: car['image'] != null && car['image'].toString().isNotEmpty
                                        ? Image.network(
                                            _getImageUrl(car['image']),
                                            width: 90,
                                            height: 90,
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
                                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                          children: [
                                            Text(
                                              car['brand']?.toUpperCase() ?? '',
                                              style: const TextStyle(
                                                fontSize: 12,
                                                color: Colors.grey,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                            Container(
                                              padding: const EdgeInsets.symmetric(
                                                  horizontal: 8, vertical: 2),
                                              decoration: BoxDecoration(
                                                color: _getStatusColor(status).withOpacity(0.1),
                                                borderRadius: BorderRadius.circular(6),
                                                border: Border.all(
                                                    color: _getStatusColor(status)),
                                              ),
                                              child: Text(
                                                status.toUpperCase(),
                                                style: TextStyle(
                                                  fontSize: 10,
                                                  fontWeight: FontWeight.bold,
                                                  color: _getStatusColor(status),
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          car['name'] ?? 'Tanpa Nama',
                                          style: const TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          'Plat: ${car['plate_number']} • Tahun ${car['year']}',
                                          style: const TextStyle(fontSize: 12, color: Colors.black87),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          'Mesin: ${car['engine_type']}${car['fuel_spec'] != null ? ' (${car['fuel_spec']})' : ''}',
                                          style: const TextStyle(fontSize: 12, color: Colors.grey),
                                        ),
                                        const SizedBox(height: 8),
                                        Row(
                                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                          children: [
                                            Text(
                                              'Rp ${car['price_per_day']} / hari',
                                              style: const TextStyle(
                                                fontSize: 14,
                                                fontWeight: FontWeight.bold,
                                                color: Colors.blue,
                                              ),
                                            ),
                                            Text(
                                              '${car['seats']} Kursi',
                                              style: const TextStyle(
                                                  fontSize: 12, color: Colors.black54),
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
                        );
                      },
                    ),
      bottomNavigationBar: Bottom(
        currentIndex: 1,
        onTap: (index) {},
      ),
    );
  }

  Widget _buildPlaceholderImage() {
    return Container(
      width: 90,
      height: 90,
      color: Colors.grey.shade200,
      child: const Icon(Icons.car_rental, size: 40, color: Colors.grey),
    );
  }
}