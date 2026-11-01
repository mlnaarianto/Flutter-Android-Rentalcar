import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:rentalcar/pages/login.dart';
import 'package:rentalcar/menu/profil.dart';
import 'package:rentalcar/menu/dashboard.dart';
import 'package:rentalcar/menu/car.dart';
import 'package:rentalcar/menu/booking_history_page.dart';
import 'package:rentalcar/menu/rental_application_page.dart'; // Halaman Pengajuan Perental
import 'package:rentalcar/config/api_config.dart';
import 'package:rentalcar/enums/app_enums.dart';
import 'package:rentalcar/services/notification_socket_service.dart'; // hapus token FCM saat logout
import 'package:rentalcar/services/api_client.dart'; // 🟢 FASE 4: POST /logout lewat ApiClient
import 'package:rentalcar/services/token_storage.dart'; // 🟢 FASE 4: cek & hapus sesi
import 'package:rentalcar/utils/navigation_service.dart'; // 🟢 FASE 4: navigatorKey global

// 🟢 FASE 4: key prefs milik user yang dibersihkan saat logout.
// Sama dengan _userPrefsKeys di main.dart. 'fcm_device_id' SENGAJA tidak
// ikut dihapus karena itu identitas device, bukan data user.
const List<String> _userPrefsKeys = [
  'access_token', // jembatan sementara dari login.dart
  'user_id',
  'user_name',
  'user_email',
  'user_roles',
  'role',
  'user_permissions',
  'avatar_url',
];

class Bottom extends StatefulWidget {
  final int currentIndex;
  final Function(int) onTap;

  const Bottom({super.key, required this.currentIndex, required this.onTap});

  @override
  State<Bottom> createState() => _BottomState();
}

class _BottomState extends State<Bottom> {
  String? _avatarUrl;
  String? _userRole;

  // ================= WARNA SENADA DENGAN HALAMAN LAIN =================
  static const Color _primaryColor = Color(0xFF2563EB);

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  /// ================== LOAD AVATAR & ROLE DARI SHARED PREFERENCES ==================
  Future<void> _loadUserData() async {
    final prefs = await SharedPreferences.getInstance();
    final String? url = prefs.getString('avatar_url');
    final String? role = prefs.getString('role');

    if (mounted) {
      setState(() {
        _avatarUrl = url;
        _userRole = role;
      });
    }
  }

