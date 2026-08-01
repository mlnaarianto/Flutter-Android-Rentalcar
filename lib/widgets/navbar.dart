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

        // 🟢 Diperbaiki: Cek apakah ada notifikasi yang 'is_read'-nya bernilai false
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
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                hintText: 'Cari sesuatu...',
                hintStyle: TextStyle(color: Colors.white70),
                border: InputBorder.none,
              ),
              onChanged: widget.onSearchChanged,
            )
          : Text(widget.title),
      centerTitle: true,
      backgroundColor: Colors.blue,
      actions: [
        IconButton(
          icon: Icon(_isSearching ? Icons.close : Icons.search),
          onPressed: () {
            setState(() {
              _isSearching = !_isSearching;
              if (!_isSearching) {
                _searchController.clear();
                if (widget.onSearchChanged != null) {
                  widget.onSearchChanged!('');
                }
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
                  // (Karena NotifikasiPage sudah mengubah is_read menjadi true di server)
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
                      border: Border.all(color: Colors.blue, width: 1.5),
                    ),
                  ),
                ),
            ],
          ),
      ],
    );
  }
}