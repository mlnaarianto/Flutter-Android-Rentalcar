import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:rentalcar/config/api_config.dart';
import 'package:rentalcar/services/api_client.dart';
import 'package:rentalcar/menu/rentals_booking_page.dart';
import 'package:rentalcar/menu/chat.dart';
import 'package:rentalcar/menu/driver_bookings_page.dart';
import 'package:rentalcar/enums/app_enums.dart';
import 'package:rentalcar/utils/theme_controller.dart'; // 🟢 TAMBAHAN

class Sidebar extends StatefulWidget {
  final String userName;
  final String userEmail;
  final List<dynamic> userRoles;

  const Sidebar({
    super.key,
    required this.userName,
    required this.userEmail,
    required this.userRoles,
  });

  @override
  State<Sidebar> createState() => _SidebarState();
}

class _SidebarState extends State<Sidebar> {
  String? _avatarUrl;
  String? _userId;

  // 🟢 FIX: sebelumnya receiver_id CS di _openAdminChat() hardcode ke '1'.
  // Sekarang diambil dari GET /api/support-agent (query berdasarkan
  // Permission::ReceiveSupportChat di backend, bukan ID tetap). Null
  // selama belum selesai fetch / fetch gagal -> _openAdminChat() akan
  // fallback ke '1' supaya menu tetap bisa dipakai walau endpoint ini
  // belum siap atau permission belum di-assign ke siapa pun.
  String? _supportAgentId;

  // Tag unik untuk animasi Hero avatar sidebar -> fullscreen viewer
  static const String _avatarHeroTag = 'sidebar-user-avatar';

  // ================= BRAND COLORS (tetap di light & dark) =================
  static const Color _primaryColor = Color(0xFF2563EB);
  static const Color _accentColor = Color(0xFFF97316);
  // 🟢 DIHAPUS: _bgColor — Drawer sekarang pakai colorScheme.surface

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;

    setState(() {
      _avatarUrl = prefs.getString('avatar_url');
      // SENGAJA tidak diberi fallback hardcode (mis. '3') di sini. Kalau
      // user_id belum tersimpan di SharedPreferences (mis. race condition
      // sesaat setelah login), _userId akan tetap null dan setiap aksi yang
      // butuh identitas user (mis. buka Chat Admin) akan di-guard secara
      // eksplisit -- bukan diam-diam "menyamar" jadi user ID lain.
      _userId = prefs.getString('user_id');
    });

