import 'dart:js_interop';

import 'package:web/web.dart' as web;

@JS('Notification')
external JSAny? get _notificationCtor;

class DeviceNotify {
  static bool get supported {
    try {
      return _notificationCtor != null;
    } catch (_) {
      return false;
    }
  }

  static String get _permission {
    try {
      return web.Notification.permission;
    } catch (_) {
      return 'denied';
    }
  }

  static bool get granted => supported && _permission == 'granted';
  static bool get blocked => supported && _permission == 'denied';

  static Future<bool> request() async {
    if (!supported) return false;
    try {
      final r = await web.Notification.requestPermission().toDart;
      return r.toDart == 'granted';
    } catch (_) {
      return false;
    }
  }

  static void show(String title, String body) {
    if (!granted) return;
    try {
      web.Notification(title, web.NotificationOptions(body: body, icon: 'icons/Icon-192.png', tag: 'heatguard'));
    } catch (_) {}
  }
}
