import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:rentalcar/config/api_config.dart';
import 'package:rentalcar/menu/profil.dart';
import 'package:rentalcar/enums/app_enums.dart'; // 👈 Import Enums agar konsisten

class CarAddPage extends StatefulWidget {
  final Map<String, dynamic>? carData; // Jika ada data, berarti mode Edit

  const CarAddPage({super.key, this.carData});

  @override
  State<CarAddPage> createState() => _CarAddPageState();
}

class _CarAddPageState extends State<CarAddPage> {
  final _formKey = GlobalKey<FormState>();

  // Controller Input Form
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _brandController = TextEditingController();
  final TextEditingController _plateController = TextEditingController();
  final TextEditingController _seatsController = TextEditingController();
  final TextEditingController _yearController = TextEditingController();
  final TextEditingController _priceController = TextEditingController();
  final TextEditingController _driverPriceController = TextEditingController();
  final TextEditingController _descController = TextEditingController();
  final TextEditingController _fuelSpecController = TextEditingController();
  final TextEditingController _videoUrlController = TextEditingController();

  // Nilai Default Dropdown
  String _engineType = 'Bensin (Gasoline)';
  String _status = 'tersedia';

  final List<String> _engineTypes = [
    'Bensin (Gasoline)',
    'Diesel (Gasoil)',
    'Listrik (Electric / EV)',
    'Hybrid (HEV / PHEV)',
  ];
  final List<String> _statuses = ['tersedia', 'disewa', 'perbaikan'];

  File? _imageFile;
  String? _existingImageUrl;
  bool _isLoading = false;
  bool get _isEditMode => widget.carData != null;

  // ================= WARNA SENADA DENGAN CarDetailPage =================
  static const Color _primaryColor = Color(0xFF2563EB);
  static const Color _accentColor = Color(0xFFF97316);
  static const Color _bgColor = Color(0xFFF4F6F9);

