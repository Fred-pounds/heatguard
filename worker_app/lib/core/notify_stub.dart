import 'package:flutter/services.dart';

class DeviceNotify {
  static bool get supported => false;
  static bool get granted => false;
  static bool get blocked => false;
  static Future<bool> request() async => false;
  static void show(String title, String body) => HapticFeedback.heavyImpact();
}
