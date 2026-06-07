// lib/features/checklist/gig_checklist_item.dart

import 'dart:convert';

enum ChecklistCategory { equipment, logistics, objectives }

extension ChecklistCategoryExtension on ChecklistCategory {
  String get displayName {
    switch (this) {
      case ChecklistCategory.equipment:
        return 'Equipment';
      case ChecklistCategory.logistics:
        return 'Logistics';
      case ChecklistCategory.objectives:
        return 'Objectives';
    }
  }
}

class GigChecklistItem {
  final String id;
  final String label;
  final ChecklistCategory category;
  final bool isChecked;
  final bool isDefault;

  const GigChecklistItem({
    required this.id,
    required this.label,
    required this.category,
    this.isChecked = false,
    this.isDefault = false,
  });

  GigChecklistItem copyWith({
    String? id,
    String? label,
    ChecklistCategory? category,
    bool? isChecked,
    bool? isDefault,
  }) {
    return GigChecklistItem(
      id: id ?? this.id,
      label: label ?? this.label,
      category: category ?? this.category,
      isChecked: isChecked ?? this.isChecked,
      isDefault: isDefault ?? this.isDefault,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'label': label,
    'category': category.name,
    'isChecked': isChecked,
    'isDefault': isDefault,
  };

  factory GigChecklistItem.fromJson(Map<String, dynamic> json) {
    return GigChecklistItem(
      id: json['id'] as String,
      label: json['label'] as String,
      category: ChecklistCategory.values.firstWhere(
            (e) => e.name == json['category'],
        orElse: () => ChecklistCategory.equipment,
      ),
      isChecked: json['isChecked'] as bool? ?? false,
      isDefault: json['isDefault'] as bool? ?? false,
    );
  }

  static String encode(List<GigChecklistItem> items) =>
      jsonEncode(items.map((i) => i.toJson()).toList());

  static List<GigChecklistItem> decode(String jsonString) {
    final List<dynamic> decoded = jsonDecode(jsonString);
    return decoded.map((e) => GigChecklistItem.fromJson(e as Map<String, dynamic>)).toList();
  }
}