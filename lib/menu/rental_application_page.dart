import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:rentalcar/config/api_config.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:rentalcar/menu/profil.dart';
import 'package:rentalcar/services/api_client.dart';

class RentalApplicationPage extends StatefulWidget {
  const RentalApplicationPage({super.key});

  @override
  State<RentalApplicationPage> createState() => _RentalApplicationPageState();
}

class _RentalApplicationPageState extends State<RentalApplicationPage> {
  final _formKey = GlobalKey<FormState>();

  final TextEditingController _businessNameController = TextEditingController();
  final TextEditingController _businessAddressController =
      TextEditingController();

  String _status = 'pending';
  String? _adminNotes;
  bool _isLoading = true;
  bool _isSubmitting = false;
  bool _isGeocoding = false;

  // Variabel Peta & Koordinat (Default: Batam)
  double _latitude = 1.1301;
  double _longitude = 104.0530;
  final MapController _mapController = MapController();
  bool _hasSelectedLocation = false;

  // ================= BRAND & SEMANTIC COLORS (tetap) =================
  static const Color _primaryColor = Color(0xFF2563EB);
  static const Color _accentColor = Color(0xFFF97316);
  static const Color _successColor = Color(0xFF16A34A);
  static const Color _dangerColor = Color(0xFFDC2626);
  // 🟢 DIHAPUS: _bgColor

  @override
  void initState() {
    super.initState();
    _fetchApplicationStatus();
  }

  @override
  void dispose() {
    _businessNameController.dispose();
    _businessAddressController.dispose();
    super.dispose();
  }

  Future<void> _fetchApplicationStatus() async {
    try {
      final response = await ApiClient.instance
          .get(Uri.parse('${ApiConfig.baseUrl}/rental-application'))
          .timeout(const Duration(seconds: 20));

      if (!mounted) return;

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final appData = data['data'];

        if (appData != null) {
          setState(() {
            _businessNameController.text = appData['business_name'] ?? '';
            _businessAddressController.text =
                appData['business_address'] ?? '';
            _status = appData['status'] ?? 'pending';
            _adminNotes = appData['admin_notes'];

            if (appData['latitude'] != null && appData['longitude'] != null) {
              _latitude = double.parse(appData['latitude'].toString());
              _longitude = double.parse(appData['longitude'].toString());
              _hasSelectedLocation = true;
            }
          });
        }
      }
    } catch (e) {
      debugPrint('Error fetch application: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _reverseGeocode(double lat, double lng) async {
    setState(() {
      _latitude = lat;
      _longitude = lng;
      _hasSelectedLocation = true;
      _isGeocoding = true;
    });

    try {
      final response = await ApiClient.instance
          .get(Uri.parse(
              '${ApiConfig.baseUrl}/rental-application/reverse-geocode?latitude=$lat&longitude=$lng'))
          .timeout(const Duration(seconds: 20));

      if (!mounted) return;

      if (response.statusCode == 200) {
        final responseData = jsonDecode(response.body);
        final addressData = responseData['data'];

        if (addressData != null && addressData['formatted_address'] != null) {
          String formattedAddress = addressData['formatted_address'];
          setState(() {
            _businessAddressController.text = formattedAddress;
          });
        }
      }
    } catch (e) {
      debugPrint('Gagal reverse geocode: $e');
    } finally {
      if (mounted) setState(() => _isGeocoding = false);
    }
  }

  Future<void> _getCurrentLocation() async {
    bool serviceEnabled;
    LocationPermission permission;

    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      _showSnackBar('Layanan GPS/Lokasi tidak aktif.', _dangerColor);
      return;
    }

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        _showSnackBar('Izin lokasi ditolak.', _dangerColor);
        return;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      _showSnackBar('Izin lokasi ditolak secara permanen.', _dangerColor);
      return;
    }

