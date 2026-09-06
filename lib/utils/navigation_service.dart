import 'package:flutter/material.dart';

/// Global navigator key.
///
/// Dipakai supaya kode di luar widget tree (misalnya
/// `NotificationSocketService`, atau handler FCM di `main.dart`)
/// tetap bisa melakukan navigasi tanpa perlu punya `BuildContext`.
///
/// Cukup pasang key ini ke `MaterialApp(navigatorKey: navigatorKey, ...)`
/// di `main.dart`, lalu di mana pun butuh navigasi tinggal:
///
/// ```dart
/// navigatorKey.currentState?.push(
///   MaterialPageRoute(builder: (_) => const SomePage()),
/// );
/// ```
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();