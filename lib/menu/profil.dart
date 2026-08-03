import 'dart:io';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:rentalcar/layouts/app.dart';
import 'package:rentalcar/config/api_config.dart';
import 'package:rentalcar/enums/app_enums.dart';

class ProfilPage extends StatefulWidget {
  const ProfilPage({super.key});

  @override
  State<ProfilPage> createState() => _ProfilPageState();
}

class _ProfilPageState extends State<ProfilPage> {
  final _formKey = GlobalKey<FormState>();

  final TextEditingController _namaController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _tglLahirController = TextEditingController();
  final TextEditingController _hpController = TextEditingController();
  final TextEditingController _addressController = TextEditingController();

  // Controller Tambahan untuk SIM
  final TextEditingController _simNumberController = TextEditingController();
  final TextEditingController _simTypeController = TextEditingController();
  final TextEditingController _simExpiredController = TextEditingController();

  String? avatarUrl;
  
  File? ktpImage;
  String? ktpUrl;

  // Variabel untuk SIM Image
  File? simImage;
  String? simUrl;

  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchUserData();
  }

  /// ================= FETCH DATA DARI LARAVEL API =================
  Future<void> _fetchUserData() async {
    try {
      SharedPreferences prefs = await SharedPreferences.getInstance();
      String? token = prefs.getString('access_token');

      if (token == null) {
        throw Exception("Token tidak ditemukan, silakan login ulang.");
      }

      final response = await http.get(
        Uri.parse(ApiConfig.userProfile),
        headers: {
          'Authorization': 'Bearer $token',
          'Accept': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final Map<String, dynamic> responseData = jsonDecode(response.body);
        final userData = responseData['data'];
        
        final personalData = userData['personal_data'] ?? {}; 

        final String? fetchedAvatar = userData['avatar'];
        if (fetchedAvatar != null && fetchedAvatar.isNotEmpty) {
          await prefs.setString('avatar_url', fetchedAvatar);
        }

        // Fungsi helper untuk membersihkan format tanggal ISO (misal: 2000-01-01T00:00:00.000000Z -> 2000-01-01)
        String formatDate(String? dateStr) {
          if (dateStr == null || dateStr.isEmpty) return '';
          return dateStr.contains('T') ? dateStr.split('T')[0] : dateStr;
        }

        setState(() {
          _namaController.text = userData['name'] ?? '';
          _emailController.text = userData['email'] ?? '';
          
          _hpController.text = personalData['phone'] ?? '';
          _addressController.text = personalData['address'] ?? '';
          ktpUrl = personalData['ktp_image']; 

          // Tanggal Lahir (Dibersihkan formatnya)
          _tglLahirController.text = formatDate(personalData['birth_date']);

          // Set Data SIM dari Server
          _simNumberController.text = personalData['sim_number'] ?? '';
          _simTypeController.text = personalData['sim_type'] ?? '';
          
          // Masa Berlaku SIM (Dibersihkan formatnya)
          _simExpiredController.text = formatDate(personalData['sim_expired_date']);
          
          simUrl = personalData['sim_image'];
          
          avatarUrl = fetchedAvatar;
          _isLoading = false;
        });
      } else {
        throw Exception("Gagal mengambil data profil (${response.statusCode})");
      }
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString())),
        );
      }
    }
  }

  /// ================= DATE PICKER (Lahir) =================
  Future<void> _pickDate() async {
    DateTime? picked = await showDatePicker(
      context: context,
      firstDate: DateTime(1950),
      lastDate: DateTime.now(),
      initialDate: DateTime(2000),
    );

    if (picked != null) {
      String formattedDate =
          "${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}";
      setState(() {
        _tglLahirController.text = formattedDate;
      });
    }
  }

  /// ================= DATE PICKER (SIM Expired) =================
  Future<void> _pickSimExpiredDate() async {
    DateTime? picked = await showDatePicker(
      context: context,
      firstDate: DateTime.now(),
      lastDate: DateTime(DateTime.now().year + 15),
      initialDate: DateTime.now(),
    );

    if (picked != null) {
      String formattedDate =
          "${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}";
      setState(() {
        _simExpiredController.text = formattedDate;
      });
    }
  }

  /// ================= UPLOAD KTP =================
  Future<void> _uploadKtp() async {
    final ImagePicker picker = ImagePicker();
    final XFile? image =
        await picker.pickImage(source: ImageSource.gallery, imageQuality: 70);

    if (image != null) {
      setState(() {
        ktpImage = File(image.path);
      });
    }
  }

  /// ================= UPLOAD SIM =================
  Future<void> _uploadSim() async {
    final ImagePicker picker = ImagePicker();
    final XFile? image =
        await picker.pickImage(source: ImageSource.gallery, imageQuality: 70);

    if (image != null) {
      setState(() {
        simImage = File(image.path);
      });
    }
  }

  /// ================= SAVE =================
  Future<void> _saveProfile() async {
    if (_formKey.currentState!.validate()) {
      if (ktpImage == null && ktpUrl == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Foto KTP wajib diupload")),
        );
        return;
      }

      if (simImage == null && simUrl == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Foto SIM wajib diupload untuk Driver/Penyewa")),
        );
        return;
      }

      try {
        SharedPreferences prefs = await SharedPreferences.getInstance();
        String? token = prefs.getString('access_token');

        if (token == null) {
          throw Exception("Token tidak ditemukan, silakan login ulang.");
        }

        final request = http.MultipartRequest(
          'POST',
          Uri.parse(ApiConfig.userProfile),
        );

        request.headers['Authorization'] = 'Bearer $token';
        request.headers['Accept'] = 'application/json';

        request.fields['_method'] = 'PATCH';

        // Data Personal Umum
        request.fields['phone'] = _hpController.text;
        request.fields['birth_date'] = _tglLahirController.text;
        request.fields['address'] = _addressController.text;

        // Data SIM
        request.fields['sim_number'] = _simNumberController.text;
        request.fields['sim_type'] = _simTypeController.text;
        request.fields['sim_expired_date'] = _simExpiredController.text;

        if (ktpImage != null) {
          request.files.add(
            await http.MultipartFile.fromPath('ktp', ktpImage!.path),
          );
        }

        if (simImage != null) {
          request.files.add(
            await http.MultipartFile.fromPath('sim_image', simImage!.path),
          );
        }

        final streamedResponse = await request.send();
        final response = await http.Response.fromStream(streamedResponse);

        if (response.statusCode == 200) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text("Data personal & SIM berhasil disimpan")),
            );
            Navigator.pop(context, true);
          }
        } else {
          throw Exception("Gagal menyimpan profil (${response.statusCode})");
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(e.toString())),
          );
        }
      }
    }
  }

  /// ================= BOTTOM NAVIGATION =================
  void _onBottomTap(int index) {
    if (index == 0) {
      Navigator.pushReplacementNamed(context, '/home');
    } else if (index == 1) {
      Navigator.pushReplacementNamed(context, '/booking');
    } else if (index == 2) {
      Navigator.pushReplacementNamed(context, '/history');
    } else if (index == 3) {
      // sudah di profil
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppLayout(
      title: "Lengkapi Data & SIM",
      currentIndex: 3,
      onTap: _onBottomTap,
      content: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    /// ================= AVATAR =================
                    Center(
                      child: Stack(
                        children: [
                          CircleAvatar(
                            radius: 45,
                            backgroundColor: Colors.blue.withOpacity(0.1),
                            backgroundImage: avatarUrl != null
                                ? NetworkImage(avatarUrl!)
                                : const AssetImage("assets/anya.jpg") as ImageProvider,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Center(
                      child: Text(
                        "Foto profil tersinkron dari akun Google",
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    ),

                    const SizedBox(height: 25),

                    /// ================= NAMA =================
                    TextFormField(
                      controller: _namaController,
                      readOnly: true,
                      decoration: const InputDecoration(
                        labelText: "Nama (Akun Google)",
                        border: OutlineInputBorder(),
                        filled: true,
                        fillColor: Colors.black12,
                        prefixIcon: Icon(Icons.person),
                      ),
                    ),

                    const SizedBox(height: 15),

                    /// ================= EMAIL =================
                    TextFormField(
                      controller: _emailController,
                      readOnly: true,
                      decoration: const InputDecoration(
                        labelText: "Email (Akun Google)",
                        border: OutlineInputBorder(),
                        filled: true,
                        fillColor: Colors.black12,
                        prefixIcon: Icon(Icons.email),
                      ),
                    ),

                    const SizedBox(height: 15),

                    /// ================= HP =================
                    TextFormField(
                      controller: _hpController,
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(
                        labelText: "Nomor HP / WhatsApp",
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.phone),
                      ),
                      validator: (v) {
                        if (v == null || v.isEmpty) {
                          return "Nomor HP wajib diisi";
                        }
                        if (v.length < 10) {
                          return "Nomor HP tidak valid";
                        }
                        return null;
                      },
                    ),

                    const SizedBox(height: 15),

                    /// ================= TANGGAL LAHIR =================
                    TextFormField(
                      controller: _tglLahirController,
                      readOnly: true,
                      onTap: _pickDate,
                      decoration: const InputDecoration(
                        labelText: "Tanggal Lahir",
                        border: OutlineInputBorder(),
                        suffixIcon: Icon(Icons.calendar_month),
                      ),
                      validator: (v) => v == null || v.isEmpty
                          ? "Tanggal lahir wajib diisi"
                          : null,
                    ),

                    const SizedBox(height: 15),

                    /// ================= ALAMAT =================
                    TextFormField(
                      controller: _addressController,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        labelText: "Alamat Lengkap",
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.home),
                      ),
                      validator: (v) =>
                          v == null || v.isEmpty ? "Alamat wajib diisi" : null,
                    ),

                    const SizedBox(height: 25),

                    /// ================= KTP =================
                    const Text(
                      "Foto KTP (Wajib)",
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 10),

                    GestureDetector(
                      onTap: _uploadKtp,
                      child: AspectRatio(
                        aspectRatio: 1.6,
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: Colors.blue, width: 1.5),
                            color: Colors.blue.withOpacity(0.05),
                          ),
                          child: ktpImage == null
                              ? (ktpUrl != null
                                  ? ClipRRect(
                                      borderRadius: BorderRadius.circular(14),
                                      child: Image.network(
                                        ktpUrl!,
                                        fit: BoxFit.cover,
                                      ),
                                    )
                                  : Column(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: const [
                                        Icon(Icons.credit_card,
                                            size: 48, color: Colors.blue),
                                        SizedBox(height: 10),
                                        Text(
                                          "Upload Foto KTP",
                                          style: TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.w500),
                                        ),
                                      ],
                                    ))
                              : ClipRRect(
                                  borderRadius: BorderRadius.circular(14),
                                  child: Image.file(
                                    ktpImage!,
                                    fit: BoxFit.cover,
                                  ),
                                ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 25),

                    /// ================= BAGIAN SIM =================
                    const Divider(thickness: 1.5),
                    const SizedBox(height: 10),
                    const Text(
                      "Informasi SIM (Wajib untuk Driver/Penyewa)",
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                    const SizedBox(height: 15),

                    // Nomor SIM
                    TextFormField(
                      controller: _simNumberController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: "Nomor SIM",
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.badge),
                      ),
                      validator: (v) => v == null || v.isEmpty
                          ? "Nomor SIM wajib diisi"
                          : null,
                    ),

                    const SizedBox(height: 15),

                    // Jenis/Golongan SIM
                    TextFormField(
                      controller: _simTypeController,
                      decoration: const InputDecoration(
                        labelText: "Golongan SIM (Contoh: A, C, B1)",
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.category),
                      ),
                      validator: (v) => v == null || v.isEmpty
                          ? "Golongan SIM wajib diisi"
                          : null,
                    ),

                    const SizedBox(height: 15),

                    // Masa Berlaku SIM
                    TextFormField(
                      controller: _simExpiredController,
                      readOnly: true,
                      onTap: _pickSimExpiredDate,
                      decoration: const InputDecoration(
                        labelText: "Masa Berlaku SIM",
                        border: OutlineInputBorder(),
                        suffixIcon: Icon(Icons.event_busy),
                      ),
                      validator: (v) => v == null || v.isEmpty
                          ? "Masa berlaku SIM wajib diisi"
                          : null,
                    ),

                    const SizedBox(height: 15),

                    // Foto SIM
                    const Text(
                      "Foto SIM (Wajib)",
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 10),

                    GestureDetector(
                      onTap: _uploadSim,
                      child: AspectRatio(
                        aspectRatio: 1.6,
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: Colors.orange, width: 1.5),
                            color: Colors.orange.withOpacity(0.05),
                          ),
                          child: simImage == null
                              ? (simUrl != null
                                  ? ClipRRect(
                                      borderRadius: BorderRadius.circular(14),
                                      child: Image.network(
                                        simUrl!,
                                        fit: BoxFit.cover,
                                      ),
                                    )
                                  : Column(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: const [
                                        Icon(Icons.directions_car,
                                            size: 48, color: Colors.orange),
                                        SizedBox(height: 10),
                                        Text(
                                          "Upload Foto SIM",
                                          style: TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.w500),
                                        ),
                                      ],
                                    ))
                              : ClipRRect(
                                  borderRadius: BorderRadius.circular(14),
                                  child: Image.file(
                                    simImage!,
                                    fit: BoxFit.cover,
                                  ),
                                ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 30),

                    /// ================= SAVE BUTTON =================
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue,
                          foregroundColor: Colors.white,
                        ),
                        onPressed: _saveProfile,
                        child: const Text("Simpan Data Personal & SIM",
                            style: TextStyle(fontSize: 16)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}