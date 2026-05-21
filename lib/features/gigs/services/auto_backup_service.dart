// lib/features/gigs/services/auto_backup_service.dart
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:the_money_gigs/core/utils/logger.dart';
import 'gig_backup_service.dart';

/// Silently creates and restores a rolling backup of SharedPreferences data.
///
/// The backup file lives in the app's documents directory and survives
/// app updates. It does NOT survive a full uninstall (use the manual
/// export/import in Profile for cross-device or post-uninstall recovery).
///
/// Typical call order at startup:
///   1. [restoreIfNeeded] — recover from a wiped state before app runs
///   2. [saveBackup]      — immediately snapshot current state
class AutoBackupService {
  static const _backupFileName = 'moneygigs_auto_backup.json';

  /// Returns the backup file path in the app's documents directory.
  static Future<File> _backupFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$_backupFileName');
  }

  // ── SAVE ──────────────────────────────────────────────────────────────────

  /// Exports all SharedPreferences to a local JSON file.
  ///
  /// Called on every startup after [restoreIfNeeded] so the backup
  /// always reflects the most recent known-good state.
  static Future<void> saveBackup() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final hasGigs = prefs.containsKey('gigs_list');

      // Don't overwrite a good backup with an empty state.
      if (!hasGigs) {
        log('📦 AutoBackup: skipping save — no gig data present.');
        return;
      }

      final json = await GigBackupService.exportAll();
      final file = await _backupFile();
      await file.writeAsString(json);
      log('📦 AutoBackup: saved to ${file.path}');
    } catch (e) {
      // Never crash the app over a backup failure.
      log('📦 AutoBackup: save failed silently — $e');
    }
  }

  // ── RESTORE ───────────────────────────────────────────────────────────────

  /// Restores from the local backup if SharedPreferences appears empty.
  ///
  /// "Empty" is defined as: the `gigs_list` key is absent. This is the
  /// earliest sign that a reinstall or clear-data event occurred.
  ///
  /// Returns [true] if a restore was performed, [false] otherwise.
  static Future<bool> restoreIfNeeded() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // Data is present — nothing to restore.
      if (prefs.containsKey('gigs_list')) {
        log('📦 AutoBackup: data intact, no restore needed.');
        return false;
      }

      final file = await _backupFile();
      if (!await file.exists()) {
        log('📦 AutoBackup: no backup file found — first install or backup cleared.');
        return false;
      }

      final json = await file.readAsString();
      final result = await GigBackupService.importAll(json);

      if (result.success) {
        log('📦 AutoBackup: restored ${result.restoredKeys} keys from backup.');
        return true;
      } else {
        log('📦 AutoBackup: restore failed — ${result.errorMessage}');
        return false;
      }
    } catch (e) {
      log('📦 AutoBackup: restore failed silently — $e');
      return false;
    }
  }

  // ── DIAGNOSTICS ───────────────────────────────────────────────────────────

  /// Returns the last-modified timestamp of the backup file, or null if none.
  /// Useful for showing "Last backed up: X" in a settings/profile screen.
  static Future<DateTime?> lastBackupTime() async {
    try {
      final file = await _backupFile();
      if (await file.exists()) {
        return file.lastModified();
      }
    } catch (_) {}
    return null;
  }
}