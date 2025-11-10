// lib/achievements.dart
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// ====== Data model (compatible with main.dart storage) ======

class Task {
  final String id;
  String title;
  bool done;
  DateTime? due;
  String notes;
  Task? parent;
  final List<Task> children;
  String? currentId;

  // Completion reflection (optional fields)
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
      due: (m['due'] == null) ? null : DateTime.tryParse(m['due'] as String),
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
          : DateTime.tryParse(m['completedAt'] as String),
    );
    final kids = (m['children'] as List? ?? const []);
    for (final k in kids) {
      final child = Task.fromMap(k as Map<String, dynamic>, parent: t);
      t.children.add(child);
    }
    return t;
  }
}

/// ====== Achievements Page ======

class AchievementsPage extends StatefulWidget {
  const AchievementsPage({super.key});

  @override
  State<AchievementsPage> createState() => _AchievementsPageState();
}

class _AchievementsPageState extends State<AchievementsPage> {
  static const _storageKey = 'split_todo_roots_v1';

  bool _loading = true;
  List<Task> _roots = [];

  // Derived
  late List<Task> _allTasks;
  late List<Task> _completed; // sorted by depth desc, then completedAt desc
  late Map<int, int> _completedPerDepth;
  late int _completedListsCount;
  late int _completedLast7Days;
  late double _avgPerWeekLast8;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_storageKey);
    if (raw != null && raw.isNotEmpty) {
      try {
        final list = jsonDecode(raw) as List<dynamic>;
        _roots =
            list.map((m) => Task.fromMap(m as Map<String, dynamic>)).toList();
      } catch (_) {
        _roots = [];
      }
    }
    _derive();
    setState(() => _loading = false);
  }

  void _derive() {
    _allTasks = [];
    void walk(Task t) {
      _allTasks.add(t);
      for (final c in t.children) {
        walk(c);
      }
    }

    for (final r in _roots) {
      walk(r);
    }

    _completed = _allTasks
        .where((t) => t.done)
        .toList()
      ..sort((a, b) {
        final d = b.depth.compareTo(a.depth);
        if (d != 0) return d;
        final at = a.completedAt?.millisecondsSinceEpoch ?? 0;
        final bt = b.completedAt?.millisecondsSinceEpoch ?? 0;
        return bt.compareTo(at);
      });

    _completedPerDepth = {};
    for (final t in _completed) {
      _completedPerDepth.update(t.depth, (v) => v + 1, ifAbsent: () => 1);
    }

    _completedListsCount = _roots.where((r) => r.done).length;

    // Weekly stats
    final now = DateTime.now();
    final sevenDaysAgo = now.subtract(const Duration(days: 7));
    _completedLast7Days = _completed
        .where((t) => (t.completedAt ?? DateTime.fromMillisecondsSinceEpoch(0))
            .isAfter(sevenDaysAgo))
        .length;

    // Average per week in last 8 full weeks (56 days)
    final cutoff = now.subtract(const Duration(days: 56));
    final recent = _completed
        .where((t) =>
            (t.completedAt ?? DateTime.fromMillisecondsSinceEpoch(0))
                .isAfter(cutoff))
        .toList();

    // Bucket by ISO week (year-week)
    final Map<String, int> perWeek = {};
    for (final t in recent) {
      final dt = t.completedAt!;
      final w = _isoYearWeek(dt);
      perWeek.update(w, (v) => v + 1, ifAbsent: () => 1);
    }
    if (perWeek.isEmpty) {
      _avgPerWeekLast8 = 0;
    } else {
      // Use exactly 8 buckets span (zero for missing weeks)
      final weeks = _lastNWeeksKeys(now, 8);
      int sum = 0;
      for (final key in weeks) {
        sum += perWeek[key] ?? 0;
      }
      _avgPerWeekLast8 = sum / 8.0;
    }
  }

  /// Return "YYYY-WW" (ISO week)
  String _isoYearWeek(DateTime dt) {
    // ISO week starts Monday
    final thursday =
        dt.add(Duration(days: 3 - ((dt.weekday + 6) % 7))); // nearest Thursday
    final firstThursday =
        DateTime(thursday.year, 1, 4); // Week 1 contains Jan 4th
    final diff = thursday
        .difference(firstThursday)
        .inDays; // number of days between Thursdays
    final week = 1 + (diff ~/ 7);
    final year = thursday.year;
    return '$year-${week.toString().padLeft(2, '0')}';
  }

  List<String> _lastNWeeksKeys(DateTime now, int n) {
    final keys = <String>[];
    DateTime cursor = now;
    for (int i = 0; i < n; i++) {
      keys.add(_isoYearWeek(cursor));
      cursor = cursor.subtract(const Duration(days: 7));
    }
    return keys.reversed.toList();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Achievements'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: () async {
              setState(() => _loading = true);
              await _load();
            },
            icon: const Icon(Icons.refresh),
          )
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _roots.isEmpty
              ? const Center(
                  child: Text('No data yet. Complete some tasks to see stats.'),
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
                  children: [
                    _StatsHeader(
                      totalCompleted: _completed.length,
                      completedLists: _completedListsCount,
                      perDepth: _completedPerDepth,
                      last7Days: _completedLast7Days,
                      avgPerWeekLast8: _avgPerWeekLast8,
                    ),
                    const SizedBox(height: 16),
                    Text('Completed tasks',
                        style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 8),
                    if (_completed.isEmpty)
                      const Text('You haven’t completed any tasks yet.')
                    else
                      ..._completed.map((t) => _CompletedTile(task: t, cs: cs)),
                  ],
                ),
    );
  }
}

