import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'dart:io' as io;

class DatabaseService {
  static final DatabaseService _instance = DatabaseService._internal();
  static Database? _database;

  factory DatabaseService() => _instance;

  DatabaseService._internal();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    String path = join(await getDatabasesPath(), 'honeypot.db');
    return await openDatabase(
      path,
      version: 7,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  Future _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE notifications (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        package_name TEXT,
        app_name TEXT,
        title TEXT,
        content TEXT,
        timestamp INTEGER,
        icon_byte_array BLOB,
        priority INTEGER DEFAULT 2,
        notification_id INTEGER,
        notification_tag TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE app_cache (
        package_name TEXT PRIMARY KEY,
        description TEXT,
        timestamp INTEGER
      )
    ''');
  }

  Future _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      // Version 2 was adding app_name columns in some branches, but we consolidated
    }
    if (oldVersion < 3) {
      try {
        await db.execute('ALTER TABLE notifications ADD COLUMN priority INTEGER DEFAULT 2');
      } catch (e) {
        debugPrint("Migration Error (priority): $e");
      }
    }
    if (oldVersion < 5) {
      try {
        await db.execute('ALTER TABLE notifications ADD COLUMN notification_id INTEGER');
        await db.execute('ALTER TABLE notifications ADD COLUMN notification_tag TEXT');
      } catch (e) {
        debugPrint("Migration Error (v5 - notification_id/tag): $e");
      }
    }
    if (oldVersion < 7) {
      try {
        await db.execute('''
          CREATE TABLE IF NOT EXISTS app_cache (
            package_name TEXT PRIMARY KEY,
            description TEXT,
            timestamp INTEGER
          )
        ''');
      } catch (e) {
        debugPrint("Migration Error (v7 - app_cache): $e");
      }
    }
  }

  Future<int> insertNotification(Map<String, dynamic> data) async {
    Database db = await database;
    return await db.insert('notifications', {
      'package_name': data['package_name'],
      'app_name': data['app_name'],
      'title': data['title'],
      'content': data['content'],
      'timestamp': data['timestamp'],
      'icon_byte_array': data['icon'],
      'priority': data['priority'] ?? 2,
    });
  }

  Future<List<Map<String, dynamic>>> getNotifications({String? filterPackage, int? priority, bool sortByPriority = false, int? limit}) async {
    Database db = await database;
    
    List<String> whereClauses = [];
    List<dynamic> whereArgs = [];

    if (filterPackage != null) {
      whereClauses.add('package_name = ?');
      whereArgs.add(filterPackage);
    }

    if (priority != null) {
      whereClauses.add('priority = ?');
      whereArgs.add(priority);
    }

    String whereClause = whereClauses.isNotEmpty ? 'WHERE ${whereClauses.join(' AND ')}' : '';
    String orderBy = sortByPriority ? 'priority DESC, timestamp DESC' : 'timestamp DESC';
    
    return await db.rawQuery('''
      SELECT 
        package_name, 
        app_name,
        title, 
        MAX(content) as content, 
        MAX(timestamp) as timestamp, 
        MAX(id) as id,
        COUNT(*) as count,
        MAX(icon_byte_array) as icon_byte_array,
        MAX(priority) as priority
      FROM notifications 
      $whereClause
      GROUP BY 
        package_name COLLATE NOCASE, 
        COALESCE(app_name, '') COLLATE NOCASE, 
        TRIM(COALESCE(title, ''))
      ORDER BY $orderBy
      ${limit != null ? 'LIMIT $limit' : ''}
    ''', whereArgs);
  }

  Future<void> deleteNotification(int id) async {
    Database db = await database;
    await db.delete('notifications', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> deleteGroup(String packageName, String title) async {
    Database db = await database;
    await db.delete(
      'notifications',
      where: 'package_name = ? AND TRIM(COALESCE(title, \'\')) = TRIM(COALESCE(?, \'\'))',
      whereArgs: [packageName, title],
    );
  }

  Future<void> clearAll() async {
    Database db = await database;
    await db.delete('notifications');
  }

  Future<List<Map<String, dynamic>>> getStats() async {
    Database db = await database;
    return await db.rawQuery('''
      SELECT app_name, package_name, COUNT(*) as count, MAX(icon_byte_array) as icon
      FROM notifications
      GROUP BY package_name
      ORDER BY count DESC
      LIMIT 8
    ''');
  }

  Future<List<Map<String, dynamic>>> getHourlyStats() async {
    Database db = await database;
    int twentyFourHoursAgo = DateTime.now().subtract(const Duration(hours: 24)).millisecondsSinceEpoch;
    return await db.rawQuery('''
      SELECT (timestamp / 3600000) as hour_bucket, COUNT(*) as count
      FROM notifications
      WHERE timestamp >= ?
      GROUP BY hour_bucket
      ORDER BY hour_bucket ASC
    ''', [twentyFourHoursAgo]);
  }

  Future<List<Map<String, dynamic>>> getWeeklyStats() async {
    Database db = await database;
    // Go back 8 days to ensure full coverage
    int eightDaysAgo = DateTime.now().subtract(const Duration(days: 8)).millisecondsSinceEpoch;
    return await db.rawQuery('''
      SELECT date(timestamp / 1000, 'unixepoch', 'localtime') as date_label, 
             priority,
             COUNT(*) as count
      FROM notifications
      WHERE timestamp >= ?
      GROUP BY date_label, priority
      ORDER BY date_label ASC
    ''', [eightDaysAgo]);
  }

  Future<Map<int, int>> getGradeDistribution() async {
    Database db = await database;
    final result = await db.rawQuery('''
      SELECT priority, COUNT(*) as count 
      FROM notifications 
      GROUP BY priority
    ''');
    
    Map<int, int> distribution = {0: 0, 1: 0, 2: 0, 3: 0};
    for (var row in result) {
      final p = row['priority'] as int? ?? 0;
      distribution[p] = row['count'] as int? ?? 0;
    }
    return distribution;
  }

  Future<List<Map<String, dynamic>>> getHeatmapData() async {
    Database db = await database;
    // Returns day (0-6) and hour (0-23) with counts
    // strftime('%w', ...) returns day of week 0-6 (Sunday is 0)
    // strftime('%H', ...) returns hour 00-23
    return await db.rawQuery('''
      SELECT 
        CAST(strftime('%w', timestamp / 1000, 'unixepoch', 'localtime') AS INTEGER) as day,
        CAST(strftime('%H', timestamp / 1000, 'unixepoch', 'localtime') AS INTEGER) as hour,
        COUNT(*) as count
      FROM notifications
      WHERE timestamp >= ?
      GROUP BY day, hour
    ''', [DateTime.now().subtract(const Duration(days: 28)).millisecondsSinceEpoch]);
  }

  Future<Map<String, dynamic>?> getPeakHour({int days = 30}) async {
    Database db = await database;
    final since = DateTime.now().subtract(Duration(days: days)).millisecondsSinceEpoch;
    final result = await db.rawQuery('''
      SELECT 
        CAST(strftime('%H', timestamp / 1000, 'unixepoch', 'localtime') AS INTEGER) as hour,
        COUNT(*) as count
      FROM notifications
      WHERE timestamp >= ?
      GROUP BY hour
      ORDER BY count DESC
      LIMIT 1
    ''', [since]);
    if (result.isNotEmpty) return result.first;
    return null;
  }
  Future<List<Map<String, dynamic>>> getStackedHourlyStats({int days = 7}) async {
    Database db = await database;
    final since = DateTime.now().subtract(Duration(days: days)).millisecondsSinceEpoch;
    return await db.rawQuery('''
      SELECT 
        CAST(strftime('%H', timestamp / 1000, 'unixepoch', 'localtime') AS INTEGER) as hour,
        priority,
        COUNT(*) as count
      FROM notifications
      WHERE timestamp >= ?
      GROUP BY hour, priority
      ORDER BY hour ASC, priority ASC
    ''', [since]);
  }

  Future<List<Map<String, dynamic>>> getTopAppsByPriority(int priority, {int limit = 5, int days = 30}) async {
    Database db = await database;
    final since = DateTime.now().subtract(Duration(days: days)).millisecondsSinceEpoch;
    return await db.rawQuery('''
      SELECT app_name, package_name, COUNT(*) as count, MAX(icon_byte_array) as icon
      FROM notifications
      WHERE priority = ? AND timestamp >= ?
      GROUP BY package_name
      ORDER BY count DESC
      LIMIT ?
    ''', [priority, since, limit]);
  }

  Future<List<int>> getRecentTimestamps({int days = 1}) async {
    Database db = await database;
    final now = DateTime.now();
    final since = now.subtract(Duration(days: days)).millisecondsSinceEpoch;
    final result = await db.rawQuery('''
      SELECT timestamp 
      FROM notifications 
      WHERE timestamp >= ?
      ORDER BY timestamp ASC
    ''', [since]);
    return result.map((row) => row['timestamp'] as int).toList();
  }

  Future<void> seedDebugData() async {
    Database db = await database;
    final now = DateTime.now();
    final batch = db.batch();
    
    // Seed random counts for each of the last 7 days
    for (int i = 0; i < 7; i++) {
      final date = now.subtract(Duration(days: i));
      final count = 5 + (i * 3); // Varying counts
      for (int j = 0; j < count; j++) {
        batch.insert('notifications', {
          'package_name': 'com.debug.test',
          'app_name': 'Bee DebugGER',
          'title': 'Mock Honey ${date.day}',
          'content': 'Seeding data for chart testing',
          'timestamp': date.millisecondsSinceEpoch - (j * 1000), // Slightly spread out
          'priority': (j % 4), // Rotate through 0-3 priorities (D, C, B, A)
        });
      }
    }
    await batch.commit(noResult: true);
  }

  Future<int> getTotalCount() async {
    Database db = await database;
    final result = await db.rawQuery('SELECT COUNT(*) as count FROM notifications');
    return result.first['count'] as int? ?? 0;
  }

  Future<double> getDatabaseSize() async {
    try {
      String dbPath = join(await getDatabasesPath(), 'honeypot.db');
      List<String> files = [dbPath, '$dbPath-wal', '$dbPath-shm'];
      
      int totalBytes = 0;
      for (var path in files) {
        final file = io.File(path);
        if (await file.exists()) {
          totalBytes += await file.length();
        }
      }
      return totalBytes / (1024 * 1024);
    } catch (e) {
      debugPrint("Error getting database size: $e");
      return 0.0;
    }
  }

  Future<void> vacuum() async {
    Database db = await database;
    // Force a checkpoint before vacuuming to ensure all WAL data is moved to the main file
    await db.execute('PRAGMA wal_checkpoint(FULL)');
    await db.execute('VACUUM');
  }

  Future<String?> getCachedAppInfo(String packageName) async {
    Database db = await database;
    final results = await db.query('app_cache', 
      where: 'package_name = ?', 
      whereArgs: [packageName]
    );
    if (results.isNotEmpty) {
      return results.first['description'] as String?;
    }
    return null;
  }

  Future<void> cacheAppInfo(String packageName, String description) async {
    Database db = await database;
    await db.insert('app_cache', {
      'package_name': packageName,
      'description': description,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }
}
