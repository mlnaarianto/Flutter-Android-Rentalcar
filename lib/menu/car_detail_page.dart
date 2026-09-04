import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_player/video_player.dart';
import 'package:chewie/chewie.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:rentalcar/config/api_config.dart';
import 'package:rentalcar/menu/booking_form_page.dart';

class CarDetailPage extends StatefulWidget {
  final int carId;

  const CarDetailPage({super.key, required this.carId});

  @override
  State<CarDetailPage> createState() => _CarDetailPageState();
}

class _CarDetailPageState extends State<CarDetailPage> {
  Map<String, dynamic>? _car;
  bool _isLoading = true;
  String? _errorMessage;

  // Controller video generik (untuk file mp4 / link langsung)
  VideoPlayerController? _videoController;
  ChewieController? _chewieController;
  bool _isVideoLoading = false;
  String? _videoError;

  // Controller khusus kalau video_url ternyata link YouTube
  YoutubePlayerController? _youtubeController;
  bool _isYoutubeVideo = false;

  // Widget player yang dihasilkan oleh YoutubePlayerScaffold.builder.
  // Ini yang dipakai di dalam card video (bukan YoutubePlayer langsung),
  // supaya tombol fullscreen bisa benar-benar rotate & menutupi layar penuh
  // sama seperti Chewie.
  Widget? _youtubePlayerWidget;

  static const Color _primaryColor = Color(0xFF2563EB);
  static const Color _accentColor = Color(0xFFF97316);
  static const Color _bgColor = Color(0xFFF4F6F9);

  @override
  void initState() {
    super.initState();
    // Izinkan rotasi ke landscape khusus di halaman ini, supaya tombol
    // fullscreen pada video (Chewie maupun YouTube) bisa benar-benar
    // memutar device. Halaman lain di app tetap portrait-only karena
    // ini di-reset lagi di dispose().
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    _fetchCarDetail();
  }

