// lib/config/api_config.dart

class ApiConfig {
  // ⚠️ Cukup ganti IP di sini, semua file akan otomatis mengikuti
  static const String baseUrl = 'http://192.168.189.5:8000/api';

  // Kumpulan Endpoint
  static const String googleLogin = '$baseUrl/auth/google/mobile';
  static const String manualLogin = '$baseUrl/auth/login';
  static const String logout = '$baseUrl/logout';

  static const String userProfile = '$baseUrl/user';
  // Nanti kalau ada endpoint lain, tinggal tambah di sini:
  // static const String getCars = '$baseUrl/cars';
  // static const String bookCar = '$baseUrl/book';
}
