import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:rentalcar/menu/rentals_booking_page.dart'; // 👈 Import halaman manajemen pesanan & driver

class Sidebar extends StatefulWidget {
  final String userName;
  final String userEmail;
  final List<dynamic> userRoles;

  const Sidebar({
    super.key,
    required this.userName,
    required this.userEmail,
    required this.userRoles,
  });

  @override
  State<Sidebar> createState() => _SidebarState();
}

class _SidebarState extends State<Sidebar> {
  String? _avatarUrl;

  @override
  void initState() {
    super.initState();
    _loadAvatar();
  }

  // Mengambil avatar tersimpan dari SharedPreferences secara real-time
  Future<void> _loadAvatar() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _avatarUrl = prefs.getString('avatar_url');
    });
  }

  @override
  Widget build(BuildContext context) {
    // Setiap kali widget dibangun, pastikan avatar ter-refresh jika ada perubahan
    _loadAvatar();

    final List<String> rolesList = widget.userRoles.map((role) => role.toString()).toList();

    return Drawer(
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          DrawerHeader(
            decoration: const BoxDecoration(color: Colors.blue),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                // Avatar otomatis mendeteksi foto profil dari SharedPreferences atau fallback ke Asset
                CircleAvatar(
                  radius: 28,
                  backgroundColor: Colors.white,
                  backgroundImage: _avatarUrl != null && _avatarUrl!.isNotEmpty
                      ? NetworkImage(_avatarUrl!) as ImageProvider
                      : const AssetImage("assets/anya.jpg"),
                ),
                const SizedBox(height: 8),
                Text(
                  widget.userName,
                  style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                ),
                Text(
                  widget.userEmail,
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.orange,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    rolesList.isNotEmpty ? rolesList.join(', ') : 'No Role',
                    style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ),
          
          ListTile(
            leading: const Icon(Icons.dashboard),
            title: const Text('Dashboard'),
            onTap: () {
              Navigator.pop(context);
            },
          ),
          ListTile(
            leading: const Icon(Icons.car_rental),
            title: const Text('Mobil'),
            onTap: () {
              Navigator.pop(context);
            },
          ),
          
          // 👇 Menu Khusus Perental / Super Admin untuk Kelola Pesanan & Driver
          if (rolesList.contains('Perental') || rolesList.contains('Super Admin')) ...[
            const Divider(),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
              child: Text(
                'MANAJEMEN RENTAL',
                style: TextStyle(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.bold),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.assignment_turned_in, color: Colors.blue),
              title: const Text('Kelola Pesanan & Driver'),
              onTap: () {
                Navigator.pop(context); // Tutup drawer sidebar
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const RentalsBookingPage()),
                );
              },
            ),
          ],

          // 👇 Menu Khusus Super Admin
          if (rolesList.contains('Super Admin')) ...[
            const Divider(),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
              child: Text(
                'ADMINISTRATOR',
                style: TextStyle(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.bold),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.admin_panel_settings, color: Colors.red),
              title: const Text('Manajemen User'),
              onTap: () {
                Navigator.pop(context);
              },
            ),
          ],
        ],
      ),
    );
  }
}