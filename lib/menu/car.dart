import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:rentalcar/config/api_config.dart';
import 'package:rentalcar/services/api_client.dart';
import 'package:rentalcar/layouts/app.dart';
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

  // ================= BRAND COLORS (tetap di light & dark) =================
  static const Color _primaryColor = Color(0xFF2563EB);
  static const Color _accentColor = Color(0xFFF97316);
  // 🟢 DIHAPUS: _bgColor — body & placeholder pakai token tema

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

  bool get _canManageCars =>
      _userRole != AppRole.penyewa.value && _userRole != AppRole.driver.value;
  bool get _isSuperAdmin => _userRole == 'Super Admin';

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
          _errorMessage =
              'Gagal memuat data mobil (Kode: ${response.statusCode})';
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
        final matchesStatus =
            _statusFilter == 'all' || car['status'] == _statusFilter;

        final name = (car['name'] ?? '').toString().toLowerCase();
        final brand = (car['brand'] ?? '').toString().toLowerCase();
        final plate = (car['plate_number'] ?? '').toString().toLowerCase();

        String ownerStr = '';
        if (car['user'] != null && car['user']['name'] != null) {
          ownerStr = car['user']['name'].toString().toLowerCase();
        } else if (car['owner_name'] != null) {
          ownerStr = car['owner_name'].toString().toLowerCase();
        }

        final query = _searchQuery.toLowerCase();

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

  Future<void> _openEditCar(dynamic car) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => CarAddPage(carData: car)),
    );
    if (result == true) _fetchCars();
  }

  Future<void> _confirmDeleteCar(int carId, String carName) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        // 🟢 Ambil colorScheme dari ctx (punya akses ke theme)
        final colorScheme = Theme.of(ctx).colorScheme;

        return AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Hapus Mobil',
              style: TextStyle(fontWeight: FontWeight.bold)),
          content: Text(
            'Yakin ingin menghapus "$carName"? Tindakan ini tidak dapat dibatalkan.',
            style: TextStyle(
              // 🟢 Ganti Colors.grey.shade700 → onSurfaceVariant
              color: colorScheme.onSurfaceVariant,
              fontSize: 13.5,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(
                'Batal',
                style: TextStyle(
                  // 🟢 Ganti Colors.grey.shade700 → onSurfaceVariant
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: FilledButton.styleFrom(
                // 🟢 Tetap merah semantic — warna destruktif
                backgroundColor: const Color(0xFFDC2626),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
              child: const Text('Hapus'),
            ),
          ],
        );
      },
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
        content: Text(message),
        backgroundColor: color, // 🟢 semantic, tetap
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.all(12),
      ),
    );
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
    final str = numValue.round().toString();
    final buffer = StringBuffer();
    for (int i = 0; i < str.length; i++) {
      final posFromRight = str.length - i;
      buffer.write(str[i]);
      if (posFromRight > 1 && posFromRight % 3 == 1) buffer.write('.');
    }
    return 'Rp $buffer';
  }

  // 🟢 Warna status semantic — tetap di kedua mode
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
    final colorScheme = Theme.of(context).colorScheme;

    return AppLayout(
      title: 'Daftar Mobil Rental',
      currentIndex: 1,
      onTap: (index) {},
      appBarSearchCallback: _onSearchChanged,
      floatingActionButton: _canManageCars
          ? FloatingActionButton.extended(
              // 🟢 Brand di atas tombol — tetap sama di kedua mode
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
                if (result == true) _fetchCars();
              },
            )
          : null,
      content: Container(
        // 🟢 DIHAPUS: color: _bgColor — pakai default tema
        child: Column(
          children: [
            _buildStatusFilterRow(),
            Expanded(
              child: _isLoading
                  ? const Center(
                      child:
                          CircularProgressIndicator(color: _primaryColor))
                  : _errorMessage != null
                      ? _buildErrorState()
                      : _filteredCars.isEmpty
                          ? _buildEmptyState()
                          : RefreshIndicator(
                              color: _primaryColor,
                              onRefresh: _fetchCars,
                              child: ListView.builder(
                                physics:
                                    const AlwaysScrollableScrollPhysics(),
                                itemCount: _filteredCars.length,
                                padding:
                                    const EdgeInsets.fromLTRB(16, 8, 16, 90),
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
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      // 🟢 Ganti Colors.white → colorScheme.surface
      color: colorScheme.surface,
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
    final colorScheme = Theme.of(context).colorScheme;
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
          // 🟢 Selected = putih di atas chip berwarna (tetap)
          // 🟢 Unselected = onSurfaceVariant (bukan grey.shade700)
          color: isSelected ? Colors.white : colorScheme.onSurfaceVariant,
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          fontSize: 12,
        ),
        // 🟢 Ganti Colors.grey.shade50 → surfaceContainerHighest
        backgroundColor: colorScheme.surfaceContainerHighest,
        // 🟢 activeColor = semantic (tetap): hijau/oranye/merah/biru
        selectedColor: activeColor,
        side: BorderSide(
          // 🟢 Unselected border outlineVariant
          color: isSelected ? activeColor : colorScheme.outlineVariant,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        showCheckmark: false,
      ),
    );
  }

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
                // 🟢 0.08 → 0.15, tetap merah semantik
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
              onPressed: _fetchCars,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Coba Lagi'),
              style: ElevatedButton.styleFrom(
                backgroundColor: _primaryColor,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    final colorScheme = Theme.of(context).colorScheme;

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.search_off_rounded,
            size: 48,
            // 🟢 Ganti Colors.grey.shade300 → outline
            color: colorScheme.outline,
          ),
          const SizedBox(height: 12),
          Text(
            _searchQuery.isNotEmpty || _statusFilter != 'all'
                ? 'Tidak ada mobil yang sesuai filter.'
                : 'Belum ada data mobil yang terdaftar.',
            style: TextStyle(
              // 🟢 Ganti Colors.grey.shade600 → onSurfaceVariant
              color: colorScheme.onSurfaceVariant,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCarCard(dynamic car) {
    final colorScheme = Theme.of(context).colorScheme;

    final String status = car['status'] ?? 'tersedia';
    final statusColor = _getStatusColor(status);
    final bool hasImage =
        car['image'] != null && car['image'].toString().isNotEmpty;

    final int carUserId = int.tryParse(car['user_id'].toString()) ?? 0;
    final bool isOwner = _currentUserId != null && carUserId == _currentUserId;
    final bool canEditThisCar = _canManageCars && (isOwner || _isSuperAdmin);

    String ownerName = 'Pemilik Tidak Diketahui';
    if (car['user'] != null && car['user']['name'] != null) {
      ownerName = car['user']['name'];
    } else if (car['owner_name'] != null) {
      ownerName = car['owner_name'];
    }

    // 🟢 Warna brand semantic — sama di kedua mode
    final Color ownerColor = isOwner ? _accentColor : _primaryColor;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        // 🟢 Ganti Colors.white → colorScheme.surface
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            // 🟢 Shadow dari tema
            color: colorScheme.shadow.withOpacity(0.06),
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
            if (canEditThisCar) {
              _openEditCar(car);
            } else {
              Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => CarDetailPage(carId: carId)),
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
                          height: 104,
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
                                // 🟢 Ganti Colors.grey.shade500 → onSurfaceVariant
                                color: colorScheme.onSurfaceVariant,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.4,
                              ),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              // 🟢 0.1 → 0.15, tetap kelihatan di dark
                              color: statusColor.withOpacity(0.15),
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

                          if (canEditThisCar)
                            SizedBox(
                              height: 28,
                              width: 28,
                              child: PopupMenuButton<String>(
                                padding: EdgeInsets.zero,
                                icon: Icon(
                                  Icons.more_vert,
                                  size: 18,
                                  // 🟢 Ganti Colors.grey.shade500 → onSurfaceVariant
                                  color: colorScheme.onSurfaceVariant,
                                ),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12)),
                                onSelected: (value) {
                                  if (value == 'edit') {
                                    _openEditCar(car);
                                  } else if (value == 'delete') {
                                    _confirmDeleteCar(
                                        car['id'], car['name'] ?? 'mobil ini');
                                  }
                                },
                                itemBuilder: (context) {
                                  // 🟢 Ambil colorScheme dari context popup
                                  final popupScheme =
                                      Theme.of(context).colorScheme;

                                  return [
                                    PopupMenuItem(
                                      value: 'edit',
                                      child: Row(children: [
                                        Icon(
                                          Icons.edit_outlined,
                                          size: 18,
                                          // 🟢 Ganti Colors.black87 → onSurface
                                          color: popupScheme.onSurface,
                                        ),
                                        const SizedBox(width: 10),
                                        const Text('Edit Mobil'),
                                      ]),
                                    ),
                                    PopupMenuItem(
                                      value: 'delete',
                                      child: Row(children: [
                                        Icon(
                                          Icons.delete_outline,
                                          size: 18,
                                          // 🟢 Tetap merah semantik
                                          color: popupScheme.error,
                                        ),
                                        const SizedBox(width: 10),
                                        Text(
                                          'Hapus Mobil',
                                          style: TextStyle(
                                            // 🟢 Tetap merah semantik
                                            color: popupScheme.error,
                                          ),
                                        ),
                                      ]),
                                    ),
                                  ];
                                },
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        car['name'] ?? 'Tanpa Nama',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 15.5,
                          fontWeight: FontWeight.bold,
                          // 🟢 Ganti Color(0xFF1E293B) → onSurface
                          color: colorScheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Row(
                        children: [
                          Icon(
                            Icons.confirmation_number_outlined,
                            size: 12.5,
                            // 🟢 Ganti Colors.grey.shade400 → outline
                            color: colorScheme.outline,
                          ),
                          const SizedBox(width: 3),
                          Text(
                            '${car['plate_number'] ?? '-'}',
                            style: TextStyle(
                              fontSize: 11.5,
                              // 🟢 Ganti Colors.grey.shade600 → onSurfaceVariant
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Icon(
                            Icons.calendar_today_outlined,
                            size: 11.5,
                            color: colorScheme.outline,
                          ),
                          const SizedBox(width: 3),
                          Text(
                            '${car['year'] ?? '-'}',
                            style: TextStyle(
                              fontSize: 11.5,
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Icon(
                            Icons.settings_outlined,
                            size: 12.5,
                            color: colorScheme.outline,
                          ),
                          const SizedBox(width: 3),
                          Expanded(
                            child: Text(
                              '${car['engine_type'] ?? '-'}${car['fuel_spec'] != null && car['fuel_spec'].toString().isNotEmpty ? ' (${car['fuel_spec']})' : ''}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 11.5,
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),

                      // 👇 Widget Kepemilikan (Pemilik Mobil)
                      Row(
                        children: [
                          Icon(Icons.person_pin_rounded,
                              size: 13, color: ownerColor), // brand semantic
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              isOwner
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
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            '${_formatPrice(car['price_per_day'])} / hari',
                            style: const TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.bold,
                              // 🟢 Brand biru — tetap
                              color: _primaryColor,
                            ),
                          ),
                          Row(
                            children: [
                              Icon(
                                Icons.event_seat_outlined,
                                size: 13,
                                // 🟢 Ganti Colors.grey.shade500 → onSurfaceVariant
                                color: colorScheme.onSurfaceVariant,
                              ),
                              const SizedBox(width: 3),
                              Text(
                                '${car['seats'] ?? '-'} Kursi',
                                style: TextStyle(
                                  fontSize: 11.5,
                                  // 🟢 Ganti Colors.grey.shade600 → onSurfaceVariant
                                  color: colorScheme.onSurfaceVariant,
                                ),
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
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      width: 92,
      height: 104,
      // 🟢 Ganti _bgColor → surfaceContainerHighest
      color: colorScheme.surfaceContainerHighest,
      child: Icon(
        Icons.directions_car_rounded,
        size: 34,
        // 🟢 Ganti Colors.grey.shade400 → outline
        color: colorScheme.outline,
      ),
    );
  }
}