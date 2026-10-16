
import 'package:flutter/material.dart';

void main() {
  runApp(const LifeQuestApp());
}

class LifeQuestApp extends StatelessWidget {
  const LifeQuestApp({super.key});

  static const purple = Color(0xFF9568F5);
  static const background = Color(0xFF101016);
  static const surface = Color(0xFF1D1D29);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'LifeQuest',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: background,
        colorScheme: ColorScheme.fromSeed(
          seedColor: purple,
          brightness: Brightness.dark,
          surface: surface,
        ),
        cardTheme: CardThemeData(
          color: surface,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
        ),
      ),
      home: const MainScreen(),
    );
  }
}

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int selectedTab = 0;
  int coins = 240;
  int xp = 320;
  int streak = 12;

  final List<Map<String, dynamic>> missions = [
    {
      'name': 'Estudar programação',
      'points': 30,
      'done': false,
    },
    {
      'name': 'Praticar violão',
      'points': 20,
      'done': false,
    },
    {
      'name': 'Organizar o quarto',
      'points': 15,
      'done': false,
    },
  ];

  final List<Map<String, dynamic>> rewards = [
    {'name': '30 minutos extras de jogo', 'cost': 40},
    {'name': 'Sessão de cinema', 'cost': 60},
    {'name': 'Atividade especial', 'cost': 100},
  ];

  void completeMission(int index) {
    if (missions[index]['done'] == true) return;

    final points = missions[index]['points'] as int;

    setState(() {
      missions[index]['done'] = true;
      coins += points;
      xp += points;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Missão concluída! +$points moedas e XP'),
      ),
    );
  }

  void redeemReward(int index) {
    final cost = rewards[index]['cost'] as int;

    if (coins < cost) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Moedas insuficientes!')),
      );
      return;
    }

    setState(() {
      coins -= cost;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Recompensa resgatada: ${rewards[index]['name']}',
        ),
      ),
    );
  }

  Widget infoCard(
    String title,
    String value,
    IconData icon,
    Color color,
  ) {
    return Expanded(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: color),
              const SizedBox(height: 12),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                title,
                style: const TextStyle(color: Colors.white60),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget homePage() {
    final completed =
        missions.where((mission) => mission['done'] == true).length;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          'Bem-vindo ao LifeQuest',
          style: TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'Transforme sua rotina em conquistas.',
          style: TextStyle(color: Colors.white60),
        ),
        const SizedBox(height: 24),
        Row(
          children: [
            infoCard(
              'Sequência',
              '$streak dias',
              Icons.local_fire_department,
              Colors.orange,
            ),
            infoCard(
              'Moedas',
              '$coins',
              Icons.monetization_on,
              Colors.amber,
            ),
          ],
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Nível 4',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text('$xp / 450 XP'),
                const SizedBox(height: 12),
                LinearProgressIndicator(
                  value: (xp / 450).clamp(0.0, 1.0),
                  minHeight: 8,
                  borderRadius: BorderRadius.circular(8),
                  color: LifeQuestApp.purple,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),
        Text(
          'Missões de hoje ($completed/${missions.length})',
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
        ...List.generate(
          missions.length,
          (index) => missionCard(index),
        ),
      ],
    );
  }

  Widget missionCard(int index) {
    final mission = missions[index];
    final done = mission['done'] as bool;

    return Card(
      child: ListTile(
        leading: Icon(
          done ? Icons.check_circle : Icons.radio_button_unchecked,
          color: done ? Colors.green : LifeQuestApp.purple,
        ),
        title: Text(mission['name'] as String),
        subtitle: Text('+${mission['points']} moedas e XP'),
        trailing: IconButton(
          icon: Icon(
            done ? Icons.check : Icons.add_circle_outline,
          ),
          onPressed: done ? null : () => completeMission(index),
        ),
      ),
    );
  }

  Widget missionsPage() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          'Minhas missões',
          style: TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 16),
        ...List.generate(
          missions.length,
          (index) => missionCard(index),
        ),
      ],
    );
  }

  Widget shopPage() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          'Loja de recompensas',
          style: TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'Saldo: $coins moedas',
          style: const TextStyle(
            fontSize: 18,
            color: Colors.amber,
          ),
        ),
        const SizedBox(height: 20),
        ...List.generate(rewards.length, (index) {
          final reward = rewards[index];

          return Card(
            child: ListTile(
              leading: const Icon(
                Icons.card_giftcard,
                color: LifeQuestApp.purple,
              ),
              title: Text(reward['name'] as String),
              subtitle: Text('${reward['cost']} moedas'),
              trailing: FilledButton(
                onPressed: () => redeemReward(index),
                child: const Text('Resgatar'),
              ),
            ),
          );
        }),
      ],
    );
  }

  Widget placeholderPage(String title, IconData icon) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            icon,
            size: 64,
            color: LifeQuestApp.purple,
          ),
          const SizedBox(height: 16),
          Text(
            title,
            style: const TextStyle(fontSize: 24),
          ),
          const SizedBox(height: 8),
          const Text(
            'Esta tela será desenvolvida em breve.',
            style: TextStyle(color: Colors.white60),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      homePage(),
      missionsPage(),
      shopPage(),
      placeholderPage('Calendário', Icons.calendar_month),
      placeholderPage('Estatísticas', Icons.bar_chart),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'LifeQuest',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: LifeQuestApp.background,
        actions: [
          IconButton(
            onPressed: () {},
            icon: const Icon(Icons.person_outline),
          ),
        ],
      ),
      body: pages[selectedTab],
      bottomNavigationBar: NavigationBar(
        selectedIndex: selectedTab,
        onDestinationSelected: (index) {
          setState(() {
            selectedTab = index;
          });
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            label: 'Início',
          ),
          NavigationDestination(
            icon: Icon(Icons.task_alt),
            label: 'Missões',
          ),
          NavigationDestination(
            icon: Icon(Icons.shopping_bag_outlined),
            label: 'Loja',
          ),
          NavigationDestination(
            icon: Icon(Icons.calendar_month_outlined),
            label: 'Agenda',
          ),
          NavigationDestination(
            icon: Icon(Icons.bar_chart_outlined),
            label: 'Estatísticas',
          ),
        ],
      ),
    );
  }
}
