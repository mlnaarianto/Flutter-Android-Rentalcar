// lib/config/api_config.dart

class ApiConfig {
  // ⚠️ Cukup ganti IP di sini, semua file akan otomatis mengikuti
  static const String baseUrl = 'http://192.168.189.13:8000/api';

  // Kumpulan Endpoint
  static const String googleLogin = '$baseUrl/auth/google/mobile';
  static const String manualLogin = '$baseUrl/auth/login';
  static const String logout = '$baseUrl/logout';
  static const String refresh = '$baseUrl/auth/refresh';

  static const String userProfile = '$baseUrl/user';

  // 🟢 TAMBAHAN: ID admin/CS yang menerima chat bantuan (dipakai sidebar.dart)
  static const String supportAgent = '$baseUrl/support-agent';

  // Nanti kalau ada endpoint lain, tinggal tambah di sini:
  // static const String getCars = '$baseUrl/cars';
  // static const String bookCar = '$baseUrl/book';
}