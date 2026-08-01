import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:rentalcar/pages/login.dart';
import 'package:rentalcar/menu/profil.dart';
import 'package:rentalcar/menu/dashboard.dart';
import 'package:rentalcar/menu/car.dart'; 
import 'package:rentalcar/menu/booking_history_page.dart'; // 👈 Import Halaman Riwayat Booking
import 'package:rentalcar/config/api_config.dart';

class Bottom extends StatefulWidget {
  final int currentIndex;
  final Function(int) onTap;

  const Bottom({
    super.key,
    required this.currentIndex,
    required this.onTap,
  });

  @override
  State<Bottom> createState() => _BottomState();
}

class _BottomState extends State<Bottom> {
  String? _avatarUrl;
  String? _userRole; // 👈 Variabel untuk menyimpan role user yang sedang login

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  /// ================== LOAD AVATAR & ROLE DARI SHARED PREFERENCES ==================
  Future<void> _loadUserData() async {
    final prefs = await SharedPreferences.getInstance();
    final String? url = prefs.getString('avatar_url');
    final String? role = prefs.getString('role'); // Ambil role yang tersimpan

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
        title: const Text('Logout'),
        content: const Text('Apakah ingin mengakhiri sesi?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Ya'),
          ),
        ],
      ),
    );

    if (result == true) {
      try {
        final prefs = await SharedPreferences.getInstance();
        final String? token = prefs.getString('access_token');

        if (token != null) {
          await http.post(
            Uri.parse(ApiConfig.logout),
            headers: {
              'Accept': 'application/json',
              'Authorization': 'Bearer $token',
            },
          );
        }

        await prefs.remove('access_token');
        await prefs.remove('avatar_url'); 
        await prefs.remove('role'); // Hapus data role saat logout

        final GoogleSignIn googleSignIn = GoogleSignIn();
        await googleSignIn.signOut();
      } catch (e) {
        print('Error saat logout: $e');
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove('access_token');
        await prefs.remove('avatar_url');
        await prefs.remove('role');
      }

      if (context.mounted) {
        Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const LoginPage()),
          (route) => false,
        );
      }
    }
  }

  /// ================== MENU PROFILE ==================
  void _showProfileMenu(BuildContext parentContext) {
    showModalBottomSheet(
      context: parentContext,
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.settings),
                title: const Text('Settings'),
                onTap: () => Navigator.pop(sheetContext),
              ),
              ListTile(
                leading: const Icon(Icons.logout),
                title: const Text('Logout'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _confirmLogout(parentContext);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  /// ================== WIDGET AVATAR ==================
  Widget _buildAvatar() {
    final bool isActive = widget.currentIndex == 3;

    return CircleAvatar(
      radius: 14,
      backgroundColor: isActive ? Colors.blue : Colors.grey.shade300,
      child: CircleAvatar(
        radius: 12,
        backgroundImage: (_avatarUrl != null && _avatarUrl!.isNotEmpty)
            ? NetworkImage(_avatarUrl!) as ImageProvider
            : const AssetImage('assets/anya.jpg'),
      ),
    );
  }

  /// ================== BUILD ==================
  @override
  Widget build(BuildContext context) {
    return BottomNavigationBar(
      currentIndex: widget.currentIndex,
      type: BottomNavigationBarType.fixed,
      selectedItemColor: Colors.blue,
      onTap: (index) {
        if (index == 0) {
          // Home / Dashboard
          Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(builder: (_) => const Dashboard()),
            (route) => false,
          );
        } else if (index == 1) {
          // Navigasi ke Halaman Mobil
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => const CarPage()),
          );
        } else if (index == 2) {
          // 👈 Diganti ke Halaman Riwayat Pemesanan (Booking History)
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => const BookingHistoryPage()),
          );
        } else if (index == 3) {
          // Profile
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
          icon: Icon(Icons.dashboard),
          label: 'Home',
        ),
        BottomNavigationBarItem(
          icon: const Icon(Icons.car_rental),
          label: _userRole == 'Penyewa' ? 'Cari Mobil' : 'Mobil',
        ),
        const BottomNavigationBarItem(
          icon: Icon(Icons.history), // 👈 Ikon Riwayat Pesanan
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
    );
  }
}