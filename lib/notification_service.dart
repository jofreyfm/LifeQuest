import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import 'database_service.dart';
import 'mission.dart';
import 'reminder_schedule.dart';

class NotificationService extends WidgetsBindingObserver {
  NotificationService._();

  static final NotificationService instance = NotificationService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;
  Future<void> _syncQueue = Future<void>.value();
  Map<int, Map<String, Object?>>? _lastReminders;
  List<Mission>? _lastMissions;
  List<InactivePeriod>? _lastInactivePeriods;
  DateTime? _scheduleAnchorDate;

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
    if (!_initialized) {
      tz_data.initializeTimeZones();

      await _plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('ic_launcher'),
        ),
      );

      WidgetsBinding.instance.addObserver(this);
      _initialized = true;
    }

    await _updateLocalTimezone();
  }

  Future<void> _updateLocalTimezone() async {
    final localTimezone = await FlutterTimezone.getLocalTimezone();
    tz.setLocalLocation(tz.getLocation(localTimezone.identifier));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed ||
        !_initialized ||
        _lastReminders == null ||
        _lastMissions == null ||
        _lastInactivePeriods == null) {
      return;
    }

    unawaited(
      syncReminders(
        reminders: _lastReminders!,
        missions: _lastMissions!,
        inactivePeriods: _lastInactivePeriods!,
      ).catchError((Object error) {
        debugPrint('Erro ao atualizar lembretes: $error');
      }),
    );
  }

  Future<void> showDueReminders({
    required List<int> missionIds,
    required List<Mission> missions,
    required DateTime now,
  }) async {
    await initialize();

    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (android == null) return;

    final date = DateTime(now.year, now.month, now.day);
    final scheduleAnchor = _scheduleAnchorDate ?? date;
    final dateKey = _dateKey(date);
    final missionById = {
      for (final mission in missions)
        if (mission.id != null) mission.id!: mission,
    };
    final activeNotifications = await _plugin.getActiveNotifications();

    for (final missionId in missionIds) {
      final mission = missionById[missionId];
      if (mission == null) continue;

      final notificationId = ReminderSchedule.notificationIdFor(
        missionId: missionId,
        date: date,
        scheduleAnchor: scheduleAnchor,
      );
      final payload = '$_payloadPrefix$missionId:$dateKey';
      if (activeNotifications.any(
        (notification) =>
            notification.id == notificationId &&
            notification.payload == payload,
      )) {
        continue;
      }

      await _plugin.cancel(id: notificationId);
      await _plugin.show(
        id: notificationId,
        title: mission.title,
        body: 'Está na hora de cumprir sua missão no LifeQuest.',
        notificationDetails: _details,
        payload: payload,
      );
    }
  }

  String _dateKey(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';

  Future<void> requestPermissions() async {
    await initialize();

    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();

    await android?.requestNotificationsPermission();
    await android?.requestExactAlarmsPermission();
  }

  Future<void> syncReminders({
    required Map<int, Map<String, Object?>> reminders,
    required List<Mission> missions,
    required List<InactivePeriod> inactivePeriods,
  }) {
    final reminderSnapshot = {
      for (final entry in reminders.entries)
        entry.key: Map<String, Object?>.from(entry.value),
    };
    final missionSnapshot = List<Mission>.of(missions);
    final inactiveSnapshot = List<InactivePeriod>.of(inactivePeriods);
    _lastReminders = reminderSnapshot;
    _lastMissions = missionSnapshot;
    _lastInactivePeriods = inactiveSnapshot;

    final nextSync = _syncQueue
        .catchError((Object error) {
          debugPrint('Erro em sincronização anterior: $error');
        })
        .then(
          (_) => _syncSnapshot(
            reminders: reminderSnapshot,
            missions: missionSnapshot,
            inactivePeriods: inactiveSnapshot,
          ),
        );
    _syncQueue = nextSync;
    return nextSync;
  }

  Future<void> _syncSnapshot({
    required Map<int, Map<String, Object?>> reminders,
    required List<Mission> missions,
    required List<InactivePeriod> inactivePeriods,
  }) async {
    await initialize();

    // Cancela agendamentos anteriores para evitar duplicatas.
    final pending = await _plugin.pendingNotificationRequests();
    for (final notification in pending) {
      if (notification.payload?.startsWith(_payloadPrefix) ?? false) {
        await _plugin.cancel(id: notification.id);
      }
    }

    final now = tz.TZDateTime.now(tz.local);
    _scheduleAnchorDate = DateTime(now.year, now.month, now.day);
    final schedule = ReminderSchedule.plan(
      now: now,
      missions: missions,
      reminders: reminders,
      inactivePeriods: inactivePeriods,
      maxScheduledNotifications: _maxScheduledNotifications,
      maxDaysAhead: _maxDaysAhead,
    );

    for (final entry in schedule) {
      final scheduledDate = tz.TZDateTime(
        tz.local,
        entry.scheduledAt.year,
        entry.scheduledAt.month,
        entry.scheduledAt.day,
        entry.scheduledAt.hour,
        entry.scheduledAt.minute,
      );
      final payload = '$_payloadPrefix${entry.missionId}:${entry.dateKey}';

      try {
        await _plugin.zonedSchedule(
          id: entry.notificationId,
          title: entry.title,
          body: 'Está na hora de cumprir sua missão no LifeQuest.',
          scheduledDate: scheduledDate,
          notificationDetails: _details,
          androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
          payload: payload,
        );
      } catch (_) {
        // Se alarmes exatos não estiverem disponíveis, usa modo aproximado.
        try {
          await _plugin.zonedSchedule(
            id: entry.notificationId,
            title: entry.title,
            body: 'Está na hora de cumprir sua missão no LifeQuest.',
            scheduledDate: scheduledDate,
            notificationDetails: _details,
            androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
            payload: payload,
          );
        } catch (e) {
          // Se ambos falharem, loga o erro mas não propaga para não quebrar o agendamento dos outros lembretes.
          debugPrint('Falha ao agendar lembrete ${entry.missionId}: $e');
        }
      }
    }
  }
}
