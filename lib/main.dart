import 'dart:async';
import 'dart:ui' show FontFeature;
import 'package:flutter/material.dart';
import 'database_service.dart';
import 'mission.dart';
import 'reward.dart';
import 'progression.dart';

void main() => runApp(const LifeQuestApp());

class LifeQuestApp extends StatelessWidget {
  const LifeQuestApp({super.key});
  static const purple = Color(0xFF9568F5);
  static const bg = Color(0xFF101016);
  static const surface = Color(0xFF1D1D29);

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    title: 'LifeQuest',
    theme: ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: bg,
      colorScheme: ColorScheme.fromSeed(seedColor: purple, brightness: Brightness.dark),
      cardTheme: CardThemeData(color: surface, elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18))),
    ),
    home: const LifeQuestHome(),
  );
}

class LifeQuestHome extends StatefulWidget {
  const LifeQuestHome({super.key});
  @override
  State<LifeQuestHome> createState() => _LifeQuestHomeState();
}

class _LifeQuestHomeState extends State<LifeQuestHome> {
  final db = DatabaseService.instance;
  List<Mission> missions = [];
  int coins = 0, xp = 0, tab = 0;
  bool loading = true;
  List<CompletionRecord> history = [];
  List<PurchaseRecord> purchasesHistory = [];
  DateTime calendarMonth = DateTime(DateTime.now().year, DateTime.now().month);
  int statsRange = 30;
  List<Reward> rewards = [];
  List<OwnedReward> ownedRewards = [];
  int shopTab = 0;
  int totalRedemptions = 0;
  StreakStatus streak = const StreakStatus(0, false, false);
  Set<int> restDays = {};
  List<InactivePeriod> inactivePeriods = [];
  Map<String, int> weeklyGoal = {'target': 5, 'bonus': 30, 'completed': 0, 'claimed': 0};
  int focusSecondsRange = 0;
  Map<int, Map<String, Object?>> reminders = {};
  final List<String> reminderInbox = [];
  Timer? reminderTimer;


  @override
  void initState() {
    super.initState();
    refresh().then((_) => checkReminders());
    reminderTimer = Timer.periodic(const Duration(seconds: 15), (_) => checkReminders());
  }

  @override
  void dispose() {
    reminderTimer?.cancel();
    super.dispose();
  }

  Future<void> checkReminders() async {
    if (!mounted || loading) return;
    try {
      if (streak.inactiveToday) return;
      final due = await db.consumeDueReminders(DateTime.now());
      if (!mounted || due.isEmpty) return;
      final names = {for (final mission in missions) mission.id: mission.title};
      setState(() {
        for (final id in due) {
          reminderInbox.insert(0, 'Hora de: ${names[id] ?? 'Missão'}');
        }
      });
      message(due.length == 1 ? 'Você tem um lembrete de missão!' :
        'Você tem ${due.length} lembretes de missões!');
    } catch (error) {
      // Falhas de leitura não impedem o uso do aplicativo.
    }
  }


