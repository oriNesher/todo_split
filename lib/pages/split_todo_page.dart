import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:todo_split/pages/achievements_board.dart';

import '../models/task.dart';
import '../utils/color_utils.dart';
import '../utils/date_utils.dart';

class SplitTodoPage extends StatefulWidget {
  const SplitTodoPage({super.key});
  @override
  State<SplitTodoPage> createState() => _SplitTodoPageState();
}

class _SplitTodoPageState extends State<SplitTodoPage> {
  static const _storageKey = 'split_todo_roots_v1';
  static const _historyLimit = 30;

  final _rand = Random();
  bool _loaded = false;

  // multiple lists
  List<Task> _roots = [];
  int _currentIndex = 0;

  // undo stack (snapshots of all lists)
  final List<String> _history = [];

  // NEW: סט של משימות שמכווצות כרגע (UI בלבד, לא נשמר ב־storage)
  final Set<String> _collapsedTaskIds = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Task? get _currentRoot =>
      _roots.isEmpty ? null : _roots[_currentIndex.clamp(0, _roots.length - 1)];

  String _newId() =>
      '${DateTime.now().microsecondsSinceEpoch}_${_rand.nextInt(1 << 20)}';

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_storageKey);
    if (raw != null && raw.isNotEmpty) {
      try {
        final list = jsonDecode(raw) as List<dynamic>;
        _roots =
            list.map((m) => Task.fromMap(m as Map<String, dynamic>)).toList();
      } catch (_) {}
    }
    setState(() => _loaded = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _roots.isEmpty) _promptForNewList();
    });
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = jsonEncode(_roots.map((r) => r.toMap()).toList());
    await prefs.setString(_storageKey, jsonStr);
  }

  void _snapshot() {
    final snap = jsonEncode(_roots.map((r) => r.toMap()).toList());
    _history.add(snap);
    if (_history.length > _historyLimit) _history.removeAt(0);
  }

  bool get _canUndo => _history.isNotEmpty;

  void _undo() {
    if (!_canUndo) return;
    final last = _history.removeLast();
    try {
      final list = jsonDecode(last) as List<dynamic>;
      setState(() {
        _roots =
            list.map((m) => Task.fromMap(m as Map<String, dynamic>)).toList();
        if (_roots.isEmpty) {
          _currentIndex = 0;
        } else {
          _currentIndex = _currentIndex.clamp(0, _roots.length - 1);
        }
      });
      _save();
    } catch (_) {}
  }

  // list ops
  void _promptForNewList() {
    final ctl = TextEditingController();
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: const Text("Create a new list"),
        content: TextField(
          controller: ctl,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Final goal (e.g., Build a portfolio website)',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (_) => _createList(ctl.text),
        ),
        actions: [
          TextButton(
            onPressed: () => _createList(ctl.text),
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }

  void _createList(String title) {
    Navigator.of(context).maybePop();
    final t = title.trim();
    if (t.isEmpty) return;
    _snapshot();
    final root = Task(id: _newId(), title: t);
    setState(() {
      _roots.add(root);
      _currentIndex = _roots.length - 1;
    });
    _save();
  }

  void _renameCurrentList() {
    final r = _currentRoot;
    if (r == null) return;
    final ctl = TextEditingController(text: r.title);
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Rename list'),
        content: TextField(
          controller: ctl,
          autofocus: true,
          decoration: const InputDecoration(border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              final t = ctl.text.trim();
              if (t.isEmpty) return;
              _snapshot();
              setState(() => r.title = t);
              _save();
              Navigator.pop(context);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _deleteCurrentList() async {
    final r = _currentRoot;
    if (r == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete this list?'),
        content: Text('This will delete “${r.title}” and all its tasks.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Delete')),
        ],
      ),
    );
    if (ok == true) {
      _snapshot();
      setState(() {
        _roots.removeAt(_currentIndex);
        if (_roots.isEmpty) {
          _currentIndex = 0;
        } else {
          _currentIndex = (_currentIndex - 1).clamp(0, _roots.length - 1);
        }
      });
      _save();
      if (_roots.isEmpty) _promptForNewList();
    }
  }

  // helpers
  Task _rootOf(Task t) {
    Task r = t;
    while (r.parent != null) {
      r = r.parent!;
    }
    return r;
  }

  bool _isThirdLevelandAbove(Task t) =>
      t.depth >= 2; // 0=root, 1=child, 2=grandchild

  bool _isCurrent(Task t) {
    final r = _rootOf(t);
    return r.currentId != null && r.currentId == t.id;
  }

  void _setCurrent(Task t) {
    if (!_isThirdLevelandAbove(t)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Only third-level tasks can be marked as CURRENT.'),
          duration: Duration(milliseconds: 1600),
        ),
      );
      return;
    }
    final r = _rootOf(t);
    _snapshot();
    setState(() {
      r.currentId = t.id;
    });
    _save();
  }

  void _clearCurrentOf(Task r) {
    _snapshot();
    setState(() {
      r.currentId = null;
    });
    _save();
  }

  bool _subtreeContainsId(Task t, String id) {
    if (t.id == id) return true;
    for (final c in t.children) {
      if (_subtreeContainsId(c, id)) return true;
    }
    return false;
  }

  Future<void> _confirmAndDeleteTask(Task t) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete task?'),
        content: Text('This will delete “${t.title}” and all its subtasks.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Delete')),
        ],
      ),
    );
    if (ok == true) _deleteTask(t);
  }

  void _deleteTask(Task t) {
    if (t.parent == null) return;

    final root = _rootOf(t);
    _snapshot();

    if (root.currentId != null && _subtreeContainsId(t, root.currentId!)) {
      root.currentId = null;
    }

    t.parent!.children.removeWhere((c) => identical(c, t) || c.id == t.id);

    setState(() {});
    _save();
  }

  // ---------- Completion reflection ----------
  Future<void> _promptCompletion(Task task) async {
    final noteCtl = TextEditingController();
    final minutesCtl = TextEditingController();

    final result = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: const Text('Nice! Mark task as completed'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: noteCtl,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'How did you complete it? (optional)',
                hintText: 'A short note…',
                border: OutlineInputBorder(),
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: minutesCtl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'How long did it take (minutes)? (optional)',
                hintText: 'e.g., 25',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(_, 'skip'),
            child: const Text('Skip'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(_, 'save'),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    _snapshot();
    setState(() {
      task.done = true;
      task.completedAt = DateTime.now();
      if (result == 'save') {
        final m = int.tryParse(minutesCtl.text.trim());
        task.completionMinutes = m;
        final note = noteCtl.text.trim();
        task.completionNote = note.isNotEmpty ? note : null;
      } else {
        task.completionMinutes = null;
        task.completionNote = null;
      }
    });
    _save();
  }

  void _splitTaskN(Task parent, List<String> titles,
      {bool allowSingle = false}) {
    final newChildren = <Task>[];
    for (final t in titles) {
      final clean = t.trim();
      if (clean.isEmpty) continue;
      newChildren.add(Task(id: _newId(), title: clean, parent: parent));
    }
    if (newChildren.length < (allowSingle ? 1 : 2)) return;

    _snapshot();
    setState(() {
      parent.children.addAll(newChildren);
      parent.done = false;
    });
    _save();
  }

  void _showSplitDialog(Task task) {
    final controllers = List.generate(5, (_) => TextEditingController());

    final bool hasChildren = task.children.isNotEmpty;
    int minCount = hasChildren ? 1 : 2;
    int count = max(minCount, 2);

    List<int> range(int start, int end) =>
        List.generate(end - start + 1, (i) => start + i);

    showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setLocal) {
          Widget field(int i) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: TextField(
                  controller: controllers[i],
                  decoration: InputDecoration(
                    labelText: 'New task #${i + 1}',
                    border: const OutlineInputBorder(),
                  ),
                  autofocus: i == 0,
                ),
              );

          return AlertDialog(
            title: Text('Split: ${task.title}'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Text('How many?  ($minCount–5)  '),
                      DropdownButton<int>(
                        value: count,
                        items: range(minCount, 5)
                            .map((n) =>
                                DropdownMenuItem(value: n, child: Text('$n')))
                            .toList(),
                        onChanged: (v) => setLocal(() => count = v ?? minCount),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  for (int i = 0; i < count; i++) field(i),
                  if (hasChildren) ...[
                    const SizedBox(height: 8),
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'This task already has subtasks — you can add even a single one via Split.',
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancel')),
              FilledButton(
                onPressed: () {
                  final titles = controllers
                      .take(count)
                      .map((c) => c.text)
                      .where((s) => s.trim().isNotEmpty)
                      .toList();

                  final requiredMin = hasChildren ? 1 : 2;
                  if (titles.length < requiredMin) return;

                  _splitTaskN(task, titles, allowSingle: hasChildren);
                  Navigator.pop(ctx);
                },
                child: const Text('Split'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showTaskSheet(Task task) async {
    final titleCtl = TextEditingController(text: task.title);
    final notesCtl = TextEditingController(text: task.notes);
    DateTime? due = task.due;
    bool done = task.done;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        final bottomInsets = MediaQuery.of(ctx).viewInsets.bottom;
        final cs = Theme.of(ctx).colorScheme;
        final accent = cs.primary.darken(0.1);

        return Padding(
          padding: EdgeInsets.only(bottom: bottomInsets),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Task settings',
                    style: Theme.of(ctx).textTheme.titleLarge),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Switch(
                      value: done,
                      onChanged: (v) async {
                        if (v == true && done == false) {
                          Navigator.pop(ctx);
                          await _promptCompletion(task);
                        } else {
                          _snapshot();
                          setState(() => task.done = v);
                          _save();
                        }
                      },
                    ),
                    const SizedBox(width: 8),
                    const Text('Completed'),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: titleCtl,
                  decoration: const InputDecoration(
                      labelText: 'Title', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: InputDecorator(
                        decoration: const InputDecoration(
                            labelText: 'Due date',
                            border: OutlineInputBorder()),
                        child: Row(
                          children: [
                            Icon(Icons.event,
                                color: Theme.of(ctx).colorScheme.primary),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                  due == null ? 'None' : fmtDate(due!)),
                            ),
                            TextButton(
                              onPressed: () async {
                                final now = DateTime.now();
                                final picked = await showDatePicker(
                                  context: ctx,
                                  firstDate: DateTime(now.year - 1),
                                  lastDate: DateTime(now.year + 5),
                                  initialDate: due ?? now,
                                );
                                if (picked != null) {
                                  _snapshot();
                                  setState(() => task.due = picked);
                                  due = picked;
                                  _save();
                                }
                              },
                              child: const Text('Pick'),
                            ),
                            if (due != null)
                              TextButton(
                                onPressed: () {
                                  _snapshot();
                                  setState(() => task.due = null);
                                  due = null;
                                  _save();
                                },
                                child: const Text('Clear'),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: notesCtl,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    labelText: 'Notes',
                    border: OutlineInputBorder(),
                    alignLabelWithHint: true,
                  ),
                ),
                const SizedBox(height: 16),
                if (task.done &&
                    (task.completionNote != null ||
                        task.completionMinutes != null))
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: accent.withOpacity(.08),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: accent.withOpacity(.25)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Completion reflection',
                            style: Theme.of(ctx).textTheme.titleMedium),
                        const SizedBox(height: 8),
                        if (task.completionNote != null) ...[
                          Row(
                            children: [
                              const Icon(Icons.notes, size: 18),
                              const SizedBox(width: 8),
                              Expanded(child: Text(task.completionNote!)),
                            ],
                          ),
                          const SizedBox(height: 6),
                        ],
                        if (task.completionMinutes != null) ...[
                          Row(
                            children: [
                              const Icon(Icons.timer, size: 18),
                              const SizedBox(width: 8),
                              Text('${task.completionMinutes} min'),
                            ],
                          ),
                        ],
                        if (task.completedAt != null) ...[
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              const Icon(Icons.event_available, size: 18),
                              const SizedBox(width: 8),
                              Text(
                                  'Completed on ${fmtDate(task.completedAt!)}'),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                const SizedBox(height: 20),
                Text('Hierarchy (path from root):',
                    style: Theme.of(ctx).textTheme.titleMedium),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _buildPathChips(task),
                ),
                const SizedBox(height: 20),
                Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  children: [
                    OutlinedButton.icon(
                      onPressed: () {
                        Navigator.pop(ctx);
                        _showSplitDialog(task);
                      },
                      icon: const Icon(Icons.call_split),
                      label: const Text('Split (2–5)'),
                    ),
                    OutlinedButton.icon(
                      onPressed: _isThirdLevelandAbove(task)
                          ? () {
                              _setCurrent(task);
                              Navigator.pop(ctx);
                            }
                          : null,
                      icon: const Icon(Icons.my_location),
                      label: const Text('Mark as current'),
                    ),
                    if (task.children.isNotEmpty)
                      OutlinedButton.icon(
                        onPressed: () {
                          _snapshot();
                          setState(() => task.children.clear());
                          _save();
                        },
                        icon: const Icon(Icons.clear_all),
                        label: const Text('Clear subtasks'),
                      ),
                    OutlinedButton.icon(
                      onPressed: () {
                        Navigator.pop(ctx);
                        _confirmAndDeleteTask(task);
                      },
                      icon: const Icon(Icons.delete_forever),
                      label: const Text('Delete'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red,
                        side: const BorderSide(color: Colors.red),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton.icon(
                    label: const Text('Save'),
                    icon: const Icon(Icons.check),
                    onPressed: () {
                      final t = titleCtl.text.trim();
                      _snapshot();
                      setState(() {
                        if (t.isNotEmpty) task.title = t;
                        task.notes = notesCtl.text;
                        task.done = done;
                      });
                      _save();
                      Navigator.pop(ctx);
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // --- UI helpers ---

  List<Widget> _buildPathChips(Task task) {
    final path = task.pathFromRoot();
    return [
      for (int i = 0; i < path.length; i++) ...[
        Chip(
          label: Text(path[i].title),
          avatar: i == 0
              ? const Icon(Icons.flight_takeoff)
              : const Icon(Icons.subdirectory_arrow_right),
        ),
        if (i < path.length - 1)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 2),
            child: Icon(Icons.chevron_right, size: 18),
          ),
      ]
    ];
  }

  // האם משימה מכווצת?
  bool _isCollapsed(Task t) => _collapsedTaskIds.contains(t.id);

  // טוגל כיווץ
  void _toggleCollapsed(Task t) {
    setState(() {
      if (_collapsedTaskIds.contains(t.id)) {
        _collapsedTaskIds.remove(t.id);
      } else {
        _collapsedTaskIds.add(t.id);
      }
    });
  }

  List<Widget> _buildTaskTree(Task task) {
    final tiles = <Widget>[];

    void walk(Task t) {
      tiles.add(_taskTile(t));

      // אם המשימה מכווצת – לא מציגים את הילדים
      if (_isCollapsed(t)) return;

      for (final c in t.children) {
        walk(c);
      }
    }

    walk(task);
    return tiles;
  }

  Widget _taskTile(Task task) {
    final depth = task.depth;
    final dueStr = task.due == null ? null : fmtDate(task.due!);
    final isCurrent = _isCurrent(task);
    final collapsed = _isCollapsed(task);

    final cs = Theme.of(context).colorScheme;
    final primary = cs.primary;
    final onPrimary = cs.onPrimary;
    final accent = primary.darken(0.1);

    return Transform.translate(
      offset: Offset(depth * 10.0, 0),
      child: SizedBox(
        width: MediaQuery.of(context).size.width,
        child: Card(
          elevation: isCurrent ? 1.5 : 0,
          shape: RoundedRectangleBorder(
            side: isCurrent
                ? BorderSide(color: primary, width: 1)
                : BorderSide.none,
            borderRadius: BorderRadius.circular(12),
          ),
          margin: const EdgeInsets.symmetric(vertical: 6),
          child: ListTile(
            onTap: () => _showTaskSheet(task),
            leading: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Checkbox(
                  value: task.done,
                  onChanged: (v) async {
                    if (v == true && task.done == false) {
                      await _promptCompletion(task);
                    } else {
                      _snapshot();
                      setState(() => task.done = v ?? false);
                      _save();
                    }
                  },
                ),
              ],
            ),
            title: Row(
              children: [
                Expanded(
                  child: Text(
                    task.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: task.done
                        ? const TextStyle(
                            decoration: TextDecoration.lineThrough,
                            color: Colors.grey,
                          )
                        : null,
                  ),
                ),
                if (isCurrent)
                  Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: accent,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Text(
                        'CURRENT',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: onPrimary,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            subtitle: Row(
              children: [
                if (dueStr != null) ...[
                  const Icon(Icons.event, size: 16),
                  const SizedBox(width: 4),
                  Text(dueStr),
                  const SizedBox(width: 12),
                ],
                if (task.completionMinutes != null) ...[
                  const Icon(Icons.timer, size: 16),
                  const SizedBox(width: 4),
                  Text('${task.completionMinutes}m'),
                  const SizedBox(width: 12),
                ],
                if (task.completionNote != null &&
                    task.completionNote!.isNotEmpty) ...[
                  const Icon(Icons.notes, size: 16),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      task.completionNote!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
                if (task.children.isNotEmpty) ...[
                  const SizedBox(width: 12),
                  const Icon(Icons.account_tree, size: 16),
                  const SizedBox(width: 4),
                  Text(
                    collapsed
                        ? '${task.children.length} subtasks (hidden)'
                        : '${task.children.length} subtasks',
                  ),
                ],
              ],
            ),
            trailing: Wrap(
              spacing: 4,
              children: [
                if (task.children.isNotEmpty)
                  IconButton(
                    tooltip: collapsed ? 'Show subtasks' : 'Hide subtasks',
                    icon: Icon(
                      collapsed ? Icons.expand_more : Icons.expand_less,
                    ),
                    onPressed: () => _toggleCollapsed(task),
                  ),
                IconButton(
                  tooltip: 'Split (2–5)',
                  onPressed: () => _showSplitDialog(task),
                  icon: const Icon(Icons.call_split),
                ),
                Tooltip(
                  message: _isThirdLevelandAbove(task)
                      ? 'Mark as current'
                      : 'Only third-level tasks can be marked as CURRENT',
                  child: IconButton(
                    onPressed: _isThirdLevelandAbove(task)
                        ? () => _setCurrent(task)
                        : null,
                    icon: const Icon(Icons.my_location),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final r = _currentRoot;

    // Find current title for banner
    String? currentTitle;
    if (r != null && r.currentId != null) {
      Task? found;
      void search(Task t) {
        if (t.id == r.currentId) {
          found = t;
          return;
        }
        for (final c in t.children) {
          if (found != null) break;
          search(c);
        }
      }

      search(r);
      currentTitle = found?.title;
    }

    final cs = Theme.of(context).colorScheme;
    final accent = cs.primary.darken(0.1);
    final onAccent = cs.onPrimary;

    return Scaffold(
      appBar: AppBar(
        title: _roots.isEmpty
            ? const Text('Split To-Do')
            : Row(
                children: [

                  Expanded(
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<int>(
                        value: _currentIndex,
                        isExpanded: true,
                        items: [
                          for (int i = 0; i < _roots.length; i++)
                            DropdownMenuItem(
                              value: i,
                              child: Text(
                                _roots[i].title,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                        onChanged: (v) {
                          if (v == null) return;
                          setState(() => _currentIndex = v);
                        },
                      ),
                    ),
                  ),
                ],
              ),
        actions: [
          IconButton(
            tooltip: _canUndo ? 'Undo' : 'Undo (disabled)',
            onPressed: _canUndo ? _undo : null,
            icon: const Icon(Icons.undo),
          ),
          IconButton(
            tooltip: 'Achievements',
            icon: const Icon(Icons.emoji_events),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const AchievementsPage()),
              );
            },
          ),
          IconButton(
            tooltip: 'New list',
            onPressed: _promptForNewList,
            icon: const Icon(Icons.playlist_add),
          ),
          PopupMenuButton<String>(
            onSelected: (value) {
              switch (value) {
                case 'rename':
                  _renameCurrentList();
                  break;
                case 'clear_current':
                  if (r != null) _clearCurrentOf(r);
                  break;
                case 'delete':
                  _deleteCurrentList();
                  break;
                case 'reset':
                  if (r != null) {
                    _snapshot();
                    setState(() {
                      r.children.clear();
                      r.done = false;
                      r.due = null;
                      r.notes = '';
                      r.currentId = null;
                    });
                    _save();
                  }
                  break;
              }
            },
            itemBuilder: (ctx) => [
              const PopupMenuItem(
                value: 'rename',
                child: Text('Rename current list'),
              ),
              const PopupMenuItem(
                value: 'clear_current',
                child: Text('Clear current marker'),
              ),
              const PopupMenuItem(
                value: 'reset',
                child: Text('Reset current list'),
              ),
              const PopupMenuItem(
                value: 'delete',
                child: Text(
                  'Delete current list',
                  style: TextStyle(color: Colors.red),
                ),
              ),
            ],
          ),
        ],
        bottom: (currentTitle != null)
            ? PreferredSize(
                preferredSize: const Size.fromHeight(40),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: accent,
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.my_location,
                              size: 16,
                              color: onAccent,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'CURRENT',
                              style: TextStyle(
                                color: onAccent,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          currentTitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                ),
              )
            : null,
      ),
      body: r == null
          ? const Center(
              child: Text('Create your first list to get started'),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
              children: [
                Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: accent,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.flag_rounded, color: onAccent),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Final goal: ${r.title}',
                          style: TextStyle(
                            color: onAccent,
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Column(
                    children: _buildTaskTree(r),
                  ),
                ),
                const SizedBox(height: 24),
              ],
            ),
    );
  }
}
