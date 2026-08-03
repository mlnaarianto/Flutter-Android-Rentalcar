import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:rentalcar/menu/dashboard.dart'; // Sesuaikan path jika berbeda
import 'package:rentalcar/pages/login.dart';
import 'firebase_options.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // 1. Inisialisasi Firebase
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } catch (e) {
    debugPrint("Firebase init error: $e");
  }

  // 2. Cek apakah token login sudah ada di SharedPreferences
  final prefs = await SharedPreferences.getInstance();
  final String? token = prefs.getString('access_token');

  // 3. Tentukan halaman awal berdasarkan status token
  final Widget initialScreen = (token != null && token.isNotEmpty)
      ? const Dashboard()
      : const LoginPage();

  runApp(MyApp(initialScreen: initialScreen));
}

class MyApp extends StatelessWidget {
  final Widget initialScreen;
  const MyApp({super.key, required this.initialScreen});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Rental Car',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
      ),
      home: initialScreen, // 👈 Otomatis diarahkan ke Dashboard jika sudah login
    );
  }
}