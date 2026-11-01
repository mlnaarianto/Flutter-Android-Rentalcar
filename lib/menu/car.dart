import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:rentalcar/config/api_config.dart';
import 'package:rentalcar/services/api_client.dart';
import 'package:rentalcar/layouts/app.dart'; // Pastikan path ini benar sesuai diskusi sebelumnya
import 'package:rentalcar/menu/car_add.dart';
import 'package:rentalcar/menu/car_detail_page.dart';
import 'package:rentalcar/enums/app_enums.dart';

class CarPage extends StatefulWidget {
  const CarPage({super.key});

  @override
  State<CarPage> createState() => _CarPageState();
}

class _CarPageState extends State<CarPage> {
  // ================= STATE VARIABLES =================
  List<dynamic> _cars = [];
  List<dynamic> _filteredCars = [];
  
  bool _isLoading = true;
  String? _errorMessage;
  String _userRole = ''; 
  int? _currentUserId;

  String _searchQuery = '';
  String _statusFilter = 'all';

  static const Color _primaryColor = Color(0xFF2563EB);
  static const Color _accentColor = Color(0xFFF97316);
  static const Color _bgColor = Color(0xFFF4F6F9);

  @override
  void initState() {
    super.initState();
    _loadRole();
    _fetchCars();
  }

