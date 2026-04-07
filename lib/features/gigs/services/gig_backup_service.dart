// lib/features/gigs/services/gig_backup_service.dart
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// Type tag constants used in the backup envelope.
/// Kept as a private detail of this service — callers just use
/// [exportAll] and [importAll].
class _T {
  static const string = 'String';
  static const stringList = 'StringList';
  static const bool_ = 'bool';
  static const int_ = 'int';
  static const double_ = 'double';
}

/// Result returned by [GigBackupService.importAll].
class ImportResult {
  final bool success;
  final int restoredKeys;
  final String? errorMessage;

  const ImportResult._({
    required this.success,
    required this.restoredKeys,
    this.errorMessage,
  });

  factory ImportResult.ok(int restoredKeys) =>
      ImportResult._(success: true, restoredKeys: restoredKeys);

  factory ImportResult.failed(String message) =>
      ImportResult._(success: false, restoredKeys: 0, errorMessage: message);
}

class GigBackupService {
  /// Keys that should never be included in a backup or cleared on restore.
  /// These are ephemeral session values that make no sense to persist across
  /// devices or reinstalls.
  static const _excludedKeys = {
    'skipped_retrospective_gigs', // session-only skip list
    'last_retrospective_check',   // rate-limit timestamp — irrelevant after restore
  };

  // ── EXPORT ──────────────────────────────────────────────────────────────────

  /// Exports all SharedPreferences data as a typed JSON string.
  ///
  /// Each value is wrapped in `{"t": "<type>", "v": <value>}` so the restore
  /// knows exactly which setter to call, regardless of JSON's ambiguous number
  /// representation.
  ///
  /// Returns the JSON string, or throws if SharedPreferences cannot be read.
  static Future<String> exportAll() async {
    final prefs = await SharedPreferences.getInstance();
    final allKeys = prefs.getKeys();

    final Map<String, dynamic> envelope = {};

    for (final key in allKeys) {
      if (_excludedKeys.contains(key)) continue;

      final value = prefs.get(key);
      if (value == null) continue;

      if (value is String) {
        envelope[key] = {'t': _T.string, 'v': value};
      } else if (value is bool) {
        envelope[key] = {'t': _T.bool_, 'v': value};
      } else if (value is int) {
        envelope[key] = {'t': _T.int_, 'v': value};
      } else if (value is double) {
        envelope[key] = {'t': _T.double_, 'v': value};
      } else if (value is List) {
        // SharedPreferences only allows List<String>, so this cast is safe.
        envelope[key] = {'t': _T.stringList, 'v': List<String>.from(value)};
      }
      // Any unknown type is silently skipped rather than corrupting the backup.
    }

    // Add a metadata header so we can version the format later.
    final backup = {
      '_meta': {
        'version': 1,
        'exportedAt': DateTime.now().toIso8601String(),
        'keyCount': envelope.length,
      },
      'data': envelope,
    };

    return const JsonEncoder.withIndent('  ').convert(backup);
  }

  // ── IMPORT ──────────────────────────────────────────────────────────────────

  /// Validates and restores a backup produced by [exportAll].
  ///
  /// Strategy: **replace** — all existing non-excluded keys are cleared before
  /// writing the backup values. This is the safest approach and avoids stale
  /// keys from a previous install leaking into the restored state.
  ///
  /// Returns an [ImportResult] describing success or the reason for failure.
  static Future<ImportResult> importAll(String jsonString) async {
    // ── 1. Parse ────────────────────────────────────────────────────────────
    Map<String, dynamic> backup;
    try {
      backup = jsonDecode(jsonString) as Map<String, dynamic>;
    } catch (_) {
      return ImportResult.failed(
        'The pasted text is not valid JSON. '
            'Make sure you copied the entire backup without truncating it.',
      );
    }

    // ── 2. Validate structure ────────────────────────────────────────────────
    if (!backup.containsKey('data') || backup['data'] is! Map) {
      return ImportResult.failed(
        'This JSON does not look like a Money Gigs backup. '
            'The required "data" field is missing or malformed.',
      );
    }

    final meta = backup['_meta'];
    if (meta is Map) {
      final version = meta['version'];
      if (version is int && version > 1) {
        return ImportResult.failed(
          'This backup was created with a newer version of the app (format v$version). '
              'Please update the app before restoring.',
        );
      }
    }

    final data = backup['data'] as Map<String, dynamic>;

    // ── 3. Clear existing data ───────────────────────────────────────────────
    final prefs = await SharedPreferences.getInstance();
    final existingKeys = prefs.getKeys().toList();
    for (final key in existingKeys) {
      if (!_excludedKeys.contains(key)) {
        await prefs.remove(key);
      }
    }

    // ── 4. Write each key ────────────────────────────────────────────────────
    int restored = 0;
    for (final entry in data.entries) {
      final key = entry.key;
      final wrapper = entry.value;

      if (wrapper is! Map || !wrapper.containsKey('t') || !wrapper.containsKey('v')) {
        // Malformed entry — skip rather than crash the whole restore.
        continue;
      }

      final type = wrapper['t'] as String?;
      final value = wrapper['v'];

      try {
        switch (type) {
          case _T.string:
            await prefs.setString(key, value as String);
          case _T.bool_:
            await prefs.setBool(key, value as bool);
          case _T.int_:
            await prefs.setInt(key, value as int);
          case _T.double_:
          // JSON numbers parsed as int when they have no decimal point.
            await prefs.setDouble(key, (value as num).toDouble());
          case _T.stringList:
            await prefs.setStringList(
              key,
              (value as List).map((e) => e.toString()).toList(),
            );
          default:
            continue; // Unknown type tag — skip
        }
        restored++;
      } catch (_) {
        // Type mismatch on a single key — skip and continue.
        continue;
      }
    }

    if (restored == 0) {
      return ImportResult.failed(
        'The backup was parsed but contained no recognisable data. '
            'Nothing was restored.',
      );
    }

    return ImportResult.ok(restored);
  }
}