    await _loadSupportAgentId();
  }

  /// ================= AMBIL ID ADMIN/CS SECARA DINAMIS =================
  /// Panggil GET /api/support-agent sekali saat Sidebar dibuka.
  ///
  /// Kalau gagal (network error, 404 karena permission belum di-assign ke
  /// siapa pun, dsb), _supportAgentId dibiarkan null dan _openAdminChat()
  /// akan pakai fallback '1'.
  Future<void> _loadSupportAgentId() async {
    try {
      final response = await ApiClient.instance.get(
        Uri.parse(ApiConfig.supportAgent),
      );

      if (response.statusCode != 200) return;

      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final id = body['data']?['id'];

      if (id != null && mounted) {
        setState(() {
          _supportAgentId = id.toString();
        });
      }
    } catch (_) {
      // Diamkan -- fallback ID lama tetap dipakai lewat _openAdminChat().
    }
  }

  /// ================= FIX FOTO GOOGLE BURAM/PIXELATED =================
  String? _hiResAvatarUrl(String? url, {int size = 720}) {
    if (url == null || url.isEmpty) return url;
    final sizePattern = RegExp(r'=s\d+-c(-[a-z0-9]+)?$');
    if (sizePattern.hasMatch(url)) {
      return url.replaceAll(sizePattern, '=s$size-c');
    }
    return url;
  }

  /// ================= BUKA FOTO PROFIL SECARA FULLSCREEN =================
  void _openAvatarViewer() {
    if (_avatarUrl == null || _avatarUrl!.isEmpty) return;

    final hiResUrl = _hiResAvatarUrl(_avatarUrl, size: 720) ?? _avatarUrl!;

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
              networkUrl: hiResUrl,
              heroTag: _avatarHeroTag,
              title: widget.userName,
            ),
          );
        },
      ),
    );
  }

  /// ================= BUKA HALAMAN CHAT ADMIN =================
  Future<void> _openAdminChat(BuildContext context) async {
    if (_userId == null || _userId!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Data pengguna belum siap, coba lagi sesaat lagi.'),
        ),
      );
      return;
    }

    Navigator.pop(context);
    if (!context.mounted) return;

    final String uniqueChatId =
        'room_user_${widget.userEmail.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_')}';

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ChatPage(
          chatId: uniqueChatId,
          currentUserId: _userId!,
          currentUserName: widget.userName,
          receiverId: _supportAgentId ?? '1',
          receiverName: "Admin Rental (CS)",
        ),
      ),
    );
  }

  /// ================= HELPER UI: JUDUL SECTION =================
  Widget _sectionLabel(String text) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
      child: Text(
        text,
        style: TextStyle(
          color: colorScheme.onSurfaceVariant,
          fontSize: 11.5,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.6,
        ),
      ),
    );
  }

  /// ================= HELPER UI: ITEM MENU =================
  Widget _menuItem({
    required IconData icon,
    required Color iconColor,
    required String title,
    String? subtitle,
    required VoidCallback onTap,
  }) {
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(9),
                  decoration: BoxDecoration(
                    color: iconColor.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Icon(icon, color: iconColor, size: 19),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          color: colorScheme.onSurface,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (subtitle != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 1),
                          child: Text(
                            subtitle,
                            style: TextStyle(
                              color: colorScheme.onSurfaceVariant,
                              fontSize: 11.5,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  size: 18,
                  color: colorScheme.outline,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    final List<String> rolesList =
        widget.userRoles.map((role) => role.toString()).toList();

    final bool hasAvatar = _avatarUrl != null && _avatarUrl!.isNotEmpty;

    return Drawer(
      backgroundColor: colorScheme.surface,
      child: SafeArea(
        child: Column(
          children: [
            // ================= HEADER PROFIL =================
            // ⚠️ ZONA BIRU: semua warna di dalamnya SENGAJA tidak diubah.
            // Latar gradient selalu biru, teks putih, border ring putih —
            // kontras sama di light maupun dark.
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(20, 22, 20, 22),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [_primaryColor, Color(0xFF3B82F6)],
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  GestureDetector(
                    onTap: hasAvatar ? _openAvatarViewer : null,
                    child: Stack(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(3),
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white, // ring putih di atas gradient biru
                          ),
                          child: Hero(
                            tag: _avatarHeroTag,
                            child: CircleAvatar(
                              radius: 26,
                              backgroundColor: Colors.white.withOpacity(0.15),
                              backgroundImage: hasAvatar
                                  ? NetworkImage(_avatarUrl!) as ImageProvider
                                  : const AssetImage("assets/anya.jpg"),
                            ),
                          ),
                        ),
                        if (hasAvatar)
                          Positioned(
                            right: 0,
                            bottom: 0,
                            child: Container(
                              padding: const EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                color: _primaryColor,
                                shape: BoxShape.circle,
                                border: Border.all(
                                    color: Colors.white, width: 1.5),
                              ),
                              child: const Icon(
                                Icons.zoom_in_rounded,
                                size: 11,
                                color: Colors.white,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.userName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15.5,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          widget.userEmail,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: rolesList.isNotEmpty
                              ? rolesList
                                  .map(
                                    (role) => Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 3,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.white.withOpacity(0.18),
                                        borderRadius:
                                            BorderRadius.circular(20),
                                        border: Border.all(
                                          color: Colors.white.withOpacity(0.3),
                                        ),
                                      ),
                                      child: Text(
                                        role,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  )
                                  .toList()
                              : [
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 3,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withOpacity(0.18),
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: const Text(
                                      'No Role',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // ================= LIST MENU =================
            Expanded(
              child: ListView(
                padding: const EdgeInsets.only(bottom: 12),
                children: [
                  _sectionLabel('BANTUAN'),
                  _menuItem(
                    icon: Icons.support_agent_rounded,
                    iconColor: _primaryColor,
                    title: 'Chat Admin',
                    subtitle: 'Hubungi customer service',
                    onTap: () => _openAdminChat(context),
                  ),

                  // MENU KHUSUS DRIVER
                  if (rolesList.contains(AppRole.driver.value)) ...[
                    _sectionLabel('MENU DRIVER'),
                    _menuItem(
                      icon: Icons.directions_car_filled_rounded,
                      iconColor: const Color(0xFF7C3AED), // ungu brand
                      title: 'Tugas Penugasan',
                      subtitle: 'Lihat jadwal & tugas antar-jemput',
                      onTap: () {
                        Navigator.pop(context);
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const DriverBookingsPage(),
                          ),
                        );
                      },
                    ),
                  ],

                  // MENU MANAJEMEN RENTAL (Perental / Super Admin)
                  if (rolesList.contains(AppRole.perental.value) ||
                      rolesList.contains(AppRole.superAdmin.value)) ...[
                    _sectionLabel('MANAJEMEN RENTAL'),
                    _menuItem(
                      icon: Icons.assignment_turned_in_rounded,
                      iconColor: _primaryColor,
                      title: 'Kelola Pesanan & Driver',
                      subtitle: 'Atur booking dan penugasan driver',
                      onTap: () {
                        Navigator.pop(context);
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const RentalsBookingPage(),
                          ),
                        );
                      },
                    ),
                  ],

                  // ================= TAMPILAN =================
                  // 🟢 TAMBAHAN: section toggle tema
                  const Divider(height: 24),
                  _sectionLabel('TAMPILAN'),
                  ValueListenableBuilder<ThemeMode>(
                    valueListenable: ThemeController.notifier,
                    builder: (context, mode, _) {
                      // 🟢 Kalau mode masih "system", baca brightness OS
                      // supaya status switch mencerminkan kondisi nyata
                      // (bukan selalu tampil "off" padahal HP sedang dark).
                      final isDark = mode == ThemeMode.dark ||
                          (mode == ThemeMode.system &&
                              MediaQuery.platformBrightnessOf(context) ==
                                  Brightness.dark);

                      return SwitchListTile(
                        title: Text(
                          'Mode Gelap',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: colorScheme.onSurface,
                          ),
                        ),
                        subtitle: Text(
                          isDark ? 'Aktif' : 'Nonaktif',
                          style: TextStyle(
                            fontSize: 11.5,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                        secondary: Icon(
                          isDark
                              ? Icons.dark_mode_rounded
                              : Icons.light_mode_rounded,
                          color: isDark
                              ? _primaryColor
                              : colorScheme.onSurfaceVariant,
                        ),
                        value: isDark,
                        contentPadding:
                            const EdgeInsets.symmetric(horizontal: 20),
                        onChanged: (value) {
                          // 🟢 Set eksplisit ke light/dark.
                          // Setelah ini, mode tidak lagi "system" —
                          // user sudah override manual, pilihannya
                          // disimpan permanen oleh ThemeController.
                          ThemeController.set(
                            value ? ThemeMode.dark : ThemeMode.light,
                          );
                        },
                      );
                    },
                  ),

                  // 🟢 OPSIONAL: tombol balik ke "Ikuti Sistem".
                  // Hanya muncul kalau user sudah pernah override manual,
                  // jadi user baru tidak bingung.
                  ValueListenableBuilder<ThemeMode>(
                    valueListenable: ThemeController.notifier,
                    builder: (context, mode, _) {
                      if (mode != ThemeMode.system) {
                        return Padding(
                          padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                          child: TextButton.icon(
                            onPressed: () =>
                                ThemeController.set(ThemeMode.system),
                            icon: const Icon(Icons.brightness_auto, size: 16),
                            label: const Text(
                              'Ikuti Pengaturan Sistem',
                              style: TextStyle(fontSize: 12),
                            ),
                          ),
                        );
                      }
                      return const SizedBox.shrink();
                    },
                  ),
                ],
              ),
            ),

            // ================= FOOTER =================
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(color: colorScheme.outlineVariant),
                ),
              ),
              child: Center(
                child: Text(
                  'RentalCar App',
                  style: TextStyle(
                    fontSize: 11,
                    color: colorScheme.outline,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// ⚠️ FULLSCREEN ZOOMABLE IMAGE VIEWER — SENGAJA tidak diubah.
/// Latar hitam & teks putih adalah standar UX photo-viewer
/// di kedua mode terang maupun gelap.
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
    _animController = AnimationController(
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

    _animation = Matrix4Tween(begin: _controller.value, end: endMatrix)
        .animate(CurveTween(curve: Curves.easeOut).animate(_animController));
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
        title: Text(widget.title,
            style: const TextStyle(color: Colors.white, fontSize: 16)),
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