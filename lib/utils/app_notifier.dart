import 'package:flutter/material.dart';
import 'package:flutter_quickalert/flutter_quickalert.dart';
import 'package:rentalcar/utils/navigation_service.dart'; // 👈 pakai navigatorKey yang SUDAH ADA, jangan bikin baru

class AppNotifier {
  static void _show(QuickAlertTypes type, String message) {
    final context = navigatorKey.currentState?.overlay?.context;
    if (context == null) return;

    QuickAlert.show(
      context: context,
      type: type,
      message: message, // 👈 bukan 'text', tapi 'message'
    );
  }

  static void error(String message) => _show(QuickAlertTypes.error, message);

  static void success(String message) => _show(QuickAlertTypes.success, message);

  static void warning(String message) => _show(QuickAlertTypes.warning, message);
}