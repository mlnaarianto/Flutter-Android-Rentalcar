import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:rentalcar/config/api_config.dart';

class CarDetailPage extends StatefulWidget {
  final int carId;

  const CarDetailPage({super.key, required this.carId});

  @override
  State<CarDetailPage> createState() => _CarDetailPageState();
}

class _CarDetailPageState extends State<CarDetailPage> {
  Map<String, dynamic>? _car;
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _fetchCarDetail();
  }

  Future<void> _fetchCarDetail() async {
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
        Uri.parse('${ApiConfig.baseUrl}/cars/${widget.carId}'),
        headers: {
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          _car = data['data'];
          _isLoading = false;
        });
      } else {
        setState(() {
          _errorMessage = 'Gagal memuat detail mobil (Kode: ${response.statusCode})';
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
    // 👇 Ambil data user/pemilik dari relasi backend
    final ownerData = _car?['user'] ?? _car?['owner'];
    final ownerName = ownerData != null ? (ownerData['name'] ?? 'Tidak diketahui') : 'Administrator / Perental';
    final ownerEmail = ownerData != null ? (ownerData['email'] ?? '-') : '';

    // 👇 Ambil data dari tabel personal_data melalui relasi user
    final personalData = ownerData != null ? ownerData['personal_data'] : null;
    final ownerPhone = personalData != null ? (personalData['phone'] ?? '-') : '-';
    final ownerAddress = personalData != null ? (personalData['address'] ?? '-') : '-';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Detail Mobil'),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Text(_errorMessage!, textAlign: TextAlign.center),
                  ),
                )
              : _car == null
                  ? const Center(child: Text('Data mobil tidak ditemukan.'))
                  : SingleChildScrollView(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Gambar Mobil
                          ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: _car!['image'] != null && _car!['image'].toString().isNotEmpty
                                ? Image.network(
                                    _getImageUrl(_car!['image']),
                                    width: double.infinity,
                                    height: 220,
                                    fit: BoxFit.cover,
                                    errorBuilder: (context, error, stackTrace) =>
                                        _buildPlaceholderImage(),
                                  )
                                : _buildPlaceholderImage(),
                          ),
                          const SizedBox(height: 16),
                          
                          // Brand & Status
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                (_car!['brand'] ?? '').toUpperCase(),
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.grey,
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: _getStatusColor(_car!['status'] ?? '').withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(color: _getStatusColor(_car!['status'] ?? '')),
                                ),
                                child: Text(
                                  (_car!['status'] ?? '').toUpperCase(),
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: _getStatusColor(_car!['status'] ?? ''),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),

                          // Nama Mobil
                          Text(
                            _car!['name'] ?? 'Tanpa Nama',
                            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 12),

                          // Harga Sewa
                          Text(
                            'Rp ${_car!['price_per_day']} / hari',
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.blue,
                            ),
                          ),
                          const Divider(height: 24),

                          // Informasi Pemilik / Perental Mobil
                          const Text(
                            'Informasi Pemilik / Perental',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 8),
                          _buildInfoRow(Icons.person, 'Nama Pengelola', ownerName),
                          if (ownerEmail.isNotEmpty)
                            _buildInfoRow(Icons.email, 'Email', ownerEmail),
                          _buildInfoRow(Icons.phone, 'Nomor HP', ownerPhone),
                          _buildInfoRow(Icons.location_on, 'Alamat', ownerAddress),
                          const Divider(height: 24),

                          // Informasi Spesifikasi
                          const Text(
                            'Spesifikasi Kendaraan',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 8),
                          _buildInfoRow(Icons.confirmation_number, 'Plat Nomor', _car!['plate_number']),
                          _buildInfoRow(Icons.settings, 'Tipe Mesin', _car!['engine_type']),
                          if (_car!['fuel_spec'] != null && _car!['fuel_spec'].toString().isNotEmpty)
                            _buildInfoRow(Icons.local_gas_station, 'Spesifikasi BBM', _car!['fuel_spec']),
                          _buildInfoRow(Icons.airline_seat_recline_normal, 'Kapasitas Kursi', '${_car!['seats']} Kursi'),
                          _buildInfoRow(Icons.calendar_today, 'Tahun Pembuatan', '${_car!['year']}'),

                          const SizedBox(height: 16),
                          const Text(
                            'Deskripsi',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            _car!['description'] ?? 'Tidak ada deskripsi tambahan.',
                            style: const TextStyle(color: Colors.black87, height: 1.4),
                          ),
                        ],
                      ),
                    ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: Colors.blue),
          const SizedBox(width: 12),
          SizedBox(
            width: 110,
            child: Text('$label:', style: const TextStyle(fontWeight: FontWeight.w500)),
          ),
          Expanded(child: Text(value, style: const TextStyle(color: Colors.black87))),
        ],
      ),
    );
  }

  Widget _buildPlaceholderImage() {
    return Container(
      width: double.infinity,
      height: 220,
      color: Colors.grey.shade200,
      child: const Icon(Icons.car_rental, size: 60, color: Colors.grey),
    );
  }
}