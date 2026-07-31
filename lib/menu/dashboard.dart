import 'package:flutter/material.dart';
import 'package:rentalcar/layouts/app.dart';

// Halaman Detail Mobil (Opsional di satu file yang sama atau bisa dipisah)
class CarDetailPage extends StatelessWidget {
  final String carName;
  final String category;
  final String price;

  const CarDetailPage({
    super.key,
    required this.carName,
    required this.category,
    required this.price,
  });

  @override
  Widget build(BuildContext context) {
    // Membuat slug sederhana dari nama mobil
    final String slug = carName.toLowerCase().replaceAll(' ', '-');

    return Scaffold(
      appBar: AppBar(
        title: Text(carName),
        backgroundColor: Colors.blue,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              carName,
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'Slug: /cars/$slug',
              style: const TextStyle(color: Colors.grey, fontStyle: FontStyle.italic),
            ),
            const SizedBox(height: 16),
            Text('Kategori: $category', style: const TextStyle(fontSize: 16)),
            const SizedBox(height: 8),
            Text('Harga: $price', style: const TextStyle(fontSize: 16, color: Colors.green, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }
}

// Halaman Utama Dashboard
class Dashboard extends StatefulWidget {
  const Dashboard({super.key});

  @override
  State<Dashboard> createState() => _DashboardState();
}

class _DashboardState extends State<Dashboard> {
  // Dummy Data daftar mobil rental
  final List<Map<String, String>> _allCars = [
    {'name': 'Toyota Avanza', 'category': 'Family Car', 'price': 'Rp 350.000 / hari'},
    {'name': 'Honda Brio', 'category': 'City Car', 'price': 'Rp 250.000 / hari'},
    {'name': 'Mitsubishi Xpander', 'category': 'Family Car', 'price': 'Rp 400.000 / hari'},
    {'name': 'Toyota Fortuner', 'category': 'SUV', 'price': 'Rp 900.000 / hari'},
    {'name': 'Honda Civic', 'category': 'Sedan', 'price': 'Rp 1.200.000 / hari'},
    {'name': 'Daihatsu Sigra', 'category': 'Family Car', 'price': 'Rp 300.000 / hari'},
  ];

  List<Map<String, String>> _filteredCars = [];
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _filteredCars = _allCars;
  }

  // Fungsi untuk memfilter data berdasarkan input search dari Navbar
  void _filterCars(String query) {
    setState(() {
      _searchQuery = query;
      if (query.isEmpty) {
        _filteredCars = _allCars;
      } else {
        _filteredCars = _allCars.where((car) {
          final carName = car['name']!.toLowerCase();
          final category = car['category']!.toLowerCase();
          final input = query.toLowerCase();
          return carName.contains(input) || category.contains(input);
        }).toList();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return AppLayout(
      title: 'Dashboard',
      currentIndex: 0,
      onTap: (index) {
        print('Bottom nav index: $index');
      },
      // Menghubungkan fungsi filter pencarian ke AppLayout/Navbar
      appBarSearchCallback: _filterCars,
      content: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Indikator teks jika sedang mencari
            if (_searchQuery.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 12.0),
                child: Text(
                  'Hasil pencarian untuk: "$_searchQuery" (${_filteredCars.length} ditemukan)',
                  style: const TextStyle(fontStyle: FontStyle.italic, color: Colors.grey),
                ),
              ),

            // Daftar List Mobil
            Expanded(
              child: _filteredCars.isEmpty
                  ? const Center(
                      child: Text(
                        'Mobil tidak ditemukan',
                        style: TextStyle(fontSize: 16, color: Colors.grey),
                      ),
                    )
                  : ListView.builder(
                      itemCount: _filteredCars.length,
                      itemBuilder: (context, index) {
                        final car = _filteredCars[index];
                        return Card(
                          elevation: 2,
                          margin: const EdgeInsets.only(bottom: 12.0),
                          child: ListTile(
                            leading: const CircleAvatar(
                              backgroundColor: Colors.blueAccent,
                              child: Icon(Icons.directions_car, color: Colors.white),
                            ),
                            title: Text(
                              car['name']!,
                              style: const TextStyle(fontWeight: FontWeight.bold),
                            ),
                            subtitle: Text('${car['category']} • ${car['price']}'),
                            trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                            onTap: () {
                              // Navigasi ke Halaman Detail saat card diklik
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => CarDetailPage(
                                    carName: car['name']!,
                                    category: car['category']!,
                                    price: car['price']!,
                                  ),
                                ),
                              );
                            },
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}