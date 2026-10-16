class Mission {
  final int? id;
  final String title;
  final String description;
  final String category;
  final String frequency;
  final int points;
  final int progress;
  final bool completed;
  final String? lastCompletedOn;

  const Mission({
    this.id,
    required this.title,
    this.description = '',
    this.category = 'Pessoal',
    this.frequency = 'Diária',
    required this.points,
    this.progress = 0,
    this.completed = false,
    this.lastCompletedOn,
  });

  Mission copyWith({int? id, String? title, String? description,
    String? category, String? frequency, int? points, int? progress,
    bool? completed, String? lastCompletedOn}) => Mission(
    id: id ?? this.id,
    title: title ?? this.title,
    description: description ?? this.description,
    category: category ?? this.category,
    frequency: frequency ?? this.frequency,
    points: points ?? this.points,
    progress: progress ?? this.progress,
    completed: completed ?? this.completed,
    lastCompletedOn: lastCompletedOn ?? this.lastCompletedOn,
  );

  Map<String, Object?> toMap() => {
    'title': title, 'description': description, 'category': category,
    'frequency': frequency, 'points': points, 'progress': progress,
    'completed': completed ? 1 : 0, 'last_completed_on': lastCompletedOn,
  };

  factory Mission.fromMap(Map<String, Object?> map) => Mission(
    id: map['id'] as int,
    title: map['title'] as String,
    description: map['description'] as String,
    category: map['category'] as String,
    frequency: map['frequency'] as String,
    points: map['points'] as int,
    progress: map['progress'] as int,
    completed: (map['completed'] as int) == 1,
    lastCompletedOn: map['last_completed_on'] as String?,
  );
}