    try {
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      LatLng currentLatLng = LatLng(position.latitude, position.longitude);
      _mapController.move(currentLatLng, 16.0);
      await _reverseGeocode(position.latitude, position.longitude);
    } catch (e) {
      _showSnackBar('Gagal mendapatkan lokasi GPS.', _dangerColor);
    }
  }

  Future<void> _submitApplication() async {
    if (!_formKey.currentState!.validate()) return;

    if (!_hasSelectedLocation) {
      _showSnackBar(
          'Silakan tandai lokasi usaha Anda di peta terlebih dahulu.',
          _dangerColor);
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final response = await ApiClient.instance
          .post(
            Uri.parse('${ApiConfig.baseUrl}/rental-application'),
            headers: {
              'Content-Type': 'application/json',
            },
            body: jsonEncode({
              'business_name': _businessNameController.text,
              'business_address': _businessAddressController.text,
              'latitude': _latitude,
              'longitude': _longitude,
              'formatted_address': _businessAddressController.text,
            }),
          )
          .timeout(const Duration(seconds: 30));

      if (!mounted) return;

      Map<String, dynamic> responseData = {};
      try {
        final decoded = jsonDecode(response.body);
        if (decoded is Map<String, dynamic>) responseData = decoded;
      } catch (_) {}

      if (response.statusCode == 200) {
        _showSnackBar('Pengajuan perental berhasil dikirim!', _successColor);
        _fetchApplicationStatus();
      } else if (response.statusCode == 401) {
        throw Exception(
            'Sesi belum bisa diperbarui. Periksa koneksi lalu coba lagi.');
      } else {
        final errors = responseData['errors'];
        if (errors is Map && errors['personal_data'] != null) {
          final dynamic raw = errors['personal_data'];
          final String message = raw is List && raw.isNotEmpty
              ? raw.first.toString()
              : raw.toString();

          _showSnackBar(message, _dangerColor);

          await Future.delayed(const Duration(milliseconds: 800));

          if (mounted) {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const ProfilPage()),
            );
          }
          return;
        }

        String errorMessage =
            responseData['message'] ?? 'Gagal mengirim pengajuan';
        throw Exception(errorMessage);
      }
    } on TimeoutException {
      _showSnackBar('Server tidak merespons. Coba lagi.', _dangerColor);
    } catch (e) {
      _showSnackBar(e.toString().replaceAll('Exception: ', ''), _dangerColor);
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
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

  // ================= HELPER STATUS (tetap semantic) =================
  Color _getStatusColor() {
    switch (_status) {
      case 'approved':
        return _successColor;
      case 'rejected':
        return _dangerColor;
      default:
        return _accentColor;
    }
  }

  IconData _getStatusIcon() {
    switch (_status) {
      case 'approved':
        return Icons.check_circle_rounded;
      case 'rejected':
        return Icons.cancel_rounded;
      default:
        return Icons.hourglass_top_rounded;
    }
  }

  String _getStatusLabel() {
    switch (_status) {
      case 'approved':
        return 'Disetujui';
      case 'rejected':
        return 'Ditolak';
      default:
        return 'Menunggu Peninjauan';
    }
  }

  String _getStatusDescription() {
    switch (_status) {
      case 'approved':
        return 'Selamat! Pengajuan Anda telah disetujui sebagai perental.';
      case 'rejected':
        return 'Pengajuan Anda ditolak oleh admin. Silakan periksa catatan di bawah dan ajukan kembali.';
      default:
        return 'Pengajuan Anda sedang ditinjau oleh Admin. Mohon tunggu konfirmasi selanjutnya.';
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final statusColor = _getStatusColor();

    return Scaffold(
      // 🟢 DIHAPUS: backgroundColor: _bgColor
      appBar: AppBar(
        title: const Text(
          'Pengajuan Perental',
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
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: _primaryColor))
          : RefreshIndicator(
              color: _primaryColor,
              onRefresh: _fetchApplicationStatus,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildStatusCard(statusColor),
                      const SizedBox(height: 14),
                      _buildInfoBanner(),
                      const SizedBox(height: 20),
                      _buildSectionTitle('Data Usaha & Lokasi Peta'),
                      const SizedBox(height: 10),
                      _buildFormCard(),
                      const SizedBox(height: 24),
                      _buildSubmitButton(),
                    ],
                  ),
                ),
              ),
            ),
    );
  }

  // ================= CARD: STATUS =================
  Widget _buildStatusCard(Color statusColor) {
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  // 🟢 0.1 → 0.15, biar tetap kelihatan di dark
                  color: statusColor.withOpacity(0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(_getStatusIcon(), color: statusColor, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Status Pengajuan',
                      style: TextStyle(
                        fontSize: 11,
                        // 🟢 Ganti Colors.grey.shade500 → onSurfaceVariant
                        color: colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.3,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _getStatusLabel(),
                      style: TextStyle(
                        fontSize: 15.5,
                        fontWeight: FontWeight.bold,
                        // 🟢 Ganti Color(0xFF1E293B) → onSurface
                        color: colorScheme.onSurface,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  // 🟢 0.1 → 0.15
                  color: statusColor.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  _status.toUpperCase(),
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: statusColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            _getStatusDescription(),
            style: TextStyle(
              fontSize: 12.5,
              // 🟢 Ganti Colors.grey.shade600 → onSurfaceVariant
              color: colorScheme.onSurfaceVariant,
              height: 1.4,
            ),
          ),
          if (_adminNotes != null && _adminNotes!.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                // 🟢 0.05 → 0.12, 0.15 → 0.30 biar tetap kelihatan di dark
                color: _primaryColor.withOpacity(0.12),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: _primaryColor.withOpacity(0.30)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.chat_bubble_outline_rounded,
                          size: 13, color: _primaryColor),
                      const SizedBox(width: 6),
                      const Text(
                        'Catatan dari Admin',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: _primaryColor, // brand
                          fontSize: 11.5,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _adminNotes!,
                    style: TextStyle(
                      fontSize: 12.5,
                      // 🟢 Ganti Color(0xFF1E293B) → onSurface
                      color: colorScheme.onSurface,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ================= BANNER INFO PERSYARATAN =================
  Widget _buildInfoBanner() {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final bool isDark = theme.brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        // 🟢 0.06 → 0.12, 0.15 → 0.30
        color: _primaryColor.withOpacity(0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _primaryColor.withOpacity(0.30)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline_rounded,
              color: _primaryColor, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Pastikan Anda sudah melengkapi Foto KTP dan Foto SIM di menu Profil sebelum mengirim pengajuan ini.',
              style: TextStyle(
                fontSize: 12,
                // 🟢 Light: tetap biru gelap (nuansa biru);
                //    Dark: biru muda terang supaya kontras di atas bg gelap
                color: isDark
                    ? Colors.lightBlue.shade200
                    : Colors.blue.shade900,
                height: 1.4,
              ),
            ),
          ),
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

  // ================= CARD: FORM & PETA =================
  Widget _buildFormCard() {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        // 🟢 Ganti Colors.white → colorScheme.surface
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: colorScheme.shadow.withOpacity(0.06),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildTextField(
            controller: _businessNameController,
            label: 'Nama Usaha Rental (Opsional)',
            icon: Icons.store_outlined,
          ),
          const SizedBox(height: 16),

          // Widget Peta Flutter Map
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Tandai Lokasi Usaha di Peta *',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.bold,
                  // 🟢 Ganti Color(0xFF1E293B) → onSurface
                  color: colorScheme.onSurface,
                ),
              ),
              TextButton.icon(
                onPressed: _getCurrentLocation,
                icon: const Icon(Icons.my_location, size: 14),
                label: const Text('Lokasi Saya',
                    style: TextStyle(fontSize: 11.5)),
                style: TextButton.styleFrom(
                    foregroundColor: _primaryColor), // brand
              ),
            ],
          ),
          const SizedBox(height: 6),

          Container(
            height: 250,
            width: double.infinity,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              // 🟢 Ganti Colors.grey.shade300 → outlineVariant
              border: Border.all(color: colorScheme.outlineVariant),
            ),
            clipBehavior: Clip.hardEdge,
            child: Stack(
              children: [
                // ⚠️ PETA OSM: tile selalu terang dari server,
                // tidak bisa di-dark-mode-kan dari sini. Dibiarkan.
                FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(
                    initialCenter: LatLng(_latitude, _longitude),
                    initialZoom: 14.0,
                    onTap: (tapPosition, point) {
                      _reverseGeocode(point.latitude, point.longitude);
                    },
                  ),
                  children: [
                    TileLayer(
                      urlTemplate:
                          'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.example.rentalcar',
                    ),
                    MarkerLayer(
                      markers: [
                        Marker(
                          point: LatLng(_latitude, _longitude),
                          width: 40,
                          height: 40,
                          child: const Icon(
                            Icons.location_pin,
                            // 🟢 Merah marker — tetap (kontras di atas tile)
                            color: Colors.red,
                            size: 40,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),

                // ➕ ➖ Tombol Zoom — tetap putih + hitam karena
                // memang di atas tile OSM yang terang.
                Positioned(
                  right: 12,
                  bottom: 12,
                  child: Column(
                    children: [
                      FloatingActionButton.small(
                        heroTag: 'zoom_in',
                        backgroundColor: Colors.white,
                        foregroundColor: Colors.black87,
                        onPressed: () {
                          final currentZoom = _mapController.camera.zoom;
                          _mapController.move(_mapController.camera.center,
                              currentZoom + 1);
                        },
                        child: const Icon(Icons.add, size: 20),
                      ),
                      const SizedBox(height: 4),
                      FloatingActionButton.small(
                        heroTag: 'zoom_out',
                        backgroundColor: Colors.white,
                        foregroundColor: Colors.black87,
                        onPressed: () {
                          final currentZoom = _mapController.camera.zoom;
                          _mapController.move(_mapController.camera.center,
                              currentZoom - 1);
                        },
                        child: const Icon(Icons.remove, size: 20),
                      ),
                    ],
                  ),
                ),

                if (_isGeocoding)
                  Container(
                    // 🟢 Overlay netral — tetap (hanya redupkan peta saat loading)
                    color: Colors.black.withOpacity(0.2),
                    child: const Center(
                      child: CircularProgressIndicator(color: _primaryColor),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _hasSelectedLocation
                ? 'Koordinat: ${_latitude.toStringAsFixed(5)}, ${_longitude.toStringAsFixed(5)}'
                : 'Ketuk pada peta untuk menandai titik lokasi usaha Anda.',
            style: TextStyle(
              fontSize: 11,
              // 🟢 Ganti Colors.grey.shade600 → onSurfaceVariant
              color: colorScheme.onSurfaceVariant,
              fontStyle: FontStyle.italic,
            ),
          ),
          const SizedBox(height: 16),

          _buildTextField(
            controller: _businessAddressController,
            label: 'Alamat Usaha / Domisili (Auto-fill dari Peta)',
            icon: Icons.location_on_outlined,
            maxLines: 3,
            validator: (v) =>
                v == null || v.isEmpty ? 'Alamat usaha wajib diisi' : null,
          ),
        ],
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    int maxLines = 1,
    String? Function(String?)? validator,
  }) {
    final colorScheme = Theme.of(context).colorScheme;

    return TextFormField(
      controller: controller,
      maxLines: maxLines,
      validator: validator,
      style: TextStyle(
        fontSize: 13.5,
        // 🟢 Teks input ikut tema
        color: colorScheme.onSurface,
      ),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(
          // 🟢 Ganti Colors.grey.shade500 → onSurfaceVariant
          color: colorScheme.onSurfaceVariant,
          fontSize: 13,
        ),
        alignLabelWithHint: true,
        prefixIcon: Padding(
          padding: EdgeInsets.only(bottom: maxLines > 1 ? 40 : 0),
          child: Icon(
            icon,
            size: 19,
            // 🟢 Ganti Colors.grey.shade500 → onSurfaceVariant
            color: colorScheme.onSurfaceVariant,
          ),
        ),
        filled: true,
        // 🟢 Ganti _bgColor → surfaceContainerHighest
        fillColor: colorScheme.surfaceContainerHighest,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          // 🟢 Ganti Colors.grey.shade200 → outlineVariant
          borderSide: BorderSide(color: colorScheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          // 🟢 Brand primary — tetap
          borderSide: const BorderSide(color: _primaryColor, width: 1.4),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          // 🟢 Merah semantic — tetap
          borderSide: const BorderSide(color: _dangerColor),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      ),
    );
  }

  // ================= TOMBOL SUBMIT =================
  Widget _buildSubmitButton() {
    return SizedBox(
      width: double.infinity,
      height: 50,
      child: ElevatedButton.icon(
        onPressed: _isSubmitting ? null : _submitApplication,
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
            : const Icon(Icons.send_rounded, size: 18),
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
                'Kirim / Perbarui Pengajuan',
                style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600),
              ),
      ),
    );
  }
}