  Future<void> refresh() async {
    try {
      final items = await db.getMissions();
      final wallet = await db.getWallet();
      final records = await db.getHistory();
      final purchasesRecords = await db.getPurchaseHistory();
      final rewardItems = await db.getRewards();
      final purchases = await db.getOwnedRewards();
      final redemptions = await db.getTotalRedemptions();
      final streakInfo = await db.getStreakStatus();
      final rests = await db.getRestDays();
      final periods = await db.getInactivePeriods();
      final weekly = await db.getWeeklyGoal();
      final savedReminders = await db.getReminders();
      final today = DateTime.now();
      final focusStart = DateTime(today.year, today.month, today.day).subtract(Duration(days: statsRange - 1));
      final focused = await db.getFocusSecondsSince(focusStart);
      if (!mounted) return;
      setState(() {
        missions = items;
        coins = wallet['coins']!;
        xp = wallet['xp']!;
        history = records;
        purchasesHistory = purchasesRecords;
        rewards = rewardItems;
        ownedRewards = purchases;
        totalRedemptions = redemptions;
        streak = streakInfo;
        restDays = rests;
        inactivePeriods = periods;
        weeklyGoal = weekly;
        reminders = savedReminders;
        focusSecondsRange = focused;
        loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => loading = false);
      message('Erro ao carregar dados: $error');
    }
  }

  void message(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> editMission([Mission? mission]) async {
    final result = await showDialog<Mission>(
      context: context,
      builder: (_) => MissionEditorDialog(mission: mission),
    );
    if (result == null || !mounted) return;
    try {
      await db.saveMission(result);
      await refresh();
    } catch (error) {
      message('Erro ao salvar missão: $error');
    }
  }

  Future<void> configureReminder(Mission mission) async {
    if (mission.id == null) return;
    final saved = reminders[mission.id];
    TimeOfDay selected = TimeOfDay(
      hour: (saved?['hour'] as int?) ?? 9,
      minute: (saved?['minute'] as int?) ?? 0);
    final action = await showDialog<String>(context: context, builder: (dialogContext) =>
      StatefulBuilder(builder: (dialogContext, update) => AlertDialog(
        title: Text('Lembrete: ${mission.title}'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('Aviso diário enquanto o aplicativo estiver aberto.'),
          const SizedBox(height: 12),
          OutlinedButton.icon(icon: const Icon(Icons.schedule),
            label: Text(selected.format(dialogContext)),
            onPressed: () async {
              final time = await showTimePicker(context: dialogContext,
                initialTime: selected);
              if (time != null) update(() => selected = time);
            }),
        ]),
        actions: [
          if (saved != null) TextButton(onPressed: () => Navigator.pop(dialogContext, 'remove'),
            child: const Text('Desativar')),
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, 'save'),
            child: const Text('Salvar')),
        ],
      )));
    try {
      if (action == 'save') {
        await db.saveReminder(mission.id!, selected.hour, selected.minute);
      } else if (action == 'remove') {
        await db.removeReminder(mission.id!);
      } else { return; }
      await refresh();
      if (action == 'save') await checkReminders();
    } catch (error) { message('Erro ao configurar lembrete: $error'); }
  }

  Widget remindersPage() => ListView(padding: const EdgeInsets.all(16), children: [
    const Text('Lembretes de missões', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
    const SizedBox(height: 8),
    const Text('Os avisos aparecem dentro do LifeQuest enquanto ele estiver aberto. '
      'Não são notificações do sistema Android.'),
    const SizedBox(height: 16),
    if (reminderInbox.isNotEmpty) Card(child: Column(children: [
      const ListTile(title: Text('Avisos recebidos'), leading: Icon(Icons.notifications_active_outlined)),
      ...reminderInbox.take(20).map((item) => ListTile(title: Text(item))),
      TextButton(onPressed: () => setState(reminderInbox.clear),
        child: const Text('Limpar avisos desta sessão')),
    ])),
    ...missions.where((m) => m.id != null).map((mission) {
      final saved = reminders[mission.id];
      final hour = saved?['hour'] as int?;
      final minute = saved?['minute'] as int?;
      final time = hour == null || minute == null ? 'Sem lembrete' :
        '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
      return Card(child: ListTile(
        leading: Icon(saved == null ? Icons.notifications_none : Icons.notifications_active_outlined),
        title: Text(mission.title), subtitle: Text(time),
        trailing: const Icon(Icons.edit_outlined),
        onTap: () => configureReminder(mission),
      ));
    }),
  ]);

  Future<void> changeProgress(Mission mission) async {
    if (streak.inactiveToday) {
      message('Tempo inativo ativado: missões e pontos estão pausados.');
      return;
    }
    double progress = mission.progress.toDouble();
    final result = await showDialog<int>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: Text(mission.title),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('Progresso: ${progress.round()}%'),
            Slider(value: progress, min: 0, max: 100, divisions: 20,
              onChanged: (value) => update(() => progress = value)),
            const Text('Moedas e XP são concedidos apenas ao atingir 100%.'),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancelar')),
            FilledButton(onPressed: () => Navigator.pop(dialogContext, progress.round()),
              child: const Text('Salvar progresso')),
          ],
        ),
      ),
    );
    if (result == null) return;
    try {
      final beforeXp = xp;
      final beforeCompletions = history.length;
      final completed = await db.updateProgress(mission, result);
      await refresh();
      if (completed && mounted) {
        message('Missão concluída! +${mission.points} moedas e XP');
        showProgressAlerts(beforeXp: beforeXp, beforeCompletions: beforeCompletions,
          beforePurchases: totalRedemptions);
      }
    } catch (error) {
      message('Erro ao atualizar progresso: $error');
    }
  }

  Future<void> removeMission(Mission mission) async {
    final confirmed = await showDialog<bool>(context: context, builder: (dialogContext) => AlertDialog(
      title: const Text('Excluir missão?'),
      content: Text('Excluir "${mission.title}"? O histórico de moedas não será apagado.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancelar')),
        TextButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Excluir')),
      ],
    ));
    if (confirmed == true) {
      try {
        await db.deleteMission(mission.id!);
        await refresh();
      } catch (error) {
        message('Erro ao excluir missão: $error');
      }
    }
  }

  Future<void> editReward([Reward? reward]) async {
    final result = await showDialog<Reward>(
      context: context, builder: (_) => RewardEditorDialog(reward: reward));
    if (result == null || !mounted) return;
    try {
      await db.saveReward(result);
      await refresh();
      message(reward == null ? 'Recompensa criada!' : 'Recompensa atualizada!');
    } catch (error) {
      message('Erro ao salvar recompensa: $error');
    }
  }

  Future<void> removeReward(Reward reward) async {
    final confirm = await showDialog<bool>(context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Excluir recompensa?'),
        content: Text('Excluir "${reward.title}" da loja? As unidades já adquiridas serão mantidas.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Excluir')),
        ],
      ));
    if (confirm != true) return;
    try {
      await db.deleteReward(reward.id!);
      await refresh();
    } catch (error) {
      message('Erro ao excluir recompensa: $error');
    }
  }

  Future<void> buyReward(Reward reward) async {
    if (coins < reward.price || !reward.available) return;
    final confirm = await showDialog<bool>(context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Confirmar resgate'),
        content: Text('Trocar ${reward.price} moedas por "${reward.title}"? Ela ficará na lista Adquiridas para usar depois.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Resgatar')),
        ],
      ));
    if (confirm != true) return;
    try {
      final previousPurchases = totalRedemptions;
      await db.redeemReward(reward.id!);
      await refresh();
      if (mounted) showProgressAlerts(beforeXp: xp, beforeCompletions: history.length,
        beforePurchases: previousPurchases);
      if (!mounted) return;
      setState(() => shopTab = 1);
      message('Recompensa adquirida!');
    } catch (error) {
      message('Erro ao resgatar: $error');
    }
  }

  Future<void> useReward(OwnedReward reward) async {
    final confirm = await showDialog<bool>(context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Marcar como utilizada?'),
        content: Text('Você já utilizou "${reward.title}"? Esta ação não pode ser desfeita.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Confirmar uso')),
        ],
      ));
    if (confirm != true) return;
    try {
      await db.useOwnedReward(reward.id);
      await refresh();
      message('Recompensa marcada como utilizada!');
    } catch (error) {
      message('Erro ao utilizar recompensa: $error');
    }
  }

  Future<void> hideUsedReward(OwnedReward reward) async {
    if (!reward.used) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Remover da lista?'),
        content: Text('Remover "${reward.title}" das recompensas adquiridas? '
            'O registro de resgate e as moedas gastas serão preservados.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Remover')),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    try {
      await db.hideUsedReward(reward.id);
      await refresh();
      message('Recompensa removida da lista.');
    } catch (error) {
      message('Erro ao remover recompensa: $error');
    }
  }

  void showProgressAlerts({required int beforeXp, required int beforeCompletions,
      required int beforePurchases}) {
    if (!mounted) return;
    final oldLevel = levelForXp(beforeXp).level;
    final newLevel = levelForXp(xp).level;
    final oldBadges = achievementsFor(xp: beforeXp, completions: beforeCompletions,
      purchases: beforePurchases);
    final newBadges = achievementsFor(xp: xp, completions: history.length,
      purchases: totalRedemptions);
    final unlocked = <String>[];
    for (var i = 0; i < newBadges.length; i++) {
      if (!oldBadges[i].unlocked && newBadges[i].unlocked) unlocked.add(newBadges[i].title);
    }
    if (newLevel == oldLevel && unlocked.isEmpty) return;
    final details = [
      if (newLevel > oldLevel) 'Você alcançou o nível $newLevel!',
      if (unlocked.isNotEmpty) 'Conquistas desbloqueadas: ${unlocked.join(', ')}',
    ].join('\n\n');
    // Notificação interna: não exige permissões do Android.
    showDialog<void>(context: context, builder: (dialogContext) => AlertDialog(
      title: const Row(children: [Icon(Icons.emoji_events, color: Colors.amber),
        SizedBox(width: 10), Text('Parabéns!')]),
      content: Text(details),
      actions: [FilledButton(onPressed: () => Navigator.pop(dialogContext),
        child: const Text('Continuar'))],
    ));
  }

  Widget profilePage() {
    final level = levelForXp(xp);
    final achievements = achievementsFor(xp: xp, completions: history.length,
      purchases: totalRedemptions);
    // Exibe as conquistas desbloqueadas primeiro, mantendo a ordem original
    // dentro dos grupos de desbloqueadas e pendentes.
    final orderedAchievements = [
      ...achievements.where((a) => a.unlocked),
      ...achievements.where((a) => !a.unlocked),
    ];
    final unlocked = achievements.where((a) => a.unlocked).length;
    return ListView(padding: const EdgeInsets.all(16), children: [
      const Text('Meu perfil', style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
      const SizedBox(height: 14),
      Card(child: Padding(padding: const EdgeInsets.all(20), child: Column(children: [
        const CircleAvatar(radius: 34, backgroundColor: LifeQuestApp.purple,
          child: Icon(Icons.person, size: 36, color: Colors.white)),
        const SizedBox(height: 12),
        Text('Nível ${level.level}', style: const TextStyle(fontSize: 27, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Text('$xp XP total • ${xp - level.currentFloor}/${level.earnedInLevel} XP neste nível'),
        const SizedBox(height: 12),
        LinearProgressIndicator(value: level.progress(xp), minHeight: 10,
          borderRadius: BorderRadius.circular(10)),
        const SizedBox(height: 8),
        Text('Próximo nível em ${level.nextFloor - xp} XP',
          style: const TextStyle(color: Colors.white70)),
      ]))),
      const SizedBox(height: 12),
      Row(children: [
        Expanded(child: Card(child: Padding(padding: const EdgeInsets.all(14),
          child: Column(children: [const Icon(Icons.task_alt, color: LifeQuestApp.purple),
            Text('${history.length}', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
            const Text('Conclusões')])))),
        Expanded(child: Card(child: Padding(padding: const EdgeInsets.all(14),
          child: Column(children: [const Icon(Icons.card_giftcard, color: LifeQuestApp.purple),
            Text('$totalRedemptions', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
            const Text('Resgates')])))),
      ]),
      const SizedBox(height: 20),
      Text('Conquistas ($unlocked/${achievements.length})',
        style: const TextStyle(fontSize: 21, fontWeight: FontWeight.bold)),
      const SizedBox(height: 10),
      ...orderedAchievements.map((a) => Card(child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 7), child: Column(children: [
          ListTile(
            leading: Icon(a.unlocked ? Icons.emoji_events : a.icon,
              color: a.unlocked ? Colors.amber : Colors.white54),
            title: Text(a.title),
            subtitle: Text(a.description),
            trailing: a.unlocked ? const Icon(Icons.check_circle, color: Colors.green)
              : Text('${a.current}/${a.goal}', style: const TextStyle(color: Colors.white70)),
          ),
          if (!a.unlocked) Padding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: LinearProgressIndicator(value: a.progress, minHeight: 5,
              borderRadius: BorderRadius.circular(8))),
        ]),
      ))),
    ]);
  }

  Widget shopPage() => Column(children: [
    Padding(padding: const EdgeInsets.fromLTRB(16, 16, 16, 8), child: Column(
      crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Expanded(child: Text('Loja de recompensas',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold))),
          const Icon(Icons.monetization_on, color: Colors.amber),
          const SizedBox(width: 5), Text('$coins', style: const TextStyle(fontSize: 20)),
        ]),
        const SizedBox(height: 12),
        SegmentedButton<int>(
          segments: const [ButtonSegment(value: 0, label: Text('Loja')),
            ButtonSegment(value: 1, label: Text('Adquiridas'))],
          selected: {shopTab}, onSelectionChanged: (v) => setState(() => shopTab = v.first),
        ),
      ],
    )),
    Expanded(child: shopTab == 0 ? ListView(padding: const EdgeInsets.all(16), children: [
      if (rewards.isEmpty) const Card(child: Padding(padding: EdgeInsets.all(20),
        child: Text('Nenhuma recompensa na loja. Toque em + para criar uma.'))),
      ...rewards.map((reward) => Card(child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(children: [
          ListTile(
            leading: const Icon(Icons.card_giftcard, color: LifeQuestApp.purple),
            title: Text(reward.title),
            subtitle: Text([reward.category, if (reward.description.isNotEmpty) reward.description].join(' • ')),
            trailing: PopupMenuButton<String>(
              onSelected: (value) => value == 'edit' ? editReward(reward) : removeReward(reward),
              itemBuilder: (_) => const [PopupMenuItem(value: 'edit', child: Text('Editar')),
                PopupMenuItem(value: 'delete', child: Text('Excluir'))],
            ),
          ),
          Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: Row(children: [
            const Icon(Icons.monetization_on, size: 18, color: Colors.amber),
            Text(' ${reward.price} moedas'),
            const SizedBox(width: 10),
            Expanded(child: Text(reward.maxRedemptions == null ? 'Sem limite' :
              '${reward.redeemedCount}/${reward.maxRedemptions} resgates',
              textAlign: TextAlign.end, style: const TextStyle(fontSize: 12))),
            const SizedBox(width: 8),
            FilledButton(onPressed: coins >= reward.price && reward.available
              ? () => buyReward(reward) : null,
              child: Text(!reward.available ? 'Esgotada' : 'Resgatar')),
          ])),
        ]),
      ))),
    ]) : ListView(padding: const EdgeInsets.all(16), children: [
      if (ownedRewards.isEmpty) const Card(child: Padding(padding: EdgeInsets.all(20),
        child: Text('Você ainda não adquiriu recompensas.'))),
      ...ownedRewards.map((reward) => Card(child: ListTile(
        leading: Icon(reward.used ? Icons.check_circle : Icons.redeem,
          color: reward.used ? Colors.green : LifeQuestApp.purple),
        title: Text(reward.title),
        subtitle: Text('${reward.used ? 'Utilizada' : 'Disponível'} • Adquirida ${formatDate(reward.purchasedAt)}'
          '${reward.usedAt == null ? '' : '\nUtilizada ${formatDate(reward.usedAt!)}'}'),
        isThreeLine: reward.used,
        trailing: reward.used
          ? IconButton(
              tooltip: 'Remover recompensa utilizada',
              icon: const Icon(Icons.delete_outline),
              onPressed: () => hideUsedReward(reward),
            )
          : TextButton(
              onPressed: () => useReward(reward), child: const Text('Utilizar')),
      ))),
    ])),
  ]);

  String formatDate(DateTime date) => '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year} às ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';

  Widget historyPage() => ListView(padding: const EdgeInsets.all(16), children: [
    const Text('Histórico de conclusões', style: TextStyle(fontSize: 25, fontWeight: FontWeight.bold)),
    const SizedBox(height: 12),
    if (history.isEmpty) const Card(child: Padding(
      padding: EdgeInsets.all(20), child: Text('Você ainda não concluiu missões.'))),
    ...history.map((record) => Card(child: ListTile(
      leading: const Icon(Icons.check_circle, color: Colors.green),
      title: Text(record.title),
      subtitle: Text(formatDate(record.when)),
      trailing: Text('+${record.points}', style: const TextStyle(color: LifeQuestApp.purple)),
    ))),
  ]);

  Future<void> openTimer(Mission mission) async {
    if (streak.inactiveToday) {
      message('Cronômetro indisponível durante o período inativo.');
      return;
    }
    await showDialog<void>(context: context, barrierDismissible: false,
      builder: (_) => FocusTimerDialog(mission: mission, db: db));
    await refresh();
  }

  Future<void> editWeeklyGoal() async {
    final target = TextEditingController(text: '${weeklyGoal['target']}');
    final bonus = TextEditingController(text: '${weeklyGoal['bonus']}');
    final result = await showDialog<List<int>>(context: context, builder: (_) => AlertDialog(
      title: const Text('Meta semanal'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: target, keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'Missões concluídas na semana')),
        TextField(controller: bonus, keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'Bônus em moedas')),
      ]),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(onPressed: () {
          final a = int.tryParse(target.text);
          final b = int.tryParse(bonus.text);
          if (a != null && b != null) Navigator.pop(context, [a,b]);
        }, child: const Text('Salvar'))],
    ));
    // Controladores locais não são descartados durante a animação de saída.
    if (result == null) return;
    try { await db.setWeeklyGoal(result[0], result[1]); await refresh(); }
    catch (e) { message('$e'); }
  }

  Future<void> claimBonus() async {
    try {
      final amount = await db.claimWeeklyBonus();
      await refresh();
      message('Bônus semanal resgatado: +$amount moedas!');
    } catch (e) { message('$e'); }
  }

  Widget weeklyGoalCard() {
    final target = weeklyGoal['target'] ?? 5;
    final completed = weeklyGoal['completed'] ?? 0;
    final bonus = weeklyGoal['bonus'] ?? 30;
    final claimed = weeklyGoal['claimed'] == 1;
    return Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(
      crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [const Icon(Icons.card_giftcard, color: LifeQuestApp.purple),
          const SizedBox(width: 10), const Expanded(child: Text('Meta semanal',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold))),
          IconButton(tooltip: 'Editar meta', icon: const Icon(Icons.settings_outlined),
            onPressed: editWeeklyGoal)]),
        Text('$completed de $target missões • Bônus: $bonus moedas'),
        const SizedBox(height: 10),
        LinearProgressIndicator(value: (completed / target).clamp(0.0, 1.0), minHeight: 7),
        const SizedBox(height: 10),
        if (claimed) const Text('Bônus desta semana já resgatado ✓')
        else if (completed >= target) FilledButton.icon(
          onPressed: claimBonus, icon: const Icon(Icons.redeem),
          label: const Text('Resgatar bônus'))
        else const Text('Conclua missões nesta semana para liberar o bônus.',
          style: TextStyle(color: Colors.white70)),
      ])));
  }

  Widget missionCard(Mission mission) => Card(
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(children: [
        ListTile(
          leading: Icon(mission.completed ? Icons.check_circle : Icons.task_alt,
            color: mission.completed ? Colors.green : LifeQuestApp.purple),
          title: Text(mission.title),
          subtitle: Text('${mission.category} • ${mission.frequency} • +${mission.points} moedas/XP'),
          trailing: PopupMenuButton<String>(
            onSelected: (value) => value == 'edit' ? editMission(mission) : removeMission(mission),
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'edit', child: Text('Editar')),
              PopupMenuItem(value: 'delete', child: Text('Excluir')),
            ],
          ),
        ),
        if (streak.inactiveToday)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: LifeQuestApp.purple.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: LifeQuestApp.purple.withValues(alpha: 0.35)),
              ),
              child: Row(children: [
                const Icon(Icons.pause_circle_outline, color: LifeQuestApp.purple),
                const SizedBox(width: 10),
                const Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Missão pausada', style: TextStyle(fontWeight: FontWeight.bold)),
                    SizedBox(height: 3),
                    Text('Você está em um período inativo. O progresso fica bloqueado até o fim desse período ou até removê-lo.',
                      style: TextStyle(fontSize: 12)),
                  ],
                )),
                IconButton(
                  tooltip: 'Ver ou alterar períodos inativos',
                  onPressed: () => setState(() => tab = 7),
                  icon: const Icon(Icons.settings_outlined),
                ),
              ]),
            ),
          ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(children: [
            Expanded(child: LinearProgressIndicator(
              value: mission.progress / 100,
              minHeight: 7, borderRadius: BorderRadius.circular(8),
            )),
            const SizedBox(width: 12),
            Text('${mission.progress}%'),
            const SizedBox(width: 8),
            IconButton(
              tooltip: 'Cronômetro da missão',
              onPressed: streak.inactiveToday ? null : () => openTimer(mission),
              icon: const Icon(Icons.timer_outlined),
            ),
            IconButton(
              tooltip: 'Atualizar progresso',
              onPressed: mission.completed || streak.inactiveToday ? null : () => changeProgress(mission),
              icon: const Icon(Icons.edit_note),
            ),
          ]),
        ),
      ]),
    ),
  );

  Widget overview() {
    final finished = missions.where((m) => m.completed).length;
    return ListView(padding: const EdgeInsets.all(16), children: [
      const Text('Bem-vindo ao LifeQuest', style: TextStyle(fontSize: 25, fontWeight: FontWeight.bold)),
      const SizedBox(height: 8),
      const Text('Transforme sua rotina em conquistas.', style: TextStyle(color: Colors.white60)),
      const SizedBox(height: 18),
      Row(children: [
        Expanded(child: Card(child: Padding(padding: const EdgeInsets.all(18),
          child: Column(children: [const Icon(Icons.monetization_on, color: Colors.amber),
            Text('$coins', style: const TextStyle(fontSize: 25, fontWeight: FontWeight.bold)),
            const Text('Moedas')])))),
        Expanded(child: Card(child: Padding(padding: const EdgeInsets.all(18),
          child: Column(children: [const Icon(Icons.auto_awesome, color: LifeQuestApp.purple),
            Text('$xp', style: const TextStyle(fontSize: 25, fontWeight: FontWeight.bold)),
            const Text('XP total')])))),
      ]),
      const SizedBox(height: 14),
      Card(child: ListTile(
        leading: const Icon(Icons.emoji_events, color: Colors.amber),
        title: Text('Nível ${levelForXp(xp).level}'),
        subtitle: Text('${levelForXp(xp).nextFloor - xp} XP até o próximo nível'),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => setState(() => tab = 6),
      )),
      const SizedBox(height: 12),
      Card(child: ListTile(
        leading: const Icon(Icons.local_fire_department, color: Colors.deepOrangeAccent),
        title: Text('Sequência: ${streak.days} dias'),
        subtitle: Text(streak.inactiveToday ? 'Tempo inativo: missões pausadas' :
          streak.restingToday ? 'Dia de descanso: sequência preservada' :
          'Conclua uma missão hoje para avançar'),
        trailing: const Icon(Icons.settings_outlined),
        onTap: () => setState(() => tab = 7),
      )),
      weeklyGoalCard(),
      const SizedBox(height: 20),
      Text('Missões ($finished/${missions.length} concluídas)',
        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
      const SizedBox(height: 10),
      if (missions.isEmpty) const Card(child: Padding(padding: EdgeInsets.all(20),
        child: Text('Nenhuma missão ainda. Toque em + para criar a primeira!'))),
      ...missions.map(missionCard),
    ]);
  }

  Widget missionList() => ListView(padding: const EdgeInsets.all(16), children: [
    const Text('Minhas missões', style: TextStyle(fontSize: 25, fontWeight: FontWeight.bold)),
    const SizedBox(height: 12),
    weeklyGoalCard(),
    ...missions.map(missionCard),
    if (missions.isEmpty) const Text('Crie uma missão usando o botão +.'),
  ]);

  Future<void> toggleRestDay(int day, bool value) async {
    try {
      await db.setRestDay(day, value);
      await refresh();
    } catch (e) { message('Erro ao atualizar descanso: $e'); }
  }

  Future<void> addInactive() async {
    final now = DateTime.now();
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 2),
      lastDate: DateTime(now.year + 5),
      initialDateRange: DateTimeRange(start: now, end: now),
      helpText: 'Selecionar tempo inativo',
    );
    if (range == null || !mounted) return;
    try {
      await db.addInactivePeriod(range.start, range.end);
      await refresh();
    } catch (e) { message('Erro ao salvar período: $e'); }
  }

  Future<void> removeInactive(InactivePeriod period) async {
    final confirmed = await showDialog<bool>(context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remover tempo inativo?'),
        content: const Text('Dias sem missões fora do período poderão interromper a sequência.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Remover')),
        ],
      ));
    if (confirmed != true) return;
    try {
      await db.deleteInactivePeriod(period.id);
      await refresh();
    } catch (e) { message('Erro ao remover período: $e'); }
  }

  Widget streakSettings() {
    const weekdays = ['Segunda-feira', 'Terça-feira', 'Quarta-feira',
      'Quinta-feira', 'Sexta-feira', 'Sábado', 'Domingo'];
    return ListView(padding: const EdgeInsets.all(16), children: [
      const Text('Sequência e pausas', style: TextStyle(fontSize: 25, fontWeight: FontWeight.bold)),
      const SizedBox(height: 12),
      Card(child: ListTile(
        leading: const Icon(Icons.local_fire_department, color: Colors.deepOrangeAccent),
        title: Text('${streak.days} dias de sequência'),
        subtitle: Text(streak.inactiveToday ? 'Tempo inativo ativo' :
          streak.restingToday ? 'Hoje é dia de descanso' : 'Hoje é dia ativo'),
      )),
      const SizedBox(height: 12),
      const Text('Dias de descanso', style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold)),
      const Text('Preservam a sequência, mas não acrescentam dias. Missões ainda podem ser concluídas nesses dias.'),
      ...List.generate(7, (i) => SwitchListTile(
        title: Text(weekdays[i]),
        value: restDays.contains(i + 1),
        onChanged: (v) => toggleRestDay(i + 1, v),
      )),
      const SizedBox(height: 16),
      const Text('Tempo inativo', style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold)),
      const Text('Viagens, acampamentos ou doenças: pausa missões e ganhos de moedas/XP; a sequência é preservada.'),
      const SizedBox(height: 10),
      FilledButton.icon(onPressed: addInactive, icon: const Icon(Icons.add),
        label: const Text('Adicionar período')),
      if (inactivePeriods.isEmpty) const Padding(padding: EdgeInsets.all(12),
        child: Text('Nenhum período cadastrado.')),
      ...inactivePeriods.map((p) => Card(child: ListTile(
        title: Text('${p.startDay} até ${p.endDay}'),
        trailing: IconButton(tooltip: 'Remover período',
          onPressed: () => removeInactive(p), icon: const Icon(Icons.delete_outline)),
      ))),
    ]);
  }

  String dateKey(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Widget calendarPage() {
    const monthNames = ['janeiro','fevereiro','março','abril','maio','junho',
      'julho','agosto','setembro','outubro','novembro','dezembro'];
    final counts = <String,int>{};
    final points = <String,int>{};
    for (final record in history) {
      final key = dateKey(record.when.toLocal());
      counts[key] = (counts[key] ?? 0) + 1;
      points[key] = (points[key] ?? 0) + record.points;
    }
    final first = DateTime(calendarMonth.year, calendarMonth.month, 1);
    final daysInMonth = DateTime(first.year, first.month + 1, 0).day;
    final offset = first.weekday - 1;
    final today = DateTime.now();
    final activeDays = counts.entries.where((e) => e.key.startsWith(
      '${first.year}-${first.month.toString().padLeft(2, '0')}-')).length;
    final totalMonth = points.entries.where((e) => e.key.startsWith(
      '${first.year}-${first.month.toString().padLeft(2, '0')}-'))
      .fold<int>(0, (sum, e) => sum + e.value);
    return ListView(padding: const EdgeInsets.all(16), children: [
      const Text('Calendário de atividades', style: TextStyle(fontSize: 23, fontWeight: FontWeight.bold)),
      const SizedBox(height: 8),
      const Text('Os dias destacados representam missões concluídas.'),
      const SizedBox(height: 16),
      Card(child: Padding(padding: const EdgeInsets.all(12), child: Column(children: [
        Row(children: [
          IconButton(tooltip: 'Mês anterior', icon: const Icon(Icons.chevron_left),
            onPressed: () => setState(() => calendarMonth = DateTime(first.year, first.month - 1))),
          Expanded(child: Text('${monthNames[first.month - 1]} de ${first.year}',
            textAlign: TextAlign.center, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
          IconButton(tooltip: 'Próximo mês', icon: const Icon(Icons.chevron_right),
            onPressed: () => setState(() => calendarMonth = DateTime(first.year, first.month + 1))),
        ]),
        Row(children: [for (final name in ['S','T','Q','Q','S','S','D'])
          Expanded(child: Center(child: Text(name, style: TextStyle(color: Colors.white70))))]),
        const SizedBox(height: 8),
        GridView.builder(shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 7,
            mainAxisSpacing: 5, crossAxisSpacing: 5, childAspectRatio: 1),
          itemCount: offset + daysInMonth,
          itemBuilder: (context, index) {
            if (index < offset) return const SizedBox.shrink();
            final day = index - offset + 1;
            final date = DateTime(first.year, first.month, day);
            final key = dateKey(date);
            final completed = counts[key] ?? 0;
            final isToday = dateKey(today) == key;
            return InkWell(borderRadius: BorderRadius.circular(10),
              onTap: () => showDayDetails(date, counts[key] ?? 0, points[key] ?? 0),
              child: Container(decoration: BoxDecoration(
                color: completed > 0 ? LifeQuestApp.purple.withValues(alpha: .35) : null,
                borderRadius: BorderRadius.circular(10),
                border: isToday ? Border.all(color: LifeQuestApp.purple, width: 2) : null),
                child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Text('$day', style: TextStyle(fontWeight: completed > 0 ? FontWeight.bold : FontWeight.normal)),
                  if (completed > 0) const Icon(Icons.circle, size: 6, color: LifeQuestApp.purple),
                ])));
          }),
      ]))),
      const SizedBox(height: 12),
      Row(children: [
        Expanded(child: Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(children: [
          const Text('Dias ativos'), Text('$activeDays', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold))])))),
        Expanded(child: Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(children: [
          const Text('XP do mês'), Text('$totalMonth', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold))])))),
      ]),
      const Padding(padding: EdgeInsets.all(8), child: Text('Toque em uma data para ver as missões daquele dia.')),
    ]);
  }

  void showDayDetails(DateTime date, int completed, int earned) {
    final records = history.where((r) => dateKey(r.when.toLocal()) == dateKey(date)).toList();
    showModalBottomSheet<void>(context: context, isScrollControlled: true,
      builder: (context) => SafeArea(child: Padding(padding: const EdgeInsets.all(20), child: Column(
        mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}',
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text('$completed conclusões • +$earned XP'),
          const SizedBox(height: 10),
          if (records.isEmpty) const Text('Nenhuma missão concluída neste dia.'),
          ...records.take(20).map((r) => ListTile(
            contentPadding: EdgeInsets.zero, leading: const Icon(Icons.check_circle_outline),
            title: Text(r.title), subtitle: Text(formatDate(r.when)), trailing: Text('+${r.points} XP'))),
          if (records.length > 20) Text('Mais ${records.length - 20} conclusões no histórico.'),
        ]))));
  }

  String formatFocusTime(int seconds) {
    final hours = seconds ~/ 3600;
    final minutes = (seconds % 3600) ~/ 60;
    final remaining = seconds % 60;
    return hours > 0 ? '${hours}h ${minutes}min' : '${minutes}min ${remaining}s';
  }

  Widget metricCard(String label, String value, IconData icon) => Card(child: Padding(
    padding: const EdgeInsets.all(14), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Icon(icon, color: LifeQuestApp.purple), const SizedBox(height: 10),
      Text(value, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
      Text(label, style: const TextStyle(color: Colors.white70)),
    ])));

  Widget statisticsPage() {
    final today = DateTime.now();
    final start = DateTime(today.year, today.month, today.day).subtract(Duration(days: statsRange - 1));
    final completions = history.where((r) => !r.when.toLocal().isBefore(start)).toList();
    final purchases = purchasesHistory.where((r) => !r.when.toLocal().isBefore(start)).toList();
    final earned = completions.fold<int>(0, (sum, r) => sum + r.points);
    final spent = purchases.fold<int>(0, (sum, r) => sum + r.price);
    final active = completions.map((r) => dateKey(r.when.toLocal())).toSet().length;
    final daily = <int>[];
    for (var i = 6; i >= 0; i--) {
      final date = DateTime(today.year, today.month, today.day).subtract(Duration(days: i));
      daily.add(history.where((r) => dateKey(r.when.toLocal()) == dateKey(date))
        .fold<int>(0, (sum, r) => sum + r.points));
    }
    final maxValue = daily.fold<int>(1, (max, v) => v > max ? v : max);
    final categoryCounts = <String,int>{};
    for (final record in completions) {
      categoryCounts[record.title] = (categoryCounts[record.title] ?? 0) + 1;
    }
    final mostDone = categoryCounts.entries.toList()..sort((a,b) => b.value.compareTo(a.value));
    return ListView(padding: const EdgeInsets.all(16), children: [
      const Text('Estatísticas', style: TextStyle(fontSize: 25, fontWeight: FontWeight.bold)),
      const SizedBox(height: 10),
      SegmentedButton<int>(segments: const [
        ButtonSegment(value: 7, label: Text('7 dias')),
        ButtonSegment(value: 30, label: Text('30 dias')),
        ButtonSegment(value: 90, label: Text('90 dias')),
      ], selected: {statsRange}, onSelectionChanged: (value) { setState(() => statsRange = value.first); refresh(); }),
      const SizedBox(height: 14),
      Row(children: [
        Expanded(child: metricCard('Missões concluídas', '${completions.length}', Icons.task_alt)),
        Expanded(child: metricCard('Dias ativos', '$active', Icons.calendar_today_outlined)),
      ]),
      Row(children: [
        Expanded(child: metricCard('XP conquistado', '$earned', Icons.bolt_outlined)),
        Expanded(child: metricCard('Moedas gastas', '$spent', Icons.shopping_bag_outlined)),
      ]),
      metricCard('Tempo de foco no período', formatFocusTime(focusSecondsRange), Icons.timer_outlined),
      Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(
        crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('XP ganho nos últimos 7 dias', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          SizedBox(height: 150, child: Row(crossAxisAlignment: CrossAxisAlignment.end,
            children: [for (var i = 0; i < 7; i++) Expanded(child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                Text('${daily[i]}', style: const TextStyle(fontSize: 10)),
                const SizedBox(height: 4),
                Container(height: 105 * daily[i] / maxValue + (daily[i] > 0 ? 3 : 0),
                  decoration: BoxDecoration(color: LifeQuestApp.purple,
                    borderRadius: BorderRadius.circular(5))),
                const SizedBox(height: 6),
                Text('${DateTime(today.year, today.month, today.day).subtract(Duration(days: 6-i)).day}',
                  style: const TextStyle(fontSize: 11)),
              ])))])),
          const SizedBox(height: 8),
          const Text('Números abaixo das barras = dia do mês', style: TextStyle(fontSize: 11, color: Colors.white70)),
        ]))),
      Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(
        crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Missões mais concluídas no período', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
          if (mostDone.isEmpty) const Padding(padding: EdgeInsets.only(top: 12),
            child: Text('Ainda não há conclusões neste período.')),
          ...mostDone.take(5).map((e) => ListTile(
            contentPadding: EdgeInsets.zero, title: Text(e.key), trailing: Text('${e.value}x'))),
        ]))),
      const Padding(padding: EdgeInsets.all(8), child: Text(
        'Os totais do período são calculados a partir do histórico salvo. '
        'As moedas gastas incluem recompensas já utilizadas ou ocultadas.',
        style: TextStyle(color: Colors.white70, fontSize: 12))),
    ]);
  }

  Widget placeholder(String name, IconData icon) => Center(child: Column(
    mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 55, color: LifeQuestApp.purple),
      const SizedBox(height: 12),
      Text(name, style: const TextStyle(fontSize: 23, fontWeight: FontWeight.bold)),
      const Text('Disponível em uma próxima etapa.'),
    ],
  ));

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(tab == 5 ? 'Histórico' : tab == 6 ? 'Perfil' : tab == 7 ? 'Sequência' : tab == 8 ? 'Lembretes' : 'LifeQuest'),
      backgroundColor: LifeQuestApp.bg,
      actions: [
        IconButton(tooltip: 'Lembretes', icon: const Icon(Icons.notifications_outlined),
          onPressed: () => setState(() => tab = 8)),
        IconButton(tooltip: 'Sequência e pausas', icon: const Icon(Icons.local_fire_department_outlined),
          onPressed: () => setState(() => tab = 7)),
        IconButton(tooltip: 'Perfil e conquistas', icon: const Icon(Icons.person_outline),
          onPressed: () => setState(() => tab = 6)),
        IconButton(tooltip: 'Histórico', icon: const Icon(Icons.history),
          onPressed: () => setState(() => tab = 5)),
      ],
    ),
    body: loading ? const Center(child: CircularProgressIndicator()) : [
      overview(), missionList(),
      shopPage(),
      calendarPage(),
      statisticsPage(),
      historyPage(), profilePage(), streakSettings(), remindersPage(),
    ][tab],
    floatingActionButton: tab <= 2 ? FloatingActionButton.extended(
      onPressed: tab == 2 ? () => editReward() : () => editMission(),
      icon: const Icon(Icons.add),
      label: Text(tab == 2 ? 'Nova recompensa' : 'Nova missão'),
    ) : null,
    bottomNavigationBar: NavigationBar(
      selectedIndex: tab >= 5 ? 0 : tab,
      onDestinationSelected: (index) => setState(() => tab = index),
      destinations: const [
        NavigationDestination(icon: Icon(Icons.home_outlined), label: 'Início'),
        NavigationDestination(icon: Icon(Icons.task_alt), label: 'Missões'),
        NavigationDestination(icon: Icon(Icons.shopping_bag_outlined), label: 'Loja'),
        NavigationDestination(icon: Icon(Icons.calendar_month_outlined), label: 'Agenda'),
        NavigationDestination(icon: Icon(Icons.bar_chart_outlined), label: 'Estatísticas'),
      ],
    ),
  );
}

