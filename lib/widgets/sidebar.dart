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

  // ================= WARNA SENADA DENGAN HALAMAN LAIN =================
  static const Color _primaryColor = Color(0xFF2563EB);
  static const Color _accentColor = Color(0xFFF97316);
  static const Color _bgColor = Color(0xFFF4F6F9);

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

  /// Warna badge role, dibedakan per peran biar gampang dikenali sekilas.
  Color _roleColor(String role) {
    if (role == AppRole.superAdmin.value) return const Color(0xFFDC2626);
    if (role == AppRole.perental.value) return _primaryColor;
    if (role == AppRole.driver.value) return const Color(0xFF7C3AED);
    return _accentColor;
  }

  /// ================= HELPER UI: JUDUL SECTION =================
  Widget _sectionLabel(String text) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
      child: Text(
        text,
        style: TextStyle(
          color: Colors.grey.shade500,
          fontSize: 11.5,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.6,
        ),
      ),
    );
  }

  /// ================= HELPER UI: ITEM MENU =================
  Widget _menuItem({
    required IconData icon,
    required Color iconColor,
    required String title,
    String? subtitle,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(9),
                  decoration: BoxDecoration(
                    color: iconColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Icon(icon, color: iconColor, size: 19),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF1E293B),
                        ),
                      ),
                      if (subtitle != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 1),
                          child: Text(
                            subtitle,
                            style: TextStyle(
                              fontSize: 11.5,
                              color: Colors.grey.shade500,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_rounded,
                    size: 18, color: Colors.grey.shade400),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final List<String> rolesList =
        widget.userRoles.map((role) => role.toString()).toList();

    final String uniqueChatId =
        'room_user_${widget.userEmail.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_')}';

    return Drawer(
      backgroundColor: _bgColor,
      child: SafeArea(
        child: Column(
          children: [
            // ================= HEADER PROFIL =================
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(20, 22, 20, 22),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [_primaryColor, Color(0xFF3B82F6)],
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(3),
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white,
                    ),
                    child: CircleAvatar(
                      radius: 26,
                      backgroundColor: Colors.blue.withOpacity(0.08),
                      backgroundImage:
                          _avatarUrl != null && _avatarUrl!.isNotEmpty
                              ? NetworkImage(_avatarUrl!) as ImageProvider
                              : const AssetImage("assets/anya.jpg"),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.userName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15.5,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          widget.userEmail,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: rolesList.isNotEmpty
                              ? rolesList
                                  .map(
                                    (role) => Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 3,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.white.withOpacity(0.18),
                                        borderRadius:
                                            BorderRadius.circular(20),
                                        border: Border.all(
                                          color:
                                              Colors.white.withOpacity(0.3),
                                        ),
                                      ),
                                      child: Text(
                                        role,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  )
                                  .toList()
                              : [
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 3,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withOpacity(0.18),
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: const Text(
                                      'No Role',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // ================= LIST MENU =================
            Expanded(
              child: ListView(
                padding: const EdgeInsets.only(bottom: 12),
                children: [
                  _sectionLabel('BANTUAN'),
                  _menuItem(
                    icon: Icons.support_agent_rounded,
                    iconColor: _primaryColor,
                    title: 'Chat Admin',
                    subtitle: 'Hubungi customer service',
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
                    _sectionLabel('MENU DRIVER'),
                    _menuItem(
                      icon: Icons.directions_car_filled_rounded,
                      iconColor: const Color(0xFF7C3AED),
                      title: 'Tugas Penugasan',
                      subtitle: 'Lihat jadwal & tugas antar-jemput',
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

                  // MENU MANAJEMEN RENTAL (Perental / Super Admin)
                  if (rolesList.contains(AppRole.perental.value) ||
                      rolesList.contains(AppRole.superAdmin.value)) ...[
                    _sectionLabel('MANAJEMEN RENTAL'),
                    _menuItem(
                      icon: Icons.assignment_turned_in_rounded,
                      iconColor: _primaryColor,
                      title: 'Kelola Pesanan & Driver',
                      subtitle: 'Atur booking dan penugasan driver',
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

                  // MENU ADMINISTRATOR (Super Admin)
                  if (rolesList.contains(AppRole.superAdmin.value)) ...[
                    _sectionLabel('ADMINISTRATOR'),
                    _menuItem(
                      icon: Icons.admin_panel_settings_rounded,
                      iconColor: const Color(0xFFDC2626),
                      title: 'Manajemen User',
                      subtitle: 'Kelola pengguna & hak akses',
                      onTap: () {
                        Navigator.pop(context);
                      },
                    ),
                  ],
                ],
              ),
            ),

            // ================= FOOTER =================
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(color: Colors.grey.shade200),
                ),
              ),
              child: Center(
                child: Text(
                  'RentalCar App',
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey.shade400,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}