  @override
  void initState() {
    super.initState();
    if (_isEditMode) {
      final car = widget.carData!;
      _nameController.text = car['name'] ?? '';
      _brandController.text = car['brand'] ?? '';
      _plateController.text = car['plate_number'] ?? '';
      _seatsController.text = car['seats']?.toString() ?? '';
      _yearController.text = car['year']?.toString() ?? '';
      _priceController.text = car['price_per_day']?.toString() ?? '';
      _driverPriceController.text =
          car['driver_price_per_day']?.toString() ?? '';
      _descController.text = car['description'] ?? '';
      _fuelSpecController.text = car['fuel_spec'] ?? '';
      _videoUrlController.text = car['video_url'] ?? '';

      if (_engineTypes.contains(car['engine_type'])) {
        _engineType = car['engine_type'];
      } else if (car['engine_type'] != null) {
        final matched = _engineTypes.firstWhere(
          (e) => e
              .toLowerCase()
              .startsWith(car['engine_type'].toString().toLowerCase()),
          orElse: () => 'Bensin (Gasoline)',
        );
        _engineType = matched;
      }

      if (_statuses.contains(car['status'])) {
        _status = car['status'];
      }
      _existingImageUrl = car['image'];
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

  Future<void> _pickImage() async {
    final pickedFile = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
    );
    if (pickedFile != null) {
      setState(() {
        _imageFile = File(pickedFile.path);
      });
    }
  }

  Future<void> _submitCar() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      final String? token = prefs.getString('access_token');

      if (token == null) {
        _showSnackBar('Sesi habis. Silakan login kembali.', Colors.red);
        setState(() => _isLoading = false);
        return;
      }

      final String url = _isEditMode
          ? '${ApiConfig.baseUrl}/cars/${widget.carData!['id']}'
          : '${ApiConfig.baseUrl}/cars';

      var request = http.MultipartRequest('POST', Uri.parse(url));

      request.headers.addAll({
        'Accept': 'application/json',
        'Authorization': 'Bearer $token',
      });

      if (_isEditMode) {
        request.fields['_method'] = 'PUT';
      }

      request.fields['name'] = _nameController.text.trim();
      request.fields['brand'] = _brandController.text.trim();
      request.fields['plate_number'] = _plateController.text.trim();
      request.fields['engine_type'] = _engineType.trim();
      request.fields['fuel_spec'] = _fuelSpecController.text.trim();
      request.fields['seats'] = _seatsController.text.trim();
      request.fields['year'] = _yearController.text.trim();
      request.fields['price_per_day'] = _priceController.text.trim();
      request.fields['driver_price_per_day'] =
          _driverPriceController.text.trim();
      request.fields['description'] = _descController.text.trim();
      request.fields['video_url'] = _videoUrlController.text.trim();
      request.fields['status'] = _status;

      if (_imageFile != null) {
        request.files.add(
          await http.MultipartFile.fromPath('image', _imageFile!.path),
        );
      }

      var streamedResponse = await request.send();
      var response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200 || response.statusCode == 201) {
        _showSnackBar(
          _isEditMode
              ? 'Mobil berhasil diperbarui!'
              : 'Mobil berhasil ditambahkan!',
          const Color(0xFF16A34A),
        );
        Navigator.pop(context, true);
      } else if (response.statusCode == 403) {
        String message =
            'Lengkapi Data Personal (No. HP & KTP) terlebih dahulu.';
        try {
          final body = jsonDecode(response.body);
          if (body['message'] != null) {
            message = body['message'];
          }
        } catch (_) {}

        _showSnackBar(message, _accentColor);

        if (mounted) {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const ProfilPage()),
          );
        }
      } else {
        String errorMessage = 'Gagal menyimpan data. Periksa kembali inputan.';
        try {
          final body = jsonDecode(response.body);
          if (body['message'] != null) {
            errorMessage = body['message'];
          }
        } catch (_) {}

        _showSnackBar(errorMessage, Colors.red);
      }
    } catch (e) {
      _showSnackBar('Terjadi kesalahan koneksi: $e', Colors.red);
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
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

  @override
  void dispose() {
    _nameController.dispose();
    _brandController.dispose();
    _plateController.dispose();
    _seatsController.dispose();
    _yearController.dispose();
    _priceController.dispose();
    _driverPriceController.dispose();
    _descController.dispose();
    _fuelSpecController.dispose();
    _videoUrlController.dispose();
    super.dispose();
  }

  // ================= HELPER UI: SECTION CARD =================
  Widget _sectionCard({
    required String title,
    required IconData icon,
    required Color iconColor,
    String? subtitle,
    required List<Widget> children,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(18),
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
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: iconColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: iconColor, size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 15.5,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF1E293B),
                      ),
                    ),
                    if (subtitle != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          subtitle,
                          style: TextStyle(
                              fontSize: 12, color: Colors.grey.shade600),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ...children,
        ],
      ),
    );
  }

  // ================= HELPER UI: TEXT FIELD SERAGAM =================
  Widget _field({
    required TextEditingController controller,
    required String label,
    String? hint,
    IconData? icon,
    TextInputType keyboardType = TextInputType.text,
    int maxLines = 1,
    String? Function(String?)? validator,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: TextFormField(
        controller: controller,
        keyboardType: keyboardType,
        maxLines: maxLines,
        style: const TextStyle(fontSize: 14),
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          prefixIcon: icon != null
              ? Icon(icon, size: 19, color: Colors.grey.shade500)
              : null,
          filled: true,
          fillColor: _bgColor,
          isDense: true,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.grey.shade200),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: _primaryColor, width: 1.4),
          ),
          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Colors.redAccent),
          ),
          labelStyle: TextStyle(color: Colors.grey.shade600, fontSize: 13),
        ),
        validator: validator,
      ),
    );
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
        return status;
    }
  }

  IconData _statusIcon(String status) {
    switch (status) {
      case 'tersedia':
        return Icons.check_circle_outline_rounded;
      case 'disewa':
        return Icons.directions_car_filled_outlined;
      case 'perbaikan':
        return Icons.build_outlined;
      default:
        return Icons.circle_outlined;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bgColor,
      appBar: AppBar(
        title: Text(
          _isEditMode ? 'Edit Data Mobil' : 'Tambah Mobil Baru',
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
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
      body: Form(
        key: _formKey,
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                children: [
                  // ============ FOTO MOBIL ============
                  Center(child: _buildPhotoPicker()),
                  const SizedBox(height: 20),

                  // ============ INFORMASI UTAMA ============
                  _sectionCard(
                    title: 'Informasi Utama',
                    subtitle: 'Identitas dasar kendaraan',
                    icon: Icons.directions_car_rounded,
                    iconColor: _primaryColor,
                    children: [
                      _field(
                        controller: _nameController,
                        label: 'Nama Mobil',
                        hint: 'Contoh: Avanza, Zenix Hybrid',
                        icon: Icons.badge_outlined,
                        validator: (v) =>
                            v!.isEmpty ? 'Nama mobil wajib diisi' : null,
                      ),
                      _field(
                        controller: _brandController,
                        label: 'Merek / Brand',
                        hint: 'Contoh: Toyota, Honda',
                        icon: Icons.local_offer_outlined,
                        validator: (v) =>
                            v!.isEmpty ? 'Merek wajib diisi' : null,
                      ),
                      _field(
                        controller: _plateController,
                        label: 'Plat Nomor',
                        hint: 'Contoh: BP 1234 XY',
                        icon: Icons.confirmation_number_outlined,
                        validator: (v) =>
                            v!.isEmpty ? 'Plat nomor wajib diisi' : null,
                      ),
                    ],
                  ),

                  // ============ SPESIFIKASI TEKNIS ============
                  _sectionCard(
                    title: 'Spesifikasi Teknis',
                    subtitle: 'Detail mesin dan kapasitas',
                    icon: Icons.build_circle_outlined,
                    iconColor: _accentColor,
                    children: [
                      DropdownButtonFormField<String>(
                        value: _engineType,
                        isExpanded: true,
                        decoration: InputDecoration(
                          labelText: 'Tipe Mesin Penggerak',
                          prefixIcon: Icon(Icons.settings_outlined,
                              size: 19, color: Colors.grey.shade500),
                          filled: true,
                          fillColor: _bgColor,
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 14),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: Colors.grey.shade200),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide:
                                const BorderSide(color: _primaryColor, width: 1.4),
                          ),
                          labelStyle:
                              TextStyle(color: Colors.grey.shade600, fontSize: 13),
                        ),
                        items: _engineTypes
                            .map((type) => DropdownMenuItem(
                                value: type,
                                child: Text(type,
                                    style: const TextStyle(fontSize: 14))))
                            .toList(),
                        onChanged: (value) =>
                            setState(() => _engineType = value!),
                      ),
                      const SizedBox(height: 14),
                      _field(
                        controller: _fuelSpecController,
                        label: 'Spesifikasi BBM (Opsional)',
                        hint: 'Contoh: Pertamax, Biosolar',
                        icon: Icons.local_gas_station_outlined,
                      ),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: _field(
                              controller: _seatsController,
                              label: 'Total Kursi',
                              icon: Icons.airline_seat_recline_normal_outlined,
                              keyboardType: TextInputType.number,
                              validator: (v) =>
                                  v!.isEmpty ? 'Wajib diisi' : null,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _field(
                              controller: _yearController,
                              label: 'Tahun',
                              hint: 'Cth: 2024',
                              icon: Icons.calendar_today_outlined,
                              keyboardType: TextInputType.number,
                              validator: (v) => v!.length != 4
                                  ? 'Format tahun 4 digit'
                                  : null,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),

                  // ============ HARGA & STATUS ============
                  _sectionCard(
                    title: 'Harga & Ketersediaan',
                    subtitle: 'Atur tarif sewa dan status mobil',
                    icon: Icons.payments_outlined,
                    iconColor: const Color(0xFF16A34A),
                    children: [
                      _field(
                        controller: _priceController,
                        label: 'Harga Sewa per Hari (Rp)',
                        icon: Icons.sell_outlined,
                        keyboardType: TextInputType.number,
                        validator: (v) =>
                            v!.isEmpty ? 'Harga sewa wajib diisi' : null,
                      ),
                      _field(
                        controller: _driverPriceController,
                        label: 'Tarif Driver per Hari (Rp)',
                        hint: 'Opsional — isi 0 jika lepas kunci',
                        icon: Icons.person_pin_circle_outlined,
                        keyboardType: TextInputType.number,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Status Mobil',
                        style: TextStyle(
                            fontSize: 12.5, color: Colors.grey.shade600),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: _statuses.map((st) {
                          final bool selected = st == _status;
                          final color = _statusColor(st);
                          return GestureDetector(
                            onTap: () => setState(() => _status = st),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 150),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 10),
                              decoration: BoxDecoration(
                                color: selected
                                    ? color.withOpacity(0.1)
                                    : _bgColor,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: selected
                                      ? color
                                      : Colors.grey.shade200,
                                  width: selected ? 1.4 : 1,
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(_statusIcon(st),
                                      size: 16,
                                      color: selected
                                          ? color
                                          : Colors.grey.shade500),
                                  const SizedBox(width: 6),
                                  Text(
                                    _statusLabel(st),
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: selected
                                          ? color
                                          : Colors.grey.shade600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ],
                  ),

                  // ============ MEDIA & DESKRIPSI ============
                  _sectionCard(
                    title: 'Media & Deskripsi',
                    subtitle: 'Lengkapi agar penyewa lebih yakin',
                    icon: Icons.description_outlined,
                    iconColor: _primaryColor,
                    children: [
                      _field(
                        controller: _videoUrlController,
                        label: 'Link Video Review (Opsional)',
                        hint: 'Tempel link YouTube di sini',
                        icon: Icons.video_library_outlined,
                        keyboardType: TextInputType.url,
                      ),
                      _field(
                        controller: _descController,
                        label: 'Deskripsi Tambahan (Opsional)',
                        icon: Icons.notes_outlined,
                        maxLines: 4,
                      ),
                    ],
                  ),

                  const SizedBox(height: 4),
                ],
              ),
            ),

            // ============ TOMBOL SIMPAN (STICKY) ============
            Container(
              padding: EdgeInsets.fromLTRB(
                  16, 12, 16, 12 + MediaQuery.of(context).padding.bottom),
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.06),
                    blurRadius: 16,
                    offset: const Offset(0, -4),
                  ),
                ],
              ),
              child: SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton.icon(
                  onPressed: _isLoading ? null : _submitCar,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _primaryColor,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: _primaryColor.withOpacity(0.6),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                  icon: _isLoading
                      ? const SizedBox.shrink()
                      : Icon(
                          _isEditMode
                              ? Icons.save_outlined
                              : Icons.add_circle_outline_rounded,
                          size: 20,
                        ),
                  label: _isLoading
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2.4,
                          ),
                        )
                      : Text(
                          _isEditMode ? 'Perbarui Mobil' : 'Simpan Mobil',
                          style: const TextStyle(
                            fontSize: 15.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ================= WIDGET FOTO MOBIL =================
  Widget _buildPhotoPicker() {
    final bool hasImage = _imageFile != null ||
        (_existingImageUrl != null && _existingImageUrl!.isNotEmpty);

    return GestureDetector(
      onTap: _pickImage,
      child: Stack(
        children: [
          Container(
            width: 140,
            height: 140,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: hasImage ? Colors.transparent : Colors.grey.shade300,
                width: 1.4,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.06),
                  blurRadius: 14,
                  offset: const Offset(0, 6),
                ),
              ],
              image: _imageFile != null
                  ? DecorationImage(
                      image: FileImage(_imageFile!), fit: BoxFit.cover)
                  : (_existingImageUrl != null &&
                          _existingImageUrl!.isNotEmpty)
                      ? DecorationImage(
                          image: NetworkImage(_getImageUrl(_existingImageUrl)),
                          fit: BoxFit.cover)
                      : null,
            ),
            child: !hasImage
                ? Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: _primaryColor.withOpacity(0.08),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.add_a_photo_outlined,
                            size: 24, color: _primaryColor),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Tambah Foto',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  )
                : null,
          ),
          if (hasImage)
            Positioned(
              right: 4,
              bottom: 4,
              child: Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: _primaryColor,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                ),
                child: const Icon(Icons.edit_rounded,
                    size: 14, color: Colors.white),
              ),
            ),
        ],
      ),
    );
  }
}