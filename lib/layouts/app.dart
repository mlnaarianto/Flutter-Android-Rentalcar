import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:rentalcar/config/api_config.dart';
import 'package:rentalcar/services/api_client.dart'; // 🟢 FASE 5: refresh token otomatis
import 'package:rentalcar/widgets/navbar.dart';
import 'package:rentalcar/widgets/sidebar.dart';
import 'package:rentalcar/widgets/bottom.dart';

class AppLayout extends StatefulWidget {
  final String title;
  final Widget content;
  final int currentIndex;
  final Function(int) onTap;
  final ValueChanged<String>? appBarSearchCallback;
  final Widget? floatingActionButton; // Parameter FAB
  final bool showNotification; // teruskan ke Navbar

  const AppLayout({
    super.key,
    required this.title,
    required this.content,
    required this.currentIndex,
    required this.onTap,
    this.appBarSearchCallback,
    this.floatingActionButton,
    this.showNotification = false, // default: tidak tampil (selain Dashboard)
  });

  @override
  State<AppLayout> createState() => _AppLayoutState();
}

class _AppLayoutState extends State<AppLayout> {
  String _name = 'Memuat...';
  String _email = 'Memuat...';
  List<String> _roles = [];

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    final prefs = await SharedPreferences.getInstance();

    // 1. Ambil cache lokal terlebih dahulu agar UI cepat tampil
    // 🟢 FASE 5: cek mounted, karena ada await sebelum setState.
    if (!mounted) return;
    setState(() {
      _name = prefs.getString('user_name') ?? 'Pengguna';
      _email = prefs.getString('user_email') ?? 'email@example.com';
      _roles = prefs.getStringList('user_roles') ?? [];
    });

    // 2. Sinkronkan dengan endpoint ApiConfig.userProfile.
    // 🟢 FASE 5: token, header Accept/Authorization, dan refresh otomatis
    // ditangani ApiClient. Tidak lagi membaca access_token dari prefs,
    // dan token tidak lagi dicetak ke log.
    try {
      debugPrint('Mengambil data dari: ${ApiConfig.userProfile}');
      final response = await ApiClient.instance
          .get(Uri.parse(ApiConfig.userProfile))
          .timeout(const Duration(seconds: 15));

      debugPrint('Response Status Code: ${response.statusCode}');

      if (response.statusCode == 200) {
        final responseData = jsonDecode(response.body);
        final userData = responseData['data'];

        final fetchedName = userData['name'] ?? '';
        final fetchedEmail = userData['email'] ?? '';

        List<dynamic> rawRoles = userData['roles'] ?? [];
        List<String> fetchedRoles =
            rawRoles.map((role) => role.toString()).toList();

        // Simpan pembaruan ke SharedPreferences
        await prefs.setString('user_name', fetchedName);
        await prefs.setString('user_email', fetchedEmail);
        await prefs.setStringList('user_roles', fetchedRoles);

        if (mounted) {
          setState(() {
            _name = fetchedName;
            _email = fetchedEmail;
            _roles = fetchedRoles;
          });
        }
      }
    } catch (e) {
      debugPrint('Gagal memperbarui data user dari API: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: Navbar(
        title: widget.title,
        onSearchChanged: widget.appBarSearchCallback,
        showNotification: widget.showNotification,
      ),
      drawer: Sidebar(
        userName: _name,
        userEmail: _email,
        userRoles: _roles,
      ),
      body: widget.content,
      floatingActionButton: widget.floatingActionButton,
      bottomNavigationBar: Bottom(
        currentIndex: widget.currentIndex,
        onTap: widget.onTap,
      ),
    );
  }
}