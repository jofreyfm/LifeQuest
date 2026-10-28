import 'database_service.dart';
import 'mission.dart';

class ReminderScheduleEntry {
  final int missionId;
  final int notificationId;
  final String title;
  final String dateKey;
  final DateTime scheduledAt;

  const ReminderScheduleEntry({
    required this.missionId,
    required this.notificationId,
    required this.title,
    required this.dateKey,
    required this.scheduledAt,
  });
}

class ReminderSchedule {
  const ReminderSchedule._();

  static List<ReminderScheduleEntry> plan({
    required DateTime now,
    required List<Mission> missions,
    required Map<int, Map<String, Object?>> reminders,
    required List<InactivePeriod> inactivePeriods,
    int maxScheduledNotifications = 350,
    int maxDaysAhead = 30,
  }) {
    if (maxScheduledNotifications <= 0 || maxDaysAhead <= 0) return [];

    final missionsById = <int, Mission>{
      for (final mission in missions)
        if (mission.id != null) mission.id!: mission,
    };
    final activeReminders = <_ReminderItem>[];

    for (final entry in reminders.entries) {
      final mission = missionsById[entry.key];
      final reminder = entry.value;

      if (mission == null || reminder['enabled'] == 0) continue;
      if (mission.frequency == 'Única' && mission.completed) continue;

      final hour = reminder['hour'] as int?;
      final minute = reminder['minute'] as int?;
      if (hour == null || minute == null) continue;
      if (hour < 0 || hour > 23 || minute < 0 || minute > 59) continue;

      activeReminders.add(
        _ReminderItem(mission: mission, hour: hour, minute: minute),
      );
    }

    if (activeReminders.isEmpty) return [];

    activeReminders.sort((a, b) => a.mission.id!.compareTo(b.mission.id!));
    if (activeReminders.length > maxScheduledNotifications) {
      activeReminders.removeRange(
        maxScheduledNotifications,
        activeReminders.length,
      );
    }

    final daysAhead = (maxScheduledNotifications ~/ activeReminders.length)
        .clamp(1, maxDaysAhead)
        .toInt();
    final today = DateTime(now.year, now.month, now.day);
    final result = <ReminderScheduleEntry>[];

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
        final scheduledAt = DateTime(
          date.year,
          date.month,
          date.day,
          reminder.hour,
          reminder.minute,
        );
        if (!scheduledAt.isAfter(now)) continue;

        result.add(
          ReminderScheduleEntry(
            missionId: reminder.mission.id!,
            notificationId: reminder.mission.id! * 100 + offset,
            title: reminder.mission.title,
            dateKey: dateKey,
            scheduledAt: scheduledAt,
          ),
        );
      }
    }

    return result;
  }

  static String _dateKey(DateTime date) =>
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
