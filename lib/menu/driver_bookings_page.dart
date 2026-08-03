import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:rentalcar/config/api_config.dart';
import 'package:rentalcar/menu/chat.dart';
import 'package:rentalcar/enums/app_enums.dart';

class DriverBookingsPage extends StatefulWidget {
  const DriverBookingsPage({super.key});

  @override
  State<DriverBookingsPage> createState() => _DriverBookingsPageState();
}

class _DriverBookingsPageState extends State<DriverBookingsPage> {
  List<dynamic> _assignedBookings = [];
  bool _isLoading = true;
  String? _currentUserId;
  String? _currentUserName;

  @override
  void initState() {
    super.initState();
    _loadLocalUserData();
    _fetchDriverBookings();
  }

  // Fungsi helper untuk membersihkan format tanggal (misal: 2026-06-06T00:00:00.000000Z -> 2026-06-06)
  String _formatDate(String? dateStr) {
    if (dateStr == null || dateStr.isEmpty) return '-';
    return dateStr.contains('T') ? dateStr.split('T')[0] : dateStr;
  }

  // Ambil data user aktif (driver) dari SharedPreferences
  Future<void> _loadLocalUserData() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _currentUserId = prefs.getString('user_id') ?? '';
      _currentUserName = prefs.getString('user_name') ?? AppRole.driver.value;
    });
  }

  // Ambil daftar tugas booking khusus untuk driver yang sedang login
  Future<void> _fetchDriverBookings() async {
    setState(() => _isLoading = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('access_token');

      final response = await http.get(
        Uri.parse(
          '${ApiConfig.baseUrl}/bookings',
        ), 
        headers: {
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        setState(() {
          _assignedBookings = decoded['data'] ?? [];
          _isLoading = false;
        });
      } else {
        setState(() => _isLoading = false);
      }
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  // Navigasi ke Halaman Chat Driver <-> Perental (Pemilik Rental)
  void _openChatWithRentalOwner(Map<String, dynamic> rentalOwner) {
    final String ownerId = rentalOwner['id']?.toString() ?? '';
    final String ownerName = rentalOwner['name'] ?? 'Perental';

    if (ownerId.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('ID Perental tidak valid.')));
      return;
    }

    // Format unik room chat antara perental dan driver (harus sama persis dengan sisi perental)
    final String uniqueChatId =
        'room_rental_${ownerId}_driver_${_currentUserId}';

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ChatPage(
          chatId: uniqueChatId,
          currentUserId: _currentUserId ?? '',
          currentUserName: _currentUserName ?? AppRole.driver.value,
          receiverName: "Perental: $ownerName",
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Chat dengan Perental'),
        backgroundColor: Colors.teal,
        foregroundColor: Colors.white,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _assignedBookings.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(16.0),
                child: Text(
                  'Belum ada penugasan rental, sehingga belum ada perental yang terhubung.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey, fontSize: 14),
                ),
              ),
            )
          : RefreshIndicator(
              onRefresh: _fetchDriverBookings,
              child: ListView.builder(
                itemCount: _assignedBookings.length,
                padding: const EdgeInsets.all(12),
                itemBuilder: (context, index) {
                  final booking = _assignedBookings[index];
                  final car = booking['car'] ?? {};
                  final renter = booking['user'] ?? {};

                  // Data perental pemilik mobil / pengelola
                  final rentalOwner =
                      booking['rental_owner'] ??
                      booking['perental'] ??
                      car['user'] ??
                      {};
                  final String currentStatus = booking['status'] ?? 'pending';

                  // Memformat tanggal mulai dan selesai secara bersih
                  final String startDateFormatted = _formatDate(booking['start_date']);
                  final String endDateFormatted = _formatDate(booking['end_date']);

                  return Card(
                    margin: const EdgeInsets.only(bottom: 12),
                    elevation: 2,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(14.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Text(
                                  'Mobil: ${car['name'] ?? '-'}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                  ),
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.teal.shade50,
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(color: Colors.teal),
                                ),
                                child: Text(
                                  currentStatus.toUpperCase(),
                                  style: const TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.teal,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text('Penyewa Mobil: ${renter['name'] ?? '-'}'),
                          Text(
                            'Jadwal: $startDateFormatted s/d $endDateFormatted',
                          ),
                          const Divider(height: 16),

                          // Informasi Perental & Tombol Chat Langsung
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade50,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.grey.shade200),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        'Pengelola / Perental:',
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: Colors.grey,
                                        ),
                                      ),
                                      Text(
                                        rentalOwner['name'] ?? 'Admin Rental',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w600,
                                          fontSize: 13,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.teal,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 6,
                                    ),
                                    minimumSize: Size.zero,
                                  ),
                                  icon: const Icon(Icons.chat, size: 14),
                                  label: const Text(
                                    'Chat Perental',
                                    style: TextStyle(fontSize: 11),
                                  ),
                                  onPressed: () =>
                                      _openChatWithRentalOwner(rentalOwner),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
    );
  }
}