import 'package:flutter_test/flutter_test.dart';
import 'package:lifequest/database_service.dart';
import 'package:lifequest/mission.dart';
import 'package:lifequest/reminder_schedule.dart';

void main() {
  group('ReminderSchedule.plan', () {
    final now = DateTime(2026, 10, 27, 10, 15);
    final missions = [
      const Mission(id: 1, title: 'Leitura', points: 10),
      const Mission(id: 2, title: 'Exercício', points: 10),
      const Mission(
        id: 3,
        title: 'Missão única concluída',
        frequency: 'Única',
        completed: true,
        points: 10,
      ),
      const Mission(id: 4, title: 'Lembrete desativado', points: 10),
    ];

    test('schedules future reminders and respects inactive periods', () {
      final result = ReminderSchedule.plan(
        now: now,
        missions: missions,
        reminders: {
          1: {'hour': 11, 'minute': 30, 'enabled': 1},
          2: {'hour': 9, 'minute': 0, 'enabled': 1},
          3: {'hour': 12, 'minute': 0, 'enabled': 1},
          4: {'hour': 12, 'minute': 0, 'enabled': 0},
        },
        inactivePeriods: const [InactivePeriod(1, '2026-10-28', '2026-10-28')],
        maxScheduledNotifications: 6,
        maxDaysAhead: 3,
      );

      expect(result.map((item) => (item.missionId, item.scheduledAt)), [
        (1, DateTime(2026, 10, 27, 11, 30)),
        (1, DateTime(2026, 10, 29, 11, 30)),
        (2, DateTime(2026, 10, 29, 9)),
      ]);
      expect(result.map((item) => item.notificationId), [100, 102, 202]);
    });

    test('limits the schedule horizon and notification count', () {
      final result = ReminderSchedule.plan(
        now: now,
        missions: missions.take(1).toList(),
        reminders: {
          1: {'hour': 11, 'minute': 30, 'enabled': 1},
        },
        inactivePeriods: const [],
        maxScheduledNotifications: 3,
        maxDaysAhead: 30,
      );

      expect(result, hasLength(3));
      expect(result.map((item) => item.scheduledAt), [
        DateTime(2026, 10, 27, 11, 30),
        DateTime(2026, 10, 28, 11, 30),
        DateTime(2026, 10, 29, 11, 30),
      ]);
    });
  });
}
