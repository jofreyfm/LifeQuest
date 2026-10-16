import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import 'mission.dart';

class CompletionRecord {
  final String title;
  final int points;
  final DateTime when;
  const CompletionRecord(this.title, this.points, this.when);
}

class DatabaseService {
  DatabaseService._();
  static final DatabaseService instance = DatabaseService._();
  Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;
    final location = join(await getDatabasesPath(), 'lifequest.db');
    _database = await openDatabase(
      location,
      version: 2,
      onCreate: (db, version) async {
        await db.execute('''CREATE TABLE missions (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          title TEXT NOT NULL, description TEXT NOT NULL,
          category TEXT NOT NULL, frequency TEXT NOT NULL,
          points INTEGER NOT NULL, progress INTEGER NOT NULL DEFAULT 0,
          completed INTEGER NOT NULL DEFAULT 0,
          last_completed_on TEXT, period_anchor TEXT
        )''');
        await db.execute('''CREATE TABLE wallet (
          id INTEGER PRIMARY KEY CHECK(id = 1),
          coins INTEGER NOT NULL DEFAULT 0, xp INTEGER NOT NULL DEFAULT 0
        )''');
        await db.insert('wallet', {'id': 1, 'coins': 0, 'xp': 0});
        await db.execute('''CREATE TABLE transactions (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          mission_id INTEGER, points INTEGER NOT NULL,
          created_at TEXT NOT NULL, title_snapshot TEXT
        )''');
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute('ALTER TABLE missions ADD COLUMN period_anchor TEXT');
          await db.execute('ALTER TABLE transactions ADD COLUMN title_snapshot TEXT');
          await db.execute('''UPDATE transactions SET title_snapshot =
            COALESCE((SELECT title FROM missions WHERE missions.id = transactions.mission_id), 'Missão excluída')''');
          await db.execute('''UPDATE missions SET period_anchor = last_completed_on
            WHERE last_completed_on IS NOT NULL''');
        }
      },
    );
    return _database!;
  }

  String _day(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  String _period(String frequency, DateTime date) {
    if (frequency == 'Semanal') {
      final monday = DateTime(date.year, date.month, date.day).subtract(Duration(days: date.weekday - 1));
      return _day(monday);
    }
    return _day(date);
  }

  bool _isDue(Map<String, Object?> row, DateTime now) {
    final frequency = row['frequency'] as String;
    if (frequency == 'Única' || frequency == 'Livre') return false;
    if (frequency != 'Diária' && frequency != 'Semanal') return false;
    final anchor = (row['period_anchor'] ?? row['last_completed_on']) as String?;
    if (anchor == null) return false;
    final date = DateTime.tryParse(anchor);
    if (date == null) return false;
    return _period(frequency, date) != _period(frequency, now);
  }

  Future<List<Mission>> getMissions() async {
    final db = await database;
    return db.transaction((txn) async {
      final rows = await txn.query('missions', orderBy: 'id DESC');
      final now = DateTime.now();
      final updated = <Mission>[];
      for (final row in rows) {
        if (_isDue(row, now)) {
          await txn.update('missions', {
            'progress': 0, 'completed': 0, 'period_anchor': null,
          }, where: 'id = ?', whereArgs: [row['id']]);
          updated.add(Mission.fromMap({...row, 'progress': 0, 'completed': 0}));
        } else {
          updated.add(Mission.fromMap(row));
        }
      }
      return updated;
    });
  }

  Future<void> saveMission(Mission mission) async {
    final db = await database;
    if (mission.id == null) {
      await db.insert('missions', mission.toMap());
    } else {
      // Preserve existing progress and completion when editing metadata.
      final values = mission.toMap()..remove('progress')..remove('completed')..remove('last_completed_on');
      await db.update('missions', values, where: 'id = ?', whereArgs: [mission.id]);
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

  Future<List<CompletionRecord>> getHistory() async {
    final db = await database;
    final rows = await db.query('transactions', orderBy: 'created_at DESC, id DESC');
    return rows.map((row) => CompletionRecord(
      (row['title_snapshot'] as String?) ?? 'Missão antiga',
      row['points'] as int,
      DateTime.parse(row['created_at'] as String),
    )).toList();
  }

  Future<bool> updateProgress(Mission mission, int progress) async {
    final db = await database;
    return db.transaction((txn) async {
      final rows = await txn.query('missions', where: 'id = ?', whereArgs: [mission.id]);
      if (rows.isEmpty) return false;
      var row = rows.first;
      final now = DateTime.now();
      if (_isDue(row, now)) {
        await txn.update('missions', {'progress': 0, 'completed': 0, 'period_anchor': null},
          where: 'id = ?', whereArgs: [mission.id]);
        row = {...row, 'progress': 0, 'completed': 0};
      }
      final current = Mission.fromMap(row);
      if (current.completed && current.frequency != 'Livre') return false;
      final safeProgress = progress.clamp(0, 100);
      final finished = safeProgress == 100;
      await txn.update('missions', {
        'progress': finished && current.frequency == 'Livre' ? 0 : safeProgress,
        'completed': finished && current.frequency != 'Livre' ? 1 : 0,
        'period_anchor': _day(now),
        if (finished) 'last_completed_on': _day(now),
      }, where: 'id = ?', whereArgs: [mission.id]);
      if (finished) {
        await txn.rawUpdate('UPDATE wallet SET coins = coins + ?, xp = xp + ? WHERE id = 1',
          [current.points, current.points]);
        await txn.insert('transactions', {
          'mission_id': current.id,
          'title_snapshot': current.title,
          'points': current.points,
          'created_at': now.toIso8601String(),
        });
      }
      return finished;
    });
  }
}
