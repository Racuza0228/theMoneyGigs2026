// lib/features/checklist/gig_checklist_page.dart

import 'package:flutter/material.dart';
import 'gig_checklist_item.dart';
import 'checklist_repository.dart';

class GigChecklistPage extends StatefulWidget {
  const GigChecklistPage({super.key});

  @override
  State<GigChecklistPage> createState() => _GigChecklistPageState();
}

class _GigChecklistPageState extends State<GigChecklistPage> {
  final ChecklistRepository _repo = ChecklistRepository();
  List<GigChecklistItem> _items = [];
  bool _loading = true;

  // Text controllers per category for the inline add field
  final Map<ChecklistCategory, TextEditingController> _controllers = {
    for (var c in ChecklistCategory.values) c: TextEditingController()
  };

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    final items = await _repo.loadItems();
    if (mounted) setState(() { _items = items; _loading = false; });
  }

  Future<void> _save() async {
    await _repo.saveItems(_items);
  }

  List<GigChecklistItem> _itemsFor(ChecklistCategory category) =>
      _items.where((i) => i.category == category).toList();

  void _toggle(GigChecklistItem item) {
    setState(() {
      final idx = _items.indexWhere((i) => i.id == item.id);
      if (idx != -1) _items[idx] = item.copyWith(isChecked: !item.isChecked);
    });
    _save();
  }

  void _delete(GigChecklistItem item) {
    setState(() { _items.removeWhere((i) => i.id == item.id); });
    _save();
  }

  void _addItem(ChecklistCategory category) {
    final ctrl = _controllers[category]!;
    final label = ctrl.text.trim();
    if (label.isEmpty) return;
    final newItem = GigChecklistItem(
      id: _repo.newId(),
      label: label,
      category: category,
      isChecked: false,
      isDefault: false,
    );
    setState(() { _items.add(newItem); });
    ctrl.clear();
    _save();
  }

  Future<void> _confirmReset() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reset Checklist?'),
        content: const Text(
          'This will uncheck all items. Your custom items will be kept.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Reset'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _repo.resetCheckedState(_items);
    await _load();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Checklist reset. Good luck tonight!')),
      );
    }
  }

  int get _checkedCount => _items.where((i) => i.isChecked).length;
  int get _totalCount => _items.length;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Gig Checklist'),
        actions: [
          if (!_loading)
            Padding(
              padding: const EdgeInsets.only(right: 12.0),
              child: Center(
                child: Text(
                  '$_checkedCount / $_totalCount',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: _checkedCount == _totalCount && _totalCount > 0
                        ? Colors.green
                        : colorScheme.onSurface,
                  ),
                ),
              ),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
        children: [
          // Progress bar
          LinearProgressIndicator(
            value: _totalCount == 0 ? 0 : _checkedCount / _totalCount,
            minHeight: 4,
            backgroundColor: colorScheme.surfaceVariant,
            valueColor: AlwaysStoppedAnimation<Color>(
              _checkedCount == _totalCount && _totalCount > 0
                  ? Colors.green
                  : colorScheme.primary,
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.only(bottom: 100),
              children: [
                for (final category in ChecklistCategory.values)
                  _buildCategorySection(category),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: _loading
          ? null
          : SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              icon: const Icon(Icons.restart_alt),
              label: const Text('Reset Checked State'),
              style: OutlinedButton.styleFrom(
                foregroundColor: colorScheme.error,
                side: BorderSide(color: colorScheme.error),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              onPressed: _confirmReset,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCategorySection(ChecklistCategory category) {
    final categoryItems = _itemsFor(category);
    final ctrl = _controllers[category]!;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Section header
        Container(
          width: double.infinity,
          color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.5),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              Icon(_categoryIcon(category),
                  size: 18,
                  color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 8),
              Text(
                category.displayName.toUpperCase(),
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                  letterSpacing: 1.2,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
              const Spacer(),
              Text(
                '${categoryItems.where((i) => i.isChecked).length}/${categoryItems.length}',
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        // Items
        ...categoryItems.map((item) => _buildItemTile(item)),
        // Add item row
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: ctrl,
                  decoration: InputDecoration(
                    hintText: 'Add to ${category.displayName}...',
                    hintStyle: const TextStyle(fontSize: 14),
                    isDense: true,
                    border: const OutlineInputBorder(),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                  ),
                  textCapitalization: TextCapitalization.sentences,
                  onSubmitted: (_) => _addItem(category),
                  style: const TextStyle(fontSize: 14),
                ),
              ),
              const SizedBox(width: 8),
              TextButton(
                onPressed: () => _addItem(category),
                child: const Text('Add'),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
      ],
    );
  }

  Widget _buildItemTile(GigChecklistItem item) {
    return Dismissible(
      key: ValueKey(item.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        color: Theme.of(context).colorScheme.errorContainer,
        padding: const EdgeInsets.only(right: 20),
        child: Icon(Icons.delete_outline,
            color: Theme.of(context).colorScheme.onErrorContainer),
      ),
      onDismissed: (_) => _delete(item),
      child: CheckboxListTile(
        value: item.isChecked,
        onChanged: (_) => _toggle(item),
        title: Text(
          item.label,
          style: TextStyle(
            decoration: item.isChecked ? TextDecoration.lineThrough : null,
            color: item.isChecked
                ? Theme.of(context).colorScheme.onSurface.withOpacity(0.45)
                : null,
            fontSize: 15,
          ),
        ),
        secondary: IconButton(
          icon: Icon(Icons.delete_outline,
              size: 20,
              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.35)),
          onPressed: () => _delete(item),
          tooltip: 'Delete',
        ),
        controlAffinity: ListTileControlAffinity.leading,
        dense: true,
        activeColor: Theme.of(context).colorScheme.primary,
      ),
    );
  }

  IconData _categoryIcon(ChecklistCategory category) {
    switch (category) {
      case ChecklistCategory.equipment:
        return Icons.headset_mic_outlined;
      case ChecklistCategory.logistics:
        return Icons.map_outlined;
      case ChecklistCategory.objectives:
        return Icons.flag_outlined;
    }
  }
}