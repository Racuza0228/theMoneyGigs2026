// lib/features/contacts/repositories/contact_repository.dart
//
// Local-only CRUD for the networking Contact feature — SharedPreferences,
// same pattern as gigs_list/saved_locations elsewhere in the app. No
// Firestore mirror: contacts are personal data, never shared or synced to
// other users (unlike the crowdsourced venue database or jam attendance
// counts). See contact_model.dart's header for the reasoning and for the
// planned (not yet built) phone-Contacts sync this is designed to leave
// room for.

import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:the_money_gigs/features/contacts/models/contact_model.dart';
import 'package:the_money_gigs/global_refresh_notifier.dart';
import 'package:the_money_gigs/core/utils/logger.dart';

class ContactRepository {
  static const String _keyContactsList = 'contacts_list';

  Future<List<Contact>> getAll() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonString = prefs.getString(_keyContactsList) ?? '[]';
      final List<dynamic> decoded = jsonDecode(jsonString) as List<dynamic>;
      return decoded
          .map((e) => Contact.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      log('❌ Error loading contacts: $e');
      return [];
    }
  }

  /// Contacts tagged as first met at a specific gig/jam occurrence — what
  /// the day-of screen's contact list shows. Later contacts met elsewhere
  /// don't disappear; they just won't show up filtered to a different gig.
  Future<List<Contact>> getForGig(String gigId) async {
    final all = await getAll();
    return all.where((c) => c.metAtGigId == gigId).toList();
  }

  Future<void> add(Contact contact) async {
    final all = await getAll();
    all.add(contact);
    await _saveAll(all);
  }

  /// Updates the contact matching [contact.localId], or adds it if no
  /// match exists — same "upsert" convenience GigsPage._setJamAttendance
  /// uses for gigs_list.
  Future<void> update(Contact contact) async {
    final all = await getAll();
    final index = all.indexWhere((c) => c.localId == contact.localId);
    if (index != -1) {
      all[index] = contact;
    } else {
      all.add(contact);
    }
    await _saveAll(all);
  }

  Future<void> delete(String localId) async {
    final all = await getAll();
    all.removeWhere((c) => c.localId == localId);
    await _saveAll(all);
  }

  Future<void> _saveAll(List<Contact> contacts) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonString =
      jsonEncode(contacts.map((c) => c.toJson()).toList());
      await prefs.setString(_keyContactsList, jsonString);
      // Same app-wide convention every other local write follows — lets any
      // other open screen (a future standalone Contacts list, chiefly)
      // pick this up immediately instead of on next natural reload.
      globalRefreshNotifier.notify();
    } catch (e) {
      log('❌ Error saving contacts: $e');
    }
  }
}
