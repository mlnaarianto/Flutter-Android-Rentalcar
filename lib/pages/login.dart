import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:rentalcar/menu/dashboard.dart';
import 'package:rentalcar/config/api_config.dart';
import 'package:rentalcar/enums/app_enums.dart'; // 👈 Import Enums yang baru dibuat
import 'package:rentalcar/services/notification_socket_service.dart'; // 🟢 TAMBAHAN
import 'package:rentalcar/services/token_storage.dart'; // 🟢 TAMBAHAN: secure storage

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  bool _isLoading = false;

  // Web Client ID (bukan Android)
  static const String _serverClientId =
      '1055921517849-kd3ps2tleptf1tmpqqadvnb9f64m7tpr.apps.googleusercontent.com';

  // ================= WARNA SENADA DENGAN HALAMAN LAIN =================
  static const Color _primaryColor = Color(0xFF2563EB);
  static const Color _accentColor = Color(0xFFF97316);
  static const Color _bgColor = Color(0xFFF4F6F9);
  static const Color _dangerColor = Color(0xFFDC2626);

  Future<void> _signInWithGoogle() async {
    setState(() => _isLoading = true);

    try {
      final GoogleSignIn googleSignIn = GoogleSignIn(
        serverClientId: _serverClientId,
        scopes: ['email', 'profile'],
      );

      // Pastikan user bisa memilih akun Google yang berbeda jika mau
      await googleSignIn.signOut();

      final GoogleSignInAccount? googleUser = await googleSignIn.signIn();
      if (googleUser == null) {
        debugPrint('Login dibatalkan oleh user');
        setState(() => _isLoading = false);
        return;
      }

      final GoogleSignInAuthentication googleAuth =
          await googleUser.authentication;

      final String? idToken = googleAuth.idToken;

      debugPrint('--- DEBUG TOKEN ---');
      debugPrint('idToken: ${idToken != null ? "ADA (${idToken.length} chars)" : "NULL ❌"}');
      debugPrint('-------------------');

      if (idToken == null) {
        throw Exception(
          'id_token null. Pastikan serverClientId sudah benar (gunakan Web Client ID).',
        );
      }

      debugPrint('Mengirim ke Laravel: ${ApiConfig.googleLogin}');

      // Hit API Backend Laravel
      // (sengaja pakai http biasa, bukan ApiClient: belum ada token saat login)
      final response = await http
          .post(
            Uri.parse(ApiConfig.googleLogin),
            headers: {
              'Accept': 'application/json',
              'Content-Type': 'application/x-www-form-urlencoded',
            },
            body: {'id_token': idToken},
          )
          .timeout(
            const Duration(seconds: 15),
            onTimeout: () {
              throw Exception(
                'Timeout! Server tidak merespons.\n'
                'Cek koneksi WiFi dan pastikan server Laravel sudah berjalan.',
              );
            },
          );

      debugPrint('Status code: ${response.statusCode}');

      // Decode aman: respons non-JSON (mis. 502 berisi HTML) tidak
      // melempar FormatException, tapi jatuh ke pesan generik di bawah.
      Map<String, dynamic> data = {};
      try {
        final decoded = jsonDecode(response.body);
        if (decoded is Map<String, dynamic>) data = decoded;
      } catch (_) {}

      if (response.statusCode == 200 && data['status'] == 'success') {
        final String? accessToken = data['access_token'] as String?;
        final String? refreshToken = data['refresh_token'] as String?;
        final num? expiresIn = data['expires_in'] as num?;
        final userData = data['user'];

        if (accessToken == null || refreshToken == null || expiresIn == null) {
          throw Exception('Respons login dari server tidak lengkap.');
        }

        // 🟢 Simpan token ke secure storage (bukan SharedPreferences lagi)
        await TokenStorage.save(
          accessToken: accessToken,
          refreshToken: refreshToken,
          expiresIn: expiresIn.toInt(),
        );

        // Data user non-sensitif tetap di SharedPreferences.
        // Token TIDAK disimpan di sini: semua halaman sudah memakai
        // ApiClient yang membaca token dari TokenStorage.
        final prefs = await SharedPreferences.getInstance();

        if (userData != null) {
          if (userData['id'] != null) {
            await prefs.setString('user_id', userData['id'].toString());
          }

          await prefs.setString('user_name', userData['name'] ?? '');
          await prefs.setString('user_email', userData['email'] ?? '');

          if (userData['avatar'] != null) {
            await prefs.setString('avatar_url', userData['avatar']);
          }

          // 1. Simpan Role Spatie
          if (userData['roles'] != null) {
            List<dynamic> rawRoles = userData['roles'];
            List<String> rolesList = rawRoles.map((e) => e.toString()).toList();

            await prefs.setStringList('user_roles', rolesList);

            if (rolesList.isNotEmpty) {
              await prefs.setString('role', rolesList.first);
            }
          }

          // 2. 👇 SIMPAN PERMISSIONS SPATIE (Agar Flutter bisa validasi pakai AppPermission)
          if (userData['permissions'] != null) {
            List<dynamic> rawPermissions = userData['permissions'];
            List<String> permissionsList = rawPermissions.map((e) => e.toString()).toList();

            await prefs.setStringList('user_permissions', permissionsList);
          }
        }

        debugPrint('✅ Login sukses! User ID: ${userData?['id']} | Email: ${userData?['email']}');

        // 🟢 TAMBAHAN: mulai koneksi real-time SEKALI di sini, tepat
        // setelah token & user_id tersimpan.
        // Sengaja tidak di-"await" — biar navigasi ke Dashboard tidak
        // ikut menunggu proses koneksi WebSocket selesai dulu.
        //
        // CATATAN: registrasi FCM token sekarang dilakukan otomatis DI
        // DALAM connect() (lihat NotificationSocketService), bukan di
        // sini lagi — supaya juga jalan saat app dibuka ulang dengan
        // sesi lama, bukan cuma pas login baru seperti alur ini.
        NotificationSocketService().connect();

        // Navigasi ke Dashboard
        if (mounted) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => const Dashboard()),
          );
        }
      } else {
        final String errorMsg =
            data['message'] ?? 'Gagal login (status: ${response.statusCode})';
        throw Exception(errorMsg);
      }
    } catch (e) {
      debugPrint('❌ Error: $e');
      if (mounted) {
        _showSnackBar(e.toString().replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: _dangerColor,
        duration: const Duration(seconds: 6),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.all(12),
        action: SnackBarAction(
          label: 'OK',
          textColor: Colors.white,
          onPressed: () {},
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bgColor,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Column(
            children: [
              const Spacer(flex: 3),
              _buildLogo(),
              const SizedBox(height: 28),
              const Text(
                'Selamat Datang',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1E293B),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Masuk untuk mulai menyewa mobil\nimpianmu dengan mudah',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.grey.shade500,
                  fontSize: 13.5,
                  height: 1.5,
                ),
              ),
              const Spacer(flex: 3),
              _buildFeatureRow(),
              const SizedBox(height: 28),
              _buildGoogleButton(),
              const SizedBox(height: 20),
              Text(
                'Dengan masuk, kamu menyetujui Syarat & Ketentuan\nserta Kebijakan Privasi kami',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey.shade400, fontSize: 11, height: 1.5),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLogo() {
    return Container(
      width: 88,
      height: 88,
      decoration: BoxDecoration(
        color: _primaryColor.withOpacity(0.1),
        shape: BoxShape.circle,
      ),
      child: const Icon(
        Icons.directions_car_filled_rounded,
        size: 44,
        color: _primaryColor,
      ),
    );
  }

  Widget _buildFeatureRow() {
    final items = [
      (Icons.verified_user_outlined, 'Aman'),
      (Icons.flash_on_outlined, 'Cepat'),
      (Icons.support_agent_outlined, '24/7'),
    ];

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: items
          .map(
            (item) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.04),
                          blurRadius: 8,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: Icon(item.$1, size: 20, color: _accentColor),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    item.$2,
                    style: TextStyle(fontSize: 10.5, color: Colors.grey.shade500),
                  ),
                ],
              ),
            ),
          )
          .toList(),
    );
  }

  Widget _buildGoogleButton() {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton(
        onPressed: _isLoading ? null : _signInWithGoogle,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.white,
          foregroundColor: const Color(0xFF1E293B),
          elevation: 0,
          side: BorderSide(color: Colors.grey.shade200),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
        child: _isLoading
            ? const SizedBox(
                height: 22,
                width: 22,
                child: CircularProgressIndicator(
                  color: _primaryColor,
                  strokeWidth: 2.4,
                ),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _buildGoogleIcon(),
                  const SizedBox(width: 12),
                  const Text(
                    'Masuk dengan Google',
                    style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
      ),
    );
  }

  /// "G" multi-warna sederhana tanpa perlu aset gambar
  Widget _buildGoogleIcon() {
    return SizedBox(
      width: 20,
      height: 20,
      child: CustomPaint(painter: _GoogleGPainter()),
    );
  }
}

class _GoogleGPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final double r = size.width / 2;
    final Offset center = Offset(size.width / 2, size.height / 2);
    final double strokeWidth = size.width * 0.22;

    final colors = <Color, List<double>>{
      const Color(0xFF4285F4): [-45, 90], // biru: kanan atas
      const Color(0xFF34A853): [45, 90], // hijau: kanan bawah
      const Color(0xFFFBBC05): [135, 70], // kuning: kiri bawah
      const Color(0xFFEA4335): [205, 85], // merah: kiri atas
    };

    colors.forEach((color, angles) {
      final paint = Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.butt;
      canvas.drawArc(
        Rect.fromCircle(radius: r - strokeWidth / 2, center: center),
        angles[0] * 3.14159 / 180,
        angles[1] * 3.14159 / 180,
        false,
        paint,
      );
    });

    // Bar horizontal biru khas logo "G"
    final barPaint = Paint()..color = const Color(0xFF4285F4);
    canvas.drawRect(
      Rect.fromLTWH(center.dx, center.dy - strokeWidth / 2, r - strokeWidth * 0.2, strokeWidth),
      barPaint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}