// Mantém os controladores vivos durante toda a vida útil do diálogo.
class MissionEditorDialog extends StatefulWidget {
  final Mission? mission;

  const MissionEditorDialog({super.key, this.mission});

  @override
  State<MissionEditorDialog> createState() => _MissionEditorDialogState();
}

class _MissionEditorDialogState extends State<MissionEditorDialog> {
  final form = GlobalKey<FormState>();
  late final TextEditingController title;
  late final TextEditingController description;
  late final TextEditingController points;
  late String category;
  late String frequency;

  @override
  void initState() {
    super.initState();
    final mission = widget.mission;
    title = TextEditingController(text: mission?.title ?? '');
    description = TextEditingController(text: mission?.description ?? '');
    points = TextEditingController(text: '${mission?.points ?? 20}');
    category = mission?.category ?? 'Pessoal';
    frequency = mission?.frequency ?? 'Diária';
  }

  @override
  void dispose() {
    title.dispose();
    description.dispose();
    points.dispose();
    super.dispose();
  }

  void save() {
    if (!(form.currentState?.validate() ?? false)) return;
    final mission = widget.mission;
    Navigator.of(context).pop(Mission(
      id: mission?.id,
      title: title.text.trim(),
      description: description.text.trim(),
      category: category,
      frequency: frequency,
      points: int.parse(points.text.trim()),
      progress: mission?.progress ?? 0,
      completed: mission?.completed ?? false,
      lastCompletedOn: mission?.lastCompletedOn,
    ));
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.mission == null ? 'Nova missão' : 'Editar missão'),
    content: SizedBox(
      width: 400,
      child: SingleChildScrollView(
        child: Form(
          key: form,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextFormField(
              controller: title,
              decoration: const InputDecoration(labelText: 'Nome'),
              validator: (value) => value == null || value.trim().isEmpty
                  ? 'Informe um nome' : null,
            ),
            TextFormField(
              controller: description,
              decoration: const InputDecoration(labelText: 'Descrição (opcional)'),
            ),
            TextFormField(
              controller: points,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Pontos'),
              validator: (value) => (int.tryParse(value?.trim() ?? '') ?? 0) <= 0
                  ? 'Informe um número maior que zero' : null,
            ),
            DropdownButtonFormField<String>(
              initialValue: category,
              decoration: const InputDecoration(labelText: 'Categoria'),
              items: ['Pessoal', 'Estudos', 'Saúde', 'Casa', 'Outros']
                  .map((item) => DropdownMenuItem(value: item, child: Text(item)))
                  .toList(),
              onChanged: (value) {
                if (value != null) setState(() => category = value);
              },
            ),
            DropdownButtonFormField<String>(
              initialValue: frequency,
              decoration: const InputDecoration(labelText: 'Frequência'),
              items: ['Diária', 'Semanal', 'Única', 'Livre']
                  .map((item) => DropdownMenuItem(value: item, child: Text(item)))
                  .toList(),
              onChanged: (value) {
                if (value != null) setState(() => frequency = value);
              },
            ),
          ]),
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Cancelar'),
      ),
      FilledButton(onPressed: save, child: const Text('Salvar')),
    ],
  );
}