  /// ================== PROSES LOGOUT ==================
  ///
  /// 🟢 FASE 4. Urutan:
  ///   1. (kalau sesi masih ada) removeFcmToken, lalu POST /logout
  ///   2. disconnect WS
  ///   3. TokenStorage.clear()
  ///   4. bersihkan prefs
  ///   5. GoogleSignIn.signOut()
  ///   6. ke LoginPage
  ///
  /// Langkah 2-5 ada di blok `finally`, jadi tetap jalan walau server
  /// error / timeout / jaringan putus. Logout lokal TIDAK boleh gagal
  /// hanya karena server tidak terjangkau.
  ///
  /// Kalau sesi sudah mati dari awal, langkah 1 dilewati.
  ///
  /// Kalau refresh token ternyata mati SAAT langkah 1, ApiClient memicu
  /// onSessionExpired (main.dart) yang sudah membersihkan semuanya dan
  /// pindah ke LoginPage. Kita deteksi itu lewat hasSession() dan tidak
  /// navigasi lagi, supaya LoginPage tidak ditumpuk dua kali.
  Future<void> _performLogout() async {
    bool handledByExpiredCallback = false;

    try {
      if (await TokenStorage.hasSession()) {
        try {
          // Hapus token FCM DULU, selagi sesi masih valid -- endpoint-nya
          // butuh Authorization. Timeout supaya logout tidak menggantung.
          await NotificationSocketService()
              .removeFcmToken()
              .timeout(const Duration(seconds: 10));

          await ApiClient.instance
              .post(Uri.parse(ApiConfig.logout))
              .timeout(const Duration(seconds: 10));
        } catch (e) {
          // Jaringan putus / timeout / dll: abaikan, lanjut logout lokal.
          debugPrint('Logout: panggilan server gagal, lanjut logout lokal: $e');
        }

        // Kalau sesi hilang selama panggilan di atas (refresh membalas 401),
        // berarti onSessionExpired sudah menangani semuanya, termasuk
        // navigasi ke LoginPage.
        handledByExpiredCallback = !await TokenStorage.hasSession();
      } else {
        debugPrint('Logout: sesi sudah tidak ada, langsung logout lokal.');
      }
    } finally {
      // Setiap langkah dibungkus try sendiri supaya satu kegagalan tidak
      // menghentikan langkah berikutnya.
      try {
        NotificationSocketService().disconnect();
      } catch (e) {
        debugPrint('Logout: disconnect WS gagal: $e');
      }

      try {
        await TokenStorage.clear();
      } catch (e) {
        debugPrint('Logout: TokenStorage.clear gagal: $e');
      }

      try {
        final prefs = await SharedPreferences.getInstance();
        for (final key in _userPrefsKeys) {
          await prefs.remove(key);
        }
      } catch (e) {
        debugPrint('Logout: bersihkan prefs gagal: $e');
      }

      try {
        await GoogleSignIn().signOut();
      } catch (e) {
        debugPrint('Logout: Google signOut gagal: $e');
      }
    }

    // Pakai navigatorKey (bukan context) karena widget ini bisa saja sudah
    // di-dispose saat sampai di sini.
    if (!handledByExpiredCallback) {
      navigatorKey.currentState?.pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginPage()),
        (route) => false,
      );
    }
  }

  /// ================== DIALOG LOGOUT ==================
  Future<void> _confirmLogout(BuildContext context) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.1),
                borderRadius: BorderRadius.circular(9),
              ),
              child: const Icon(Icons.logout_rounded, size: 18, color: Colors.red),
            ),
            const SizedBox(width: 10),
            const Text('Logout',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          ],
        ),
        content: Text(
          'Apakah kamu yakin ingin mengakhiri sesi ini?',
          style: TextStyle(color: Colors.grey.shade600, fontSize: 13.5),
        ),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text('Batal', style: TextStyle(color: Colors.grey.shade700)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Ya, Logout'),
          ),
        ],
      ),
    );

    if (result == true) {
      await _performLogout();
    }
  }

  /// ================== MENU PROFILE / PENGAJUAN ==================
  void _showProfileMenu(BuildContext parentContext) {
    showModalBottomSheet(
      context: parentContext,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return SafeArea(
          child: Container(
            margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 10),
                // Drag handle, biar keliatan ini bottom sheet yang bisa ditutup
                Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
                const SizedBox(height: 12),
                _profileMenuTile(
                  icon: Icons.store_mall_directory_rounded,
                  iconColor: _primaryColor,
                  title: 'Pengajuan Perental',
                  subtitle: 'Daftar jadi partner rental mobil',
                  onTap: () {
                    Navigator.pop(sheetContext); // Tutup bottom sheet
                    Navigator.push(
                      parentContext,
                      MaterialPageRoute(
                        builder: (_) => const RentalApplicationPage(),
                      ),
                    );
                  },
                ),
                Divider(height: 1, color: Colors.grey.shade100, indent: 16, endIndent: 16),
                _profileMenuTile(
                  icon: Icons.logout_rounded,
                  iconColor: Colors.red,
                  title: 'Logout',
                  subtitle: 'Keluar dari akun ini',
                  titleColor: Colors.red,
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _confirmLogout(parentContext);
                  },
                ),
                const SizedBox(height: 6),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _profileMenuTile({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    Color? titleColor,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: iconColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: iconColor, size: 20),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w600,
                        color: titleColor ?? const Color(0xFF1E293B),
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      subtitle,
                      style: TextStyle(fontSize: 11.5, color: Colors.grey.shade500),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// ================== WIDGET AVATAR ==================
  Widget _buildAvatar() {
    final bool isActive = widget.currentIndex == 3;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          padding: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: isActive ? _primaryColor : Colors.transparent,
              width: 1.6,
            ),
          ),
          child: CircleAvatar(
            radius: 12,
            backgroundColor: Colors.grey.shade200,
            backgroundImage: (_avatarUrl != null && _avatarUrl!.isNotEmpty)
                ? NetworkImage(_avatarUrl!) as ImageProvider
                : const AssetImage('assets/anya.jpg'),
          ),
        ),
        // Titik kecil penanda "ada menu tambahan" (tahan lama untuk buka).
        Positioned(
          right: -2,
          bottom: -2,
          child: Container(
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 1.2),
            ),
            child: Icon(Icons.more_horiz_rounded, size: 10, color: Colors.grey.shade600),
          ),
        ),
      ],
    );
  }

  /// ================== BUILD ==================
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 12,
            offset: const Offset(0, -3),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: 60,
              child: BottomNavigationBar(
                currentIndex: widget.currentIndex,
                type: BottomNavigationBarType.fixed,
                backgroundColor: Colors.white,
                elevation: 0,
                selectedItemColor: _primaryColor,
                unselectedItemColor: Colors.grey.shade400,
                selectedLabelStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                unselectedLabelStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500),
                onTap: (index) {
                  if (index == 0) {
                    Navigator.pushAndRemoveUntil(
                      context,
                      MaterialPageRoute(builder: (_) => const Dashboard()),
                      (route) => false,
                    );
                  } else if (index == 1) {
                    Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(builder: (_) => const CarPage()),
                    );
                  } else if (index == 2) {
                    Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(builder: (_) => const BookingHistoryPage()),
                    );
                  } else if (index == 3) {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const ProfilPage()),
                    ).then((_) => _loadUserData());
                  } else {
                    widget.onTap(index);
                  }
                },
                items: [
                  const BottomNavigationBarItem(
                    icon: Icon(Icons.dashboard_rounded),
                    label: 'Home',
                  ),
                  BottomNavigationBarItem(
                    icon: const Icon(Icons.car_rental_rounded),
                    label:
                        _userRole == AppRole.penyewa.value ? 'Cari Mobil' : 'Mobil',
                  ),
                  const BottomNavigationBarItem(
                    icon: Icon(Icons.history_rounded),
                    label: 'Riwayat',
                  ),
                  BottomNavigationBarItem(
                    icon: GestureDetector(
                      onLongPress: () => _showProfileMenu(context),
                      child: _buildAvatar(),
                    ),
                    label: 'Profile',
                  ),
                ],
              ),
            ),
            // Petunjuk kecil biar user TAU kalau long-press avatar bisa buka menu.
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                'Tahan lama foto profil untuk menu lainnya',
                style: TextStyle(fontSize: 9.5, color: Colors.grey.shade400),
              ),
            ),
          ],
        ),
      ),
    );
  }
}