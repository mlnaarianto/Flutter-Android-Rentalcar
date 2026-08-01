import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'pages/homepage.dart';
import 'firebase_options.dart'; // 👈 1. Import file options yang baru dibuat

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  try {
    // 👈 2. Masukkan options di sini agar Firebase tahu kredensial project-nya
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } catch (e) {
    debugPrint("Firebase init error: $e");
  }

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Rental Car',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
      ),
      home: const HomePage(),
    );
  }
}