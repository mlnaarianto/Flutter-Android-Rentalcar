import 'package:flutter/material.dart';
import 'package:rentalcar/menu/notifikasi.dart';
import 'package:rentalcar/services/notification_socket_service.dart'; // 🟢 TAMBAHAN

class Navbar extends StatefulWidget implements PreferredSizeWidget {
  final String title;
  final ValueChanged<String>? onSearchChanged;

  const Navbar({
    super.key,
    required this.title,
    this.onSearchChanged,
  });

  @override
  State<Navbar> createState() => _NavbarState();

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);
}

class _NavbarState extends State<Navbar> {
  bool _isSearching = false;
  final TextEditingController _searchController = TextEditingController();

  // 🟢 TAMBAHAN: pakai service singleton, bukan fetch/koneksi sendiri.
  // Navbar cuma "dengarkan" status dari sini — koneksi WebSocket-nya
  // sendiri sudah hidup sejak login, dikelola terpusat di satu tempat.
  final NotificationSocketService _socketService = NotificationSocketService();

  // ================= WARNA SENADA DENGAN HALAMAN LAIN (PUTIH) =================
  static const Color _fgColor = Color(0xFF1E293B);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      automaticallyImplyLeading: false,
      backgroundColor: Colors.white,
      foregroundColor: _fgColor,
      elevation: 0,
      surfaceTintColor: Colors.white,
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(1),
        child: Container(height: 1, color: Colors.grey.shade200),
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
              style: const TextStyle(color: _fgColor),
              decoration: InputDecoration(
                hintText: 'Cari sesuatu...',
                hintStyle: TextStyle(color: Colors.grey.shade500),
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
        if (!_isSearching)
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
              // 🟢 TAMBAHAN: dengarkan status real-time dari service,
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
                        color: Colors.red,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 1.5),
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