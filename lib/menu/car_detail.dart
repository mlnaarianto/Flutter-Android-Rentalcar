import 'package:flutter/material.dart';

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
    // Membuat slug sederhana dari nama mobil untuk URL/Route simulasi
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