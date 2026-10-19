import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import 'database_service.dart';
import 'mission.dart';

class NotificationService {
  NotificationService._();

  static final NotificationService instance = NotificationService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;

  static const String _payloadPrefix = 'lifequest_reminder:';
  static const int _maxScheduledNotifications = 350;
  static const int _maxDaysAhead = 30;

  static const NotificationDetails _details = NotificationDetails(
    android: AndroidNotificationDetails(
      'lifequest_mission_reminders',
      'Lembretes de missões',
      channelDescription: 'Avisos nos horários definidos para suas missões.',
      importance: Importance.high,
      priority: Priority.high,
    ),
  );

  Future<void> initialize() async {
    if (_initialized) return;

    tz_data.initializeTimeZones();

    final localTimezone = await FlutterTimezone.getLocalTimezone();
    tz.setLocalLocation(tz.getLocation(localTimezone.identifier));

    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('ic_launcher'),
      ),
    );

    _initialized = true;
  }

  Future<void> requestPermissions() async {
    await initialize();

    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();

    await android?.requestNotificationsPermission();
    await android?.requestExactAlarmsPermission();
  }

  Future<void> syncReminders({
    required Map<int, Map<String, Object?>> reminders,
    required List<Mission> missions,
    required List<InactivePeriod> inactivePeriods,
  }) async {
    await initialize();

    // Cancela os agendamentos anteriores deste serviço para evitar duplicatas.
    final pending = await _plugin.pendingNotificationRequests();

    for (final notification in pending) {
      if (notification.payload?.startsWith(_payloadPrefix) ?? false) {
        await _plugin.cancel(id: notification.id);
      }
    }

    final missionsById = <int, Mission>{
      for (final mission in missions)
        if (mission.id != null) mission.id!: mission,
    };

    final activeReminders = <_ReminderItem>[];

    for (final entry in reminders.entries) {
      final mission = missionsById[entry.key];
      final reminder = entry.value;

      if (mission == null) continue;
      if (reminder['enabled'] == 0) continue;

      // Uma missão única já concluída não precisa de novos avisos.
      if (mission.frequency == 'Única' && mission.completed) {
        continue;
      }

      final hour = reminder['hour'] as int?;
      final minute = reminder['minute'] as int?;

      if (hour == null || minute == null) continue;

      if (hour < 0 || hour > 23 || minute < 0 || minute > 59) {
        continue;
      }

      activeReminders.add(
        _ReminderItem(
          mission: mission,
          hour: hour,
          minute: minute,
        ),
      );
    }

    if (activeReminders.isEmpty) return;

    // Limita a quantidade de alarmes pendentes no Android.
    activeReminders.sort(
      (a, b) => a.mission.id!.compareTo(b.mission.id!),
    );

    if (activeReminders.length > _maxScheduledNotifications) {
      activeReminders.removeRange(
        _maxScheduledNotifications,
        activeReminders.length,
      );
    }

    final daysAhead =
        (_maxScheduledNotifications ~/ activeReminders.length)
            .clamp(1, _maxDaysAhead)
            .toInt();

    final now = tz.TZDateTime.now(tz.local);
    final today = DateTime(now.year, now.month, now.day);

    for (var offset = 0; offset < daysAhead; offset++) {
      final date = today.add(Duration(days: offset));
      final dateKey = _dateKey(date);

      final inactive = inactivePeriods.any(
        (period) =>
            period.startDay.compareTo(dateKey) <= 0 &&
            period.endDay.compareTo(dateKey) >= 0,
      );

      if (inactive) continue;

      for (final reminder in activeReminders) {
        final scheduledDate = tz.TZDateTime(
          tz.local,
          date.year,
          date.month,
          date.day,
          reminder.hour,
          reminder.minute,
        );

        // Nunca agenda um horário que já passou.
        if (!scheduledDate.isAfter(now)) continue;

        // Cada missão recebe um ID diferente para cada dia.
        final notificationId = reminder.mission.id! * 100 + offset;

        final payload =
            '$_payloadPrefix${reminder.mission.id}:$dateKey';

        try {
          await _plugin.zonedSchedule(
  id: notificationId,
  title: reminder.mission.title,
  body: 'Está na hora de cumprir sua missão no LifeQuest.',
  scheduledDate: scheduledDate,
  notificationDetails: _details,
  androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
  payload: payload,
);
        } catch (_) {
          // Se o Android não permitir alarmes exatos, tenta o modo aproximado.
          await _plugin.zonedSchedule(
  id: notificationId,
  title: reminder.mission.title,
  body: 'Está na hora de cumprir sua missão no LifeQuest.',
  scheduledDate: scheduledDate,
  notificationDetails: _details,
  androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
  payload: payload,
);
        }
      }
    }
  }

  String _dateKey(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';
}

class _ReminderItem {
  final Mission mission;
  final int hour;
  final int minute;

  const _ReminderItem({
    required this.mission,
    required this.hour,
    required this.minute,
  });
}