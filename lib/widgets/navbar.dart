import 'package:flutter/material.dart';
import 'package:rentalcar/menu/notifikasi.dart';

class Navbar extends StatefulWidget implements PreferredSizeWidget {
  final String title;
  final ValueChanged<String>? onSearchChanged; // Callback untuk menangkap teks pencarian

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

  @override
  Widget build(BuildContext context) {
    return AppBar(
      automaticallyImplyLeading: false,
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
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                hintText: 'Cari sesuatu...',
                hintStyle: TextStyle(color: Colors.white70),
                border: InputBorder.none,
              ),
              onChanged: widget.onSearchChanged,
            )
          : Text(widget.title),
      centerTitle: true,
      backgroundColor: Colors.blue,
      actions: [
        // Tombol Toggle Search
        IconButton(
          icon: Icon(_isSearching ? Icons.close : Icons.search),
          onPressed: () {
            setState(() {
              _isSearching = !_isSearching;
              if (!_isSearching) {
                _searchController.clear();
                if (widget.onSearchChanged != null) {
                  widget.onSearchChanged!('');
                }
              }
            });
          },
        ),
        // Tombol Notifikasi (hanya muncul saat tidak sedang search agar rapi)
        if (!_isSearching)
          IconButton(
            icon: const Icon(Icons.notifications),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const NotifikasiPage(),
                ),
              );
            },
          ),
      ],
    );
  }
}