  Future<void> _loadRole() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    
    setState(() {
      _userRole = prefs.getString('role') ?? '';
      final storedId = prefs.get('user_id');
      if (storedId is int) {
        _currentUserId = storedId;
      } else if (storedId is String) {
        _currentUserId = int.tryParse(storedId);
      }
    });
  }

  bool get _canManageCars => _userRole != AppRole.penyewa.value && _userRole != AppRole.driver.value;
  bool get _isSuperAdmin => _userRole == 'Super Admin'; 

  // Token dipasang dan di-refresh otomatis oleh ApiClient. Kalau sesi
  // benar-benar mati, onSessionExpired di main.dart yang mengarahkan ke login.
  Future<void> _fetchCars() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final response = await ApiClient.instance.get(
        Uri.parse('${ApiConfig.baseUrl}/cars'),
      );

      if (!mounted) return;

      if (response.statusCode == 200) {
        final decodedData = jsonDecode(response.body);
        setState(() {
          _cars = decodedData['data'] ?? [];
          _filteredCars = List.from(_cars);
          _applyFilters();
          _isLoading = false;
        });
      } else if (response.statusCode == 401) {
        setState(() {
          _errorMessage = 'Sesi habis. Silakan login kembali.';
          _isLoading = false;
        });
      } else {
        setState(() {
          _errorMessage = 'Gagal memuat data mobil (Kode: ${response.statusCode})';
          _isLoading = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Terjadi kesalahan koneksi ke server: $e';
        _isLoading = false;
      });
    }
  }

  // ================= LOGIKA FILTERING =================
  void _applyFilters() {
    setState(() {
      _filteredCars = _cars.where((car) {
        final matchesStatus = _statusFilter == 'all' || car['status'] == _statusFilter;
        
        final name = (car['name'] ?? '').toString().toLowerCase();
        final brand = (car['brand'] ?? '').toString().toLowerCase();
        final plate = (car['plate_number'] ?? '').toString().toLowerCase();
        
        // 👇 Ambil nama pemilik dari relasi user atau fallback ke owner_name
        String ownerStr = '';
        if (car['user'] != null && car['user']['name'] != null) {
          ownerStr = car['user']['name'].toString().toLowerCase();
        } else if (car['owner_name'] != null) {
          ownerStr = car['owner_name'].toString().toLowerCase();
        }

        final query = _searchQuery.toLowerCase();
        
        // 👇 Cek juga apakah query ada di dalam nama pemilik
        final matchesSearch = query.isEmpty || 
                              name.contains(query) || 
                              brand.contains(query) || 
                              plate.contains(query) ||
                              ownerStr.contains(query);

        return matchesStatus && matchesSearch;
      }).toList();
    });
  }

  void _onSearchChanged(String query) {
    _searchQuery = query;
    _applyFilters();
  }

  void _onStatusFilterChanged(String status) {
    _statusFilter = status;
    _applyFilters();
  }
  // =====================================================

  Future<void> _openEditCar(dynamic car) async {
    final result = await Navigator.push(context, MaterialPageRoute(builder: (_) => CarAddPage(carData: car)));
    if (result == true) _fetchCars();
  }

  Future<void> _confirmDeleteCar(int carId, String carName) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Hapus Mobil', style: TextStyle(fontWeight: FontWeight.bold)),
        content: Text(
          'Yakin ingin menghapus "$carName"? Tindakan ini tidak dapat dibatalkan.',
          style: TextStyle(color: Colors.grey.shade700, fontSize: 13.5),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text('Batal', style: TextStyle(color: Colors.grey.shade700))),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFFDC2626), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
            child: const Text('Hapus'),
          ),
        ],
      ),
    );

    if (confirm == true) _deleteCar(carId);
  }

  Future<void> _deleteCar(int carId) async {
    try {
      final response = await ApiClient.instance.delete(
        Uri.parse('${ApiConfig.baseUrl}/cars/$carId'),
      );

      if (!mounted) return;

      if (response.statusCode == 200) {
        setState(() {
          _cars.removeWhere((car) => car['id'] == carId);
          _applyFilters();
        });
        _showSnackBar('Mobil berhasil dihapus', const Color(0xFF16A34A));
      } else if (response.statusCode == 401) {
        _showSnackBar('Sesi habis. Silakan login kembali.', Colors.red);
      } else {
        _showSnackBar('Gagal menghapus mobil', Colors.red);
      }
    } catch (e) {
      if (!mounted) return;
      _showSnackBar('Terjadi kesalahan koneksi', Colors.red);
    }
  }

  void _showSnackBar(String message, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message), backgroundColor: color, behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)), margin: const EdgeInsets.all(12),
      ),
    );
  }

  String _getImageUrl(String? imagePath) {
    if (imagePath == null || imagePath.isEmpty) return '';
    if (imagePath.startsWith('http://') || imagePath.startsWith('https://')) return imagePath;
    final serverRoot = ApiConfig.baseUrl.replaceAll('/api', '');
    return imagePath.startsWith('/') ? '$serverRoot$imagePath' : '$serverRoot/storage/$imagePath';
  }

  String _formatPrice(dynamic raw) {
    if (raw == null) return 'Rp 0';
    final numValue = num.tryParse(raw.toString()) ?? 0;
    final str = numValue.round().toString();
    final buffer = StringBuffer();
    for (int i = 0; i < str.length; i++) {
      final posFromRight = str.length - i;
      buffer.write(str[i]);
      if (posFromRight > 1 && posFromRight % 3 == 1) buffer.write('.');
    }
    return 'Rp $buffer';
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'tersedia': return const Color(0xFF16A34A);
      case 'disewa': return _accentColor;
      case 'perbaikan': return const Color(0xFFDC2626);
      default: return Colors.grey;
    }
  }

  String _getStatusLabel(String status) {
    switch (status) {
      case 'tersedia': return 'Tersedia';
      case 'disewa': return 'Disewa';
      case 'perbaikan': return 'Perbaikan';
      default: return status.isEmpty ? '-' : status;
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppLayout(
      title: 'Daftar Mobil Rental',
      currentIndex: 1, 
      onTap: (index) {
        // Logika perpindahan tab Anda di sini
      },
      appBarSearchCallback: _onSearchChanged, 
      floatingActionButton: _canManageCars
          ? FloatingActionButton.extended(
              backgroundColor: _primaryColor,
              foregroundColor: Colors.white,
              elevation: 2,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Tambah Mobil', style: TextStyle(fontWeight: FontWeight.w600)),
              onPressed: () async {
                final result = await Navigator.push(context, MaterialPageRoute(builder: (_) => const CarAddPage()));
                if (result == true) _fetchCars();
              },
            )
          : null,
      content: Container(
        color: _bgColor,
        child: Column(
          children: [
            _buildStatusFilterRow(),
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator(color: _primaryColor))
                  : _errorMessage != null
                      ? _buildErrorState()
                      : _filteredCars.isEmpty
                          ? _buildEmptyState()
                          : RefreshIndicator(
                              color: _primaryColor,
                              onRefresh: _fetchCars,
                              child: ListView.builder(
                                physics: const AlwaysScrollableScrollPhysics(),
                                itemCount: _filteredCars.length,
                                padding: const EdgeInsets.fromLTRB(16, 8, 16, 90),
                                itemBuilder: (context, index) {
                                  final car = _filteredCars[index];
                                  return _buildCarCard(car);
                                },
                              ),
                            ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusFilterRow() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      width: double.infinity,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _buildFilterChip('Semua', 'all', Colors.blue),
            _buildFilterChip('Tersedia', 'tersedia', const Color(0xFF16A34A)),
            _buildFilterChip('Disewa', 'disewa', _accentColor),
            _buildFilterChip('Perbaikan', 'perbaikan', const Color(0xFFDC2626)),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterChip(String label, String value, Color activeColor) {
    final isSelected = _statusFilter == value;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label),
        selected: isSelected,
        onSelected: (selected) {
          if (selected) _onStatusFilterChanged(value);
        },
        labelStyle: TextStyle(
          color: isSelected ? Colors.white : Colors.grey.shade700,
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          fontSize: 12,
        ),
        backgroundColor: Colors.grey.shade50,
        selectedColor: activeColor,
        side: BorderSide(
          color: isSelected ? activeColor : Colors.grey.shade300,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        showCheckmark: false,
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(color: Colors.red.withOpacity(0.08), shape: BoxShape.circle),
              child: const Icon(Icons.error_outline_rounded, size: 40, color: Colors.red),
            ),
            const SizedBox(height: 16),
            Text(_errorMessage!, textAlign: TextAlign.center, style: TextStyle(color: Colors.grey.shade700, fontSize: 14)),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: _fetchCars,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Coba Lagi'),
              style: ElevatedButton.styleFrom(
                backgroundColor: _primaryColor,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.search_off_rounded, size: 48, color: Colors.grey.shade300),
          const SizedBox(height: 12),
          Text(
            _searchQuery.isNotEmpty || _statusFilter != 'all' 
                ? 'Tidak ada mobil yang sesuai filter.'
                : 'Belum ada data mobil yang terdaftar.',
            style: TextStyle(color: Colors.grey.shade600, fontSize: 14, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }

  Widget _buildCarCard(dynamic car) {
    final String status = car['status'] ?? 'tersedia';
    final statusColor = _getStatusColor(status);
    final bool hasImage = car['image'] != null && car['image'].toString().isNotEmpty;

    final int carUserId = int.tryParse(car['user_id'].toString()) ?? 0;
    final bool isOwner = _currentUserId != null && carUserId == _currentUserId;
    final bool canEditThisCar = _canManageCars && (isOwner || _isSuperAdmin);

    // 👇 Ambil nama pemilik untuk ditampilkan di UI
    String ownerName = 'Pemilik Tidak Diketahui';
    if (car['user'] != null && car['user']['name'] != null) {
      ownerName = car['user']['name'];
    } else if (car['owner_name'] != null) {
      ownerName = car['owner_name'];
    }

    // 👇 Tentukan warna berdasarkan kepemilikan
    final Color ownerColor = isOwner ? _accentColor : _primaryColor;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 12, offset: const Offset(0, 4)),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () async {
            final carId = car['id'];
            if (canEditThisCar) {
              _openEditCar(car);
            } else {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => CarDetailPage(carId: carId)),
              );
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
                          height: 104, // 👈 Sedikit ditambah tinggi gambarnya biar balance
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) => _buildPlaceholderImage(),
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
                              style: TextStyle(fontSize: 10.5, color: Colors.grey.shade500, fontWeight: FontWeight.bold, letterSpacing: 0.4),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: statusColor.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              _getStatusLabel(status),
                              style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: statusColor),
                            ),
                          ),
                          
                          if (canEditThisCar)
                            SizedBox(
                              height: 28,
                              width: 28,
                              child: PopupMenuButton<String>(
                                padding: EdgeInsets.zero,
                                icon: Icon(Icons.more_vert, size: 18, color: Colors.grey.shade500),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                onSelected: (value) {
                                  if (value == 'edit') {
                                    _openEditCar(car);
                                  } else if (value == 'delete') {
                                    _confirmDeleteCar(car['id'], car['name'] ?? 'mobil ini');
                                  }
                                },
                                itemBuilder: (context) => [
                                  const PopupMenuItem(value: 'edit', child: Row(children: [Icon(Icons.edit_outlined, size: 18, color: Colors.black87), SizedBox(width: 10), Text('Edit Mobil')])),
                                  const PopupMenuItem(value: 'delete', child: Row(children: [Icon(Icons.delete_outline, size: 18, color: Colors.red), SizedBox(width: 10), Text('Hapus Mobil', style: TextStyle(color: Colors.red))])),
                                ],
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(car['name'] ?? 'Tanpa Nama', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.bold, color: Color(0xFF1E293B))),
                      const SizedBox(height: 5),
                      Row(
                        children: [
                          Icon(Icons.confirmation_number_outlined, size: 12.5, color: Colors.grey.shade400),
                          const SizedBox(width: 3),
                          Text('${car['plate_number'] ?? '-'}', style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600)),
                          const SizedBox(width: 10),
                          Icon(Icons.calendar_today_outlined, size: 11.5, color: Colors.grey.shade400),
                          const SizedBox(width: 3),
                          Text('${car['year'] ?? '-'}', style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600)),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Icon(Icons.settings_outlined, size: 12.5, color: Colors.grey.shade400),
                          const SizedBox(width: 3),
                          Expanded(
                            child: Text(
                              '${car['engine_type'] ?? '-'}${car['fuel_spec'] != null && car['fuel_spec'].toString().isNotEmpty ? ' (${car['fuel_spec']})' : ''}',
                              maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      
                      // 👇 Widget Kepemilikan (Pemilik Mobil) 
                      Row(
                        children: [
                          Icon(Icons.person_pin_rounded, size: 13, color: ownerColor),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              isOwner ? 'Milik Anda ($ownerName)' : 'Milik $ownerName',
                              maxLines: 1, 
                              overflow: TextOverflow.ellipsis, 
                              style: TextStyle(
                                fontSize: 11.5, 
                                fontWeight: FontWeight.w600, 
                                color: ownerColor, // 👈 Warnanya dinamis sesuai pesanan Anda
                              ),
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('${_formatPrice(car['price_per_day'])} / hari', style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.bold, color: _primaryColor)),
                          Row(
                            children: [
                              Icon(Icons.event_seat_outlined, size: 13, color: Colors.grey.shade500),
                              const SizedBox(width: 3),
                              Text('${car['seats'] ?? '-'} Kursi', style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600)),
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
      height: 104,
      color: _bgColor,
      child: Icon(Icons.directions_car_rounded, size: 34, color: Colors.grey.shade400),
    );
  }
}