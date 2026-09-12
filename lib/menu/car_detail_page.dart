import 'dart:async';
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
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

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

  VideoPlayerController? _videoController;
  ChewieController? _chewieController;
  bool _isVideoLoading = false;
  String? _videoError;

  String? _youtubeId;
  bool _isYoutubeVideo = false;

  final MapController _businessMapController = MapController();

  static const Color _primaryColor = Color(0xFF2563EB);
  static const Color _accentColor = Color(0xFFF97316);
  static const Color _bgColor = Color(0xFFF4F6F9);

  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
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

        final String? videoUrl = carData['video_url'];
        if (videoUrl != null && videoUrl.isNotEmpty) {
          final youtubeId = _extractYoutubeId(videoUrl);
          if (youtubeId != null) {
            _isYoutubeVideo = true;
            _youtubeId = youtubeId;
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

  String _resolveVideoUrl(String url) {
    final driveMatch = RegExp(
      r'drive\.google\.com/file/d/([^/]+)',
    ).firstMatch(url);
    if (driveMatch != null) {
      final fileId = driveMatch.group(1);
      return 'https://drive.google.com/uc?export=download&id=$fileId';
    }
    return url;
  }

  @override
  void dispose() {
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
    _chewieController?.dispose();
    _videoController?.dispose();
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

  void _openImageViewer({
    required String networkUrl,
    required String heroTag,
    required String title,
  }) {
    Navigator.push(
      context,
      PageRouteBuilder(
        opaque: false,
        barrierColor: Colors.black,
        transitionDuration: const Duration(milliseconds: 220),
        pageBuilder: (context, animation, secondaryAnimation) {
          return FadeTransition(
            opacity: animation,
            child: _ZoomableImageViewer(
              networkUrl: networkUrl,
              heroTag: heroTag,
              title: title,
            ),
          );
        },
      ),
    );
  }

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
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade600,
                          ),
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

  /// ================= PHONE / WHATSAPP TILE =================
  Widget _buildPhoneTile(String phone) {
    final bool hasPhone = phone.isNotEmpty && phone != '-';
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
            child: Icon(Icons.phone_outlined, size: 16, color: _primaryColor),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Nomor HP',
                  style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600),
                ),
                const SizedBox(height: 1),
                Text(
                  phone.isEmpty ? '-' : phone,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF1E293B),
                  ),
                ),
              ],
            ),
          ),
          if (hasPhone) ...[
            _phoneActionButton(
              icon: Icons.call_rounded,
              color: const Color(0xFF16A34A),
              tooltip: 'Telepon',
              onPressed: () => _launchPhoneCall(phone),
            ),
            const SizedBox(width: 8),
            _phoneActionButton(
              icon: FontAwesomeIcons
                  .whatsapp, // 👈 diganti dari Icons.chat_rounded
              color: const Color(0xFF25D366),
              tooltip: 'WhatsApp',
              onPressed: () => _launchWhatsApp(phone),
            ),
          ],
        ],
      ),
    );
  }

  Widget _phoneActionButton({
    required dynamic icon,
    required Color color,
    required String tooltip,
    required VoidCallback onPressed,
  }) {
    final Widget iconWidget = icon is FaIconData
        ? FaIcon(icon, size: 18, color: color)
        : Icon(icon as IconData, size: 18, color: color);

    return Tooltip(
      message: tooltip,
      child: Material(
        color: color.withOpacity(0.1),
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onPressed,
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: iconWidget,
          ),
        ),
      ),
    );
  }

  String _sanitizePhoneDigits(String phone) {
    return phone.replaceAll(RegExp(r'[^0-9+]'), '');
  }

  /// Konversi nomor ke format internasional untuk wa.me (tanpa '+', tanpa '0' di depan)
  /// Mendukung multi-negara: kalau nomor sudah punya '+' atau kode negara, dipakai apa adanya.
  /// Kalau nomor masih format lokal (diawali '0'), baru pakai [defaultCountryCode] sebagai fallback.
  String _toWhatsAppFormat(String phone, {String defaultCountryCode = '62'}) {
    String digits = _sanitizePhoneDigits(phone);

    // Kasus 1: nomor sudah eksplisit pakai '+' -> kode negara sudah pasti benar, tinggal buang '+'
    if (digits.startsWith('+')) {
      return digits.substring(1);
    }

    // Kasus 2: nomor format lokal (diawali '0') -> ga ada info negara, pakai default sebagai fallback
    if (digits.startsWith('0')) {
      return '$defaultCountryCode${digits.substring(1)}';
    }

    // Kasus 3: nomor sudah diawali kode negara tanpa '+' dan tanpa '0' (mis. 60123456789, 6281234567890)
    // -> dibiarkan apa adanya, tidak dipaksa jadi '62'
    return digits;
  }

  Future<void> _launchPhoneCall(String phone) async {
    final uri = Uri.parse('tel:${_sanitizePhoneDigits(phone)}');
    try {
      final launched = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
      if (!launched && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Tidak dapat membuka aplikasi telepon.'),
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Tidak dapat membuka aplikasi telepon.'),
          ),
        );
      }
    }
  }

  Future<void> _launchWhatsApp(String phone) async {
    final waNumber = _toWhatsAppFormat(phone);
    final carName = _car?['name'] ?? 'mobil ini';
    final message = Uri.encodeComponent(
      'Halo, saya tertarik untuk menyewa $carName.',
    );
    final waUri = Uri.parse('https://wa.me/$waNumber?text=$message');
    try {
      final launched = await launchUrl(
        waUri,
        mode: LaunchMode.externalApplication,
      );
      if (!launched && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('WhatsApp tidak terpasang di perangkat ini.'),
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Tidak dapat membuka WhatsApp.')),
        );
      }
    }
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
    final ownerPhone = personalData != null
        ? (personalData['phone'] ?? '-')
        : '-';
    final ownerAddress = personalData != null
        ? (personalData['address'] ?? '-')
        : '-';

    final rentalApplication = ownerData != null
        ? ownerData['rental_application']
        : null;
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

    return Scaffold(
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
  }

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
              child: const Icon(
                Icons.error_outline_rounded,
                size: 40,
                color: Colors.red,
              ),
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
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 12,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.directions_car_outlined,
            size: 48,
            color: Colors.grey.shade400,
          ),
          const SizedBox(height: 12),
          const Text('Data mobil tidak ditemukan.'),
        ],
      ),
    );
  }

  Widget _buildHeaderImage() {
    final hasImage =
        _car!['image'] != null && _car!['image'].toString().isNotEmpty;
    final String imageUrl = hasImage ? _getImageUrl(_car!['image']) : '';
    const String heroTag = 'car-detail-photo';

    return SizedBox(
      height: 300,
      width: double.infinity,
      child: Stack(
        fit: StackFit.expand,
        children: [
          GestureDetector(
            onTap: hasImage
                ? () => _openImageViewer(
                    networkUrl: imageUrl,
                    heroTag: heroTag,
                    title: _car!['name'] ?? 'Foto Mobil',
                  )
                : null,
            child: Hero(
              tag: heroTag,
              child: hasImage
                  ? Image.network(
                      imageUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) =>
                          _buildPlaceholderImage(),
                    )
                  : _buildPlaceholderImage(),
            ),
          ),
          IgnorePointer(
            child: Container(
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
          ),
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
                  child: Icon(
                    Icons.arrow_back_rounded,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
              ),
            ),
          ),
          if (hasImage)
            Positioned(
              top: MediaQuery.of(context).padding.top + 8,
              right: 16,
              child: Material(
                color: Colors.black.withOpacity(0.35),
                shape: const CircleBorder(),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: () => _openImageViewer(
                    networkUrl: imageUrl,
                    heroTag: heroTag,
                    title: _car!['name'] ?? 'Foto Mobil',
                  ),
                  child: const Padding(
                    padding: EdgeInsets.all(9),
                    child: Icon(
                      Icons.zoom_in_rounded,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                ),
              ),
            ),
          Positioned(
            left: 20,
            right: 20,
            bottom: 20,
            child: IgnorePointer(
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
          ),
        ],
      ),
    );
  }

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
                      style: TextStyle(
                        fontSize: 11.5,
                        color: Colors.grey.shade600,
                      ),
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
                      style: TextStyle(
                        fontSize: 11.5,
                        color: Colors.grey.shade600,
                      ),
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
              border: Border.all(
                color: _getStatusColor(status).withOpacity(0.3),
              ),
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
    bool hasLocation,
  ) {
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
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 40),
          sliver: SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _sectionCard(
                  title: 'Pemilik / Perental',
                  subtitle: 'Kontak yang bertanggung jawab atas kendaraan ini',
                  icon: Icons.person_pin_circle_rounded,
                  iconColor: _primaryColor,
                  children: [
                    _infoTile(
                      Icons.person_outline,
                      'Nama Pengelola',
                      ownerName,
                    ),
                    if (ownerEmail.isNotEmpty)
                      _infoTile(Icons.email_outlined, 'Email', ownerEmail),
                    _buildPhoneTile(ownerPhone),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 0),
                      child: _infoTile(
                        Icons.location_on_outlined,
                        'Alamat',
                        ownerAddress,
                      ),
                    ),
                  ],
                ),

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
                        _specChip(
                          Icons.confirmation_number_outlined,
                          'Plat Nomor',
                          '${_car!['plate_number'] ?? '-'}',
                        ),
                        _specChip(
                          Icons.settings_outlined,
                          'Tipe Mesin',
                          '${_car!['engine_type'] ?? '-'}',
                        ),
                        if (_car!['fuel_spec'] != null &&
                            _car!['fuel_spec'].toString().isNotEmpty)
                          _specChip(
                            Icons.local_gas_station_outlined,
                            'Spesifikasi BBM',
                            '${_car!['fuel_spec']}',
                          ),
                        _specChip(
                          Icons.airline_seat_recline_normal_outlined,
                          'Kapasitas Kursi',
                          '${_car!['seats'] ?? '-'} Kursi',
                        ),
                        _specChip(
                          Icons.calendar_today_outlined,
                          'Tahun Pembuatan',
                          '${_car!['year'] ?? '-'}',
                        ),
                      ],
                    ),
                  ],
                ),

                if (_isYoutubeVideo ||
                    _isVideoLoading ||
                    _videoError != null ||
                    _chewieController != null)
                  _sectionCard(
                    title: 'Video Review Kendaraan',
                    subtitle:
                        'Lihat lebih dekat kondisi kendaraan sebelum menyewa',
                    icon: Icons.play_circle_outline_rounded,
                    iconColor: _primaryColor,
                    children: [_buildVideoSection()],
                  ),

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

  Widget _buildBusinessLocationSection(
    String businessAddress,
    double? lat,
    double? lng,
    bool hasLocation,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (hasLocation)
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: SizedBox(
              height: 200,
              width: double.infinity,
              child: Stack(
                children: [
                  FlutterMap(
                    mapController: _businessMapController,
                    options: MapOptions(
                      initialCenter: LatLng(lat!, lng!),
                      initialZoom: 15.0,
                      minZoom: 4.0,
                      maxZoom: 18.0,
                      interactionOptions: const InteractionOptions(
                        flags:
                            InteractiveFlag.pinchZoom |
                            InteractiveFlag.drag |
                            InteractiveFlag.doubleTapZoom,
                      ),
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
                  Positioned(
                    top: 8,
                    left: 8,
                    child: Row(
                      children: [
                        _mapActionButton(
                          icon: Icons.open_in_new_rounded,
                          label: 'Google Maps',
                          backgroundColor: Colors.white,
                          foregroundColor: Colors.black87,
                          onPressed: () => _openInGoogleMaps(lat, lng),
                        ),
                        const SizedBox(width: 8),
                        _mapActionButton(
                          icon: Icons.alt_route_rounded,
                          label: 'Rute',
                          backgroundColor: _primaryColor,
                          foregroundColor: Colors.white,
                          onPressed: () => _openDirections(lat, lng),
                        ),
                      ],
                    ),
                  ),
                  Positioned(
                    right: 8,
                    bottom: 8,
                    child: Column(
                      children: [
                        _mapZoomButton(
                          icon: Icons.add,
                          heroTag: 'business_zoom_in',
                          onPressed: () {
                            final z = _businessMapController.camera.zoom;
                            _businessMapController.move(
                              _businessMapController.camera.center,
                              z + 1,
                            );
                          },
                        ),
                        const SizedBox(height: 6),
                        _mapZoomButton(
                          icon: Icons.remove,
                          heroTag: 'business_zoom_out',
                          onPressed: () {
                            final z = _businessMapController.camera.zoom;
                            _businessMapController.move(
                              _businessMapController.camera.center,
                              z - 1,
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        if (businessAddress.isNotEmpty) ...[
          const SizedBox(height: 12),
          _infoTile(
            Icons.location_on_outlined,
            'Alamat Usaha',
            businessAddress,
          ),
        ],
      ],
    );
  }

  Widget _mapActionButton({
    required IconData icon,
    required String label,
    required Color backgroundColor,
    required Color foregroundColor,
    required VoidCallback onPressed,
  }) {
    return Material(
      color: backgroundColor,
      borderRadius: BorderRadius.circular(10),
      elevation: 2,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onPressed,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: foregroundColor),
              const SizedBox(width: 5),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: foregroundColor,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _mapZoomButton({
    required IconData icon,
    required String heroTag,
    required VoidCallback onPressed,
  }) {
    return Material(
      color: Colors.white,
      shape: const CircleBorder(),
      elevation: 2,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onPressed,
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Icon(icon, size: 18, color: Colors.black87),
        ),
      ),
    );
  }

  Future<void> _openInGoogleMaps(double lat, double lng) async {
    final label = Uri.encodeComponent(_car?['name'] ?? 'Lokasi Usaha');
    final geoUri = Uri.parse('geo:$lat,$lng?q=$lat,$lng($label)');
    final webUri = Uri.parse(
      'https://www.google.com/maps/search/?api=1&query=$lat,$lng',
    );

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

  Future<void> _openDirections(double lat, double lng) async {
    final navUri = Uri.parse('google.navigation:q=$lat,$lng&mode=d');
    final webUri = Uri.parse(
      'https://www.google.com/maps/dir/?api=1&destination=$lat,$lng',
    );

    try {
      final launched = await launchUrl(
        navUri,
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

  /// ================= VIDEO SECTION =================
  Widget _buildVideoSection() {
    if (_isYoutubeVideo && _youtubeId != null) {
      final thumbnailUrl =
          'https://img.youtube.com/vi/$_youtubeId/hqdefault.jpg';

      return ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: AspectRatio(
          aspectRatio: 16 / 9,
          child: Material(
            color: Colors.black,
            child: InkWell(
              onTap: () {
                // MODAL BOTTOM SHEET DENGAN DESAIN MODERN & ANIMASI HALUS
                showModalBottomSheet(
                  context: context,
                  isScrollControlled: true,
                  backgroundColor: Colors.transparent,
                  barrierColor: Colors.black87,
                  builder: (context) => Padding(
                    padding: EdgeInsets.only(
                      bottom: MediaQuery.of(context).viewInsets.bottom,
                    ),
                    child: Container(
                      decoration: const BoxDecoration(
                        color: Colors.black,
                        borderRadius: BorderRadius.vertical(
                          top: Radius.circular(24),
                        ),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const SizedBox(height: 12),
                          Container(
                            width: 40,
                            height: 4,
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.3),
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 8,
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text(
                                  'Review Kendaraan',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                IconButton(
                                  style: IconButton.styleFrom(
                                    backgroundColor: Colors.white.withOpacity(
                                      0.1,
                                    ),
                                    padding: const EdgeInsets.all(8),
                                  ),
                                  icon: const Icon(
                                    Icons.close,
                                    color: Colors.white,
                                    size: 20,
                                  ),
                                  onPressed: () => Navigator.pop(context),
                                ),
                              ],
                            ),
                          ),
                          const Divider(color: Colors.white12, height: 1),
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            child: YoutubePopupPlayer(youtubeId: _youtubeId!),
                          ),
                          SizedBox(
                            height: MediaQuery.of(context).padding.bottom + 16,
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Image.network(
                    thumbnailUrl,
                    fit: BoxFit.cover,
                    errorBuilder: (ctx, err, trace) =>
                        Container(color: Colors.black),
                  ),
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          Colors.black.withOpacity(0.6),
                        ],
                      ),
                    ),
                  ),
                  Center(
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: _primaryColor.withOpacity(0.9),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.3),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.play_arrow_rounded,
                        size: 36,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  Positioned(
                    bottom: 12,
                    left: 12,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.6),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.play_circle_fill,
                            size: 14,
                            color: Colors.red,
                          ),
                          SizedBox(width: 4),
                          Text(
                            'Tonton Video',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
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
                Text(
                  'Memuat video...',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
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
                  const Icon(
                    Icons.error_outline_rounded,
                    color: Colors.red,
                    size: 26,
                  ),
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
          aspectRatio:
              _chewieController!.videoPlayerController.value.aspectRatio,
          child: Chewie(controller: _chewieController!),
        ),
      );
    }

    return const SizedBox.shrink();
  }

  /// ================= BOTTOM BAR =================
  Widget _buildBottomBar(String status) {
    final bool available = status == 'tersedia';
    return Material(
      elevation: 24,
      color: Colors.white,
      shadowColor: Colors.black.withOpacity(0.5),
      child: Container(
        padding: EdgeInsets.fromLTRB(
          16,
          12,
          16,
          12 + MediaQuery.of(context).padding.bottom,
        ),
        child: SizedBox(
          width: double.infinity,
          height: 52,
          child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: available ? _primaryColor : Colors.grey.shade400,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
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
            icon: Icon(
              available
                  ? Icons.directions_car_filled_rounded
                  : Icons.block_rounded,
              size: 20,
            ),
            label: Text(
              available ? 'Sewa Mobil Ini' : 'Mobil Sedang Tidak Tersedia',
              style: const TextStyle(
                fontSize: 15.5,
                fontWeight: FontWeight.w600,
              ),
            ),
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
      child: const Icon(
        Icons.directions_car_rounded,
        size: 64,
        color: Colors.white,
      ),
    );
  }
}

/// ================= FULLSCREEN ZOOMABLE IMAGE VIEWER =================
class _ZoomableImageViewer extends StatefulWidget {
  final String networkUrl;
  final String heroTag;
  final String title;

  const _ZoomableImageViewer({
    required this.networkUrl,
    required this.heroTag,
    required this.title,
  });

  @override
  State<_ZoomableImageViewer> createState() => _ZoomableImageViewerState();
}

class _ZoomableImageViewerState extends State<_ZoomableImageViewer>
    with SingleTickerProviderStateMixin {
  final TransformationController _controller = TransformationController();
  TapDownDetails? _doubleTapDetails;
  late final AnimationController _animController;
  Animation<Matrix4>? _animation;

  @override
  void initState() {
    super.initState();
    _animController =
        AnimationController(
          vsync: this,
          duration: const Duration(milliseconds: 220),
        )..addListener(() {
          if (_animation != null) {
            _controller.value = _animation!.value;
          }
        });
  }

  @override
  void dispose() {
    _animController.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _handleDoubleTap() {
    Matrix4 endMatrix;
    final position = _doubleTapDetails?.localPosition ?? Offset.zero;

    if (_controller.value != Matrix4.identity()) {
      endMatrix = Matrix4.identity();
    } else {
      endMatrix = Matrix4.identity()
        ..translate(-position.dx * 1.8, -position.dy * 1.8)
        ..scale(2.8);
    }

    _animation = Matrix4Tween(
      begin: _controller.value,
      end: endMatrix,
    ).animate(CurveTween(curve: Curves.easeOut).animate(_animController));
    _animController.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Text(
          widget.title,
          style: const TextStyle(color: Colors.white, fontSize: 16),
        ),
      ),
      body: GestureDetector(
        onDoubleTapDown: (details) => _doubleTapDetails = details,
        onDoubleTap: _handleDoubleTap,
        child: Center(
          child: Hero(
            tag: widget.heroTag,
            child: InteractiveViewer(
              transformationController: _controller,
              minScale: 1,
              maxScale: 5,
              child: Image.network(
                widget.networkUrl,
                fit: BoxFit.contain,
                width: double.infinity,
                errorBuilder: (context, error, stackTrace) => const Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    "Gagal memuat gambar",
                    style: TextStyle(color: Colors.white70),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// ================= YOUTUBE POPUP BOTTOM SHEET PLAYER =================
class YoutubePopupPlayer extends StatefulWidget {
  final String youtubeId;

  const YoutubePopupPlayer({super.key, required this.youtubeId});

  @override
  State<YoutubePopupPlayer> createState() => _YoutubePopupPlayerState();
}

class _YoutubePopupPlayerState extends State<YoutubePopupPlayer> {
  late YoutubePlayerController _controller;
  bool _isDisposed = false;

  // 🔧 Guard untuk mencegah feedback loop fullscreen <-> orientasi
  bool? _lastFullScreenState;
  bool _isHandlingFullScreenChange = false;

  // 🔽 TAMBAHAN: melacak posisi tonton real-time, sama seperti
  //    "currentTime" + setInterval di versi React (web)
  double _currentSeconds = 0;
  Timer? _timeTrackerTimer;

  @override
  void initState() {
    super.initState();
    _initController();
    _startTimeTracker();
  }

  // 🔽 TAMBAHAN: polling posisi video tiap 1 detik selagi popup terbuka.
  //    Analog dengan useEffect + setInterval(..., 1000) di CarDetail.tsx
  void _startTimeTracker() {
    _timeTrackerTimer = Timer.periodic(const Duration(seconds: 1), (_) async {
      if (_isDisposed) return;
      try {
        final time = await _controller.currentTime;
        if (!_isDisposed && mounted) {
          setState(() {
            _currentSeconds = time;
          });
        }
      } catch (_) {
        // player belum siap / lagi transisi fullscreen, abaikan saja
      }
    });
  }

  // 🔽 TAMBAHAN: format detik -> "M:SS", sama persis dengan logic di React:
  //    `${Math.floor(seconds / 60)}:${(Math.floor(seconds % 60)).padStart(2,'0')}`
  String _formatTimestamp(double seconds) {
    final secondsInt = seconds.floor();
    final minutes = secondsInt ~/ 60;
    final secs = (secondsInt % 60).toString().padLeft(2, '0');
    return '$minutes:$secs';
  }

  void _initController() {
    // Selalu buat instance controller baru yang bersih setiap kali widget dipasang/dibuka
    _controller = YoutubePlayerController.fromVideoId(
      videoId: widget.youtubeId,
      autoPlay: true,
      params: const YoutubePlayerParams(
        showFullscreenButton: true,
        showControls: true,
        strictRelatedVideos: true,
        enableJavaScript: true,
      ),
    );

    _controller.setFullScreenListener((isFullScreen) async {
      if (_isDisposed) return;

      // 1) Abaikan event duplikat/gema dengan value yang sama persis
      if (_lastFullScreenState == isFullScreen) return;

      // 2) Cegah proses tumpang tindih saat transisi sebelumnya masih berjalan
      if (_isHandlingFullScreenChange) return;

      _isHandlingFullScreenChange = true;
      _lastFullScreenState = isFullScreen;

      try {
        if (isFullScreen) {
          await SystemChrome.setEnabledSystemUIMode(
            SystemUiMode.immersiveSticky,
          );
          await Future.delayed(const Duration(milliseconds: 50));
          if (_isDisposed) return;
          await SystemChrome.setPreferredOrientations([
            DeviceOrientation.landscapeLeft,
            DeviceOrientation.landscapeRight,
          ]);
        } else {
          await SystemChrome.setPreferredOrientations([
            DeviceOrientation.portraitUp,
            DeviceOrientation.portraitDown,
          ]);
          await Future.delayed(const Duration(milliseconds: 50));
          if (_isDisposed) return;
          await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
        }
      } finally {
        // 3) Beri jeda sebelum listener "siap" lagi, supaya gema resize
        //    dari WebView tidak langsung memicu ulang perubahan orientasi
        await Future.delayed(const Duration(milliseconds: 400));
        if (!_isDisposed) {
          _isHandlingFullScreenChange = false;
        }
      }
    });
  }

  Future<void> _openInYouTubeApp() async {
    try {
      // 1) Ambil posisi tonton dulu, SEBELUM player di-pause/di-reset
      double currentSeconds = 0;
      try {
        currentSeconds = await _controller.currentTime;
      } catch (_) {
        currentSeconds = 0;
      }
      final int secondsInt = currentSeconds.floor();

      // 2) Pause video supaya WebView tidak terus render/decode di background
      try {
        await _controller.pauseVideo();
      } catch (_) {}

      // 3) Reset orientasi & system UI ke kondisi normal SEBELUM pindah app
      //    (kalau masih immersive/landscape, YouTube app bisa render blank sesaat)
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
      ]);

      // 4) PERBAIKAN: Diperpanjang menjadi 300ms agar OS Android benar-benar
      //    selesai menerapkan perubahan UI/orientasi sebelum app lain dibuka
      await Future.delayed(const Duration(milliseconds: 300));

      if (_isDisposed || !mounted) return;

      final String urlString = secondsInt > 1
          ? 'https://www.youtube.com/watch?v=${widget.youtubeId}&t=${secondsInt}s'
          : 'https://www.youtube.com/watch?v=${widget.youtubeId}';

      final youtubeUrl = Uri.parse(urlString);

      final launched = await launchUrl(
        youtubeUrl,
        mode: LaunchMode.externalApplication,
      );

      if (!launched && mounted) {
        _showErrorSnackBar('Tidak dapat membuka aplikasi YouTube.');
      }
    } catch (e) {
      if (mounted) {
        _showErrorSnackBar('Terjadi kesalahan saat membuka YouTube.');
      }
    }
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  void dispose() {
    _isDisposed = true;
    _timeTrackerTimer
        ?.cancel(); // 🔽 TAMBAHAN: hentikan polling supaya tidak leak

    // Kembalikan orientasi layar ke portrait terlebih dahulu
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

    // PERBAIKAN: Gunakan Future.microtask untuk menutup controller secara aman
    // agar WebView tidak terpotong mendadak saat animasi tutup bottom sheet berjalan
    Future.microtask(() {
      try {
        _controller.close();
      } catch (_) {}
    });

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        YoutubePlayerScaffold(
          controller: _controller,
          aspectRatio: 16 / 9,
          builder: (context, player) {
            return Center(child: player);
          },
        ),
        const SizedBox(height: 12),
        TextButton.icon(
          onPressed: _openInYouTubeApp,
          icon: const Icon(
            Icons.open_in_new_rounded,
            size: 16,
            color: Colors.redAccent,
          ),
          // 🔽 UBAH: label sekarang dinamis, menampilkan menit:detik terakhir
          //    ditonton — sama seperti tombol "Tonton di YouTube (Lanjutkan di M:SS)"
          //    di versi React.
          label: Text(
            _currentSeconds > 1
                ? 'Tonton di Aplikasi YouTube (Lanjutkan di ${_formatTimestamp(_currentSeconds)})'
                : 'Tonton langsung di Aplikasi YouTube',
            style: const TextStyle(color: Colors.white70, fontSize: 13),
          ),
        ),
      ],
    );
  }
}
