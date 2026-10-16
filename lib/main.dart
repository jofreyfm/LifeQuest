import 'package:flutter/material.dart';
import 'database_service.dart';
import 'mission.dart';

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

  @override
  void initState() {
    super.initState();
    refresh();
  }

  Future<void> refresh() async {
    try {
      final items = await db.getMissions();
      final wallet = await db.getWallet();
      final records = await db.getHistory();
      if (!mounted) return;
      setState(() {
        missions = items;
        coins = wallet['coins']!;
        xp = wallet['xp']!;
        history = records;
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

  Future<void> changeProgress(Mission mission) async {
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
      final completed = await db.updateProgress(mission, result);
      await refresh();
      if (completed) message('Missão concluída! +${mission.points} moedas e XP');
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
              tooltip: 'Atualizar progresso',
              onPressed: mission.completed ? null : () => changeProgress(mission),
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
    ...missions.map(missionCard),
    if (missions.isEmpty) const Text('Crie uma missão usando o botão +.'),
  ]);

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
      title: Text(tab == 5 ? 'Histórico' : 'LifeQuest'),
      backgroundColor: LifeQuestApp.bg,
      actions: [IconButton(tooltip: 'Histórico', icon: const Icon(Icons.history),
        onPressed: () => setState(() => tab = 5))],
    ),
    body: loading ? const Center(child: CircularProgressIndicator()) : [
      overview(), missionList(),
      placeholder('Loja', Icons.shopping_bag_outlined),
      placeholder('Calendário', Icons.calendar_month_outlined),
      placeholder('Estatísticas', Icons.bar_chart_outlined),
      historyPage(),
    ][tab],
    floatingActionButton: tab <= 1 ? FloatingActionButton.extended(
      onPressed: () => editMission(), icon: const Icon(Icons.add), label: const Text('Nova missão'),
    ) : null,
    bottomNavigationBar: NavigationBar(
      selectedIndex: tab == 5 ? 1 : tab,
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
