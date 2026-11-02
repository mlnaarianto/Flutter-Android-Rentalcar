import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:rentalcar/menu/dashboard.dart';
import 'package:rentalcar/config/api_config.dart';
import 'package:rentalcar/enums/app_enums.dart';
import 'package:rentalcar/services/notification_socket_service.dart';
import 'package:rentalcar/services/token_storage.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  bool _isLoading = false;

  static const String _serverClientId =
      '1055921517849-kd3ps2tleptf1tmpqqadvnb9f64m7tpr.apps.googleusercontent.com';

  // ================= BRAND COLORS (tetap di light & dark) =================
  static const Color _primaryColor = Color(0xFF2563EB);
  static const Color _accentColor = Color(0xFFF97316);
  static const Color _dangerColor = Color(0xFFDC2626);
  // 🟢 DIHAPUS: _bgColor — latar Scaffold sekarang ambil dari tema

  Future<void> _signInWithGoogle() async {
    setState(() => _isLoading = true);

    try {
      final GoogleSignIn googleSignIn = GoogleSignIn(
        serverClientId: _serverClientId,
        scopes: ['email', 'profile'],
      );

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
      debugPrint(
          'idToken: ${idToken != null ? "ADA (${idToken.length} chars)" : "NULL ❌"}');
      debugPrint('-------------------');

      if (idToken == null) {
        throw Exception(
          'id_token null. Pastikan serverClientId sudah benar (gunakan Web Client ID).',
        );
      }

      debugPrint('Mengirim ke Laravel: ${ApiConfig.googleLogin}');

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

        await TokenStorage.save(
          accessToken: accessToken,
          refreshToken: refreshToken,
          expiresIn: expiresIn.toInt(),
        );

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

          if (userData['roles'] != null) {
            List<dynamic> rawRoles = userData['roles'];
            List<String> rolesList =
                rawRoles.map((e) => e.toString()).toList();

            await prefs.setStringList('user_roles', rolesList);

            if (rolesList.isNotEmpty) {
              await prefs.setString('role', rolesList.first);
            }
          }

          if (userData['permissions'] != null) {
            List<dynamic> rawPermissions = userData['permissions'];
            List<String> permissionsList =
                rawPermissions.map((e) => e.toString()).toList();

            await prefs.setStringList('user_permissions', permissionsList);
          }
        }

        debugPrint(
            '✅ Login sukses! User ID: ${userData?['id']} | Email: ${userData?['email']}');

        NotificationSocketService().connect();

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
    // 🟢 Ambil token tema
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      // 🟢 DIHAPUS: backgroundColor hardcoded → pakai default tema
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Column(
            children: [
              const Spacer(flex: 3),
              _buildLogo(),
              const SizedBox(height: 28),

              // 🟢 'Selamat Datang' — headline + onSurface
              Text(
                'Selamat Datang',
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 8),

              // 🟢 Subtitle — bodyMedium + onSurfaceVariant
              Text(
                'Masuk untuk mulai menyewa mobil\nimpianmu dengan mudah',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  height: 1.5,
                ),
              ),

              const Spacer(flex: 3),
              _buildFeatureRow(),
              const SizedBox(height: 28),
              _buildGoogleButton(),
              const SizedBox(height: 20),

              // 🟢 Footer — bodySmall + outline (lebih redup, tetap terbaca)
              Text(
                'Dengan masuk, kamu menyetujui Syarat & Ketentuan\nserta Kebijakan Privasi kami',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.outline,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLogo() {
    // 🟢 Tetap pakai _primaryColor — brand warna yang sama di light/dark.
    // Container pakai opacity 0.1 dari primary, di dark mode jadi biru gelap,
    // kontras dengan ikon biru cerah di atasnya.
    return Container(
      width: 88,
      height: 88,
      decoration: BoxDecoration(
        color: _primaryColor.withOpacity(0.15),
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
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

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
                      // 🟢 Ganti Colors.white → surfaceContainerHighest
                      // (light: abu terang, dark: abu gelap)
                      color: colorScheme.surfaceContainerHighest,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          // 🟢 Shadow pakai skema tema biar halus di dark
                          color: colorScheme.shadow.withOpacity(0.08),
                          blurRadius: 8,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    // 🟢 _accentColor tetap — oranye khas brand
                    child: Icon(item.$1, size: 20, color: _accentColor),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    item.$2,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          )
          .toList(),
    );
  }

  Widget _buildGoogleButton() {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton(
        onPressed: _isLoading ? null : _signInWithGoogle,
        style: ElevatedButton.styleFrom(
          // 🟢 Adaptif: light = putih, dark = surface gelap
          backgroundColor: colorScheme.surface,
          foregroundColor: colorScheme.onSurface,
          elevation: 0,
          side: BorderSide(color: colorScheme.outlineVariant),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
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
                  Text(
                    'Masuk dengan Google',
                    style: theme.textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  /// "G" multi-warna sederhana tanpa perlu aset gambar
  /// 🟢 TIDAK diubah — warna logo Google memang harus tetap
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
      const Color(0xFF4285F4): [-45, 90],
      const Color(0xFF34A853): [45, 90],
      const Color(0xFFFBBC05): [135, 70],
      const Color(0xFFEA4335): [205, 85],
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

    final barPaint = Paint()..color = const Color(0xFF4285F4);
    canvas.drawRect(
      Rect.fromLTWH(center.dx, center.dy - strokeWidth / 2,
          r - strokeWidth * 0.2, strokeWidth),
      barPaint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}