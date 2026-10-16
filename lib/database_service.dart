import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import 'mission.dart';

class DatabaseService {
  DatabaseService._();
  static final DatabaseService instance = DatabaseService._();
  Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;
    final location = join(await getDatabasesPath(), 'lifequest.db');
    _database = await openDatabase(location, version: 1, onCreate: (db, version) async {
      await db.execute('''
        CREATE TABLE missions (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          title TEXT NOT NULL,
          description TEXT NOT NULL,
          category TEXT NOT NULL,
          frequency TEXT NOT NULL,
          points INTEGER NOT NULL,
          progress INTEGER NOT NULL DEFAULT 0,
          completed INTEGER NOT NULL DEFAULT 0,
          last_completed_on TEXT
        )
      ''');
      await db.execute('''
        CREATE TABLE wallet (
          id INTEGER PRIMARY KEY CHECK(id = 1),
          coins INTEGER NOT NULL DEFAULT 0,
          xp INTEGER NOT NULL DEFAULT 0
        )
      ''');
      await db.insert('wallet', {'id': 1, 'coins': 0, 'xp': 0});
      await db.execute('''
        CREATE TABLE transactions (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          mission_id INTEGER,
          points INTEGER NOT NULL,
          created_at TEXT NOT NULL
        )
      ''');
    });
    return _database!;
  }

  Future<List<Mission>> getMissions() async {
    final db = await database;
    final rows = await db.query('missions', orderBy: 'id DESC');
    return rows.map(Mission.fromMap).toList();
  }

  Future<void> saveMission(Mission mission) async {
    final db = await database;
    if (mission.id == null) {
      await db.insert('missions', mission.toMap());
    } else {
      await db.update('missions', mission.toMap(), where: 'id = ?', whereArgs: [mission.id]);
    }
  }

  Future<void> deleteMission(int id) async {
    final db = await database;
    await db.delete('missions', where: 'id = ?', whereArgs: [id]);
  }

  Future<Map<String, int>> getWallet() async {
    final db = await database;
    final rows = await db.query('wallet', where: 'id = 1');
    return {'coins': rows.first['coins'] as int, 'xp': rows.first['xp'] as int};
  }

  Future<bool> updateProgress(Mission mission, int progress) async {
    final db = await database;
    return db.transaction((txn) async {
      final rows = await txn.query('missions', where: 'id = ?', whereArgs: [mission.id]);
      if (rows.isEmpty) return false;
      final current = Mission.fromMap(rows.first);
      if (current.completed) return false;
      final safeProgress = progress.clamp(0, 100);
      final finished = safeProgress == 100;
      await txn.update('missions', {
        'progress': safeProgress,
        'completed': finished ? 1 : 0,
        'last_completed_on': finished ? DateTime.now().toIso8601String().substring(0, 10) : null,
      }, where: 'id = ?', whereArgs: [mission.id]);
      if (finished) {
        await txn.rawUpdate('UPDATE wallet SET coins = coins + ?, xp = xp + ? WHERE id = 1', [current.points, current.points]);
        await txn.insert('transactions', {
          'mission_id': current.id,
          'points': current.points,
          'created_at': DateTime.now().toIso8601String(),
        });
      }
      return finished;
    });
  }
}
