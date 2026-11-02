import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:rentalcar/config/api_config.dart';
import 'package:rentalcar/services/api_client.dart';
import 'package:rentalcar/menu/profil.dart';
import 'package:rentalcar/menu/booking_history_page.dart';

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

  // ================= BRAND & SEMANTIC COLORS (tetap di light & dark) =====
  static const Color _primaryColor = Color(0xFF2563EB);
  static const Color _accentColor = Color(0xFFF97316);
  static const Color _successColor = Color(0xFF16A34A);
  static const Color _dangerColor = Color(0xFFDC2626);
  static const Color _indigoColor = Color(0xFF6366F1);
  // 🟢 DIHAPUS: _bgColor — pakai surfaceContainerHighest

  double get _driverRatePerDay {
    return double.tryParse(
            widget.car['driver_price_per_day']?.toString() ?? '0') ??
        0.0;
  }

  double get _carRatePerDay {
    return double.tryParse(widget.car['price_per_day']?.toString() ?? '0') ??
        0.0;
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

  String _formatDate(DateTime? date) {
    if (date == null) return '';
    return "${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}";
  }

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
      // 🟢 DIPERBAIKI: sebelumnya di-hardcode ColorScheme.light(),
      // jadi di dark mode date picker tetap putih terang menyilaukan.
      // Sekarang pakai colorScheme aktif hanya untuk override primary —
      // brightness & surface otomatis ikut tema.
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme:
                Theme.of(context).colorScheme.copyWith(primary: _primaryColor),
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
      _showSnackBar(
          'Silakan pilih tanggal mulai dan selesai sewa!', _accentColor);
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final response = await ApiClient.instance.post(
        Uri.parse('${ApiConfig.baseUrl}/bookings'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'car_id': widget.car['id'],
          'start_date': _formatDate(_startDate),
          'end_date': _formatDate(_endDate),
          'with_driver': _withDriver,
          'payment_method': _paymentMethod,
          'notes': _notesController.text,
        }),
      );

      if (!mounted) return;

      if (response.statusCode == 401) {
        _showSnackBar('Sesi habis. Silakan login kembali.', _dangerColor);
        return;
      }

      final decoded = jsonDecode(response.body);

      if (response.statusCode == 201) {
        _showSnackBar(
            'Booking berhasil dibuat! Silakan cek riwayat pesanan.',
            _successColor);

        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (context) => const BookingHistoryPage()),
          (route) => route.isFirst,
        );
      } else if (response.statusCode == 403) {
        String message = decoded['message'] ?? 'Akses ditolak.';

        if (message.contains('Data Personal')) {
          _showSnackBar(message, _accentColor);

          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const ProfilPage()),
          );
        } else {
          _showPendingWarningDialog(message);
        }
      } else {
        _showSnackBar(
            decoded['message'] ?? 'Gagal membuat booking', _dangerColor);
      }
    } catch (e) {
      if (!mounted) return;
      _showSnackBar('Terjadi kesalahan koneksi: $e', _dangerColor);
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  void _showSnackBar(String message, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: color, // 🟢 semantic, tetap
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.all(12),
      ),
    );
  }

  void _showPendingWarningDialog(String message) {
    showDialog(
      context: context,
      builder: (context) {
        // 🟢 Ambil colorScheme dari context dialog
        final colorScheme = Theme.of(context).colorScheme;

        return AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Pesanan Pending Ditemukan',
              style: TextStyle(fontWeight: FontWeight.bold)),
          content: Text(
            message,
            style: TextStyle(
              // 🟢 Ganti Colors.grey.shade700 → onSurfaceVariant
              color: colorScheme.onSurfaceVariant,
              fontSize: 13.5,
            ),
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(context),
              style: FilledButton.styleFrom(
                backgroundColor: _primaryColor, // brand
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
              child: const Text('OK'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      // 🟢 DIHAPUS: backgroundColor: _bgColor
      appBar: AppBar(
        title: const Text(
          'Form Pemesanan Mobil',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
        ),
        centerTitle: false,
        // 🟢 AppBar pakai token tema
        backgroundColor: colorScheme.surface,
        foregroundColor: colorScheme.onSurface,
        elevation: 0,
        surfaceTintColor: colorScheme.surface,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: colorScheme.outlineVariant),
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
    final colorScheme = Theme.of(context).colorScheme;

    return Text(
      title,
      style: TextStyle(
        fontSize: 13.5,
        fontWeight: FontWeight.bold,
        // 🟢 Ganti Color(0xFF1E293B) → onSurface
        color: colorScheme.onSurface,
      ),
    );
  }

  Widget _card({required Widget child}) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        // 🟢 Ganti Colors.white → colorScheme.surface
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            // 🟢 Shadow dari tema
            color: colorScheme.shadow.withOpacity(0.06),
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
    final colorScheme = Theme.of(context).colorScheme;

    return _card(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              // 🟢 0.08 → 0.15, tetap kelihatan di dark
              color: _primaryColor.withOpacity(0.15),
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
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    // 🟢 Ganti Color(0xFF1E293B) → onSurface
                    color: colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(
                      Icons.local_offer_outlined,
                      size: 13,
                      // 🟢 Ganti Colors.grey.shade400 → outline
                      color: colorScheme.outline,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '${_formatPrice(_carRatePerDay)} / hari',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: _primaryColor, // brand
                      ),
                    ),
                  ],
                ),
                if (_driverRatePerDay > 0) ...[
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      Icon(
                        Icons.person_outline_rounded,
                        size: 13,
                        color: colorScheme.outline,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Tarif Sopir: ${_formatPrice(_driverRatePerDay)} / hari',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: _indigoColor, // brand semantic
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
    final colorScheme = Theme.of(context).colorScheme;

    return _card(
      child: Column(
        children: [
          _buildDateTile(
            label: 'Tanggal Mulai',
            date: _startDate,
            onTap: () => _selectDate(context, true),
          ),
          Divider(height: 20, color: colorScheme.outlineVariant),
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
                // 🟢 0.08 → 0.15, hijau semantic
                color: _successColor.withOpacity(0.15),
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
    final colorScheme = Theme.of(context).colorScheme;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          // 🟢 Ganti _bgColor → surfaceContainerHighest
          color: colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
          // 🟢 Ganti Colors.grey.shade200 → outlineVariant
          border: Border.all(color: colorScheme.outlineVariant),
        ),
        child: Row(
          children: [
            const Icon(Icons.calendar_today_rounded,
                size: 17, color: _primaryColor),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 10.5,
                      // 🟢 Ganti Colors.grey.shade500 → onSurfaceVariant
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    date == null
                        ? 'Ketuk untuk memilih'
                        : _formatDateDisplay(date),
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      // 🟢 Placeholder pakai outline (redup),
                      //    tanggal terisi pakai onSurface (terang)
                      color: date == null
                          ? colorScheme.outline
                          : colorScheme.onSurface,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: colorScheme.outline),
          ],
        ),
      ),
    );
  }

  // ================= CARD: OPSI TAMBAHAN =================
  Widget _buildOptionsCard() {
    final colorScheme = Theme.of(context).colorScheme;

    return _card(
      child: Column(
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  // 🟢 0.1 → 0.15, oranye semantic
                  color: _accentColor.withOpacity(0.15),
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
                    Text(
                      'Gunakan Jasa Sopir',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13.5,
                        // 🟢 Tambahkan onSurface (sebelumnya default)
                        color: colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Tambahan ${_formatPrice(_driverRatePerDay)} / hari',
                      style: TextStyle(
                        fontSize: 11.5,
                        // 🟢 Ganti Colors.grey.shade500 → onSurfaceVariant
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Switch(
                value: _withDriver,
                // 🟢 Brand biru — tetap di kedua mode
                activeColor: _primaryColor,
                onChanged: (val) {
                  setState(() {
                    _withDriver = val;
                  });
                },
              ),
            ],
          ),
          Divider(height: 24, color: colorScheme.outlineVariant),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  // 🟢 0.1 → 0.15, biru brand
                  color: _primaryColor.withOpacity(0.15),
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
                    Text(
                      'Metode Pembayaran',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13.5,
                        color: colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      value: _paymentMethod,
                      isExpanded: true,
                      // 🟢 Teks dropdown ikut tema
                      style: TextStyle(
                        fontSize: 13,
                        color: colorScheme.onSurface,
                      ),
                      icon: Icon(Icons.keyboard_arrow_down_rounded,
                          color: colorScheme.onSurfaceVariant),
                      decoration: InputDecoration(
                        filled: true,
                        // 🟢 Ganti _bgColor → surfaceContainerHighest
                        fillColor: colorScheme.surfaceContainerHighest,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide.none,
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          // 🟢 Ganti Colors.grey.shade200 → outlineVariant
                          borderSide:
                              BorderSide(color: colorScheme.outlineVariant),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(
                              color: _primaryColor, width: 1.4),
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
    final colorScheme = Theme.of(context).colorScheme;

    return _card(
      child: TextField(
        controller: _notesController,
        maxLines: 2,
        style: TextStyle(
          fontSize: 13.5,
          // 🟢 Teks input ikut tema
          color: colorScheme.onSurface,
        ),
        decoration: InputDecoration(
          hintText: 'Contoh: Tolong dibersihkan dulu, dijemput jam 9 pagi, dll.',
          hintStyle: TextStyle(
            fontSize: 12.5,
            // 🟢 Ganti Colors.grey.shade400 → outline
            color: colorScheme.outline,
          ),
          border: InputBorder.none,
          isCollapsed: true,
        ),
      ),
    );
  }

  // ================= CARD: RINGKASAN BIAYA =================
  Widget _buildSummaryCard() {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        // 🟢 0.05 → 0.12, tetap kelihatan di dark (sebelumnya nyaris tak
        // terlihat karena opacity sangat rendah di atas bg gelap)
        color: _primaryColor.withOpacity(0.12),
        borderRadius: BorderRadius.circular(16),
        // 🟢 0.15 → 0.30 border biar jelas di dark
        border: Border.all(color: _primaryColor.withOpacity(0.30)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.receipt_long_rounded,
                  size: 16, color: _primaryColor),
              const SizedBox(width: 6),
              Text(
                'Ringkasan Biaya',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13.5,
                  // 🟢 Tambahkan onSurface
                  color: colorScheme.onSurface,
                ),
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
          Divider(
            height: 20,
            // 🟢 Naikkan opacity biar kelihatan di dark
            color: _primaryColor.withOpacity(0.30),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Total Biaya',
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  color: colorScheme.onSurface,
                ),
              ),
              Text(
                _formatPrice(_totalPrice),
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                  color: _primaryColor, // brand biru
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _summaryRow(String label, String value) {
    final colorScheme = Theme.of(context).colorScheme;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12.5,
            // 🟢 Ganti Colors.grey.shade600 → onSurfaceVariant
            color: colorScheme.onSurfaceVariant,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            // 🟢 Ganti Color(0xFF1E293B) → onSurface
            color: colorScheme.onSurface,
          ),
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
          // 🟢 Brand biru, tetap sama di kedua mode
          backgroundColor: _primaryColor,
          foregroundColor: Colors.white,
          elevation: 0,
          disabledBackgroundColor: _primaryColor.withOpacity(0.5),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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