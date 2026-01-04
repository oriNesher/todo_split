// lib/pages/lists_overview_page.dart
import 'package:flutter/material.dart';

import '../models/task.dart';

class ListsOverviewPage extends StatelessWidget {
  /// Creates the Lists Overview (Home) screen.
  ///
  /// This screen is intentionally "dumb":
  /// - It only renders the UI for the lists gallery.
  /// - It does NOT own persistence, undo history, or list mutations.
  /// Those are injected via callbacks to keep refactor minimal and safe.
  const ListsOverviewPage({
    super.key,
    required this.roots,
    required this.onOpenList,
    required this.onCreateNewList,
    this.title = 'Your Lists',
  });

  /// All list roots (each root == one user list).
  final List<Task> roots;

  /// Called when user taps a list card.
  /// The parent decides how to navigate (push to SplitTodoPage).
  final ValueChanged<int> onOpenList;

  /// Called when user wants to create a new list.
  /// Parent should reuse the existing "create list" dialog logic.
  final VoidCallback onCreateNewList;

  /// AppBar title (configurable).
  final String title;

  @override
  Widget build(BuildContext context) {
    final hasLists = roots.isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          // Add new list (reuses the existing implementation through callback).
          IconButton(
            tooltip: 'New list',
            onPressed: onCreateNewList,
            icon: const Icon(Icons.playlist_add),
          ),

          // NOTE (future):
          // This is a good place to add an Undo icon later, once list-level undo is implemented.
          // Example:
          // IconButton(onPressed: onUndo, icon: const Icon(Icons.undo)),
        ],
      ),
      body: SafeArea(
        child: hasLists ? _buildGrid(context) : _buildEmptyState(context),
      ),
    );
  }

  /// Builds the 2-column gallery grid of list cards.
  ///
  /// Grid is fixed to 2 columns, and each item aims to be square-like using childAspectRatio: 1.
  Widget _buildGrid(BuildContext context) {
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 1, // square cards
      ),
      itemCount: roots.length,
      itemBuilder: (context, index) {
        final root = roots[index];
        return _ListCard(
          title: root.title,
          onTap: () => onOpenList(index),
        );
      },
    );
  }

  /// Builds an empty state UI when user has no lists yet.
  ///
  /// Provides a clear CTA to create the first list.
  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.view_module_outlined, size: 44),
            const SizedBox(height: 12),
            Text(
              'No lists yet',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              'Create your first list to get started.',
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onCreateNewList,
              icon: const Icon(Icons.playlist_add),
              label: const Text('Create a new list'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ListCard extends StatelessWidget {
  /// A single square-like card representing a list (root).
  ///
  /// For now it only shows the list title.
  /// Later we can extend it with:
  /// - double tap / long press menu
  /// - list metadata (tasks count, last updated, etc.)
  const _ListCard({
    required this.title,
    required this.onTap,
  });

  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Material(
      color: cs.surface,
      borderRadius: BorderRadius.circular(16),
      elevation: 0,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: cs.outlineVariant.withOpacity(0.6)),
          ),
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Small icon to visually communicate "this is a list".
              Icon(Icons.flag_rounded, color: cs.primary),
              const SizedBox(height: 10),

              // List title (root.title)
              Expanded(
                child: Align(
                  alignment: Alignment.topLeft,
                  child: Text(
                    title,
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ),

              // NOTE (future):
              // This area can host subtle metadata (e.g., tasks count).
              // Keeping it empty for now to match the current requirement.
            ],
          ),
        ),
      ),
    );
  }
}
