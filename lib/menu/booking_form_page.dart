import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:rentalcar/config/api_config.dart';
import 'package:rentalcar/menu/profil.dart';
import 'package:rentalcar/menu/booking_history_page.dart'; // 👈 DITAMBAHKAN: dibutuhkan untuk redirect ke Riwayat Pemesanan

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

  // ================= WARNA SENADA DENGAN HALAMAN LAIN =================
  static const Color _primaryColor = Color(0xFF2563EB);
  static const Color _accentColor = Color(0xFFF97316);
  static const Color _bgColor = Color(0xFFF4F6F9);
  static const Color _successColor = Color(0xFF16A34A);
  static const Color _dangerColor = Color(0xFFDC2626);
  static const Color _indigoColor = Color(0xFF6366F1);

  // Ambil tarif driver secara dinamis dari data mobil yang dipilih
  double get _driverRatePerDay {
    return double.tryParse(widget.car['driver_price_per_day']?.toString() ?? '0') ?? 0.0;
  }

  double get _carRatePerDay {
    return double.tryParse(widget.car['price_per_day']?.toString() ?? '0') ?? 0.0;
  }

  int get _totalDays {
    if (_startDate == null || _endDate == null) return 0;
    return _endDate!.difference(_startDate!).inDays + 1;
  }

  double get _totalPrice {
    if (_totalDays <= 0) return 0;
    double driverFee = _withDriver ? _driverRatePerDay : 0;
    return _totalDays * (_carRatePerDay + driverFee);
  }

  /// Format angka jadi "Rp 1.200.000" tanpa desimal, konsisten dgn halaman lain
  String _formatPrice(dynamic raw) {
    if (raw == null) return 'Rp 0';
    final numValue = num.tryParse(raw.toString()) ?? 0;
    final intValue = numValue.round();
    final str = intValue.toString();
    final buffer = StringBuffer();
    for (int i = 0; i < str.length; i++) {
      final posFromRight = str.length - i;
      buffer.write(str[i]);
      if (posFromRight > 1 && posFromRight % 3 == 1) {
        buffer.write('.');
      }
    }
    return 'Rp $buffer';
  }

  // Fungsi helper untuk memformat DateTime menjadi string bersih (YYYY-MM-DD)
  String _formatDate(DateTime? date) {
    if (date == null) return '';
    return "${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}";
  }

  /// Format tanggal untuk ditampilkan ke user, mis. "30 Agu 2026"
  String _formatDateDisplay(DateTime? date) {
    if (date == null) return '';
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'Mei', 'Jun',
      'Jul', 'Agu', 'Sep', 'Okt', 'Nov', 'Des'
    ];
    return '${date.day} ${months[date.month - 1]} ${date.year}';
  }

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _selectDate(BuildContext context, bool isStart) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(primary: _primaryColor),
          ),
          child: child!,
        );
      },
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
      _showSnackBar('Silakan pilih tanggal mulai dan selesai sewa!', _accentColor);
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('access_token');

      if (token == null) {
        _showSnackBar('Sesi habis. Silakan login kembali.', _dangerColor);
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
        // 👇 DIGANTI: dulu cuma Navigator.pop(context, true) (balik ke halaman
        // sebelumnya / detail mobil). Sekarang, setelah booking sukses,
        // langsung dilempar ke halaman Riwayat Pemesanan (path menu yang sama:
        // BookingHistoryPage), dan seluruh stack navigasi sebelumnya
        // (form + detail mobil) dibersihkan sampai halaman paling awal
        // (route.isFirst, biasanya Home/Dashboard). Jadi kalau user tekan
        // tombol back dari halaman Riwayat, dia langsung ke Home, bukan
        // balik lagi ke form/detail mobil yang sudah tidak relevan.
        _showSnackBar('Booking berhasil dibuat! Silakan cek riwayat pesanan.', _successColor);

        if (mounted) {
          Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(builder: (context) => const BookingHistoryPage()),
            (route) => route.isFirst,
          );
        }
      } else if (response.statusCode == 403) {
        String message = decoded['message'] ?? 'Akses ditolak.';

        if (message.contains('Data Personal')) {
          _showSnackBar(message, _accentColor);

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
        _showSnackBar(decoded['message'] ?? 'Gagal membuat booking', _dangerColor);
      }
    } catch (e) {
      _showSnackBar('Terjadi kesalahan koneksi: $e', _dangerColor);
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  void _showSnackBar(String message, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.all(12),
      ),
    );
  }

  void _showPendingWarningDialog(String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Pesanan Pending Ditemukan',
            style: TextStyle(fontWeight: FontWeight.bold)),
        content: Text(
          message,
          style: TextStyle(color: Colors.grey.shade700, fontSize: 13.5),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(context),
            style: FilledButton.styleFrom(
              backgroundColor: _primaryColor,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bgColor,
      appBar: AppBar(
        title: const Text(
          'Form Pemesanan Mobil',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
        ),
        centerTitle: false,
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF1E293B),
        elevation: 0,
        surfaceTintColor: Colors.white,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: Colors.grey.shade200),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          _buildCarSummaryCard(),
          const SizedBox(height: 16),
          _buildSectionTitle('Jadwal Sewa'),
          const SizedBox(height: 10),
          _buildDateCard(),
          const SizedBox(height: 16),
          _buildSectionTitle('Opsi Tambahan'),
          const SizedBox(height: 10),
          _buildOptionsCard(),
          const SizedBox(height: 16),
          _buildSectionTitle('Catatan'),
          const SizedBox(height: 10),
          _buildNotesField(),
          const SizedBox(height: 20),
          if (_totalDays > 0) ...[
            _buildSummaryCard(),
            const SizedBox(height: 20),
          ],
          _buildSubmitButton(),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 13.5,
        fontWeight: FontWeight.bold,
        color: Color(0xFF1E293B),
      ),
    );
  }

  Widget _card({required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: child,
    );
  }

  // ================= CARD: RINGKASAN MOBIL =================
  Widget _buildCarSummaryCard() {
    return _card(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _primaryColor.withOpacity(0.08),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.directions_car_rounded,
                color: _primaryColor, size: 26),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.car['name'] ?? 'Mobil Rental',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1E293B),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(Icons.local_offer_outlined,
                        size: 13, color: Colors.grey.shade400),
                    const SizedBox(width: 4),
                    Text(
                      '${_formatPrice(_carRatePerDay)} / hari',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: _primaryColor,
                      ),
                    ),
                  ],
                ),
                if (_driverRatePerDay > 0) ...[
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      Icon(Icons.person_outline_rounded,
                          size: 13, color: Colors.grey.shade400),
                      const SizedBox(width: 4),
                      Text(
                        'Tarif Sopir: ${_formatPrice(_driverRatePerDay)} / hari',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: _indigoColor,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ================= CARD: TANGGAL SEWA =================
  Widget _buildDateCard() {
    return _card(
      child: Column(
        children: [
          _buildDateTile(
            label: 'Tanggal Mulai',
            date: _startDate,
            onTap: () => _selectDate(context, true),
          ),
          Divider(height: 20, color: Colors.grey.shade200),
          _buildDateTile(
            label: 'Tanggal Selesai',
            date: _endDate,
            onTap: () => _selectDate(context, false),
          ),
          if (_totalDays > 0) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                color: _successColor.withOpacity(0.08),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Center(
                child: Text(
                  'Total Durasi: $_totalDays Hari',
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.bold,
                    color: _successColor,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDateTile({
    required String label,
    required DateTime? date,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: _bgColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Row(
          children: [
            Icon(Icons.calendar_today_rounded, size: 17, color: _primaryColor),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(fontSize: 10.5, color: Colors.grey.shade500),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    date == null ? 'Ketuk untuk memilih' : _formatDateDisplay(date),
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      color: date == null ? Colors.grey.shade400 : const Color(0xFF1E293B),
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: Colors.grey.shade400),
          ],
        ),
      ),
    );
  }

  // ================= CARD: OPSI TAMBAHAN =================
  Widget _buildOptionsCard() {
    return _card(
      child: Column(
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: _accentColor.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.person_pin_circle_outlined,
                    size: 18, color: _accentColor),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Gunakan Jasa Sopir',
                      style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Tambahan ${_formatPrice(_driverRatePerDay)} / hari',
                      style: TextStyle(fontSize: 11.5, color: Colors.grey.shade500),
                    ),
                  ],
                ),
              ),
              Switch(
                value: _withDriver,
                activeColor: _primaryColor,
                onChanged: (val) {
                  setState(() {
                    _withDriver = val;
                  });
                },
              ),
            ],
          ),
          Divider(height: 24, color: Colors.grey.shade200),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: _primaryColor.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.payments_outlined,
                    size: 18, color: _primaryColor),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Metode Pembayaran',
                      style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5),
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      value: _paymentMethod,
                      isExpanded: true,
                      style: const TextStyle(fontSize: 13, color: Color(0xFF1E293B)),
                      icon: Icon(Icons.keyboard_arrow_down_rounded,
                          color: Colors.grey.shade500),
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: _bgColor,
                        contentPadding:
                            const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide.none,
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide(color: Colors.grey.shade200),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(color: _primaryColor, width: 1.4),
                        ),
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
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ================= CATATAN =================
  Widget _buildNotesField() {
    return _card(
      child: TextField(
        controller: _notesController,
        maxLines: 2,
        style: const TextStyle(fontSize: 13.5),
        decoration: InputDecoration(
          hintText: 'Contoh: Tolong dibersihkan dulu, dijemput jam 9 pagi, dll.',
          hintStyle: TextStyle(fontSize: 12.5, color: Colors.grey.shade400),
          border: InputBorder.none,
          isCollapsed: true,
        ),
      ),
    );
  }

  // ================= CARD: RINGKASAN BIAYA =================
  Widget _buildSummaryCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _primaryColor.withOpacity(0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _primaryColor.withOpacity(0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.receipt_long_rounded, size: 16, color: _primaryColor),
              const SizedBox(width: 6),
              const Text(
                'Ringkasan Biaya',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _summaryRow('Durasi Sewa', '$_totalDays Hari'),
          const SizedBox(height: 6),
          _summaryRow(
            'Opsi Driver',
            _withDriver
                ? 'Ya (${_formatPrice(_driverRatePerDay)}/hari)'
                : 'Tidak (Lepas Kunci)',
          ),
          const SizedBox(height: 6),
          _summaryRow(
            'Metode Pembayaran',
            _paymentMethod == 'cod' ? 'Bayar di Tempat (COD)' : 'QRIS',
          ),
          Divider(height: 20, color: _primaryColor.withOpacity(0.15)),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Total Biaya',
                style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
              ),
              Text(
                _formatPrice(_totalPrice),
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                  color: _primaryColor,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _summaryRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: TextStyle(fontSize: 12.5, color: Colors.grey.shade600)),
        Text(
          value,
          style: const TextStyle(
              fontSize: 12.5, fontWeight: FontWeight.w600, color: Color(0xFF1E293B)),
        ),
      ],
    );
  }

  // ================= TOMBOL SUBMIT =================
  Widget _buildSubmitButton() {
    return SizedBox(
      width: double.infinity,
      height: 50,
      child: ElevatedButton.icon(
        onPressed: _isSubmitting ? null : _submitBooking,
        style: ElevatedButton.styleFrom(
          backgroundColor: _primaryColor,
          foregroundColor: Colors.white,
          elevation: 0,
          disabledBackgroundColor: _primaryColor.withOpacity(0.5),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        icon: _isSubmitting
            ? const SizedBox.shrink()
            : const Icon(Icons.check_circle_outline_rounded, size: 19),
        label: _isSubmitting
            ? const SizedBox(
                height: 22,
                width: 22,
                child: CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 2.4,
                ),
              )
            : const Text(
                'Konfirmasi & Buat Pesanan',
                style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600),
              ),
      ),
    );
  }
}