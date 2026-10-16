import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import 'mission.dart';
import 'reward.dart';


class InactivePeriod {
  final int id;
  final String startDay, endDay;
  const InactivePeriod(this.id, this.startDay, this.endDay);
}

class StreakStatus {
  final int days;
  final bool inactiveToday, restingToday;
  const StreakStatus(this.days, this.inactiveToday, this.restingToday);
}

class CompletionRecord {
  final String title;
  final int points;
  final DateTime when;
  const CompletionRecord(this.title, this.points, this.when);
}

class PurchaseRecord {
  final String title;
  final int price;
  final DateTime when;
  const PurchaseRecord(this.title, this.price, this.when);
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
      version: 8,
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
        await _createRewardTables(db);
        await _createStreakTables(db);
        await _createFocusTables(db);
        await _createDraftTimerTable(db);
        await _createReminderTable(db);
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
        if (oldVersion < 3) {
          await _createRewardTables(db);
        }
        if (oldVersion < 4) {
          await db.execute('ALTER TABLE owned_rewards ADD COLUMN hidden_at TEXT');
        }
        if (oldVersion < 5) {
          await _createStreakTables(db);
        }
        if (oldVersion < 6) {
          await _createFocusTables(db);
        }
        if (oldVersion < 7) {
          await _createDraftTimerTable(db);
        }
        if (oldVersion < 8) {
          await _createReminderTable(db);
        }
      },
    );
    return _database!;
  }

  static Future<void> _createReminderTable(DatabaseExecutor db) async {
    await db.execute('''CREATE TABLE IF NOT EXISTS mission_reminders (
      mission_id INTEGER PRIMARY KEY, hour INTEGER NOT NULL,
      minute INTEGER NOT NULL, enabled INTEGER NOT NULL DEFAULT 1,
      last_notified TEXT,
      FOREIGN KEY (mission_id) REFERENCES missions(id) ON DELETE CASCADE
    )''');
  }

  Future<Map<int, Map<String, Object?>>> getReminders() async {
    final rows = await (await database).query('mission_reminders');
    return {for (final row in rows) row['mission_id'] as int: row};
  }

  Future<void> saveReminder(int missionId, int hour, int minute) async {
    if (hour < 0 || hour > 23 || minute < 0 || minute > 59) {
      throw StateError('Horário inválido.');
    }
    await (await database).insert('mission_reminders', {
      'mission_id': missionId, 'hour': hour, 'minute': minute,
      'enabled': 1, 'last_notified': null,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> removeReminder(int missionId) async {
    await (await database).delete('mission_reminders',
      where: 'mission_id = ?', whereArgs: [missionId]);
  }

  Future<List<int>> consumeDueReminders(DateTime now) async {
    final today = '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    final db = await database;
    return db.transaction((txn) async {
      final due = await txn.rawQuery('''SELECT r.mission_id FROM mission_reminders r
        JOIN missions m ON m.id = r.mission_id
        WHERE r.enabled = 1 AND (r.hour * 60 + r.minute) <= ?
        AND (r.last_notified IS NULL OR r.last_notified <> ?)
        AND NOT (m.frequency = 'Única' AND m.completed = 1)''',
        [now.hour * 60 + now.minute, today]);
      final ids = due.map((r) => r['mission_id'] as int).toList();
      for (final id in ids) {
        await txn.update('mission_reminders', {'last_notified': today},
          where: 'mission_id = ?', whereArgs: [id]);
      }
      return ids;
    });
  }

  static Future<void> _createRewardTables(DatabaseExecutor db) async {
    await db.execute('''CREATE TABLE IF NOT EXISTS rewards (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      title TEXT NOT NULL, description TEXT NOT NULL,
      category TEXT NOT NULL, price INTEGER NOT NULL CHECK(price > 0),
      max_redemptions INTEGER CHECK(max_redemptions > 0)
    )''');
    await db.execute('''CREATE TABLE IF NOT EXISTS owned_rewards (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      reward_id INTEGER, title_snapshot TEXT NOT NULL,
      description_snapshot TEXT NOT NULL, price_paid INTEGER NOT NULL,
      purchased_at TEXT NOT NULL, used_at TEXT, hidden_at TEXT
    )''');
  }


  static Future<void> _createStreakTables(DatabaseExecutor db) async {
    await db.execute('''CREATE TABLE IF NOT EXISTS rest_days (
      weekday INTEGER PRIMARY KEY CHECK(weekday BETWEEN 1 AND 7)
    )''');
    await db.execute('''CREATE TABLE IF NOT EXISTS inactive_periods (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      start_day TEXT NOT NULL, end_day TEXT NOT NULL,
      CHECK(start_day <= end_day)
    )''');
  }

  static Future<void> _createFocusTables(DatabaseExecutor db) async {
    await db.execute('''CREATE TABLE IF NOT EXISTS focus_sessions (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      mission_id INTEGER NOT NULL,
      title_snapshot TEXT NOT NULL,
      seconds INTEGER NOT NULL CHECK(seconds > 0),
      created_at TEXT NOT NULL
    )''');
    await db.execute('''CREATE TABLE IF NOT EXISTS weekly_goals (
      id INTEGER PRIMARY KEY CHECK(id = 1),
      target INTEGER NOT NULL DEFAULT 5 CHECK(target > 0),
      bonus INTEGER NOT NULL DEFAULT 30 CHECK(bonus > 0)
    )''');
    await db.insert('weekly_goals', {'id': 1, 'target': 5, 'bonus': 30},
      conflictAlgorithm: ConflictAlgorithm.ignore);
    await db.execute('''CREATE TABLE IF NOT EXISTS weekly_claims (
      week_key TEXT PRIMARY KEY, coins INTEGER NOT NULL, claimed_at TEXT NOT NULL
    )''');
  }

  static Future<void> _createDraftTimerTable(DatabaseExecutor db) async {
    await db.execute('''CREATE TABLE IF NOT EXISTS focus_drafts (
      mission_id INTEGER PRIMARY KEY,
      elapsed_seconds INTEGER NOT NULL DEFAULT 0,
      updated_at TEXT NOT NULL
    )''');
  }

  Future<int> getFocusDraft(int missionId) async {
    final rows = await (await database).query('focus_drafts',
      columns: ['elapsed_seconds'], where: 'mission_id = ?', whereArgs: [missionId]);
    return rows.isEmpty ? 0 : (rows.first['elapsed_seconds'] as int);
  }

  Future<void> saveFocusDraft(int missionId, int seconds) async {
    if (seconds < 0) throw ArgumentError('Tempo inválido');
    await (await database).insert('focus_drafts', {
      'mission_id': missionId, 'elapsed_seconds': seconds,
      'updated_at': DateTime.now().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> finishFocusDraft(int missionId, String title, int seconds) async {
    final db = await database;
    await db.transaction((txn) async {
      if ((await txn.query('missions', where: 'id = ?', whereArgs: [missionId])).isEmpty) {
        throw StateError('Missão não encontrada.');
      }
      if (seconds > 0) {
        await txn.insert('focus_sessions', {
          'mission_id': missionId, 'title_snapshot': title,
          'seconds': seconds, 'created_at': DateTime.now().toIso8601String(),
        });
      }
      await txn.delete('focus_drafts', where: 'mission_id = ?', whereArgs: [missionId]);
    });
  }

  Future<int> getMissionFocusSeconds(int missionId) async {
    final rows = await (await database).rawQuery(
      'SELECT COALESCE(SUM(seconds),0) AS total FROM focus_sessions WHERE mission_id = ?', [missionId]);
    return (rows.first['total'] as int?) ?? 0;
  }

  Future<int> getFocusSecondsSince(DateTime start) async {
    final rows = await (await database).rawQuery(
      'SELECT COALESCE(SUM(seconds),0) AS total FROM focus_sessions WHERE created_at >= ?',
      [start.toIso8601String()]);
    return (rows.first['total'] as int?) ?? 0;
  }

  Future<void> saveFocusSession(int missionId, String title, int seconds) async {
    if (seconds <= 0) return;
    final db = await database;
    if ((await db.query('missions', where: 'id = ?', whereArgs: [missionId])).isEmpty) {
      throw StateError('Missão não encontrada.');
    }
    await db.insert('focus_sessions', {
      'mission_id': missionId, 'title_snapshot': title,
      'seconds': seconds, 'created_at': DateTime.now().toIso8601String(),
    });
  }

  String _weekKey(DateTime d) {
    final monday = DateTime(d.year, d.month, d.day).subtract(Duration(days: d.weekday - 1));
    return _day(monday);
  }

  Future<Map<String, int>> getWeeklyGoal() async {
    final db = await database;
    final rows = await db.query('weekly_goals', where: 'id = 1');
    final week = _weekKey(DateTime.now());
    final count = Sqflite.firstIntValue(await db.rawQuery(
      'SELECT COUNT(*) FROM transactions WHERE created_at >= ? AND created_at < ?',
      ['${week}T00:00:00', DateTime.parse(week).add(const Duration(days: 7)).toIso8601String()])) ?? 0;
    final claimed = (await db.query('weekly_claims', where: 'week_key = ?', whereArgs: [week])).isNotEmpty;
    return {'target': rows.first['target'] as int, 'bonus': rows.first['bonus'] as int,
      'completed': count, 'claimed': claimed ? 1 : 0};
  }

  Future<void> setWeeklyGoal(int target, int bonus) async {
    if (target < 1 || target > 100 || bonus < 1 || bonus > 10000) {
      throw StateError('Defina uma meta de 1 a 100 missões e um bônus de 1 a 10.000 moedas.');
    }
    await (await database).update('weekly_goals', {'target': target, 'bonus': bonus},
      where: 'id = 1');
  }

  Future<int> claimWeeklyBonus() async {
    final db = await database;
    return db.transaction((txn) async {
      final week = _weekKey(DateTime.now());
      final previous = await txn.query('weekly_claims', where: 'week_key = ?', whereArgs: [week]);
      if (previous.isNotEmpty) throw StateError('Bônus desta semana já resgatado.');
      final goal = (await txn.query('weekly_goals', where: 'id = 1')).first;
      final count = Sqflite.firstIntValue(await txn.rawQuery(
        'SELECT COUNT(*) FROM transactions WHERE created_at >= ? AND created_at < ?',
        ['${week}T00:00:00', DateTime.parse(week).add(const Duration(days: 7)).toIso8601String()])) ?? 0;
      if (count < (goal['target'] as int)) throw StateError('Meta semanal ainda não atingida.');
      final bonus = goal['bonus'] as int;
      await txn.insert('weekly_claims', {
        'week_key': week, 'coins': bonus, 'claimed_at': DateTime.now().toIso8601String()});
      await txn.rawUpdate('UPDATE wallet SET coins = coins + ? WHERE id = 1', [bonus]);
      return bonus;
    });
  }

  Future<Set<int>> getRestDays() async {
    final rows = await (await database).query('rest_days');
    return rows.map((r) => r['weekday'] as int).toSet();
  }

  Future<void> setRestDay(int weekday, bool enabled) async {
    if (weekday < 1 || weekday > 7) throw ArgumentError('Dia inválido');
    final db = await database;
    if (enabled) {
      await db.insert('rest_days', {'weekday': weekday}, conflictAlgorithm: ConflictAlgorithm.ignore);
    } else {
      await db.delete('rest_days', where: 'weekday = ?', whereArgs: [weekday]);
    }
  }

  Future<List<InactivePeriod>> getInactivePeriods() async {
    final rows = await (await database).query('inactive_periods', orderBy: 'start_day DESC');
    return rows.map((r) => InactivePeriod(r['id'] as int,
      r['start_day'] as String, r['end_day'] as String)).toList();
  }

  Future<void> addInactivePeriod(DateTime start, DateTime end) async {
    final a = _day(start), b = _day(end);
    if (a.compareTo(b) > 0) throw StateError('A data inicial deve ser anterior à final.');
    await (await database).insert('inactive_periods', {'start_day': a, 'end_day': b});
  }

  Future<void> deleteInactivePeriod(int id) async {
    await (await database).delete('inactive_periods', where: 'id = ?', whereArgs: [id]);
  }

  bool _inactiveOn(String day, List<InactivePeriod> periods) =>
    periods.any((p) => p.startDay.compareTo(day) <= 0 && p.endDay.compareTo(day) >= 0);

  Future<bool> isInactiveToday() async {
    return _inactiveOn(_day(DateTime.now()), await getInactivePeriods());
  }

  Future<StreakStatus> getStreakStatus() async {
    final db = await database;
    final rows = await db.query('transactions', columns: ['created_at']);
    final completedDays = <String>{};
    for (final row in rows) {
      final date = DateTime.tryParse(row['created_at'] as String);
      if (date != null) completedDays.add(_day(date.toLocal()));
    }
    final rest = await getRestDays();
    final periods = await getInactivePeriods();
    final today = DateTime.now();
    final inactive = _inactiveOn(_day(today), periods);
    final resting = rest.contains(today.weekday);
    var streak = 0;
    var started = false;
    // Um dia de descanso ou inatividade preserva a sequência, mas não a aumenta.
    // Hoje ainda não concluído também não quebra a sequência até o dia terminar.
    for (var offset = 0; offset <= 36500; offset++) {
      final date = DateTime(today.year, today.month, today.day).subtract(Duration(days: offset));
      final key = _day(date);
      if (completedDays.contains(key)) {
        streak++;
        started = true;
      } else if (_inactiveOn(key, periods) || rest.contains(date.weekday) || (offset == 0)) {
        continue;
      } else {
        break;
      }
      if (started && streak >= completedDays.length) break;
    }
    return StreakStatus(streak, inactive, resting);
  }

  Future<List<Reward>> getRewards() async {
    final db = await database;
    final rows = await db.rawQuery('''
      SELECT r.*, (SELECT COUNT(*) FROM owned_rewards o
        WHERE o.reward_id = r.id) AS redeemed_count
      FROM rewards r ORDER BY r.id DESC
    ''');
    return rows.map(Reward.fromMap).toList();
  }

  Future<List<OwnedReward>> getOwnedRewards() async {
    final db = await database;
    final rows = await db.query('owned_rewards',
      where: 'hidden_at IS NULL',
      orderBy: 'purchased_at DESC, id DESC');
    return rows.map(OwnedReward.fromMap).toList();
  }

  Future<void> saveReward(Reward reward) async {
    final db = await database;
    if (reward.price <= 0 || (reward.maxRedemptions != null && reward.maxRedemptions! <= 0)) {
      throw StateError('Preço e limite devem ser positivos.');
    }
    if (reward.id == null) {
      await db.insert('rewards', reward.toMap());
    } else {
      final changed = await db.update('rewards', reward.toMap(),
        where: 'id = ?', whereArgs: [reward.id]);
      if (changed == 0) throw StateError('Recompensa não encontrada.');
    }
  }

  Future<void> deleteReward(int id) async {
    final db = await database;
    await db.delete('rewards', where: 'id = ?', whereArgs: [id]);
    // Compras anteriores são preservadas com nome e preço históricos.
  }

  Future<void> redeemReward(int rewardId) async {
    final db = await database;
    await db.transaction((txn) async {
      final rows = await txn.query('rewards', where: 'id = ?', whereArgs: [rewardId]);
      if (rows.isEmpty) throw StateError('Recompensa não encontrada.');
      final reward = Reward.fromMap({...rows.first, 'redeemed_count': 0});
      final count = Sqflite.firstIntValue(await txn.rawQuery(
        'SELECT COUNT(*) FROM owned_rewards WHERE reward_id = ?', [rewardId])) ?? 0;
      if (reward.maxRedemptions != null && count >= reward.maxRedemptions!) {
        throw StateError('Limite de resgates atingido.');
      }
      final wallet = await txn.query('wallet', where: 'id = 1');
      if (wallet.isEmpty || (wallet.first['coins'] as int) < reward.price) {
        throw StateError('Moedas insuficientes.');
      }
      await txn.rawUpdate('UPDATE wallet SET coins = coins - ? WHERE id = 1', [reward.price]);
      await txn.insert('owned_rewards', {
        'reward_id': rewardId, 'title_snapshot': reward.title,
        'description_snapshot': reward.description,
        'price_paid': reward.price, 'purchased_at': DateTime.now().toIso8601String(),
      });
    });
  }

  Future<void> useOwnedReward(int id) async {
    final db = await database;
    final changed = await db.update('owned_rewards',
      {'used_at': DateTime.now().toIso8601String()},
      where: 'id = ? AND used_at IS NULL', whereArgs: [id]);
    if (changed == 0) throw StateError('Recompensa já utilizada ou não encontrada.');
  }

  // Oculta apenas uma unidade já utilizada. O registro continua no banco
  // para preservar o histórico e a contagem de limites de resgate.
  Future<void> hideUsedReward(int id) async {
    final db = await database;
    final changed = await db.update('owned_rewards',
      {'hidden_at': DateTime.now().toIso8601String()},
      where: 'id = ? AND used_at IS NOT NULL AND hidden_at IS NULL',
      whereArgs: [id]);
    if (changed == 0) {
      throw StateError('A recompensa não está utilizada ou já foi removida.');
    }
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

  /// Inclui recompensas utilizadas e ocultadas, preservando conquistas.
  Future<int> getTotalRedemptions() async {
    final db = await database;
    return Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM owned_rewards')) ?? 0;
  }

  Future<Map<String, int>> getWallet() async {
    final db = await database;
    final rows = await db.query('wallet', where: 'id = 1');
    return {'coins': rows.first['coins'] as int, 'xp': rows.first['xp'] as int};
  }

  Future<List<PurchaseRecord>> getPurchaseHistory() async {
    final rows = await (await database).query('owned_rewards',
      columns: ['title_snapshot', 'price_paid', 'purchased_at'],
      orderBy: 'purchased_at DESC, id DESC');
    return rows.map((row) => PurchaseRecord(
      row['title_snapshot'] as String,
      row['price_paid'] as int,
      DateTime.parse(row['purchased_at'] as String),
    )).toList();
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
      final inactiveRows = await txn.query('inactive_periods',
        where: 'start_day <= ? AND end_day >= ?', whereArgs: [_day(now), _day(now)]);
      if (inactiveRows.isNotEmpty) throw StateError('Missões pausadas durante o tempo inativo.');
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
