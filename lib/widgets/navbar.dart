import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:rentalcar/config/api_config.dart';
import 'package:rentalcar/menu/notifikasi.dart';

class Navbar extends StatefulWidget implements PreferredSizeWidget {
  final String title;
  final ValueChanged<String>? onSearchChanged;

  const Navbar({
    super.key,
    required this.title,
    this.onSearchChanged,
  });

  @override
  State<Navbar> createState() => _NavbarState();

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);
}

class _NavbarState extends State<Navbar> {
  bool _isSearching = false;
  final TextEditingController _searchController = TextEditingController();

  bool _hasNewNotifications = false;

  // ================= WARNA SENADA DENGAN HALAMAN LAIN (PUTIH) =================
  static const Color _fgColor = Color(0xFF1E293B);

  @override
  void initState() {
    super.initState();
    _checkNotificationStatus();
  }

  /// ================= CEK STATUS NOTIFIKASI DARI BACKEND =================
  Future<void> _checkNotificationStatus() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String? token = prefs.getString('access_token');

      if (token == null) return;

      final response = await http.get(
        Uri.parse('${ApiConfig.baseUrl}/notifications'),
        headers: {
          'Authorization': 'Bearer $token',
          'Accept': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        final List notifications = decoded['data'] ?? [];

        // Cek apakah ada notifikasi yang 'is_read'-nya bernilai false
        bool hasUnread = notifications.any((notif) => notif['is_read'] == false);

        setState(() {
          _hasNewNotifications = hasUnread;
        });
      }
    } catch (_) {
      // Abaikan jika terjadi kendala koneksi
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppBar(
      automaticallyImplyLeading: false,
      backgroundColor: Colors.white,
      foregroundColor: _fgColor,
      elevation: 0,
      surfaceTintColor: Colors.white,
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(1),
        child: Container(height: 1, color: Colors.grey.shade200),
      ),
      leading: _isSearching
          ? IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () {
                setState(() {
                  _isSearching = false;
                  _searchController.clear();
                  if (widget.onSearchChanged != null) {
                    widget.onSearchChanged!('');
                  }
                });
              },
            )
          : IconButton(
              icon: const Icon(Icons.menu),
              onPressed: () {
                Scaffold.of(context).openDrawer();
              },
            ),
      title: _isSearching
          ? TextField(
              controller: _searchController,
              autofocus: true,
              style: const TextStyle(color: _fgColor),
              decoration: InputDecoration(
                hintText: 'Cari sesuatu...',
                hintStyle: TextStyle(color: Colors.grey.shade500),
                border: InputBorder.none,
              ),
              onChanged: widget.onSearchChanged,
            )
          : Text(
              widget.title,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
            ),
      centerTitle: true,
      actions: [
        // Ikon search cuma muncul kalau halaman ini butuh pencarian
        // (yaitu kalau onSearchChanged di-pass). Kalau tidak, sembunyikan
        // total — misalnya di halaman Profil yang memang tidak ada search.
        if (widget.onSearchChanged != null)
          IconButton(
            icon: Icon(_isSearching ? Icons.close : Icons.search),
            onPressed: () {
              setState(() {
                _isSearching = !_isSearching;
                if (!_isSearching) {
                  _searchController.clear();
                  widget.onSearchChanged!('');
                }
              });
            },
          ),
        if (!_isSearching)
          Stack(
            alignment: Alignment.center,
            children: [
              IconButton(
                icon: const Icon(Icons.notifications),
                onPressed: () async {
                  // Buka halaman notifikasi
                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const NotifikasiPage(),
                    ),
                  );
                  // Segarkan status titik merah setelah kembali dari halaman notifikasi
                  _checkNotificationStatus();
                },
              ),
              // Titik Indikator Merah
              if (_hasNewNotifications)
                Positioned(
                  right: 11,
                  top: 11,
                  child: Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: Colors.red,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 1.5),
                    ),
                  ),
                ),
            ],
          ),
      ],
    );
  }
}