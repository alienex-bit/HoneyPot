import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'dart:async';

class NotificationService {
  static const _channel = MethodChannel('com.example.honeypot/notifications');
  
  // Stream controller to broadcast new notification events to the UI
  static final _notificationStreamController = StreamController<void>.broadcast();
  static Stream<void> get onNotificationReceived => _notificationStreamController.stream;

  static void initialize() {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onNotificationReceived') {
        triggerRefresh();
      }
    });
  }

  static void triggerRefresh() {
    _notificationStreamController.add(null);
  }

  static Future<bool> isServiceEnabled() async {
    try {
      final bool enabled = await _channel.invokeMethod('isNotificationServiceEnabled');
      return enabled;
    } on PlatformException catch (e) {
      debugPrint("Failed to check service status: '${e.message}'.");
      return false;
    }
  }

  static Future<void> requestPermission() async {
    try {
      await _channel.invokeMethod('requestNotificationPermission');
    } on PlatformException catch (e) {
      debugPrint("Failed to request permission: '${e.message}'.");
    }
  }
  static Future<void> openNotificationApp() async {
    try {
      await _channel.invokeMethod('openNotificationApp');
    } on PlatformException catch (e) {
      debugPrint("Failed to open notification app: '${e.message}'.");
    }
  }

  static Future<void> requestIgnoreBatteryOptimizations() async {
    try {
      await _channel.invokeMethod('requestIgnoreBatteryOptimizations');
    } on PlatformException catch (e) {
      debugPrint("Failed to request battery optimization ignore: '${e.message}'.");
    }
  }

  static Future<void> launchApp(String packageName) async {
    try {
      await _channel.invokeMethod('launchApp', {'packageName': packageName});
    } on PlatformException catch (e) {
      debugPrint("Failed to launch app: '${e.message}'.");
    }
  }

  static Future<void> refreshStats() async {
    try {
      await _channel.invokeMethod('refreshStats');
    } on PlatformException catch (e) {
      debugPrint("Failed to refresh stats: '${e.message}'.");
    }
  }

  static Future<void> requestPostNotificationsPermission() async {
    try {
      await _channel.invokeMethod('requestPostNotificationsPermission');
    } on PlatformException catch (e) {
      debugPrint("Failed to request post notifications permission: '${e.message}'.");
    }
  }

  static Future<bool> areNotificationsEnabled() async {
    try {
      final bool enabled = await _channel.invokeMethod('areNotificationsEnabled');
      return enabled;
    } on PlatformException catch (e) {
      debugPrint("Failed to check notifications enabled: '${e.message}'.");
      return false;
    }
  }
}
