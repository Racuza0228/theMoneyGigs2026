// lib/features/checklist/checklist_repository.dart

import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import 'gig_checklist_item.dart';

class ChecklistRepository {
  static const String _keyItems = 'gig_checklist_items';
  static const String _keySeeded = 'gig_checklist_seeded_v1';

  static const List<Map<String, dynamic>> _defaultItems = [
    // Equipment
    {'label': 'Instrument', 'category': 'equipment'},
    {'label': 'Cables', 'category': 'equipment'},
    {'label': 'Pedalboard / effects', 'category': 'equipment'},
    {'label': 'Amp or DI box', 'category': 'equipment'},
    {'label': 'Backup strings / reeds / sticks', 'category': 'equipment'},
    {'label': 'Power strip', 'category': 'equipment'},
    {'label': 'Music stand + charts', 'category': 'equipment'},
    // Logistics
    {'label': 'Parking paid / meter set', 'category': 'logistics'},
    {'label': 'Load-in time confirmed', 'category': 'logistics'},
    {'label': 'Venue contact saved', 'category': 'logistics'},
    {'label': 'Set list printed or on phone', 'category': 'logistics'},
    {'label': 'Gas / travel time checked', 'category': 'logistics'},
    // Objectives
    {'label': 'Power up 4K camera for content', 'category': 'objectives'},
    {'label': 'Hand out cards or share app with musicians', 'category': 'objectives'},
    {'label': 'Note venue details for app entry', 'category': 'objectives'},
    {'label': 'Collect email / booking contact', 'category': 'objectives'},
  ];

  final _uuid = const Uuid();

  Future<List<GigChecklistItem>> loadItems() async {
    final prefs = await SharedPreferences.getInstance();

    // Seed defaults once
    final bool alreadySeeded = prefs.getBool(_keySeeded) ?? false;
    if (!alreadySeeded) {
      final seeded = _defaultItems.map((d) {
        return GigChecklistItem(
          id: _uuid.v4(),
          label: d['label'] as String,
          category: ChecklistCategory.values.firstWhere(
                (e) => e.name == d['category'],
            orElse: () => ChecklistCategory.equipment,
          ),
          isChecked: false,
          isDefault: true,
        );
      }).toList();
      await prefs.setString(_keyItems, GigChecklistItem.encode(seeded));
      await prefs.setBool(_keySeeded, true);
      return seeded;
    }

    final String? stored = prefs.getString(_keyItems);
    if (stored == null || stored.isEmpty) return [];
    try {
      return GigChecklistItem.decode(stored);
    } catch (_) {
      return [];
    }
  }

  Future<void> saveItems(List<GigChecklistItem> items) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyItems, GigChecklistItem.encode(items));
  }

  Future<void> resetCheckedState(List<GigChecklistItem> items) async {
    final reset = items.map((i) => i.copyWith(isChecked: false)).toList();
    await saveItems(reset);
  }

  String newId() => _uuid.v4();
}