class Task {
  final String id;
  String title;
  bool done;
  DateTime? due;
  String notes;
  Task? parent;
  final List<Task> children;
  String? currentId;

  String? completionNote;
  int? completionMinutes;
  DateTime? completedAt;

  Task({
    required this.id,
    required this.title,
    this.done = false,
    this.due,
    this.notes = '',
    this.parent,
    this.currentId,
    this.completionNote,
    this.completionMinutes,
    this.completedAt,
    List<Task>? children,
  }) : children = children ?? [];

  int get depth {
    int d = 0;
    Task? cur = parent;
    while (cur != null) {
      d++;
      cur = cur.parent;
    }
    return d;
  }

  get allTasks => null;

  List<Task> pathFromRoot() {
    final path = <Task>[];
    Task? cur = this;
    while (cur != null) {
      path.add(cur);
      cur = cur.parent;
    }
    return path.reversed.toList();
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'title': title,
        'done': done,
        'due': due?.toIso8601String(),
        'notes': notes,
        'currentId': currentId,
        'completionNote': completionNote,
        'completionMinutes': completionMinutes,
        'completedAt': completedAt?.toIso8601String(),
        'children': children.map((c) => c.toMap()).toList(),
      };

  static Task fromMap(Map<String, dynamic> m, {Task? parent}) {
    final t = Task(
      id: m['id'] as String,
      title: (m['title'] ?? '') as String,
      done: (m['done'] ?? false) as bool,
      due: (m['due'] == null) ? null : DateTime.parse(m['due'] as String),
      notes: (m['notes'] ?? '') as String,
      parent: parent,
      currentId: m['currentId'] as String?,
      completionNote: m['completionNote'] as String?,
      completionMinutes: (m['completionMinutes'] is int)
          ? m['completionMinutes'] as int
          : (m['completionMinutes'] is num)
              ? (m['completionMinutes'] as num).toInt()
              : null,
      completedAt: (m['completedAt'] == null)
          ? null
          : DateTime.parse(m['completedAt'] as String),
    );
    final kids = (m['children'] as List? ?? const []);
    for (final k in kids) {
      final child = Task.fromMap(k as Map<String, dynamic>, parent: t);
      t.children.add(child);
    }
    return t;
  }
}
