// lib/features/setlists/models/song_model.dart
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart'; // <<< FIX: Added import



class Song {
  final String id;
  final String title;
  final String? artist; // Composer/Artist
  final String? songKey; // Key
  final int? tempo; // BPM
  final Duration? duration;
  final String? notes;
  // --- 'order' property REMOVED ---

  Song({
    required this.id,
    required this.title,
    this.artist,
    this.songKey,
    this.tempo,
    this.duration,
    this.notes,
    // --- 'order' parameter REMOVED from constructor ---
  });

  Song copyWith({
    String? id,
    String? title,
    String? artist,
    String? songKey,
    int? tempo,
    Duration? duration,
    String? notes,
    // --- No 'order' here ---
  }) {
    return Song(
      id: id ?? this.id,
      title: title ?? this.title,
      artist: artist ?? this.artist,
      songKey: songKey ?? this.songKey,
      tempo: tempo ?? this.tempo,
      duration: duration ?? this.duration,
      notes: notes ?? this.notes,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'artist': artist,
      'songKey': songKey,
      'tempo': tempo,
      'duration': duration?.inSeconds,
      'notes': notes,
      // --- 'order' REMOVED from JSON ---
    };
  }

  factory Song.fromJson(Map<String, dynamic> map) {
    return Song(
      id: map['id'] as String,
      title: map['title'] as String,
      artist: map['artist'] as String?,
      songKey: map['songKey'] as String?,
      tempo: map['tempo'] as int?,
      duration: map['duration'] != null ? Duration(seconds: map['duration'] as int) : null,
      notes: map['notes'] as String?,
      // --- 'order' REMOVED from factory ---
    );
  }

  // It would be beneficial to have a central repository for songs.
  // For now, let's add static methods here to manage a list in SharedPreferences.

  static Future<void> saveSongs(List<Song> songs) async {
    final prefs = await SharedPreferences.getInstance();
    final String encodedData = json.encode(
      songs.map((song) => song.toJson()).toList(),
    );
    await prefs.setString('all_songs', encodedData);
  }

  static Future<List<Song>> loadSongs() async {
    final prefs = await SharedPreferences.getInstance();
    final String? songsString = prefs.getString('all_songs');
    if (songsString == null) {
      return [];
    }
    final List<dynamic> decodedData = json.decode(songsString);
    return decodedData.map((item) => Song.fromJson(item)).toList();
  }
}
