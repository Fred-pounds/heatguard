import 'dart:js_interop';

import 'package:web/web.dart' as web;

/// Browser notifications for the worker view (phone or desktop browser).
/// A pilot would add native push (Firebase Cloud Messaging) and SMS fallback.
class BrowserNotify {
  static bool get granted {
    try {
      return web.Notification.permission == 'granted';
    } catch (_) {
      return false;
    }
  }

  static Future<bool> request() async {
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
      web.Notification(title, web.NotificationOptions(body: body));
    } catch (_) {}
  }
}
