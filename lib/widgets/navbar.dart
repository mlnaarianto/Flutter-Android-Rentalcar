import 'package:flutter/material.dart';
import 'package:rentalcar/menu/notifikasi.dart';
import 'package:rentalcar/services/notification_socket_service.dart'; // 🟢 TAMBAHAN

class Navbar extends StatefulWidget implements PreferredSizeWidget {
  final String title;
  final ValueChanged<String>? onSearchChanged;
  final bool showNotification; // 🟢 TAMBAHAN: kontrol tampil/tidaknya icon notif

  const Navbar({
    super.key,
    required this.title,
    this.onSearchChanged,
    this.showNotification = false, // 🟢 default: tidak tampil
  });

  @override
  State<Navbar> createState() => _NavbarState();

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);
}

class _NavbarState extends State<Navbar> {
  bool _isSearching = false;
  final TextEditingController _searchController = TextEditingController();

  // 🟢 pakai service singleton, bukan fetch/koneksi sendiri.
  // Navbar cuma "dengarkan" status dari sini — koneksi WebSocket-nya
  // sendiri sudah hidup sejak login, dikelola terpusat di satu tempat.
  final NotificationSocketService _socketService = NotificationSocketService();

  // 🟢 DIHAPUS: _fgColor — sekarang pakai colorScheme.onSurface
  // supaya otomatis gelap di light mode, terang di dark mode.

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return AppBar(
      automaticallyImplyLeading: false,
      // 🟢 Adaptif: light → surface putih, dark → surface gelap
      backgroundColor: colorScheme.surface,
      foregroundColor: colorScheme.onSurface,
      elevation: 0,
      surfaceTintColor: colorScheme.surface,
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(1),
        // 🟢 Garis bawah halus, otomatis menyesuaikan mode
        child: Container(height: 1, color: colorScheme.outlineVariant),
      ),
      leading: _isSearching
          ? IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () {
                setState(() {
                  _isSearching = false;
                  _searchController.clear();
                  if (widget.onSearchChanged != null) {
                    widget.onSearchChanged!('');
                  }
                });
              },
            )
          : IconButton(
              icon: const Icon(Icons.menu),
              onPressed: () {
                Scaffold.of(context).openDrawer();
              },
            ),
      title: _isSearching
          ? TextField(
              controller: _searchController,
              autofocus: true,
              // 🟢 Teks ketikan ikut tema
              style: TextStyle(color: colorScheme.onSurface),
              decoration: InputDecoration(
                hintText: 'Cari sesuatu...',
                // 🟢 Hint lebih redup, tetap terbaca di kedua mode
                hintStyle: TextStyle(color: colorScheme.onSurfaceVariant),
                border: InputBorder.none,
              ),
              onChanged: widget.onSearchChanged,
            )
          : Text(
              widget.title,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
            ),
      centerTitle: true,
      actions: [
        if (widget.onSearchChanged != null)
          IconButton(
            icon: Icon(_isSearching ? Icons.close : Icons.search),
            onPressed: () {
              setState(() {
                _isSearching = !_isSearching;
                if (!_isSearching) {
                  _searchController.clear();
                  widget.onSearchChanged!('');
                }
              });
            },
          ),
        // 🟢 TAMBAHAN: hanya tampil kalau tidak sedang searching
        // DAN showNotification bernilai true (misalnya hanya di Dashboard)
        if (!_isSearching && widget.showNotification)
          Stack(
            alignment: Alignment.center,
            children: [
              IconButton(
                icon: const Icon(Icons.notifications),
                onPressed: () async {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const NotifikasiPage(),
                    ),
                  );
                  // Tidak perlu manual refetch lagi di sini — begitu
                  // NotifikasiPage dibuka, dia otomatis markAsSeen()
                  // lewat service, dan badge ikut update via listener.
                },
              ),
              // 🟢 dengarkan status real-time dari service,
              // bukan state lokal lagi. ValueListenableBuilder otomatis
              // rebuild widget ini SETIAP KALI hasUnread berubah —
              // termasuk saat event WebSocket masuk kapan saja, di
              // halaman manapun user sedang berada.
              ValueListenableBuilder<bool>(
                valueListenable: _socketService.hasUnread,
                builder: (context, hasUnread, _) {
                  if (!hasUnread) return const SizedBox.shrink();
                  return Positioned(
                    right: 11,
                    top: 11,
                    child: Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        // 🟢 error = merah di light, merah terang di dark
                        color: colorScheme.error,
                        shape: BoxShape.circle,
                        // 🟢 border pakai surface (sama dgn bg AppBar),
                        // supaya "menyatu" di kedua mode
                        border: Border.all(
                          color: colorScheme.surface,
                          width: 1.5,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
      ],
    );
  }
}