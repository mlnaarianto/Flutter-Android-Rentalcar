import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:rentalcar/config/api_config.dart';
import 'package:rentalcar/services/api_client.dart';
import 'package:rentalcar/menu/rentals_booking_page.dart';
import 'package:rentalcar/menu/chat.dart';
import 'package:rentalcar/menu/driver_bookings_page.dart';
import 'package:rentalcar/enums/app_enums.dart';

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

  // ================= WARNA SENADA DENGAN HALAMAN LAIN =================
  static const Color _primaryColor = Color(0xFF2563EB);
  static const Color _accentColor = Color(0xFFF97316);
  static const Color _bgColor = Color(0xFFF4F6F9);

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

    // Dipisah dari setState di atas karena butuh 'await' network call --
    // tidak masalah dipanggil setelah _userId di-set, keduanya independen.
    await _loadSupportAgentId();
  }

  /// ================= AMBIL ID ADMIN/CS SECARA DINAMIS =================
  /// Panggil GET /api/support-agent sekali saat Sidebar dibuka. Endpoint
  /// ini di backend query user berdasarkan Permission::ReceiveSupportChat,
  /// jadi kalau admin CS dipindah/diganti lewat Filament, aplikasi ini
  /// otomatis ikut tanpa perlu update kode atau rilis ulang.
  ///
  /// Token dipasang dan di-refresh otomatis oleh ApiClient, jadi tidak
  /// perlu membaca token dari prefs lagi di sini.
  ///
  /// Kalau gagal (network error, 404 karena permission belum di-assign ke
  /// siapa pun, dsb), _supportAgentId dibiarkan null dan _openAdminChat()
  /// akan pakai fallback '1' -- supaya menu Chat Admin tidak ikut rusak
  /// hanya karena endpoint ini belum siap.
  Future<void> _loadSupportAgentId() async {
    try {
      final response = await ApiClient.instance.get(
        Uri.parse(ApiConfig.supportAgent), // 🟢 DIUBAH: sebelumnya '${ApiConfig.baseUrl}/support-agent'
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
  /// Kalau foto profil berasal dari Google Sign-In, URL-nya biasanya sudah
  /// dibatasi ukurannya kecil (mis. diakhiri "=s96-c" -> cuma 96x96px).
  /// Di avatar kecil di header sidebar ini tidak kelihatan, tapi begitu
  /// di-stretch ke viewer fullscreen jadi buram/pecah. Solusinya: ganti
  /// angka ukuran di URL-nya jadi lebih besar sebelum dipakai untuk viewer
  /// full-screen. Sama persis dengan yang dipakai di ProfilPage & ChatPage.
  String? _hiResAvatarUrl(String? url, {int size = 720}) {
    if (url == null || url.isEmpty) return url;
    final sizePattern = RegExp(r'=s\d+-c(-[a-z0-9]+)?$');
    if (sizePattern.hasMatch(url)) {
      return url.replaceAll(sizePattern, '=s$size-c');
    }
    // Kalau backend sudah menyimpan ulang foto ini sendiri (bukan link
    // langsung dari Google), parameter ukuran ini tidak akan ada, berarti
    // sumber resolusi rendahnya ada di sisi server, bukan di aplikasi ini.
    return url;
  }

  /// ================= BUKA FOTO PROFIL SECARA FULLSCREEN =================
  /// Ketuk avatar di header sidebar -> layar hitam + foto besar dengan
  /// pinch-to-zoom & double-tap zoom. Hanya aktif kalau ada foto asli dari
  /// server (bukan foto default assets/anya.jpg), karena tidak ada gunanya
  /// nge-zoom gambar placeholder.
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
  /// Dipisah dari onTap langsung supaya bisa di-guard: kalau _userId belum
  /// sempat ke-load dari SharedPreferences, jangan kirim user ke ChatPage
  /// dengan identitas kosong/salah -- beri tahu user untuk coba lagi.
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
          // 🟢 FIX: sebelumnya hardcode '1'. Sekarang pakai _supportAgentId
          // hasil fetch dari /api/support-agent, dengan fallback ke '1'
          // kalau fetch belum selesai / gagal -- lihat _loadSupportAgentId().
          receiverId: _supportAgentId ?? '1',
          receiverName: "Admin Rental (CS)",
        ),
      ),
    );
  }

  /// ================= HELPER UI: JUDUL SECTION =================
  Widget _sectionLabel(String text) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
      child: Text(
        text,
        style: TextStyle(
          color: Colors.grey.shade500,
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
                    color: iconColor.withOpacity(0.1),
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
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF1E293B),
                        ),
                      ),
                      if (subtitle != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 1),
                          child: Text(
                            subtitle,
                            style: TextStyle(
                              fontSize: 11.5,
                              color: Colors.grey.shade500,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_rounded,
                    size: 18, color: Colors.grey.shade400),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final List<String> rolesList =
        widget.userRoles.map((role) => role.toString()).toList();

    final bool hasAvatar = _avatarUrl != null && _avatarUrl!.isNotEmpty;

    return Drawer(
      backgroundColor: _bgColor,
      child: SafeArea(
        child: Column(
          children: [
            // ================= HEADER PROFIL =================
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
                            color: Colors.white,
                          ),
                          child: Hero(
                            tag: _avatarHeroTag,
                            child: CircleAvatar(
                              radius: 26,
                              backgroundColor: Colors.blue.withOpacity(0.08),
                              backgroundImage: hasAvatar
                                  ? NetworkImage(_avatarUrl!) as ImageProvider
                                  : const AssetImage("assets/anya.jpg"),
                            ),
                          ),
                        ),
                        // Indikator kecil "bisa di-zoom", hanya muncul kalau
                        // ada foto asli (bukan foto default).
                        if (hasAvatar)
                          Positioned(
                            right: 0,
                            bottom: 0,
                            child: Container(
                              padding: const EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                color: _primaryColor,
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.white, width: 1.5),
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
                                          color:
                                              Colors.white.withOpacity(0.3),
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
                      iconColor: const Color(0xFF7C3AED),
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

                  // Menu "ADMINISTRATOR" (Manajemen User) sudah dihapus --
                  // sebelumnya cuma memanggil Navigator.pop(context) tanpa
                  // tujuan nyata (belum ada halamannya).
                ],
              ),
            ),

            // ================= FOOTER =================
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(color: Colors.grey.shade200),
                ),
              ),
              child: Center(
                child: Text(
                  'RentalCar App',
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey.shade400,
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

/// ================= FULLSCREEN ZOOMABLE IMAGE VIEWER =================
/// Pola yang sama dengan _ZoomableImageViewer di ProfilPage / CarDetailPage /
/// ChatPage: pinch-to-zoom, drag, dan double-tap untuk zoom in/out. Khusus
/// untuk gambar dari network (foto profil user selalu berasal dari server).
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
        title: Text(widget.title, style: const TextStyle(color: Colors.white, fontSize: 16)),
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