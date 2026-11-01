/// Key SharedPreferences milik user (non-sensitif) yang dibersihkan
/// saat logout atau sesi berakhir. Token ada di TokenStorage, bukan di sini.
///
/// Kalau login.dart menyimpan key baru ke prefs, tambahkan juga di sini
/// supaya ikut terhapus saat logout.
const List<String> userPrefsKeys = [
  'user_id',
  'user_name',
  'user_email',
  'user_roles',
  'role',
  'user_permissions',
  'avatar_url',
];