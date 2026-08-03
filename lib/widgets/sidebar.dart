import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:rentalcar/menu/rentals_booking_page.dart';
import 'package:rentalcar/menu/chat.dart';
import 'package:rentalcar/menu/driver_bookings_page.dart'; 
import 'package:rentalcar/enums/app_enums.dart';

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
  String? _userId;

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _avatarUrl = prefs.getString('avatar_url');
      _userId = prefs.getString('user_id') ?? '3';
    });
  }

  @override
  Widget build(BuildContext context) {
    final List<String> rolesList = widget.userRoles
        .map((role) => role.toString())
        .toList();

    final String uniqueChatId =
        'room_user_${widget.userEmail.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_')}';
        
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
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  widget.userEmail,
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.orange,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    rolesList.isNotEmpty ? rolesList.join(', ') : 'No Role',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Menu Chat Admin (CS)
          ListTile(
            leading: const Icon(Icons.chat, color: Colors.blue),
            title: const Text('Chat Admin'),
            onTap: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => ChatPage(
                    chatId: uniqueChatId,
                    currentUserId: _userId ?? '3',
                    currentUserName: widget.userName,
                    receiverName: "Admin Rental (CS)",
                  ),
                ),
              );
            },
          ),

          // MENU KHUSUS DRIVER
          if (rolesList.contains(AppRole.driver.value)) ...[
            const Divider(),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
              child: Text(
                'MENU DRIVER',
                style: TextStyle(
                  color: Colors.grey,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            ListTile(
              leading: const Icon(
                Icons.directions_car,
                color: Colors.indigo,
              ),
              title: const Text('Tugas Penugasan'),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const DriverBookingsPage(),
                  ),
                );
              },
            ),
          ],

          // Menu Manajemen Rental (Perental / Super Admin)
          if (rolesList.contains(AppRole.perental.value) ||
              rolesList.contains(AppRole.superAdmin.value)) ...[
            const Divider(),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
              child: Text(
                'MANAJEMEN RENTAL',
                style: TextStyle(
                  color: Colors.grey,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            ListTile(
              leading: const Icon(
                Icons.assignment_turned_in,
                color: Colors.blue,
              ),
              title: const Text('Kelola Pesanan & Driver'),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const RentalsBookingPage(),
                  ),
                );
              },
            ),
          ],

          // Menu Administrator (Super Admin)
          if (rolesList.contains(AppRole.superAdmin.value)) ...[
            const Divider(),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
              child: Text(
                'ADMINISTRATOR',
                style: TextStyle(
                  color: Colors.grey,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            ListTile(
              leading: const Icon(
                Icons.admin_panel_settings,
                color: Colors.red,
              ),
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