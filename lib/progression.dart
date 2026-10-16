import 'package:flutter/material.dart';

/// Nível 1 começa em 0 XP. Cada nível exige 100 XP a mais que o anterior.
class LevelInfo {
  final int level, currentFloor, nextFloor;
  const LevelInfo(this.level, this.currentFloor, this.nextFloor);
  int get earnedInLevel => nextFloor - currentFloor;
  double progress(int xp) => ((xp - currentFloor) / earnedInLevel).clamp(0.0, 1.0);
}

LevelInfo levelForXp(int xp) {
  var level = 1;
  var floor = 0;
  while (xp >= floor + level * 100) {
    floor += level * 100;
    level++;
  }
  return LevelInfo(level, floor, floor + level * 100);
}

class Achievement {
  final String id, title, description;
  final IconData icon;
  final int goal, current;
  const Achievement(this.id, this.title, this.description, this.icon, this.goal, this.current);
  bool get unlocked => current >= goal;
  double get progress => (current / goal).clamp(0.0, 1.0);
}

List<Achievement> achievementsFor({required int xp, required int completions, required int purchases}) => [
  Achievement('first', 'Primeiro passo', 'Conclua sua primeira missão', Icons.flag_outlined, 1, completions),
  Achievement('five', 'Em movimento', 'Conclua 5 missões', Icons.directions_run, 5, completions),
  Achievement('ten', 'Constância', 'Conclua 10 missões', Icons.local_fire_department_outlined, 10, completions),
  Achievement('twentyfive', 'Determinação', 'Conclua 25 missões', Icons.emoji_events_outlined, 25, completions),
  Achievement('xp100', 'Aprendiz', 'Acumule 100 XP', Icons.auto_awesome, 100, xp),
  Achievement('xp500', 'Explorador', 'Acumule 500 XP', Icons.explore_outlined, 500, xp),
  Achievement('xp1000', 'Veterano', 'Acumule 1.000 XP', Icons.military_tech_outlined, 1000, xp),
  Achievement('buy1', 'Primeira conquista', 'Resgate sua primeira recompensa', Icons.card_giftcard, 1, purchases),
  Achievement('buy5', 'Colecionador', 'Resgate 5 recompensas', Icons.inventory_2_outlined, 5, purchases),
];
