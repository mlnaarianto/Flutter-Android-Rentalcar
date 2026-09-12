import 'dart:io';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl_phone_field/intl_phone_field.dart';
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

  // 🟢 TAMBAHAN: nomor HP lengkap format internasional (mis. "+6281234567890")
  // Inilah yang dikirim ke backend, bukan _hpController.text lagi.
  String _completePhoneNumber = '';

  String? avatarUrl;

  File? ktpImage;
  String? ktpUrl;

  // Variabel untuk SIM Image
  File? simImage;
  String? simUrl;

  bool _isLoading = true;
  bool _isSaving = false;

  static const Color _primaryColor = Color(0xFF2563EB);
  static const Color _accentColor = Color(0xFFF97316);
  static const Color _dangerColor = Color(0xFFDC2626);

  @override
  void initState() {
    super.initState();
    _fetchUserData();
  }

  /// ================= FIX FOTO GOOGLE BURAM/PIXELATED =================
  /// Google Sign-In mengembalikan URL foto profil dengan parameter ukuran
  /// bawaan yang kecil, biasanya diakhiri "=s96-c" (96x96 px, thumbnail).
  /// Kalau dipakai langsung untuk avatar besar/full-screen, hasilnya pecah
  /// karena gambar kecil di-stretch. Ini BUKAN masalah scope OAuth ("profile"/
  /// "email"), murni parameter resolusi di URL-nya.
  ///
  /// Solusinya: ganti angka ukurannya jadi lebih besar sebelum dipakai render.
  /// [size] 200 cukup untuk avatar bulat, dan otomatis dipakai lebih besar (600)
  /// untuk mode full-screen viewer supaya tetap tajam saat di-zoom.
  String? _hiResAvatarUrl(String? url, {int size = 200}) {
    if (url == null || url.isEmpty) return url;
    final sizePattern = RegExp(r'=s\d+-c(-[a-z0-9]+)?$');
    if (sizePattern.hasMatch(url)) {
      return url.replaceAll(sizePattern, '=s$size-c');
    }
    // Kalau backend menyimpan ulang fotonya sendiri (bukan URL langsung dari
    // Google, misalnya sudah di-download & disimpan di server), parameter
    // ukuran ini tidak akan ada. Berarti sumber buramnya ada di sisi server
    // (foto disimpan dalam resolusi kecil), bukan di aplikasi Flutter ini.
    return url;
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

          // Nomor HP yang tersimpan di server (bisa jadi format lama tanpa '+',
          // atau sudah format internasional). Dipakai sebagai initialValue
          // IntlPhoneField, dan sebagai fallback _completePhoneNumber sebelum
          // user mengubahnya.
          final String rawPhone = personalData['phone'] ?? '';
          _hpController.text = rawPhone;
          _completePhoneNumber = rawPhone;

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

  /// ================= ZOOM VIEWER =================
  /// Buka foto secara fullscreen dengan pinch-to-zoom + double-tap zoom.
  /// Menerima salah satu dari [networkUrl] atau [localFile] (prioritas file lokal
  /// kalau user baru saja memilih foto baru yang belum diupload).
  void _openImageViewer({
    String? networkUrl,
    File? localFile,
    required String heroTag,
    required String title,
  }) {
    if (networkUrl == null && localFile == null) return;

    Navigator.push(
      context,
      PageRouteBuilder(
        opaque: false,
        barrierColor: Colors.black,
        transitionDuration: const Duration(milliseconds: 220),
        pageBuilder: (context, animation, secondaryAnimation) {
          return FadeTransition(
            opacity: animation,
            child: _ZoomableImageViewer(
              networkUrl: networkUrl,
              localFile: localFile,
              heroTag: heroTag,
              title: title,
            ),
          );
        },
      ),
    );
  }

  /// ================= HELPER: EKSTRAK PESAN ERROR VALIDASI DARI LARAVEL =================
  /// 🟢 TAMBAHAN: Laravel mengembalikan HTTP 422 dengan body:
  /// {
  ///   "message": "...",
  ///   "errors": {
  ///     "phone": ["Nomor HP ini sudah digunakan oleh akun lain"],
  ///     "sim_number": ["Nomor SIM ini sudah digunakan oleh akun lain"]
  ///   }
  /// }
  /// Fungsi ini mengambil SEMUA pesan dari setiap field yang error, lalu
  /// menggabungkannya jadi satu string yang bisa ditampilkan ke user
  /// (bukan cuma "Gagal menyimpan profil (422)" yang tidak informatif).
  String _extractValidationMessage(Map<String, dynamic> responseData, int statusCode) {
    final errors = responseData['errors'];

    if (errors is Map<String, dynamic> && errors.isNotEmpty) {
      final List<String> messages = [];
      errors.forEach((field, fieldMessages) {
        if (fieldMessages is List) {
          for (final msg in fieldMessages) {
            messages.add(msg.toString());
          }
        } else if (fieldMessages != null) {
          messages.add(fieldMessages.toString());
        }
      });

      if (messages.isNotEmpty) {
        return messages.join('\n');
      }
    }

    // Fallback kalau tidak ada 'errors' spesifik, pakai 'message' dari backend
    return responseData['message'] ?? "Gagal menyimpan profil ($statusCode)";
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

      setState(() => _isSaving = true);

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
        // 🟢 UBAH: pakai nomor lengkap format internasional (+62..., +60..., dst)
        // yang dihasilkan IntlPhoneField, bukan _hpController.text mentah lagi.
        request.fields['phone'] = _completePhoneNumber;
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

        // 🟢 TAMBAHAN: decode body-nya dulu supaya bisa baca 'errors' dari Laravel,
        // baik untuk kasus sukses (200) maupun gagal (422/500/dll).
        Map<String, dynamic> responseData = {};
        try {
          responseData = jsonDecode(response.body);
        } catch (_) {
          // Body bukan JSON valid, biarkan responseData tetap kosong,
          // nanti fallback ke pesan generic di bawah.
        }

        if (response.statusCode == 200) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text("Data personal & SIM berhasil disimpan")),
            );
            Navigator.pop(context, true);
          }
        } else if (response.statusCode == 422) {
          // 🟢 TAMBAHAN: Error validasi (nomor HP/SIM sudah dipakai, format salah, dll)
          // Ambil pesan asli dari backend, bukan pesan generic.
          final String message = _extractValidationMessage(responseData, response.statusCode);
          throw Exception(message);
        } else {
          final String message = responseData['message'] ?? "Gagal menyimpan profil (${response.statusCode})";
          throw Exception(message);
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(e.toString().replaceAll('Exception: ', '')),
              backgroundColor: _dangerColor,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              margin: const EdgeInsets.all(12),
              duration: const Duration(seconds: 4),
            ),
          );
        }
      } finally {
        if (mounted) setState(() => _isSaving = false);
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

  /// ================= HELPER UI: SECTION CARD =================
  Widget _sectionCard({
    required String title,
    required IconData icon,
    required Color iconColor,
    String? subtitle,
    required List<Widget> children,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 18),
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
                          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
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

  /// ================= HELPER UI: FOTO DOKUMEN (KTP / SIM) DENGAN ZOOM =================
  Widget _documentPhotoPicker({
    required String label,
    required Color color,
    required IconData placeholderIcon,
    required File? localImage,
    required String? remoteUrl,
    required VoidCallback onPick,
    required String heroTag,
  }) {
    final bool hasImage = localImage != null || remoteUrl != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5)),
            const SizedBox(width: 6),
            if (hasImage)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text(
                  "Terupload",
                  style: TextStyle(fontSize: 10, color: Colors.green, fontWeight: FontWeight.w600),
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        Stack(
          children: [
            GestureDetector(
              onTap: onPick,
              child: AspectRatio(
                aspectRatio: 1.6,
                child: Hero(
                  tag: heroTag,
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: color, width: 1.5),
                      color: color.withOpacity(0.05),
                    ),
                    child: localImage == null
                        ? (remoteUrl != null
                            ? ClipRRect(
                                borderRadius: BorderRadius.circular(14),
                                child: Image.network(remoteUrl, fit: BoxFit.cover),
                              )
                            : Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(placeholderIcon, size: 44, color: color),
                                  const SizedBox(height: 8),
                                  Text(
                                    "Ketuk untuk upload",
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w500,
                                      color: color,
                                    ),
                                  ),
                                ],
                              ))
                        : ClipRRect(
                            borderRadius: BorderRadius.circular(14),
                            child: Image.file(localImage, fit: BoxFit.cover),
                          ),
                  ),
                ),
              ),
            ),
            // Tombol zoom & ganti foto, muncul di pojok kanan-bawah kalau sudah ada gambar
            if (hasImage)
              Positioned(
                right: 8,
                bottom: 8,
                child: Row(
                  children: [
                    _circleIconButton(
                      icon: Icons.zoom_in_rounded,
                      onTap: () => _openImageViewer(
                        networkUrl: localImage == null ? remoteUrl : null,
                        localFile: localImage,
                        heroTag: heroTag,
                        title: label,
                      ),
                    ),
                    const SizedBox(width: 8),
                    _circleIconButton(icon: Icons.edit_rounded, onTap: onPick),
                  ],
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _circleIconButton({required IconData icon, required VoidCallback onTap}) {
    return Material(
      color: Colors.black.withOpacity(0.55),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(7),
          child: Icon(icon, size: 17, color: Colors.white),
        ),
      ),
    );
  }

  Widget _styledField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    bool readOnly = false,
    VoidCallback? onTap,
    TextInputType? keyboardType,
    int maxLines = 1,
    Widget? suffixIcon,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      readOnly: readOnly,
      onTap: onTap,
      keyboardType: keyboardType,
      maxLines: maxLines,
      validator: validator,
      style: const TextStyle(fontSize: 14.5),
      decoration: InputDecoration(
        labelText: label,
        filled: true,
        fillColor: readOnly ? const Color(0xFFF1F5F9) : const Color(0xFFF8FAFC),
        prefixIcon: Icon(icon, size: 20, color: Colors.grey.shade600),
        suffixIcon: suffixIcon,
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
          borderSide: const BorderSide(color: _primaryColor, width: 1.5),
        ),
      ),
    );
  }

  /// ================= HELPER UI: FIELD NOMOR HP INTERNASIONAL =================
  /// 🟢 TAMBAHAN: pengganti _styledField khusus untuk nomor HP, dengan
  /// dropdown kode negara. Hasil akhirnya (phone.completeNumber) selalu
  /// berupa format "+<kodenegara><nomor>", disimpan ke _completePhoneNumber.
  Widget _phoneField() {
    return IntlPhoneField(
      initialCountryCode: 'ID', // default Indonesia, user bisa ganti sendiri
      initialValue: _hpController.text,
      style: const TextStyle(fontSize: 14.5),
      dropdownTextStyle: const TextStyle(fontSize: 14.5),
      decoration: InputDecoration(
        labelText: "Nomor HP / WhatsApp",
        filled: true,
        fillColor: const Color(0xFFF8FAFC),
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
          borderSide: const BorderSide(color: _primaryColor, width: 1.5),
        ),
      ),
      onChanged: (phone) {
        // completeNumber selalu diawali '+', mis. "+6281234567890"
        _completePhoneNumber = phone.completeNumber;
      },
      validator: (phone) {
        if (phone == null || phone.number.isEmpty) {
          return "Nomor HP wajib diisi";
        }
        if (phone.number.length < 6) {
          return "Nomor HP tidak valid";
        }
        return null;
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    // Versi resolusi menengah untuk avatar bulat kecil, dan resolusi tinggi
    // khusus saat dibuka full-screen supaya tetap tajam walau di-zoom.
    final String? avatarThumb = _hiResAvatarUrl(avatarUrl, size: 200);
    final String? avatarFull = _hiResAvatarUrl(avatarUrl, size: 720);

    return AppLayout(
      title: "Lengkapi Data & SIM",
      currentIndex: 3,
      onTap: _onBottomTap,
      content: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Container(
              color: const Color(0xFFF4F6F9),
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      /// ================= AVATAR (ZOOMABLE) =================
                      Center(
                        child: Column(
                          children: [
                            GestureDetector(
                              onTap: avatarUrl != null
                                  ? () => _openImageViewer(
                                        networkUrl: avatarFull,
                                        heroTag: 'avatar-photo',
                                        title: 'Foto Profil',
                                      )
                                  : null,
                              child: Stack(
                                children: [
                                  Hero(
                                    tag: 'avatar-photo',
                                    child: Container(
                                      padding: const EdgeInsets.all(3),
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        gradient: const LinearGradient(
                                          colors: [_primaryColor, Color(0xFF60A5FA)],
                                        ),
                                        boxShadow: [
                                          BoxShadow(
                                            color: _primaryColor.withOpacity(0.25),
                                            blurRadius: 14,
                                            offset: const Offset(0, 6),
                                          ),
                                        ],
                                      ),
                                      child: CircleAvatar(
                                        radius: 48,
                                        backgroundColor: Colors.white,
                                        child: CircleAvatar(
                                          radius: 45,
                                          backgroundColor: Colors.blue.withOpacity(0.08),
                                          backgroundImage: avatarThumb != null
                                              ? NetworkImage(avatarThumb)
                                              : const AssetImage("assets/anya.jpg") as ImageProvider,
                                        ),
                                      ),
                                    ),
                                  ),
                                  if (avatarUrl != null)
                                    Positioned(
                                      right: 2,
                                      bottom: 2,
                                      child: Container(
                                        padding: const EdgeInsets.all(6),
                                        decoration: BoxDecoration(
                                          color: _primaryColor,
                                          shape: BoxShape.circle,
                                          border: Border.all(color: Colors.white, width: 2),
                                        ),
                                        child: const Icon(Icons.zoom_in_rounded, size: 14, color: Colors.white),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              _namaController.text.isNotEmpty ? _namaController.text : 'Pengguna',
                              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              "Tersinkron dari akun Google · Ketuk foto untuk memperbesar",
                              textAlign: TextAlign.center,
                              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 24),

                      /// ================= AKUN (Nama & Email) =================
                      _sectionCard(
                        title: "Informasi Akun",
                        subtitle: "Bersumber dari akun Google, tidak bisa diubah",
                        icon: Icons.account_circle_rounded,
                        iconColor: _primaryColor,
                        children: [
                          _styledField(
                            controller: _namaController,
                            label: "Nama",
                            icon: Icons.person_outline,
                            readOnly: true,
                          ),
                          const SizedBox(height: 12),
                          _styledField(
                            controller: _emailController,
                            label: "Email",
                            icon: Icons.email_outlined,
                            readOnly: true,
                          ),
                        ],
                      ),

                      /// ================= DATA PERSONAL =================
                      _sectionCard(
                        title: "Data Personal",
                        subtitle: "Digunakan untuk keperluan verifikasi & komunikasi",
                        icon: Icons.badge_outlined,
                        iconColor: _accentColor,
                        children: [
                          // 🟢 UBAH: field HP sekarang pakai IntlPhoneField
                          _phoneField(),
                          const SizedBox(height: 12),
                          _styledField(
                            controller: _tglLahirController,
                            label: "Tanggal Lahir",
                            icon: Icons.cake_outlined,
                            readOnly: true,
                            onTap: _pickDate,
                            suffixIcon: const Icon(Icons.calendar_month, size: 20),
                            validator: (v) =>
                                v == null || v.isEmpty ? "Tanggal lahir wajib diisi" : null,
                          ),
                          const SizedBox(height: 12),
                          _styledField(
                            controller: _addressController,
                            label: "Alamat Lengkap",
                            icon: Icons.home_outlined,
                            maxLines: 3,
                            validator: (v) => v == null || v.isEmpty ? "Alamat wajib diisi" : null,
                          ),
                        ],
                      ),

                      /// ================= KTP =================
                      _sectionCard(
                        title: "Foto KTP",
                        subtitle: "Wajib diupload, pastikan foto jelas dan tidak buram",
                        icon: Icons.credit_card_rounded,
                        iconColor: _primaryColor,
                        children: [
                          _documentPhotoPicker(
                            label: "Foto KTP",
                            color: _primaryColor,
                            placeholderIcon: Icons.credit_card,
                            localImage: ktpImage,
                            remoteUrl: ktpUrl,
                            onPick: _uploadKtp,
                            heroTag: 'ktp-photo',
                          ),
                        ],
                      ),

                      /// ================= BAGIAN SIM =================
                      _sectionCard(
                        title: "Informasi SIM",
                        subtitle: "Wajib untuk Driver/Penyewa sebelum bisa membuat pesanan",
                        icon: Icons.directions_car_filled_rounded,
                        iconColor: _accentColor,
                        children: [
                          _styledField(
                            controller: _simNumberController,
                            label: "Nomor SIM",
                            icon: Icons.numbers_rounded,
                            keyboardType: TextInputType.number,
                            validator: (v) => v == null || v.isEmpty ? "Nomor SIM wajib diisi" : null,
                          ),
                          const SizedBox(height: 12),
                          _styledField(
                            controller: _simTypeController,
                            label: "Golongan SIM (Contoh: A, C, B1)",
                            icon: Icons.category_outlined,
                            validator: (v) => v == null || v.isEmpty ? "Golongan SIM wajib diisi" : null,
                          ),
                          const SizedBox(height: 12),
                          _styledField(
                            controller: _simExpiredController,
                            label: "Masa Berlaku SIM",
                            icon: Icons.event_busy_outlined,
                            readOnly: true,
                            onTap: _pickSimExpiredDate,
                            suffixIcon: const Icon(Icons.calendar_month, size: 20),
                            validator: (v) =>
                                v == null || v.isEmpty ? "Masa berlaku SIM wajib diisi" : null,
                          ),
                          const SizedBox(height: 16),
                          _documentPhotoPicker(
                            label: "Foto SIM",
                            color: _accentColor,
                            placeholderIcon: Icons.directions_car,
                            localImage: simImage,
                            remoteUrl: simUrl,
                            onPick: _uploadSim,
                            heroTag: 'sim-photo',
                          ),
                        ],
                      ),

                      const SizedBox(height: 8),

                      /// ================= SAVE BUTTON =================
                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _primaryColor,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          onPressed: _isSaving ? null : _saveProfile,
                          child: _isSaving
                              ? const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.4,
                                    valueColor: AlwaysStoppedAnimation(Colors.white),
                                  ),
                                )
                              : const Text(
                                  "Simpan Data Personal & SIM",
                                  style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w600),
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
    );
  }
}

/// ================= FULLSCREEN ZOOMABLE IMAGE VIEWER =================
/// Widget terpisah supaya bisa dipakai ulang untuk avatar, KTP, dan SIM.
/// Mendukung pinch-to-zoom, drag, dan double-tap untuk zoom in/out.
class _ZoomableImageViewer extends StatefulWidget {
  final String? networkUrl;
  final File? localFile;
  final String heroTag;
  final String title;

  const _ZoomableImageViewer({
    this.networkUrl,
    this.localFile,
    required this.heroTag,
    required this.title,
  });

  @override
  State<_ZoomableImageViewer> createState() => _ZoomableImageViewerState();
}

class _ZoomableImageViewerState extends State<_ZoomableImageViewer>
    with SingleTickerProviderStateMixin {
  final TransformationController _controller = TransformationController();
  TapDownDetails? _doubleTapDetails;
  late final AnimationController _animController;
  Animation<Matrix4>? _animation;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    )..addListener(() {
        if (_animation != null) {
          _controller.value = _animation!.value;
        }
      });
  }

  @override
  void dispose() {
    _animController.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _handleDoubleTap() {
    Matrix4 endMatrix;
    final position = _doubleTapDetails?.localPosition ?? Offset.zero;

    if (_controller.value != Matrix4.identity()) {
      endMatrix = Matrix4.identity();
    } else {
      endMatrix = Matrix4.identity()
        ..translate(-position.dx * 1.8, -position.dy * 1.8)
        ..scale(2.8);
    }

    _animation = Matrix4Tween(begin: _controller.value, end: endMatrix)
        .animate(CurveTween(curve: Curves.easeOut).animate(_animController));
    _animController.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    final ImageProvider imageProvider = widget.localFile != null
        ? FileImage(widget.localFile!) as ImageProvider
        : NetworkImage(widget.networkUrl!);

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Text(widget.title, style: const TextStyle(color: Colors.white, fontSize: 16)),
      ),
      body: GestureDetector(
        onDoubleTapDown: (details) => _doubleTapDetails = details,
        onDoubleTap: _handleDoubleTap,
        child: Center(
          child: Hero(
            tag: widget.heroTag,
            child: InteractiveViewer(
              transformationController: _controller,
              minScale: 1,
              maxScale: 5,
              child: Image(
                image: imageProvider,
                fit: BoxFit.contain,
                width: double.infinity,
                errorBuilder: (context, error, stackTrace) => const Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    "Gagal memuat gambar",
                    style: TextStyle(color: Colors.white70),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}