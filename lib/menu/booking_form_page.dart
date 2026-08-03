import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:rentalcar/config/api_config.dart';
import 'package:rentalcar/menu/profil.dart';

class BookingFormPage extends StatefulWidget {
  final Map<String, dynamic> car;

  const BookingFormPage({super.key, required this.car});

  @override
  State<BookingFormPage> createState() => _BookingFormPageState();
}

class _BookingFormPageState extends State<BookingFormPage> {
  DateTime? _startDate;
  DateTime? _endDate;
  bool _withDriver = false;
  String _paymentMethod = 'cod';
  final TextEditingController _notesController = TextEditingController();
  bool _isSubmitting = false;

  // Ambil tarif driver secara dinamis dari data mobil yang dipilih
  double get _driverRatePerDay {
    return double.tryParse(widget.car['driver_price_per_day']?.toString() ?? '0') ?? 0.0;
  }

  int get _totalDays {
    if (_startDate == null || _endDate == null) return 0;
    return _endDate!.difference(_startDate!).inDays + 1;
  }

  double get _totalPrice {
    if (_totalDays <= 0) return 0;
    double carPricePerDay = double.tryParse(widget.car['price_per_day'].toString()) ?? 0;
    double driverFee = _withDriver ? _driverRatePerDay : 0;
    return _totalDays * (carPricePerDay + driverFee);
  }

  // Fungsi helper untuk memformat DateTime menjadi string bersih (YYYY-MM-DD)
  String _formatDate(DateTime? date) {
    if (date == null) return '';
    return "${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}";
  }

  Future<void> _selectDate(BuildContext context, bool isStart) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) {
      setState(() {
        if (isStart) {
          _startDate = picked;
          if (_endDate != null && _endDate!.isBefore(_startDate!)) {
            _endDate = null;
          }
        } else {
          _endDate = picked;
        }
      });
    }
  }

  Future<void> _submitBooking() async {
    if (_startDate == null || _endDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Silakan pilih tanggal mulai dan selesai sewa!')),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('access_token');

      if (token == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Sesi habis. Silakan login kembali.')),
        );
        setState(() => _isSubmitting = false);
        return;
      }

      final response = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/bookings'),
        headers: {
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'car_id': widget.car['id'],
          'start_date': _formatDate(_startDate), // Menggunakan format bersih YYYY-MM-DD
          'end_date': _formatDate(_endDate),     // Menggunakan format bersih YYYY-MM-DD
          'with_driver': _withDriver,
          'payment_method': _paymentMethod,
          'notes': _notesController.text,
        }),
      );

      final decoded = jsonDecode(response.body);

      if (response.statusCode == 201) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Booking berhasil dibuat! Silakan cek riwayat pesanan.')),
        );
        Navigator.pop(context, true); 
      } else if (response.statusCode == 403) {
        String message = decoded['message'] ?? 'Akses ditolak.';
        
        if (message.contains('Data Personal')) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(message), backgroundColor: Colors.orange),
          );
          
          if (mounted) {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const ProfilPage()),
            );
          }
        } else {
          _showPendingWarningDialog(message);
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(decoded['message'] ?? 'Gagal membuat booking')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Terjadi kesalahan koneksi: $e')),
      );
    } finally {
      setState(() => _isSubmitting = false);
    }
  }

  void _showPendingWarningDialog(String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Pesanan Pending Ditemukan'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Form Pemesanan Mobil'),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: ListView(
          children: [
            Text(
              widget.car['name'] ?? 'Mobil Rental',
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              'Tarif Mobil: Rp ${widget.car['price_per_day']} / hari',
              style: const TextStyle(color: Colors.blue, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 2),
            Text(
              'Tarif Driver: Rp $_driverRatePerDay / hari',
              style: const TextStyle(color: Colors.indigo, fontWeight: FontWeight.w500),
            ),
            const Divider(height: 30),
            
            // Tanggal Mulai Sewa
            ListTile(
              shape: RoundedRectangleBorder(
                side: const BorderSide(color: Colors.grey, width: 0.5),
                borderRadius: BorderRadius.circular(8),
              ),
              title: Text(_startDate == null
                  ? 'Pilih Tanggal Mulai'
                  : 'Mulai: ${_formatDate(_startDate)}'),
              trailing: const Icon(Icons.calendar_today, color: Colors.blue),
              onTap: () => _selectDate(context, true),
            ),
            const SizedBox(height: 12),
            
            // Tanggal Selesai Sewa
            ListTile(
              shape: RoundedRectangleBorder(
                side: const BorderSide(color: Colors.grey, width: 0.5),
                borderRadius: BorderRadius.circular(8),
              ),
              title: Text(_endDate == null
                  ? 'Pilih Tanggal Selesai'
                  : 'Selesai: ${_formatDate(_endDate)}'),
              trailing: const Icon(Icons.calendar_today, color: Colors.blue),
              onTap: () => _selectDate(context, false),
            ),
            const SizedBox(height: 12),
            
            SwitchListTile(
              title: const Text('Gunakan Jasa Sopir (Driver)', style: TextStyle(fontWeight: FontWeight.w500)),
              subtitle: Text('Tarif tambahan: Rp $_driverRatePerDay / hari'),
              value: _withDriver,
              activeColor: Colors.blue,
              onChanged: (val) {
                setState(() {
                  _withDriver = val;
                });
              },
            ),
            const SizedBox(height: 12),

            DropdownButtonFormField<String>(
              value: _paymentMethod,
              decoration: const InputDecoration(
                labelText: 'Metode Pembayaran',
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(
                  value: 'cod',
                  child: Text('Bayar di Tempat (COD / Tunai)'),
                ),
                DropdownMenuItem(
                  value: 'qris',
                  child: Text('QRIS (Statik / Transfer)'),
                ),
              ],
              onChanged: (val) {
                setState(() {
                  _paymentMethod = val!;
                });
              },
            ),

            const SizedBox(height: 16),
            TextField(
              controller: _notesController,
              decoration: const InputDecoration(
                labelText: 'Catatan tambahan (Opsional)',
                border: OutlineInputBorder(),
              ),
              maxLines: 2,
            ),
            const SizedBox(height: 20),
            if (_totalDays > 0) ...[
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.blue.shade200),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Durasi Sewa: $_totalDays Hari', style: const TextStyle(fontSize: 14)),
                    const SizedBox(height: 4),
                    Text('Opsi Driver: ${_withDriver ? "Ya (Rp $_driverRatePerDay/hari)" : "Tidak (Lepas Kunci)"}', 
                      style: const TextStyle(fontSize: 13, color: Colors.black87)),
                    const SizedBox(height: 4),
                    Text('Metode Pembayaran: ${_paymentMethod == "cod" ? "Bayar di Tempat (COD)" : "QRIS"}', 
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.indigo)),
                    const Divider(height: 16),
                    Text(
                      'Total Biaya: Rp $_totalPrice',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: Colors.blue,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
            ],
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: _isSubmitting ? null : _submitBooking,
              child: _isSubmitting
                  ? const CircularProgressIndicator(color: Colors.white)
                  : const Text('Konfirmasi & Buat Pesanan', style: TextStyle(fontSize: 16)),
            ),
          ],
        ),
      ),
    );
  }
}