class RewardEditorDialog extends StatefulWidget {
  final Reward? reward;
  const RewardEditorDialog({super.key, this.reward});

  @override
  State<RewardEditorDialog> createState() => _RewardEditorDialogState();
}

class _RewardEditorDialogState extends State<RewardEditorDialog> {
  final form = GlobalKey<FormState>();
  late final TextEditingController title;
  late final TextEditingController description;
  late final TextEditingController price;
  late final TextEditingController limit;
  late String category;

  @override
  void initState() {
    super.initState();
    final reward = widget.reward;
    title = TextEditingController(text: reward?.title ?? '');
    description = TextEditingController(text: reward?.description ?? '');
    price = TextEditingController(text: '${reward?.price ?? 40}');
    limit = TextEditingController(text: reward?.maxRedemptions?.toString() ?? '');
    category = reward?.category ?? 'Lazer';
  }

  @override
  void dispose() {
    title.dispose();
    description.dispose();
    price.dispose();
    limit.dispose();
    super.dispose();
  }

  void save() {
    if (!(form.currentState?.validate() ?? false)) return;
    Navigator.pop(context, Reward(
      id: widget.reward?.id,
      title: title.text.trim(), description: description.text.trim(),
      category: category, price: int.parse(price.text.trim()),
      maxRedemptions: limit.text.trim().isEmpty ? null : int.parse(limit.text.trim()),
    ));
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.reward == null ? 'Nova recompensa' : 'Editar recompensa'),
    content: SizedBox(width: 400, child: SingleChildScrollView(child: Form(
      key: form,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        TextFormField(controller: title, decoration: const InputDecoration(labelText: 'Nome'),
          validator: (value) => value == null || value.trim().isEmpty ? 'Informe um nome' : null),
        TextFormField(controller: description,
          decoration: const InputDecoration(labelText: 'Descrição (opcional)')),
        TextFormField(controller: price, keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'Preço em moedas'),
          validator: (value) => (int.tryParse(value?.trim() ?? '') ?? 0) <= 0
            ? 'Informe um preço maior que zero' : null),
        TextFormField(controller: limit, keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Limite total de resgates (opcional)',
            helperText: 'Deixe vazio para permitir resgates ilimitados.'),
          validator: (value) => value == null || value.trim().isEmpty ||
            ((int.tryParse(value.trim()) ?? 0) > 0) ? null : 'Informe um inteiro positivo'),
        DropdownButtonFormField<String>(initialValue: category,
          decoration: const InputDecoration(labelText: 'Categoria'),
          items: ['Lazer', 'Comida', 'Experiências', 'Pessoal', 'Outros']
            .map((item) => DropdownMenuItem(value: item, child: Text(item))).toList(),
          onChanged: (value) { if (value != null) setState(() => category = value); }),
      ]),
    ))),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
      FilledButton(onPressed: save, child: const Text('Salvar')),
    ],
  );
}


