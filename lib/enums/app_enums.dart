// lib/enums/app_enums.dart

enum AppRole {
  superAdmin('Super Admin'),
  perental('Perental'),
  penyewa('Penyewa'),
  driver('Driver');

  final String value;
  const AppRole(this.value);
}

enum AppPermission {
  // Manajemen Sistem & User
  manageUsers('manage-users'),
  manageRoles('manage-roles'),

  // Manajemen Mobil (Mobil & Katalog)
  manageCars('manage-cars'),
  viewCars('view-cars'),

  // Manajemen Booking & Pembayaran
  manageBookings('manage-bookings'),
  managePayments('manage-payments'),
  
  // Hak akses untuk Penyewa & Pengguna
  createBooking('create-booking'),
  viewOwnBooking('view-own-booking'),
  cancelOwnBooking('cancel-own-booking'),
  manageProfile('manage-profile'),

  // Hak akses untuk Driver / Perental
  viewAssignedBooking('view-assigned-booking'),
  updateBookingStatus('update-booking-status');

  final String value;
  const AppPermission(this.value);
}