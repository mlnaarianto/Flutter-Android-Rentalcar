import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:rentalcar/menu/dashboard.dart';
import 'package:rentalcar/config/api_config.dart';

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
      
      final data = jsonDecode(response.body);

      if (response.statusCode == 200 && data['status'] == 'success') {
        final String sanctumToken = data['access_token'];
        final userData = data['user'];

        // Simpan token dan data user ke SharedPreferences
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('access_token', sanctumToken);

        if (userData != null) {
          await prefs.setString('user_name', userData['name'] ?? '');
          await prefs.setString('user_email', userData['email'] ?? '');
          
          if (userData['avatar'] != null) {
            await prefs.setString('avatar_url', userData['avatar']);
          }

          // 👇 SIMPAN ROLE SPATIE DENGAN BENAR
          if (userData['roles'] != null) {
            List<dynamic> rawRoles = userData['roles'];
            List<String> rolesList = rawRoles.map((e) => e.toString()).toList();
            
            // Simpan sebagai List untuk pengecekan fleksibel
            await prefs.setStringList('user_roles', rolesList);
            
            // Simpan juga string role pertama untuk kemudahan akses (misal: 'Perental' atau 'Penyewa')
            if (rolesList.isNotEmpty) {
              await prefs.setString('role', rolesList.first);
            }
          }
        }

        debugPrint('✅ Login sukses! User: ${userData?['email']}');

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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString().replaceFirst('Exception: ', '')),
            backgroundColor: Colors.red.shade700,
            duration: const Duration(seconds: 6),
            action: SnackBarAction(
              label: 'OK',
              textColor: Colors.white,
              onPressed: () {},
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Login'), centerTitle: true),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const FlutterLogo(size: 80),
              const SizedBox(height: 40),
              const Text(
                'Rental Car',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                'Masuk dengan akun Google kamu',
                style: TextStyle(color: Colors.grey.shade600),
              ),
              const SizedBox(height: 40),

              // ── Tombol Sign in with Google ──
              SizedBox(
                width: double.infinity,
                height: 50,
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : OutlinedButton.icon(
                        onPressed: _signInWithGoogle,
                        icon: const Icon(Icons.login),
                        label: const Text('Sign in with Google'),
                        style: OutlinedButton.styleFrom(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
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