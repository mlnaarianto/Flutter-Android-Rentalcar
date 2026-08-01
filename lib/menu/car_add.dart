import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:rentalcar/config/api_config.dart';
import 'package:rentalcar/menu/profil.dart'; 

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
      _driverPriceController.text = car['driver_price_per_day']?.toString() ?? '';
      _descController.text = car['description'] ?? '';
      _fuelSpecController.text = car['fuel_spec'] ?? '';

      if (_engineTypes.contains(car['engine_type'])) {
        _engineType = car['engine_type'];
      } else if (car['engine_type'] != null) {
        final matched = _engineTypes.firstWhere(
          (e) => e.toLowerCase().startsWith(car['engine_type'].toString().toLowerCase()),
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
      request.fields['driver_price_per_day'] = _driverPriceController.text.trim();
      request.fields['description'] = _descController.text.trim();
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
          Colors.green,
        );
        Navigator.pop(context, true); 
      } else if (response.statusCode == 403) {
        // Tangkap pesan dari backend jika ada
        String message = 'Lengkapi Data Personal (No. HP & KTP) terlebih dahulu.';
        try {
          final body = jsonDecode(response.body);
          if (body['message'] != null) {
            message = body['message'];
          }
        } catch (_) {}

        _showSnackBar(message, Colors.orange);

        // 🚀 Langsung arahkan ke Halaman Profil / Menu Pengisian Data
        // Ganti '/profil' dengan rute yang sesuai di aplikasi Anda atau gunakan MaterialPageRoute
        if (mounted) {
          // Opsi A Menggunakan Named Route:
          // Navigator.pushNamed(context, '/profil');
          
          // Opsi B Langsung Panggil Widget Halaman Profil:
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
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _showSnackBar(String message, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: color),
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
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditMode ? 'Edit Data Mobil' : 'Tambah Mobil Baru'),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: GestureDetector(
                  onTap: _pickImage,
                  child: Container(
                    width: 130,
                    height: 130,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade200,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey.shade400),
                      image: _imageFile != null
                          ? DecorationImage(
                              image: FileImage(_imageFile!),
                              fit: BoxFit.cover,
                            )
                          : (_existingImageUrl != null &&
                              _existingImageUrl!.isNotEmpty)
                          ? DecorationImage(
                              image: NetworkImage(
                                  _getImageUrl(_existingImageUrl)),
                              fit: BoxFit.cover,
                            )
                          : null,
                    ),
                    child: (_imageFile == null &&
                            (_existingImageUrl == null ||
                                _existingImageUrl!.isEmpty))
                        ? Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: const [
                              Icon(
                                Icons.camera_alt,
                                size: 40,
                                color: Colors.grey,
                              ),
                              SizedBox(height: 6),
                              Text(
                                'Foto Mobil',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey,
                                ),
                              ),
                            ],
                          )
                        : null,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'Nama Mobil (Contoh: Avanza, Zenix Hybrid)',
                  border: OutlineInputBorder(),
                ),
                validator: (value) =>
                    value!.isEmpty ? 'Nama mobil wajib diisi' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _brandController,
                decoration: const InputDecoration(
                  labelText: 'Merek / Brand (Contoh: Toyota, Honda)',
                  border: OutlineInputBorder(),
                ),
                validator: (value) =>
                    value!.isEmpty ? 'Merek wajib diisi' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _plateController,
                decoration: const InputDecoration(
                  labelText: 'Plat Nomor (Contoh: BP 1234 XY)',
                  border: OutlineInputBorder(),
                ),
                validator: (value) =>
                    value!.isEmpty ? 'Plat nomor wajib diisi' : null,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: _engineType,
                decoration: const InputDecoration(
                  labelText: 'Tipe Mesin Penggerak',
                  border: OutlineInputBorder(),
                ),
                items: _engineTypes.map((type) {
                  return DropdownMenuItem(value: type, child: Text(type));
                }).toList(),
                onChanged: (value) => setState(() => _engineType = value!),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _fuelSpecController,
                decoration: const InputDecoration(
                  labelText: 'Spesifikasi BBM (Contoh: Pertamax, Biosolar)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _seatsController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Total Kursi',
                        border: OutlineInputBorder(),
                      ),
                      validator: (value) =>
                          value!.isEmpty ? 'Wajib diisi' : null,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _yearController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Tahun (Cth: 2024)',
                        border: OutlineInputBorder(),
                      ),
                      validator: (value) =>
                          value!.length != 4 ? 'Format tahun 4 digit' : null,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _priceController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Harga Sewa per Hari (Rp)',
                  border: OutlineInputBorder(),
                ),
                validator: (value) =>
                    value!.isEmpty ? 'Harga sewa wajib diisi' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _driverPriceController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Tarif Driver per Hari (Rp) - Opsional/0 jika lepas kunci',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: _status,
                decoration: const InputDecoration(
                  labelText: 'Status Mobil',
                  border: OutlineInputBorder(),
                ),
                items: _statuses.map((st) {
                  return DropdownMenuItem(
                    value: st,
                    child: Text(st.toUpperCase()),
                  );
                }).toList(),
                onChanged: (value) => setState(() => _status = value!),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _descController,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Deskripsi Tambahan (Opsional)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _isLoading ? null : _submitCar,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: _isLoading
                    ? const CircularProgressIndicator(color: Colors.white)
                    : Text(
                        _isEditMode ? 'Perbarui Mobil' : 'Simpan Mobil',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}