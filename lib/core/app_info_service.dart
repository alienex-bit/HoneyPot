import 'package:http/http.dart' as http;
import 'package:html/parser.dart' as parser;
import 'package:flutter/foundation.dart';
import 'database_service.dart';

class AppInfoService {
  static final AppInfoService _instance = AppInfoService._internal();
  factory AppInfoService() => _instance;
  AppInfoService._internal();

  final DatabaseService _db = DatabaseService();

  Future<String?> getAppDescription(String packageName) async {
    // 1. Check local cache first
    String? cached = await _db.getCachedAppInfo(packageName);
    if (cached != null) {
      debugPrint('AppInfoService: Local cache hit for $packageName');
      return cached;
    }

    // 2. Filter system apps
    if (packageName.startsWith('com.android.') ||
        packageName.startsWith('android') ||
        packageName == 'com.google.android.packageinstaller') {
      return 'System Component: This is a core part of your device\'s operating system and usually isn\'t listed on the Play Store.';
    }

    // 3. Fetch from Play Store
    try {
      debugPrint('AppInfoService: Fetching Play Store data for $packageName');
      final response = await http.get(
        Uri.parse('https://play.google.com/store/apps/details?id=$packageName'),
        headers: {
          'User-Agent':
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36',
        },
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final document = parser.parse(response.body);

        // Try og:description first (most reliable meta tag)
        final metaTags = document.getElementsByTagName('meta');
        String? description;

        for (var tag in metaTags) {
          if (tag.attributes['property'] == 'og:description' ||
              tag.attributes['name'] == 'description') {
            description = tag.attributes['content'];
            break;
          }
        }

        // Clean up description (remove excess whitespace)
        if (description != null) {
          description = description.trim();

          // Limit length for the modal
          if (description.length > 500) {
            description = '${description.substring(0, 497)}...';
          }

          // Cache it
          await _db.cacheAppInfo(packageName, description);
          return description;
        }
      } else if (response.statusCode == 404) {
        return 'App not found on Play Store. This might be a system app, a private enterprise app, or a side-loaded utility.';
      }
    } catch (e) {
      debugPrint('AppInfoService Error: $e');
      return 'Could not retrieve app info at this time. Check your internet connection and try again.';
    }

    return 'No description available for this app.';
  }
}