  Future<void> _fetchCarDetail() async {
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
        Uri.parse('${ApiConfig.baseUrl}/cars/${widget.carId}'),
        headers: {
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final carData = data['data'];

        // Ambil video_url dan tentukan jenis player yang dipakai
        final String? videoUrl = carData['video_url'];
        if (videoUrl != null && videoUrl.isNotEmpty) {
          final youtubeId = _extractYoutubeId(videoUrl);
          if (youtubeId != null) {
            _isYoutubeVideo = true;
            _youtubeController = YoutubePlayerController.fromVideoId(
              videoId: youtubeId,
              autoPlay: false,
              params: const YoutubePlayerParams(showFullscreenButton: true),
            );

            // FIX ROTASI: paksa secara eksplisit ke landscape saat masuk
            // fullscreen, dan balik ke portrait saat keluar. Ini perlu
            // dipasang manual karena berbeda dari Chewie, YoutubePlayerScaffold
            // di beberapa kondisi tidak otomatis memaksa rotasi device.
            _youtubeController!.setFullScreenListener((isFullScreen) {
              if (isFullScreen) {
                SystemChrome.setPreferredOrientations([
                  DeviceOrientation.landscapeLeft,
                  DeviceOrientation.landscapeRight,
                ]);
                SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
              } else {
                SystemChrome.setPreferredOrientations([
                  DeviceOrientation.portraitUp,
                  DeviceOrientation.portraitDown,
                ]);
                SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
              }
            });
          } else {
            _isYoutubeVideo = false;
            _initVideoPlayer(videoUrl);
          }
        }

        setState(() {
          _car = carData;
          _isLoading = false;
        });
      } else {
        setState(() {
          _errorMessage =
              'Gagal memuat detail mobil (Kode: ${response.statusCode})';
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

  Future<void> _initVideoPlayer(String rawUrl) async {
    setState(() {
      _isVideoLoading = true;
      _videoError = null;
    });

    try {
      final url = _resolveVideoUrl(rawUrl);

      final controller = VideoPlayerController.networkUrl(Uri.parse(url));
      await controller.initialize();

      final chewie = ChewieController(
        videoPlayerController: controller,
        autoPlay: false,
        looping: false,
        aspectRatio: controller.value.aspectRatio == 0
            ? 16 / 9
            : controller.value.aspectRatio,
        materialProgressColors: ChewieProgressColors(
          playedColor: _primaryColor,
          handleColor: _primaryColor,
          bufferedColor: _primaryColor.withOpacity(0.15),
          backgroundColor: Colors.grey.shade300,
        ),
      );

      setState(() {
        _videoController = controller;
        _chewieController = chewie;
        _isVideoLoading = false;
      });
    } catch (e) {
      setState(() {
        _videoError = 'Video tidak dapat dimuat: $e';
        _isVideoLoading = false;
      });
    }
  }

  /// Mendeteksi apakah url adalah link YouTube dan mengambil video ID-nya.
  /// Mendukung format: youtube.com/watch?v=ID, youtu.be/ID, youtube.com/shorts/ID
  /// Return null kalau bukan link YouTube (berarti diperlakukan sebagai file video biasa).
  String? _extractYoutubeId(String url) {
    final patterns = [
      RegExp(r'youtu\.be/([a-zA-Z0-9_-]{11})'),
      RegExp(r'youtube\.com/watch\?v=([a-zA-Z0-9_-]{11})'),
      RegExp(r'youtube\.com/shorts/([a-zA-Z0-9_-]{11})'),
      RegExp(r'youtube\.com/embed/([a-zA-Z0-9_-]{11})'),
    ];
    for (final pattern in patterns) {
      final match = pattern.firstMatch(url);
      if (match != null) return match.group(1);
    }
    return null;
  }

  /// Mengubah beberapa format link umum (mis. Google Drive share link)
  /// menjadi direct-link yang bisa di-stream video_player.
  /// Kalau link sudah berupa direct video URL (.mp4, dll), dikembalikan apa adanya.
  String _resolveVideoUrl(String url) {
    final driveMatch =
        RegExp(r'drive\.google\.com/file/d/([^/]+)').firstMatch(url);
    if (driveMatch != null) {
      final fileId = driveMatch.group(1);
      return 'https://drive.google.com/uc?export=download&id=$fileId';
    }
    return url;
  }

  @override
  void dispose() {
    // Kunci lagi ke portrait-only saat meninggalkan halaman ini,
    // supaya halaman lain di app tidak ikut bisa landscape.
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
    _chewieController?.dispose();
    _videoController?.dispose();
    _youtubeController?.close();
    super.dispose();
  }

  String _getImageUrl(String? imagePath) {
    if (imagePath == null || imagePath.isEmpty) return '';
    if (imagePath.startsWith('http://') || imagePath.startsWith('https://')) {
      return imagePath;
    }
    final serverRoot = ApiConfig.baseUrl.replaceAll('/api', '');
    if (imagePath.startsWith('/')) {
      return '$serverRoot$imagePath';
    } else {
      return '$serverRoot/storage/$imagePath';
    }
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'tersedia':
        return const Color(0xFF16A34A);
      case 'disewa':
        return _accentColor;
      case 'perbaikan':
        return const Color(0xFFDC2626);
      default:
        return Colors.grey;
    }
  }

  /// Format angka harga jadi "Rp 1.200.000" (buang desimal ".00", kasih titik ribuan)
  /// supaya nggak wrap/kepotong di kartu harga yang sempit.
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

  String _getStatusLabel(String status) {
    switch (status) {
      case 'tersedia':
        return 'Tersedia';
      case 'disewa':
        return 'Disewa';
      case 'perbaikan':
        return 'Perbaikan';
      default:
        return status.isEmpty ? '-' : status;
    }
  }

  /// ================= HELPER UI: SECTION CARD (selaras dgn ProfilPage) =================
  Widget _sectionCard({
    required String title,
    required IconData icon,
    required Color iconColor,
    String? subtitle,
    required List<Widget> children,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: iconColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: iconColor, size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 15.5,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF1E293B),
                      ),
                    ),
                    if (subtitle != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          subtitle,
                          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ...children,
        ],
      ),
    );
  }

  Widget _infoTile(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: _primaryColor.withOpacity(0.08),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(icon, size: 16, color: _primaryColor),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600),
                ),
                const SizedBox(height: 1),
                Text(
                  value.isEmpty ? '-' : value,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF1E293B),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _specChip(IconData icon, String label, String value) {
    return Container(
      width: (MediaQuery.of(context).size.width - 32 - 18 * 2 - 10) / 2,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _bgColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: _accentColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 18, color: _accentColor),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(fontSize: 10.5, color: Colors.grey.shade600),
                ),
                const SizedBox(height: 1),
                Text(
                  value.isEmpty ? '-' : value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1E293B),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ownerData = _car?['user'] ?? _car?['owner'];
    final ownerName = ownerData != null
        ? (ownerData['name'] ?? 'Tidak diketahui')
        : 'Administrator / Perental';
    final ownerEmail = ownerData != null ? (ownerData['email'] ?? '-') : '';

    final personalData = ownerData != null ? ownerData['personal_data'] : null;
    final ownerPhone = personalData != null ? (personalData['phone'] ?? '-') : '-';
    final ownerAddress =
        personalData != null ? (personalData['address'] ?? '-') : '-';

    // ============ DATA LOKASI USAHA (dari relasi user.rental_application) ============
    final rentalApplication =
        ownerData != null ? ownerData['rental_application'] : null;
    final businessName = rentalApplication != null
        ? (rentalApplication['business_name']?.toString() ?? '')
        : '';
    final businessAddress = rentalApplication != null
        ? (rentalApplication['formatted_address']?.toString() ??
            rentalApplication['business_address']?.toString() ??
            '')
        : '';
    final double? businessLat =
        rentalApplication != null && rentalApplication['latitude'] != null
            ? double.tryParse(rentalApplication['latitude'].toString())
            : null;
    final double? businessLng =
        rentalApplication != null && rentalApplication['longitude'] != null
            ? double.tryParse(rentalApplication['longitude'].toString())
            : null;
    final bool hasLocation = businessLat != null && businessLng != null;

    final status = _car?['status'] ?? '';
    final driverPrice = _car?['driver_price_per_day'] ?? 0;

    // Body utama halaman (Scaffold biasa, isinya sama seperti sebelumnya).
    final scaffoldBody = Scaffold(
      backgroundColor: _bgColor,
      extendBodyBehindAppBar: true,
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null
              ? _buildErrorState()
              : _car == null
                  ? _buildEmptyState()
                  : _buildContent(
                      status,
                      driverPrice,
                      ownerName,
                      ownerEmail,
                      ownerPhone,
                      ownerAddress,
                      businessName,
                      businessAddress,
                      businessLat,
                      businessLng,
                      hasLocation,
                    ),
      bottomNavigationBar: _isLoading || _car == null || _errorMessage != null
          ? null
          : _buildBottomBar(status),
    );

    // Kalau video-nya YouTube, bungkus dengan YoutubePlayerScaffold.
    // Widget ini WAJIB jadi root/widget paling atas supaya tombol fullscreen
    // bisa rotate ke landscape & menutupi seluruh layar (persis seperti Chewie).
    if (_isYoutubeVideo && _youtubeController != null) {
      return YoutubePlayerScaffold(
        controller: _youtubeController!,
        aspectRatio: 16 / 9,
        builder: (context, player) {
          // Simpan player yang "sadar fullscreen" ini, dipakai di _buildVideoSection().
          _youtubePlayerWidget = player;
          return scaffoldBody;
        },
      );
    }

    return scaffoldBody;
  }

  /// ================= STATE: ERROR =================
  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.08),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.error_outline_rounded, size: 40, color: Colors.red),
            ),
            const SizedBox(height: 16),
            Text(
              _errorMessage!,
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade700, fontSize: 14),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: _fetchCarDetail,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Coba Lagi'),
              style: ElevatedButton.styleFrom(
                backgroundColor: _primaryColor,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// ================= STATE: EMPTY =================
  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.directions_car_outlined, size: 48, color: Colors.grey.shade400),
          const SizedBox(height: 12),
          const Text('Data mobil tidak ditemukan.'),
        ],
      ),
    );
  }

  /// ================= HEADER (GAMBAR + APPBAR MELAYANG) =================
  Widget _buildHeaderImage() {
    final hasImage = _car!['image'] != null && _car!['image'].toString().isNotEmpty;
    return SizedBox(
      height: 300,
      width: double.infinity,
      child: Stack(
        fit: StackFit.expand,
        children: [
          hasImage
              ? Image.network(
                  _getImageUrl(_car!['image']),
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) => _buildPlaceholderImage(),
                )
              : _buildPlaceholderImage(),
          // Gradient supaya tombol back & chip status tetap terbaca
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withOpacity(0.45),
                  Colors.transparent,
                  Colors.black.withOpacity(0.55),
                ],
                stops: const [0.0, 0.45, 1.0],
              ),
            ),
          ),
          // Tombol back melayang
          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            left: 16,
            child: Material(
              color: Colors.black.withOpacity(0.35),
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: () => Navigator.pop(context),
                child: const Padding(
                  padding: EdgeInsets.all(9),
                  child: Icon(Icons.arrow_back_rounded, color: Colors.white, size: 20),
                ),
              ),
            ),
          ),
          // Nama & brand mobil di atas gambar
          Positioned(
            left: 20,
            right: 20,
            bottom: 20,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  (_car!['brand'] ?? '').toString().toUpperCase(),
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.1,
                    color: Colors.white.withOpacity(0.85),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _car!['name'] ?? 'Tanpa Nama',
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// ================= KARTU HARGA (MENGAMBANG DI BAWAH HEADER) =================
  Widget _buildPriceCard(String status, dynamic driverPrice) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Harga Sewa / Hari',
                      style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600),
                    ),
                    const SizedBox(height: 3),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        _formatPrice(_car!['price_per_day']),
                        maxLines: 1,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: _primaryColor,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 14),
                width: 1,
                height: 34,
                color: Colors.grey.shade200,
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Jasa Driver / Hari',
                      style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600),
                    ),
                    const SizedBox(height: 3),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        _formatPrice(driverPrice),
                        maxLines: 1,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: _accentColor,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: _getStatusColor(status).withOpacity(0.1),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: _getStatusColor(status).withOpacity(0.3)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: _getStatusColor(status),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 5),
                Text(
                  _getStatusLabel(status),
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: _getStatusColor(status),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// ================= KONTEN UTAMA =================
  Widget _buildContent(
      String status,
      dynamic driverPrice,
      String ownerName,
      String ownerEmail,
      String ownerPhone,
      String ownerAddress,
      String businessName,
      String businessAddress,
      double? businessLat,
      double? businessLng,
      bool hasLocation) {
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(child: _buildHeaderImage()),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
            child: _buildPriceCard(status, driverPrice),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          sliver: SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ============ PEMILIK / PERENTAL ============
                _sectionCard(
                  title: 'Pemilik / Perental',
                  subtitle: 'Kontak yang bertanggung jawab atas kendaraan ini',
                  icon: Icons.person_pin_circle_rounded,
                  iconColor: _primaryColor,
                  children: [
                    _infoTile(Icons.person_outline, 'Nama Pengelola', ownerName),
                    if (ownerEmail.isNotEmpty)
                      _infoTile(Icons.email_outlined, 'Email', ownerEmail),
                    _infoTile(Icons.phone_outlined, 'Nomor HP', ownerPhone),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 0),
                      child: _infoTile(Icons.location_on_outlined, 'Alamat', ownerAddress),
                    ),
                  ],
                ),

                // ============ LOKASI USAHA (MAP) ============
                if (hasLocation || businessName.isNotEmpty)
                  _sectionCard(
                    title: 'Lokasi Usaha',
                    subtitle: businessName.isNotEmpty
                        ? businessName
                        : 'Titik lokasi rental di peta',
                    icon: Icons.storefront_rounded,
                    iconColor: _accentColor,
                    children: [
                      _buildBusinessLocationSection(
                        businessAddress,
                        businessLat,
                        businessLng,
                        hasLocation,
                      ),
                    ],
                  ),

                // ============ SPESIFIKASI ============
                _sectionCard(
                  title: 'Spesifikasi Kendaraan',
                  subtitle: 'Detail teknis kendaraan yang akan disewa',
                  icon: Icons.build_circle_outlined,
                  iconColor: _accentColor,
                  children: [
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        _specChip(Icons.confirmation_number_outlined, 'Plat Nomor',
                            '${_car!['plate_number'] ?? '-'}'),
                        _specChip(Icons.settings_outlined, 'Tipe Mesin',
                            '${_car!['engine_type'] ?? '-'}'),
                        if (_car!['fuel_spec'] != null &&
                            _car!['fuel_spec'].toString().isNotEmpty)
                          _specChip(Icons.local_gas_station_outlined,
                              'Spesifikasi BBM', '${_car!['fuel_spec']}'),
                        _specChip(Icons.airline_seat_recline_normal_outlined,
                            'Kapasitas Kursi', '${_car!['seats'] ?? '-'} Kursi'),
                        _specChip(Icons.calendar_today_outlined,
                            'Tahun Pembuatan', '${_car!['year'] ?? '-'}'),
                      ],
                    ),
                  ],
                ),

                // ============ VIDEO ============
                if (_isYoutubeVideo || _isVideoLoading || _videoError != null || _chewieController != null)
                  _sectionCard(
                    title: 'Video Review Kendaraan',
                    subtitle: 'Lihat lebih dekat kondisi kendaraan sebelum menyewa',
                    icon: Icons.play_circle_outline_rounded,
                    iconColor: _primaryColor,
                    children: [_buildVideoSection()],
                  ),

                // ============ DESKRIPSI ============
                _sectionCard(
                  title: 'Deskripsi',
                  icon: Icons.description_outlined,
                  iconColor: _accentColor,
                  children: [
                    Text(
                      _car!['description'] ?? 'Tidak ada deskripsi tambahan.',
                      style: TextStyle(
                        color: Colors.grey.shade700,
                        height: 1.5,
                        fontSize: 13.5,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// ================= LOKASI USAHA (MAP PREVIEW + TOMBOL) =================
  /// Map ditampilkan non-interaktif (IgnorePointer + InteractiveFlag.none)
  /// supaya tidak konflik gesture scroll dengan CustomScrollView halaman ini.
  /// Untuk navigasi/detail, user diarahkan ke Google Maps lewat tombol.
  Widget _buildBusinessLocationSection(
      String businessAddress, double? lat, double? lng, bool hasLocation) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (hasLocation)
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: SizedBox(
              height: 180,
              width: double.infinity,
              child: IgnorePointer(
                child: FlutterMap(
                  options: MapOptions(
                    initialCenter: LatLng(lat!, lng!),
                    initialZoom: 15.0,
                    interactionOptions: const InteractionOptions(
                      flags: InteractiveFlag.none,
                    ),
                  ),
                  children: [
                    TileLayer(
                      urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.example.rentalcar',
                    ),
                    MarkerLayer(
                      markers: [
                        Marker(
                          point: LatLng(lat, lng),
                          width: 40,
                          height: 40,
                          child: const Icon(
                            Icons.location_pin,
                            color: Colors.red,
                            size: 40,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        if (businessAddress.isNotEmpty) ...[
          const SizedBox(height: 12),
          _infoTile(Icons.location_on_outlined, 'Alamat Usaha', businessAddress),
        ],
        if (hasLocation) ...[
          const SizedBox(height: 4),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => _openInGoogleMaps(lat!, lng!),
              icon: const Icon(Icons.map_outlined, size: 18),
              label: const Text('Buka di Google Maps'),
              style: OutlinedButton.styleFrom(
                foregroundColor: _primaryColor,
                side: BorderSide(color: _primaryColor.withOpacity(0.4)),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
        ],
      ],
    );
  }

  /// Buka lokasi di aplikasi Google Maps (kalau ada) dengan pin tepat di
  /// titik lokasi usaha, mirip perilaku app driver/ojek online.
  /// Pakai skema geo: dulu (native Android, langsung buka app Maps),
  /// fallback ke URL web Google Maps kalau geo: gagal/tidak didukung.
  Future<void> _openInGoogleMaps(double lat, double lng) async {
    final label = Uri.encodeComponent(_car?['name'] ?? 'Lokasi Usaha');

    final geoUri = Uri.parse('geo:$lat,$lng?q=$lat,$lng($label)');
    final webUri = Uri.parse(
        'https://www.google.com/maps/search/?api=1&query=$lat,$lng');

    try {
      final launched = await launchUrl(
        geoUri,
        mode: LaunchMode.externalApplication,
      );
      if (!launched) {
        await launchUrl(webUri, mode: LaunchMode.externalApplication);
      }
    } catch (_) {
      try {
        await launchUrl(webUri, mode: LaunchMode.externalApplication);
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Tidak dapat membuka aplikasi Maps.')),
          );
        }
      }
    }
  }

  /// ================= VIDEO SECTION (isi dari card, sudah dibungkus rounded) =================
  Widget _buildVideoSection() {
    if (_isYoutubeVideo && _youtubeController != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: AspectRatio(
          aspectRatio: 16 / 9,
          // Pakai player dari YoutubePlayerScaffold.builder (sudah "sadar" fullscreen).
          // Fallback ke YoutubePlayer biasa kalau widget-nya belum sempat ke-build.
          child: _youtubePlayerWidget ??
              YoutubePlayer(controller: _youtubeController!),
        ),
      );
    }

    if (_isVideoLoading) {
      return AspectRatio(
        aspectRatio: 16 / 9,
        child: Container(
          decoration: BoxDecoration(
            color: _bgColor,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(
                  width: 26,
                  height: 26,
                  child: CircularProgressIndicator(strokeWidth: 2.6),
                ),
                const SizedBox(height: 10),
                Text('Memuat video...', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
              ],
            ),
          ),
        ),
      );
    }

    if (_videoError != null) {
      return AspectRatio(
        aspectRatio: 16 / 9,
        child: Container(
          decoration: BoxDecoration(
            color: Colors.red.withOpacity(0.05),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.red.withOpacity(0.15)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.error_outline_rounded, color: Colors.red, size: 26),
                  const SizedBox(height: 8),
                  Text(
                    _videoError!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.red, fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    if (_chewieController != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: AspectRatio(
          aspectRatio: _chewieController!.videoPlayerController.value.aspectRatio,
          child: Chewie(controller: _chewieController!),
        ),
      );
    }

    return const SizedBox.shrink();
  }

  /// ================= BOTTOM BAR (STICKY) =================
  Widget _buildBottomBar(String status) {
    final bool available = status == 'tersedia';
    return Container(
      padding: EdgeInsets.fromLTRB(16, 12, 16, 12 + MediaQuery.of(context).padding.bottom),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 16,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SizedBox(
        width: double.infinity,
        height: 52,
        child: ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            backgroundColor: available ? _primaryColor : Colors.grey.shade400,
            foregroundColor: Colors.white,
            elevation: 0,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
          onPressed: available
              ? () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => BookingFormPage(car: _car!),
                    ),
                  );
                }
              : null,
          icon: Icon(available ? Icons.directions_car_filled_rounded : Icons.block_rounded, size: 20),
          label: Text(
            available ? 'Sewa Mobil Ini' : 'Mobil Sedang Tidak Tersedia',
            style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w600),
          ),
        ),
      ),
    );
  }

  Widget _buildPlaceholderImage() {
    return Container(
      width: double.infinity,
      height: 300,
      color: Colors.grey.shade300,
      child: const Icon(Icons.directions_car_rounded, size: 64, color: Colors.white),
    );
  }
}