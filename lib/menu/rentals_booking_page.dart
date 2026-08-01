import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:rentalcar/config/api_config.dart';

class RentalsBookingPage extends StatefulWidget {
  const RentalsBookingPage({super.key});

  @override
  State<RentalsBookingPage> createState() => _RentalsBookingPageState();
}

class _RentalsBookingPageState extends State<RentalsBookingPage> {
  List<dynamic> _bookings = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchBookings();
  }

  // 1. Ambil daftar booking (khusus perental/admin dari API backend)
  Future<void> _fetchBookings() async {
    setState(() => _isLoading = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('access_token');

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
        setState(() => _isLoading = false);
      }
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  // 2. Ambil daftar user ber-role 'Driver' dari backend
  Future<List<dynamic>> _fetchAvailableDrivers() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('access_token');

      final response = await http.get(
        Uri.parse('${ApiConfig.baseUrl}/drivers-list'),
        headers: {
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        return decoded['data'] ?? [];
      }
      return [];
    } catch (e) {
      return [];
    }
  }

  // 3. Dialog untuk Memilih & Menugaskan Driver
  Future<void> _showAssignDriverDialog(int bookingId) async {
    List<dynamic> drivers = await _fetchAvailableDrivers();
    int? selectedDriverId;

    if (!mounted) return;

    if (drivers.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Tidak ada driver yang tersedia di sistem saat ini.')),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Pilih Driver untuk Penugasan'),
          content: StatefulBuilder(
            builder: (context, setStateDialog) {
              return DropdownButtonFormField<int>(
                isExpanded: true, // 👈 Mencegah overflow pada layout dropdown
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: 'Pilih Nama Driver',
                ),
                items: drivers.map<DropdownMenuItem<int>>((driver) {
                  return DropdownMenuItem<int>(
                    value: driver['id'],
                    child: Text(
                      '${driver['name']} (${driver['email']})',
                      overflow: TextOverflow.ellipsis, // 👈 Memotong teks panjang dengan aman
                    ),
                  );
                }).toList(),
                onChanged: (value) {
                  setStateDialog(() {
                    selectedDriverId = value;
                  });
                },
              );
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Batal'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.blue, foregroundColor: Colors.white),
              onPressed: () async {
                if (selectedDriverId == null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Silakan pilih driver terlebih dahulu!')),
                  );
                  return;
                }
                Navigator.pop(context);
                await _submitAssignDriver(bookingId, selectedDriverId!);
              },
              child: const Text('Simpan & Tugaskan'),
            ),
          ],
        );
      },
    );
  }

  // 4. Kirim request API penugasan driver ke backend
  Future<void> _submitAssignDriver(int bookingId, int driverId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('access_token');

      final response = await http.patch(
        Uri.parse('${ApiConfig.baseUrl}/bookings/$bookingId/assign-driver'),
        headers: {
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'driver_id': driverId}),
      );

      final decoded = jsonDecode(response.body);

      if (response.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Driver berhasil ditugaskan!')),
        );
        _fetchBookings(); // Refresh data
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(decoded['message'] ?? 'Gagal menugaskan driver')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    }
  }

  // 5. Kirim request API pembaruan status booking ke backend
  Future<void> _updateBookingStatus(int bookingId, String newStatus) async {
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
        body: jsonEncode({'status': newStatus}),
      );

      final decoded = jsonDecode(response.body);

      if (response.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Status booking berhasil diperbarui!')),
        );
        _fetchBookings(); // Refresh data
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(decoded['message'] ?? 'Gagal memperbarui status')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Manajemen Pesanan & Driver'),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _bookings.isEmpty
              ? const Center(child: Text('Belum ada pesanan masuk.'))
              : RefreshIndicator(
                  onRefresh: _fetchBookings,
                  child: ListView.builder(
                    itemCount: _bookings.length,
                    padding: const EdgeInsets.all(12),
                    itemBuilder: (context, index) {
                      final booking = _bookings[index];
                      final car = booking['car'] ?? {};
                      final renter = booking['user'] ?? {};
                      final driver = booking['driver'];
                      final bool withDriver = booking['with_driver'] == 1 || booking['with_driver'] == true;
                      final String currentStatus = booking['status'] ?? 'pending';
                      final String paymentStatus = booking['payment_status'] ?? 'unpaid';
                      final String paymentMethod = booking['payment_method'] ?? 'cod';

                      return Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        elevation: 2,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        child: Padding(
                          padding: const EdgeInsets.all(14.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Mobil: ${car['name'] ?? '-'}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                              const SizedBox(height: 4),
                              Text('Penyewa: ${renter['name'] ?? '-'}'),
                              Text('Tanggal: ${booking['start_date']} s/d ${booking['end_date']} (${booking['total_days']} Hari)'),
                              const Divider(height: 16),
                              
                              // Status Pesanan (Dropdown Ubah Status)
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text('Status Pesanan:', style: TextStyle(fontWeight: FontWeight.w500)),
                                  DropdownButton<String>(
                                    value: ['pending', 'confirmed', 'active', 'completed', 'cancelled'].contains(currentStatus) 
                                        ? currentStatus 
                                        : 'pending',
                                    items: ['pending', 'confirmed', 'active', 'completed', 'cancelled']
                                        .map((st) => DropdownMenuItem(
                                              value: st,
                                              child: Text(st.toUpperCase(), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                                            ))
                                        .toList(),
                                    onChanged: (newStatus) {
                                      if (newStatus != null) {
                                        _updateBookingStatus(booking['id'], newStatus);
                                      }
                                    },
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),

                              // Informasi Metode Pembayaran
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text('Metode Pembayaran:', style: TextStyle(color: Colors.grey, fontSize: 12)),
                                  Text(
                                    paymentMethod == 'qris' ? 'QRIS (Online)' : 'Bayar di Tempat (COD)',
                                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12, color: Colors.black87),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),

                              // Informasi Status Pembayaran (Paid / Unpaid)
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text('Status Pembayaran:', style: TextStyle(color: Colors.grey, fontSize: 12)),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: paymentStatus == 'paid' ? Colors.green.shade50 : Colors.orange.shade50,
                                      borderRadius: BorderRadius.circular(4),
                                      border: Border.all(
                                        color: paymentStatus == 'paid' ? Colors.green : Colors.orange,
                                      ),
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
                              const SizedBox(height: 8),

                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    'Layanan:', 
                                    style: TextStyle(color: Colors.grey.shade700),
                                  ),
                                  Text(
                                    withDriver ? "Dengan Driver" : "Lepas Kunci",
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold, 
                                      color: withDriver ? Colors.indigo : Colors.grey.shade800,
                                    ),
                                  ),
                                ],
                              ),
                              
                              if (withDriver) ...[
                                const SizedBox(height: 8),
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
                                        child: Text(
                                          driver != null 
                                              ? 'Driver: ${driver['name']}' 
                                              : 'Driver: Belum Ditugaskan',
                                          style: TextStyle(
                                            color: driver != null ? Colors.green.shade700 : Colors.red.shade700,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                      ElevatedButton(
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: Colors.orange,
                                          foregroundColor: Colors.white,
                                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                          minimumSize: Size.zero,
                                        ),
                                        onPressed: () => _showAssignDriverDialog(booking['id']),
                                        child: Text(driver != null ? 'Ganti Driver' : 'Tugaskan'),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                              const SizedBox(height: 8),
                              Text(
                                'Total Harga: Rp ${booking['total_price']}',
                                style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blue),
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