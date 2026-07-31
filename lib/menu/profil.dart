import 'dart:io';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:rentalcar/layouts/app.dart';
import 'package:rentalcar/config/api_config.dart';

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

  File? avatarImage;
  String? avatarUrl;
  
  File? ktpImage;
  String? ktpUrl;

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
      // 👇 UBAH DARI 'auth_token' MENJADI 'access_token'
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

        setState(() {
          _namaController.text = userData['name'] ?? '';
          _emailController.text = userData['email'] ?? '';
          
          _hpController.text = personalData['phone'] ?? '';
          _tglLahirController.text = personalData['birth_date'] ?? '';
          _addressController.text = personalData['address'] ?? '';
          ktpUrl = personalData['ktp_image']; 
          
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

  /// ================= AVATAR =================
  Future<void> _pickAvatar() async {
    final ImagePicker picker = ImagePicker();
    final XFile? image =
        await picker.pickImage(source: ImageSource.gallery, imageQuality: 70);

    if (image != null) {
      setState(() {
        avatarImage = File(image.path);
      });
    }
  }

  /// ================= DATE =================
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

  /// ================= KTP =================
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

  /// ================= SAVE =================
  Future<void> _saveProfile() async {
    if (_formKey.currentState!.validate()) {
      
      if (ktpImage == null && ktpUrl == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Foto KTP wajib diupload pertama kali")),
        );
        return;
      }

      try {
        SharedPreferences prefs = await SharedPreferences.getInstance();
        // 👇 UBAH DARI 'auth_token' MENJADI 'access_token'
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

        request.fields['name'] = _namaController.text;
        request.fields['phone'] = _hpController.text;
        request.fields['birth_date'] = _tglLahirController.text;
        request.fields['address'] = _addressController.text;

        if (ktpImage != null) {
          request.files.add(
            await http.MultipartFile.fromPath('ktp', ktpImage!.path),
          );
        }

        if (avatarImage != null) {
          request.files.add(
            await http.MultipartFile.fromPath('avatar', avatarImage!.path),
          );
        }

        final streamedResponse = await request.send();
        final response = await http.Response.fromStream(streamedResponse);

        if (response.statusCode == 200) {
          try {
            final responseData = jsonDecode(response.body);
            final String? newAvatar =
                responseData['data']?['avatar'] ?? responseData['user']?['avatar'];
            if (newAvatar != null && newAvatar.isNotEmpty) {
              await prefs.setString('avatar_url', newAvatar);
              setState(() => avatarUrl = newAvatar);
            }
          } catch (_) {}

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text("Profil berhasil disimpan")),
            );
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
      title: "Profil",
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
                      child: GestureDetector(
                        onTap: _pickAvatar,
                        child: Stack(
                          children: [
                            CircleAvatar(
                              radius: 45,
                              backgroundColor: Colors.blue.withOpacity(0.1),
                              backgroundImage: avatarImage != null
                                  ? FileImage(avatarImage!) as ImageProvider
                                  : (avatarUrl != null
                                      ? NetworkImage(avatarUrl!)
                                      : const AssetImage("assets/anya.jpg") as ImageProvider),
                            ),
                            Positioned(
                              bottom: 0,
                              right: 0,
                              child: Container(
                                padding: const EdgeInsets.all(6),
                                decoration: const BoxDecoration(
                                  color: Colors.blue,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.camera_alt,
                                  size: 16,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 8),
                    const Center(
                      child: Text(
                        "Ketuk untuk ganti foto profil",
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    ),

                    const SizedBox(height: 25),

                    /// ================= NAMA =================
                    TextFormField(
                      controller: _namaController,
                      decoration: const InputDecoration(
                        labelText: "Nama",
                        border: OutlineInputBorder(),
                      ),
                      validator: (v) =>
                          v == null || v.isEmpty ? "Nama wajib diisi" : null,
                    ),

                    const SizedBox(height: 15),

                    /// ================= EMAIL =================
                    TextFormField(
                      controller: _emailController,
                      readOnly: true,
                      decoration: const InputDecoration(
                        labelText: "Email",
                        border: OutlineInputBorder(),
                        filled: true,
                        fillColor: Colors.black12,
                      ),
                    ),

                    const SizedBox(height: 15),

                    /// ================= HP =================
                    TextFormField(
                      controller: _hpController,
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(
                        labelText: "Nomor HP",
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
                      "Foto KTP",
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
                                        SizedBox(height: 6),
                                        Text(
                                          "Ketuk untuk memilih dari galeri",
                                          style: TextStyle(
                                              fontSize: 12, color: Colors.grey),
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

                    const SizedBox(height: 30),

                    /// ================= SAVE =================
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                        onPressed: _saveProfile,
                        child: const Text("Simpan Profil"),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}