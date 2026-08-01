import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:rentalcar/config/api_config.dart';
import 'package:rentalcar/widgets/bottom.dart';

class NotifikasiPage extends StatefulWidget {
  const NotifikasiPage({super.key});

  @override
  State<NotifikasiPage> createState() => _NotifikasiPageState();
}

class _NotifikasiPageState extends State<NotifikasiPage> {
  List<dynamic> _notifications = [];
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _fetchNotifications();
  }

  Future<void> _fetchNotifications() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('access_token');

      if (token == null) {
        setState(() {
          _errorMessage = 'Sesi habis. Silakan login kembali.';
          _isLoading = false;
        });
        return;
      }

      final response = await http.get(
        Uri.parse('${ApiConfig.baseUrl}/notifications'),
        headers: {
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        setState(() {
          _notifications = decoded['data'] ?? [];
          _isLoading = false;
        });

        // 🟢 Otomatis simpan tanda bahwa semua notifikasi sudah dibaca (titik merah hilang)
        await prefs.setBool('has_unread_notifications', false);
      } else {
        setState(() {
          _errorMessage = 'Gagal memuat notifikasi (Kode: ${response.statusCode})';
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Terjadi kesalahan koneksi: $e';
        _isLoading = false;
      });
    }
  }

  IconData _getNotifIcon(String? type) {
    switch (type) {
      case 'booking':
        return Icons.bookmark_add;
      case 'payment':
        return Icons.payments;
      case 'driver_assignment':
        return Icons.person_pin;
      case 'booking_cancelled':
        return Icons.cancel;
      default:
        return Icons.notifications_active;
    }
  }

  Color _getNotifColor(String? type) {
    switch (type) {
      case 'booking':
        return Colors.blue;
      case 'payment':
        return Colors.green;
      case 'driver_assignment':
        return Colors.orange;
      case 'booking_cancelled':
        return Colors.red;
      default:
        return Colors.indigo;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifikasi Aktivitas'),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null
              ? Center(child: Text(_errorMessage!))
              : _notifications.isEmpty
                  ? const Center(
                      child: Text(
                        'Belum ada notifikasi kejadian.',
                        style: TextStyle(fontSize: 16, color: Colors.grey),
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _fetchNotifications,
                      child: ListView.builder(
                        itemCount: _notifications.length,
                        padding: const EdgeInsets.all(12),
                        itemBuilder: (context, index) {
                          final notif = _notifications[index];
                          final type = notif['type'];

                          return Card(
                            margin: const EdgeInsets.only(bottom: 10),
                            elevation: 2,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: ListTile(
                              leading: CircleAvatar(
                                backgroundColor: _getNotifColor(type).withOpacity(0.1),
                                child: Icon(
                                  _getNotifIcon(type),
                                  color: _getNotifColor(type),
                                ),
                              ),
                              title: Text(
                                notif['title'] ?? 'Informasi',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                ),
                              ),
                              subtitle: Padding(
                                padding: const EdgeInsets.only(top: 4.0),
                                child: Text(
                                  notif['message'] ?? '',
                                  style: const TextStyle(fontSize: 12, color: Colors.black87),
                                ),
                              ),
                              trailing: Text(
                                notif['created_at'] != null
                                    ? notif['created_at'].toString().split('T')[0]
                                    : '',
                                style: const TextStyle(fontSize: 10, color: Colors.grey),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
      bottomNavigationBar: Bottom(
        currentIndex: 3, 
        onTap: (index) {},
      ),
    );
  }
}