/// ====== Widgets ======

class _StatsHeader extends StatelessWidget {
  final int totalCompleted;
  final int completedLists;
  final Map<int, int> perDepth;
  final int last7Days;
  final double avgPerWeekLast8;

  const _StatsHeader({
    required this.totalCompleted,
    required this.completedLists,
    required this.perDepth,
    required this.last7Days,
    required this.avgPerWeekLast8,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        _StatCard(
          title: 'Completed tasks',
          value: '$totalCompleted',
          icon: Icons.check_circle,
          cs: cs,
        ),
        _StatCard(
          title: 'Completed lists (final goals)',
          value: '$completedLists',
          icon: Icons.flag,
          cs: cs,
        ),
        _StatCard(
          title: 'Last 7 days',
          value: '$last7Days',
          icon: Icons.calendar_today,
          cs: cs,
        ),
        _StatCard(
          title: 'Avg/week (8w)',
          value: avgPerWeekLast8.toStringAsFixed(1),
          icon: Icons.show_chart,
          cs: cs,
        ),
        _PerDepthCard(perDepth: perDepth, cs: cs),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final ColorScheme cs;

  const _StatCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.cs,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 220,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Icon(icon, size: 28, color: cs.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: Theme.of(context).textTheme.labelMedium),
                    const SizedBox(height: 4),
                    Text(
                      value,
                      style: Theme.of(context)
                          .textTheme
                          .titleLarge
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PerDepthCard extends StatelessWidget {
  final Map<int, int> perDepth;
  final ColorScheme cs;

  const _PerDepthCard({required this.perDepth, required this.cs});

  @override
  Widget build(BuildContext context) {
    // Sort by depth asc for display (0,1,2,3…)
    final entries = perDepth.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));

    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 220, maxWidth: 480),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Completed by generation',
                  style: Theme.of(context).textTheme.labelMedium),
              const SizedBox(height: 8),
              if (entries.isEmpty)
                const Text('No completed tasks yet.')
              else
                Column(
                  children: entries
                      .map(
                        (e) => Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Row(
                            children: [
                              Container(
                                width: 10,
                                height: 10,
                                decoration: BoxDecoration(
                                  color: cs.primary.withOpacity(.75),
                                  borderRadius: BorderRadius.circular(2),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                  child: Text('Depth ${e.key} (Gen ${e.key})')),
                              Text('${e.value}'),
                            ],
                          ),
                        ),
                      )
                      .toList(),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CompletedTile extends StatelessWidget {
  final Task task;
  final ColorScheme cs;

  const _CompletedTile({required this.task, required this.cs});

  String _fmtDate(DateTime d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.day)}.${two(d.month)}.${d.year}';
    // (שומר על אותו פורמט כמו האפליקציה הראשית)
  }

  @override
  Widget build(BuildContext context) {
    final dateStr =
        task.completedAt != null ? _fmtDate(task.completedAt!) : '—';
    final note = task.completionNote;

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: cs.primary.withOpacity(.15),
          foregroundColor: cs.primary,
          child: Text('${task.depth}'),
        ),
        title: Text(
          task.title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Wrap(
          spacing: 12,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.event_available, size: 16),
                const SizedBox(width: 4),
                Text(dateStr),
              ],
            ),
            if (task.completionMinutes != null)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.timer, size: 16),
                  const SizedBox(width: 4),
                  Text('${task.completionMinutes}m'),
                ],
              ),
            if (note != null && note.isNotEmpty)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.notes, size: 16),
                  const SizedBox(width: 4),
                  Text(
                    note,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
