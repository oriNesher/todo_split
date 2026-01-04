import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:todo_split/models/task.dart';

import 'pages/lists_overview_page.dart';
import 'pages/split_todo_page.dart';

void main() => runApp(const TaskSplitApp());

class TaskSplitApp extends StatelessWidget {
  const TaskSplitApp({super.key});

  @override
  Widget build(BuildContext context) {
    const trophyOrange = Color(0xFFFFA733);
    const darkBackground = Color(0xFF05060A);
    const darkSurface = Color(0xFF14151F);

    final darkColorScheme = ColorScheme.fromSeed(
      seedColor: trophyOrange,
      brightness: Brightness.dark,
    );

    final darkTheme = ThemeData(
      useMaterial3: true,
      colorScheme: darkColorScheme.copyWith(
        background: darkBackground,
        surface: darkSurface,
      ),
      scaffoldBackgroundColor: darkBackground,
      cardTheme: CardThemeData(
        color: darkSurface,
        margin: const EdgeInsets.symmetric(vertical: 6),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
      ),
    );

    return MaterialApp(
      title: 'Split To-Do',
      debugShowCheckedModeBanner: false,
      theme: darkTheme,
      darkTheme: darkTheme,
      themeMode: ThemeMode.dark,
      home: const AppRoot(), // home lives inside MaterialApp
    );
  }
}

class AppRoot extends StatefulWidget {
  const AppRoot({super.key});

  @override
  State<AppRoot> createState() => _AppRootState();
}

class _AppRootState extends State<AppRoot> {
  static const _storageKey = 'split_todo_roots_v1';

  bool _loaded = false;
  List<Task> _roots = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  static const _historyLimit = 30;
  final List<String> _history = [];

  /// Takes a snapshot of all roots for undo purposes.
  void _snapshot() {
    final snap = jsonEncode(_roots.map((r) => r.toMap()).toList());
    _history.add(snap);
    if (_history.length > _historyLimit) {
      _history.removeAt(0);
    }
  }

  void _undo() {
    if (_history.isEmpty) return;

    final last = _history.removeLast();

    try {
      final decoded = jsonDecode(last) as List<dynamic>;
      final restored =
          decoded.map((m) => Task.fromMap(m as Map<String, dynamic>)).toList();

      setState(() {
        _applyRestoredRootsInPlace(restored);
      });

      _save();
    } catch (_) {}
  }

  /// Applies restored roots without replacing existing object references.
  /// This is critical so an already-open SplitTodoPage (holding widget.root)
  /// will see the updated data.
  void _applyRestoredRootsInPlace(List<Task> restored) {
    // Build lookup by id for quick matching
    final restoredById = <String, Task>{for (final r in restored) r.id: r};
    final currentById = <String, Task>{for (final r in _roots) r.id: r};

    // 1) Update existing roots in place OR add new ones
    for (final restoredRoot in restored) {
      final existing = currentById[restoredRoot.id];
      if (existing == null) {
        _roots.add(restoredRoot);
      } else {
        // Update scalar fields
        existing.title = restoredRoot.title;
        existing.done = restoredRoot.done;
        existing.notes = restoredRoot.notes;
        existing.due = restoredRoot.due;
        existing.currentId = restoredRoot.currentId;

        // Replace children list in place (keep same root reference)
        existing.children
          ..clear()
          ..addAll(restoredRoot.children);

        // Ensure parent pointers are correct in the restored subtree
        _fixParentPointers(existing, parent: null);
      }
    }

    // 2) Remove roots that no longer exist in restored snapshot
    _roots.removeWhere((r) => !restoredById.containsKey(r.id));
  }

  /// Fixes parent pointers recursively after replacing children.
  /// Important because fromMap typically reconstructs objects fresh.
  void _fixParentPointers(Task node, {required Task? parent}) {
    node.parent = parent;
    for (final c in node.children) {
      _fixParentPointers(c, parent: node);
    }
  }

  void _resetHistory() {
    _history.clear();
  }

  /// Loads all roots (lists) from SharedPreferences.
  /// This runs once when the app starts.
  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_storageKey);

    if (raw != null && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw) as List<dynamic>;
        _roots = decoded
            .map((e) => Task.fromMap(e as Map<String, dynamic>))
            .toList();
      } catch (_) {
        _roots = [];
      }
    }

    setState(() => _loaded = true);
  }

  /// Persists the current roots list to SharedPreferences.
  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    final json = jsonEncode(_roots.map((r) => r.toMap()).toList());
    await prefs.setString(_storageKey, json);
  }

  /// Creates a new list (root) and saves it.
  void _createNewList(BuildContext context) {
    final ctl = TextEditingController();

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: const Text('Create a new list'),
        content: TextField(
          controller: ctl,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Final goal (e.g., Build a portfolio website)',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              final title = ctl.text.trim();
              if (title.isEmpty) return;

              setState(() {
                _roots.add(Task(
                  id: DateTime.now().microsecondsSinceEpoch.toString(),
                  title: title,
                ));
              });

              _save();
              Navigator.pop(context);
            },
            child: const Text('Create'),
          ),
        ],
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

    return ListsOverviewPage(
      roots: _roots,
      onOpenList: (index) {
        _resetHistory();
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => SplitTodoPage(
              root: _roots[index],
              onSave: _save,
              onBeforeChange: _snapshot,
              onUndo: _undo,
              canUndo: () => _history.isNotEmpty,
              onExit: _resetHistory,
            ),
          ),
        );
      },
      onCreateNewList: () => _createNewList(context),
    );
  }
}