class FocusTimerDialog extends StatefulWidget {
  final Mission mission;
  final DatabaseService db;
  const FocusTimerDialog({super.key, required this.mission, required this.db});
  @override
  State<FocusTimerDialog> createState() => _FocusTimerDialogState();
}

class _FocusTimerDialogState extends State<FocusTimerDialog> {
  final Stopwatch watch = Stopwatch();
  Timer? ticker;
  int accumulatedSeconds = 0;
  bool saving = false;
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _restore();
    ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && watch.isRunning) setState(() {});
    });
  }

  Future<void> _restore() async {
    try {
      final saved = await widget.db.getFocusDraft(widget.mission.id!);
      if (mounted) setState(() { accumulatedSeconds = saved; loading = false; });
    } catch (e) {
      if (mounted) {
        setState(() => loading = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  int get seconds => accumulatedSeconds + watch.elapsed.inSeconds;

  void _pauseWatch() {
    if (watch.isRunning) {
      accumulatedSeconds += watch.elapsed.inSeconds;
      watch.stop();
      watch.reset();
    }
  }

  Future<void> _pause() async {
    if (saving || loading) return;
    setState(() => saving = true);
    _pauseWatch();
    try {
      await widget.db.saveFocusDraft(widget.mission.id!, seconds);
      if (mounted) setState(() => saving = false);
    } catch (e) { _error(e); }
  }

  Future<void> _resume() async {
    if (saving || loading) return;
    setState(() => watch.start());
  }

  Future<void> _leave() async {
    if (saving || loading) return;
    setState(() => saving = true);
    _pauseWatch();
    try {
      await widget.db.saveFocusDraft(widget.mission.id!, seconds);
      if (mounted) Navigator.pop(context);
    } catch (e) { _error(e); }
  }

  Future<void> finish() async {
    if (saving || loading) return;
    setState(() => saving = true);
    _pauseWatch();
    try {
      await widget.db.finishFocusDraft(widget.mission.id!, widget.mission.title, seconds);
      if (mounted) Navigator.pop(context);
    } catch (e) { _error(e); }
  }

  void _error(Object e) {
    if (mounted) {
      setState(() => saving = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  @override
  void dispose() {
    ticker?.cancel();
    watch.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final duration = Duration(seconds: seconds);
    final display = '${duration.inHours.toString().padLeft(2, '0')}:'
      '${(duration.inMinutes % 60).toString().padLeft(2, '0')}:'
      '${(duration.inSeconds % 60).toString().padLeft(2, '0')}';
    return PopScope(canPop: false, child: AlertDialog(
      title: Text('Foco: ${widget.mission.title}'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.timer_outlined, size: 42, color: LifeQuestApp.purple),
        const SizedBox(height: 14),
        if (loading) const CircularProgressIndicator()
        else Text(display, style: const TextStyle(fontSize: 38, fontWeight: FontWeight.bold,
          fontFeatures: [FontFeature.tabularFigures()])),
        const SizedBox(height: 10),
        const Text('Sair salva o tempo e pausa a sessão. Ao voltar, você continua de onde parou.',
          textAlign: TextAlign.center, style: TextStyle(color: Colors.white70)),
      ]),
      actions: [
        TextButton(onPressed: saving || loading ? null : _leave,
          child: const Text('Sair e salvar')),
        TextButton(onPressed: saving || loading ? null : (watch.isRunning ? _pause : _resume),
          child: Text(watch.isRunning ? 'Pausar' : 'Iniciar / Retomar')),
        FilledButton(onPressed: saving || loading ? null : finish,
          child: Text(saving ? 'Salvando...' : 'Finalizar')),
      ],
    ));
  }
}
