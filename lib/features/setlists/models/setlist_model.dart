// lib/features/setlists/models/setlist_model.dart
import 'dart:convert';
import 'package:uuid/uuid.dart';

/// Represents a single group of songs, like "Set 1" or "Encore".
class SongSet {
  String id;
  String name;
  List<String> songIds; // Ordered list of song IDs in this set

  SongSet({
    required this.id,
    required this.name,
    required this.songIds,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'songIds': songIds,
  };

  factory SongSet.fromJson(Map<String, dynamic> map) {
    return SongSet(
      id: map['id'] as String,
      name: map['name'] as String,
      songIds: List<String>.from(map['songIds'] as List<dynamic>),
    );
  }
}

/// Represents a complete Setlist, which can be tied to a gig or be independent.
class Setlist {
  String id; // Unique ID for the setlist itself
  String name; // e.g., "Standard Rock Gig", "Acoustic Cafe Set"
  String? gigId; // Nullable, to allow for independent setlists
  List<SongSet> sets; // A setlist contains one or more `SongSet`s

  Setlist({
    required this.id,
    required this.name,
    this.gigId,
    required this.sets,
  }) {
    // Ensure that every setlist has at least one set.
    if (sets.isEmpty) {
      sets.add(SongSet(id: const Uuid().v4(), name: 'Set 1', songIds: []));
    }
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'gigId': gigId,
    'sets': sets.map((set) => set.toJson()).toList(),
  };

  factory Setlist.fromJson(Map<String, dynamic> map) {
    return Setlist(
      id: map['id'] as String,
      name: map['name'] as String,
      gigId: map['gigId'] as String?,
      sets: (map['sets'] as List<dynamic>)
          .map((setMap) => SongSet.fromJson(setMap as Map<String, dynamic>))
          .toList(),
    );
  }

  /// Finds the total number of songs across all sets.
  int get totalSongCount {
    return sets.fold(0, (previousValue, set) => previousValue + set.songIds.length);
  }

  /// Encodes a list of Setlist objects to a JSON string.
  static String encode(List<Setlist> setlists) => json.encode(
    setlists.map((setlist) => setlist.toJson()).toList(),
  );

  /// Decodes a JSON string into a list of Setlist objects, with added safety checks.
  static List<Setlist> decode(String setlistsString) {
    if (setlistsString.isEmpty) {
      return [];
    }
    try {
      final dynamic decoded = json.decode(setlistsString);
      if (decoded is List) {
        return decoded
            .map<Setlist?>((item) {
          try {
            return Setlist.fromJson(item as Map<String, dynamic>);
          } catch (e) {
            // Safely skip items that fail to parse
            print("Error decoding a single setlist item: $e");
            return null;
          }
        })
            .whereType<Setlist>() // Filter out any nulls from failed parsing
            .toList();
      }
      return []; // Return empty if the decoded JSON is not a list
    } catch (e) {
      print("Error decoding setlist string: $e");
      return []; // Return empty on a general decoding error
    }
  }
}
