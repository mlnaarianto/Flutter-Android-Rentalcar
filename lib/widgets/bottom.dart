import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:rentalcar/pages/login.dart';
import 'package:rentalcar/menu/profil.dart';
import 'package:rentalcar/menu/dashboard.dart';
import 'package:rentalcar/menu/car.dart';
import 'package:rentalcar/menu/booking_history_page.dart';
import 'package:rentalcar/menu/rental_application_page.dart';
import 'package:rentalcar/config/api_config.dart';
import 'package:rentalcar/enums/app_enums.dart';
import 'package:rentalcar/services/notification_socket_service.dart';
import 'package:rentalcar/services/api_client.dart';
import 'package:rentalcar/services/token_storage.dart';
import 'package:rentalcar/utils/navigation_service.dart';
import 'package:rentalcar/utils/user_prefs.dart';

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

  // ================= BRAND COLOR (tetap di light & dark) =================
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
  /// Tidak diubah sama sekali — 100% logika lama.
  Future<void> _performLogout() async {
    bool handledByExpiredCallback = false;

    try {
      if (await TokenStorage.hasSession()) {
        try {
          await NotificationSocketService()
              .removeFcmToken()
              .timeout(const Duration(seconds: 10));

          await ApiClient.instance
              .post(Uri.parse(ApiConfig.logout))
              .timeout(const Duration(seconds: 10));
        } catch (e) {
          debugPrint('Logout: panggilan server gagal, lanjut logout lokal: $e');
        }

        handledByExpiredCallback = !await TokenStorage.hasSession();
      } else {
        debugPrint('Logout: sesi sudah tidak ada, langsung logout lokal.');
      }
    } finally {
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
        for (final key in userPrefsKeys) {
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
      builder: (dialogContext) {
        // 🟢 Ambil token tema dari dialogContext (punya akses ke theme)
        final colorScheme = Theme.of(dialogContext).colorScheme;

        return AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  // 🟢 error dengan opacity: merah di light, merah terang di dark
                  color: colorScheme.error.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(Icons.logout_rounded,
                    size: 18, color: colorScheme.error),
              ),
              const SizedBox(width: 10),
              const Text('Logout',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            ],
          ),
          content: Text(
            'Apakah kamu yakin ingin mengakhiri sesi ini?',
            style: TextStyle(
              color: colorScheme.onSurfaceVariant,
              fontSize: 13.5,
            ),
          ),
          actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text('Batal',
                  style: TextStyle(color: colorScheme.onSurfaceVariant)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                // 🟢 Pakai error/onError: kontras terjamin di kedua mode
                backgroundColor: colorScheme.error,
                foregroundColor: colorScheme.onError,
                elevation: 0,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Ya, Logout'),
            ),
          ],
        );
      },
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
        // 🟢 Ambil token tema dari sheetContext
        final colorScheme = Theme.of(sheetContext).colorScheme;

        return SafeArea(
          child: Container(
            margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            decoration: BoxDecoration(
              // 🟢 surface: light = putih, dark = abu gelap
              color: colorScheme.surface,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 10),
                // Drag handle
                Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    // 🟢 outlineVariant: abu sesuai mode
                    color: colorScheme.outlineVariant,
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
                const SizedBox(height: 12),
                _profileMenuTile(
                  icon: Icons.store_mall_directory_rounded,
                  iconColor: _primaryColor, // brand
                  title: 'Pengajuan Perental',
                  subtitle: 'Daftar jadi partner rental mobil',
                  onTap: () {
                    Navigator.pop(sheetContext);
                    Navigator.push(
                      parentContext,
                      MaterialPageRoute(
                        builder: (_) => const RentalApplicationPage(),
                      ),
                    );
                  },
                ),
                Divider(
                  height: 1,
                  // 🟢 outlineVariant, bukan grey.shade100
                  color: colorScheme.outlineVariant,
                  indent: 16,
                  endIndent: 16,
                ),
                _profileMenuTile(
                  icon: Icons.logout_rounded,
                  iconColor: colorScheme.error,
                  title: 'Logout',
                  subtitle: 'Keluar dari akun ini',
                  titleColor: colorScheme.error,
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
    final colorScheme = Theme.of(context).colorScheme;

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
                  // 🟢 0.1 → 0.12 (sedikit lebih kuat biar kelihatan di dark)
                  color: iconColor.withOpacity(0.12),
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
                        // 🟢 titleColor (untuk logout = error), default onSurface
                        color: titleColor ?? colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 11.5,
                        // 🟢 Ganti Colors.grey.shade500 → onSurfaceVariant
                        color: colorScheme.onSurfaceVariant,
                      ),
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
    final colorScheme = Theme.of(context).colorScheme;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          padding: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              // 🟢 _primaryColor = brand, tetap sama di light & dark
              color: isActive ? _primaryColor : Colors.transparent,
              width: 1.6,
            ),
          ),
          child: CircleAvatar(
            radius: 12,
            // 🟢 surfaceContainerHighest: light = abu terang, dark = abu gelap
            backgroundColor: colorScheme.surfaceContainerHighest,
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
              // 🟢 Sama dengan latar navbar supaya "menyatu"
              color: colorScheme.surface,
              shape: BoxShape.circle,
              // 🟢 Border pakai surface lagi (efek "ring" tipis)
              border: Border.all(color: colorScheme.surface, width: 1.2),
            ),
            child: Icon(
              Icons.more_horiz_rounded,
              size: 10,
              // 🟢 Ganti Colors.grey.shade600 → onSurfaceVariant
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }

  /// ================== BUILD ==================
  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      decoration: BoxDecoration(
        // 🟢 surface: light = putih, dark = abu gelap
        color: colorScheme.surface,
        boxShadow: [
          BoxShadow(
            // 🟢 shadow dari tema (tidak hitam pekat di dark mode)
            color: colorScheme.shadow.withOpacity(0.08),
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
                // 🟢 Ikut tema Container di atas
                backgroundColor: colorScheme.surface,
                elevation: 0,
                // 🟢 _primaryColor tetap — brand, kontras di kedua mode
                selectedItemColor: _primaryColor,
                // 🟢 onSurfaceVariant: abu redup, terbaca di light & dark
                unselectedItemColor: colorScheme.onSurfaceVariant,
                selectedLabelStyle: const TextStyle(
                    fontSize: 11, fontWeight: FontWeight.bold),
                unselectedLabelStyle: const TextStyle(
                    fontSize: 11, fontWeight: FontWeight.w500),
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
                      MaterialPageRoute(
                          builder: (_) => const BookingHistoryPage()),
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
                style: TextStyle(
                  fontSize: 9.5,
                  // 🟢 Ganti Colors.grey.shade400 → outline
                  color: colorScheme.outline,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}