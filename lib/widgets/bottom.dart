import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:rentalcar/pages/login.dart';
import 'package:rentalcar/menu/profil.dart';
import 'package:rentalcar/menu/dashboard.dart';
import 'package:rentalcar/menu/car.dart';
import 'package:rentalcar/menu/booking_history_page.dart';
import 'package:rentalcar/menu/rental_application_page.dart'; // 👈 Import Halaman Pengajuan Perental
import 'package:rentalcar/config/api_config.dart';
import 'package:rentalcar/enums/app_enums.dart';
import 'package:rentalcar/services/notification_socket_service.dart'; // 👈 tambahan: hapus token FCM saat logout

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
      try {
        final prefs = await SharedPreferences.getInstance();
        final String? token = prefs.getString('access_token');

        if (token != null) {
          // 🟢 BARU: hapus token FCM device ini dari server DULU,
          // sebelum access_token dihapus/di-invalidate -- karena
          // endpoint ini butuh header Authorization yang masih valid.
          // Tanpa ini, device ini akan TETAP menerima push notification
          // walau sudah logout, karena baris token di tabel
          // user_fcm_tokens tidak pernah terhapus.
          await NotificationSocketService().removeFcmToken(token);

          await http.post(
            Uri.parse(ApiConfig.logout),
            headers: {
              'Accept': 'application/json',
              'Authorization': 'Bearer $token',
            },
          );
        }

        // 🟢 BARU: tutup koneksi WebSocket & reset state service,
        // supaya kalau ada user login lagi (akun sama/beda) di device
        // ini, service mulai dari kondisi bersih -- bukan meneruskan
        // sesi user sebelumnya.
        NotificationSocketService().disconnect();

        await prefs.remove('access_token');
        await prefs.remove('avatar_url');
        await prefs.remove('role');
        await prefs.remove('user_permissions');

        final GoogleSignIn googleSignIn = GoogleSignIn();
        await googleSignIn.signOut();
      } catch (e) {
        debugPrint('Error saat logout: $e');
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove('access_token');
        await prefs.remove('avatar_url');
        await prefs.remove('role');
        await prefs.remove('user_permissions');
      }

      if (context.mounted) {
        Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const LoginPage()),
          (route) => false,
        );
      }
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
        // 👇 Titik kecil penanda "ada menu tambahan" (tahan lama untuk buka).
        // Sebelumnya fitur long-press ini tidak ada petunjuk visual sama
        // sekali, jadi kemungkinan besar tidak akan ditemukan user.
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
            // 👇 Petunjuk kecil biar user TAU kalau long-press avatar bisa
            // buka menu (sebelumnya fitur ini "tersembunyi" tanpa petunjuk
            // sama sekali, jadi kemungkinan besar tidak akan ditemukan user).
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