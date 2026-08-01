import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:rentalcar/config/api_config.dart';
import 'package:rentalcar/widgets/bottom.dart';

class BookingHistoryPage extends StatefulWidget {
  const BookingHistoryPage({super.key});

  @override
  State<BookingHistoryPage> createState() => _BookingHistoryPageState();
}

class _BookingHistoryPageState extends State<BookingHistoryPage> {
  List<dynamic> _bookings = [];
  bool _isLoading = true;
  String? _errorMessage;
  String? _currentUserRole;

  @override
  void initState() {
    super.initState();
    _loadUserRoleAndBookings();
  }

  Future<void> _loadUserRoleAndBookings() async {
    final prefs = await SharedPreferences.getInstance();
    // Mengambil role dari key 'role' yang disimpan saat proses login
    setState(() {
      _currentUserRole = prefs.getString('role') ?? 'Penyewa'; 
    });
    _fetchBookings();
  }

  Future<void> _fetchBookings() async {
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
        Uri.parse('${ApiConfig.baseUrl}/bookings'),
        headers: {
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        setState(() {
          _bookings = decoded['data'] ?? [];
          _isLoading = false;
        });
      } else {
        setState(() {
          _errorMessage = 'Gagal memuat riwayat booking (Kode: ${response.statusCode})';
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

  Future<void> _cancelBooking(int bookingId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('access_token');

      final response = await http.patch(
        Uri.parse('${ApiConfig.baseUrl}/bookings/$bookingId/cancel'),
        headers: {
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Booking berhasil dibatalkan.')),
        );
        _fetchBookings(); 
      } else {
        final decoded = jsonDecode(response.body);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(decoded['message'] ?? 'Gagal membatalkan pesanan')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    }
  }

  // Simulasi Pembayaran QRIS (Untuk Penyewa)
  Future<void> _simulateQrisPayment(int bookingId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('access_token');

      final response = await http.patch(
        Uri.parse('${ApiConfig.baseUrl}/bookings/$bookingId/status'),
        headers: {
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'payment_status': 'paid'}),
      );

      if (response.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Pembayaran QRIS Berhasil Dikonfirmasi! Status: Lunas.')),
        );
      } else {
        final decoded = jsonDecode(response.body);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(decoded['message'] ?? 'Gagal memperbarui status pembayaran')),
        );
      }
      _fetchBookings();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
      _fetchBookings();
    }
  }

  // Konfirmasi Pembayaran Tunai/COD LUNAS (Khusus Driver / Perental)
  Future<void> _confirmCodPayment(int bookingId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('access_token');

      final response = await http.patch(
        Uri.parse('${ApiConfig.baseUrl}/bookings/$bookingId/status'),
        headers: {
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'payment_status': 'paid'}),
      );

      if (response.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Pembayaran Tunai (COD) berhasil dikonfirmasi LUNAS!')),
        );
      } else {
        final decoded = jsonDecode(response.body);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(decoded['message'] ?? 'Gagal mengkonfirmasi pembayaran')),
        );
      }
      _fetchBookings();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
      _fetchBookings();
    }
  }

  void _showQrisDialog(BuildContext context, dynamic booking) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Pembayaran QRIS'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Silakan scan QR Code di bawah ini:', textAlign: TextAlign.center),
              const SizedBox(height: 16),
              Container(
                height: 180,
                width: 180,
                decoration: BoxDecoration(
                  color: Colors.grey.shade200,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.qr_code_2, size: 80, color: Colors.blue),
                    Text('QRIS RENTAL', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Text('Total: Rp ${booking['total_price']}', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blue)),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Tutup'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
              onPressed: () {
                Navigator.pop(context);
                _simulateQrisPayment(booking['id']);
              },
              child: const Text('Simulasi Sudah Bayar'),
            ),
          ],
        );
      },
    );
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'confirmed':
      case 'active':
        return Colors.blue;
      case 'completed':
        return Colors.green;
      case 'cancelled':
        return Colors.red;
      default:
        return Colors.orange; 
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Riwayat Pemesanan'),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null
              ? Center(child: Text(_errorMessage!))
              : _bookings.isEmpty
                  ? const Center(child: Text('Belum ada riwayat pemesanan.'))
                  : ListView.builder(
                      itemCount: _bookings.length,
                      padding: const EdgeInsets.all(12),
                      itemBuilder: (context, index) {
                        final booking = _bookings[index];
                        final car = booking['car'] ?? {};
                        final driver = booking['driver'];
                        final status = booking['status'] ?? 'pending';
                        final paymentStatus = booking['payment_status'] ?? 'unpaid';
                        final paymentMethod = booking['payment_method'] ?? 'cod';
                        final bool withDriver = booking['with_driver'] == 1 || booking['with_driver'] == true;

                        // Pengecekan role secara case-insensitive agar lebih fleksibel
                        final String role = (_currentUserRole ?? '').toLowerCase();
                        bool isStaffOrDriver = role.contains('driver') || 
                                               role.contains('perental') || 
                                               role.contains('super admin');

                        return Card(
                          margin: const EdgeInsets.only(bottom: 12),
                          elevation: 2,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
                                        car['name'] ?? 'Mobil Rental',
                                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                                      ),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: _getStatusColor(status).withOpacity(0.1),
                                        borderRadius: BorderRadius.circular(6),
                                        border: Border.all(color: _getStatusColor(status)),
                                      ),
                                      child: Text(
                                        status.toUpperCase(),
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                          color: _getStatusColor(status),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                Text('Mulai: ${booking['start_date']} s/d ${booking['end_date']}'),
                                Text('Durasi: ${booking['total_days']} Hari'),
                                Text('Layanan: ${withDriver ? "Dengan Driver" : "Lepas Kunci"}', 
                                  style: TextStyle(color: withDriver ? Colors.indigo : Colors.grey.shade700, fontWeight: FontWeight.w500)),
                                
                                if (withDriver && driver != null)
                                  Text('Driver Bertugas: ${driver['name']}', style: const TextStyle(color: Colors.green, fontWeight: FontWeight.w500)),

                                const SizedBox(height: 8),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    const Text('Metode Pembayaran:', style: TextStyle(color: Colors.grey, fontSize: 12)),
                                    Text(
                                      paymentMethod == 'qris' ? 'QRIS' : 'Bayar di Tempat (COD)',
                                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12, color: Colors.black87),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    const Text('Status Pembayaran:', style: TextStyle(color: Colors.grey, fontSize: 12)),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: paymentStatus == 'paid' ? Colors.green.shade50 : Colors.orange.shade50,
                                        borderRadius: BorderRadius.circular(4),
                                        border: Border.all(color: paymentStatus == 'paid' ? Colors.green : Colors.orange),
                                      ),
                                      child: Text(
                                        paymentStatus == 'paid' ? 'LUNAS (PAID)' : 'BELUM BAYAR (UNPAID)',
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                          color: paymentStatus == 'paid' ? Colors.green.shade700 : Colors.orange.shade700,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                Text('Total Biaya: Rp ${booking['total_price']}', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blue, fontSize: 15)),
                                const Divider(height: 20),
                                
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    // 1. Jika Penyewa dan metode QRIS (Belum Lunas) -> Muncul tombol Bayar QRIS
                                    if (!isStaffOrDriver && paymentStatus != 'paid' && paymentMethod == 'qris' && status != 'cancelled')
                                      ElevatedButton.icon(
                                        style: ElevatedButton.styleFrom(backgroundColor: Colors.indigo, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6), minimumSize: Size.zero),
                                        onPressed: () => _showQrisDialog(context, booking),
                                        icon: const Icon(Icons.qr_code, size: 16),
                                        label: const Text('Bayar via QRIS', style: TextStyle(fontSize: 12)),
                                      ),

                                    // 2. Jika Driver/Perental dan metode COD (Belum Lunas) -> Muncul tombol Konfirmasi Tunai Lunas
                                    if (isStaffOrDriver && paymentStatus != 'paid' && paymentMethod == 'cod' && status != 'cancelled')
                                      ElevatedButton.icon(
                                        style: ElevatedButton.styleFrom(backgroundColor: Colors.green.shade700, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6), minimumSize: Size.zero),
                                        onPressed: () => _confirmCodPayment(booking['id']),
                                        icon: const Icon(Icons.money, size: 16),
                                        label: const Text('Konfirmasi Tunai Lunas', style: TextStyle(fontSize: 12)),
                                      ),

                                    const Spacer(),

                                    // Tombol Batalkan (hanya untuk status pending)
                                    if (status == 'pending')
                                      OutlinedButton.icon(
                                        style: OutlinedButton.styleFrom(foregroundColor: Colors.red, padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6), minimumSize: Size.zero),
                                        onPressed: () => _cancelBooking(booking['id']),
                                        icon: const Icon(Icons.cancel, size: 16),
                                        label: const Text('Batalkan', style: TextStyle(fontSize: 12)),
                                      ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
      bottomNavigationBar: Bottom(
        currentIndex: 2, 
        onTap: (index) {},
      ),
    );
  }
}