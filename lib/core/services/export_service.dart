// lib/services/export_service.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

class ExportService {
  // Define SharedPreferences keys here to be self-contained.
  static const String _keyAddress1 = 'profile_address1';
  static const String _keyAddress2 = 'profile_address2';
  static const String _keyCity = 'profile_city';
  static const String _keyState = 'profile_state';
  static const String _keyZipCode = 'profile_zip_code';
  static const String _keyMinHourlyRate = 'profile_min_hourly_rate';
  static const String _keyGigsList = 'gigs_list';
  static const String _keySavedLocations = 'saved_locations';

  /// Gathers all necessary data from SharedPreferences and prepares it for export.
  /// Sensitive data is filtered or obfuscated for privacy.
  Future<Map<String, dynamic>> _gatherData(SharedPreferences prefs) async {
    // 1. Gather Profile Data and Obfuscate Rate
    Map<String, dynamic> profileData = {
      'address1': prefs.getString(_keyAddress1) ?? '',
      'address2': prefs.getString(_keyAddress2) ?? '',
      'city': prefs.getString(_keyCity) ?? '',
      'state': prefs.getString(_keyState), // Can be null
      'zip_code': prefs.getString(_keyZipCode) ?? '',
      // OBFUSCATION: Check if a rate exists, but don't export the value.
      'has_min_hourly_rate': (prefs.getInt(_keyMinHourlyRate) ?? 0) > 0,
    };

    // --- START OF REVISED SECTION ---

    // 2. Gather, Filter, and Obfuscate Venues Data
    final List<String>? venuesJsonStringList = prefs.getStringList(_keySavedLocations);
    final List<Map<String, dynamic>> allVenuesList = venuesJsonStringList != null
        ? venuesJsonStringList.map((v) => jsonDecode(v) as Map<String, dynamic>).toList()
        : [];

    // Identify the placeIds of all private venues.
    final Set<String> privateVenuePlaceIds = allVenuesList
        .where((venue) => venue['isPrivate'] == true)
        .map((venue) => venue['placeId'] as String)
        .toSet();

    // Create the final list of venues for export:
    // - Filter out all private venues.
    // - Obfuscate the contact details of the remaining public venues.
    final List<Map<String, dynamic>> sanitizedVenuesList = allVenuesList
        .where((venue) => !(venue['isPrivate'] as bool? ?? false))
        .map((venue) {
      final newVenue = Map<String, dynamic>.from(venue);
      // OBFUSCATION: If contact info exists, replace it with a placeholder.
      if (newVenue.containsKey('contact') && newVenue['contact'] != null) {
        newVenue['contact'] = {
          'name': 'CONTACT_NAME',
          'phone': 'CONTACT_PHONE',
          'email': 'CONTACT_EMAIL',
        };
      }
      return newVenue;
    }).toList();


    // 3. Gather, Filter, and Obfuscate Gigs Data
    final String? gigsJsonString = prefs.getString(_keyGigsList);
    List<dynamic> allGigsList = gigsJsonString != null && gigsJsonString.isNotEmpty
        ? jsonDecode(gigsJsonString)
        : [];

    // Create the final list of gigs for export:
    // - Filter out any gigs associated with a private venue.
    // - Obfuscate the 'pay' field for the remaining public gigs.
    final List<dynamic> sanitizedGigsList = allGigsList
        .where((gig) {
      // Keep the gig only if its placeId is NOT in our set of private venue IDs.
      return gig is Map<String, dynamic> && !privateVenuePlaceIds.contains(gig['placeId']);
    })
        .map((gig) {
      // This will only run on public gigs now.
      final newGig = Map<String, dynamic>.from(gig as Map<String, dynamic>);
      // OBFUSCATION: Replace the actual 'pay' amount with a placeholder.
      if (newGig.containsKey('pay') && newGig['pay'] != null) {
        newGig['pay'] = "\$PAY";
      }
      return newGig;
    }).toList();

    // --- END OF REVISED SECTION ---

    // 4. Combine all sanitized data into a single map
    return {
      'profile': profileData,
      'gigs': sanitizedGigsList,
      'venues': sanitizedVenuesList,
      'exported_at': DateTime.now().toIso8601String(),
      'app_version': '1.0.0', // TODO: Replace with a dynamic app version loader if possible
    };
  }

  /// Main method to trigger the feedback email.
  /// If includeData is true, diagnostic data is attached (with sensitive info removed).
  /// If includeData is false, only a blank feedback email is opened.
  Future<void> sendFeedback(BuildContext context, {required bool includeData}) async {
    try {
      final String emailTo = 'cliff@themoneygigs.com';
      final String emailSubject = 'MoneyGigs App - Feedback';
      String emailBody;

      if (includeData) {
        // Gather and sanitize data
        final prefs = await SharedPreferences.getInstance();
        final allData = await _gatherData(prefs);
        String prettyJsonData = const JsonEncoder.withIndent('  ').convert(allData);

        emailBody = 'Hi Developer,\n\n'
            'Please find my feedback below:\n\n'
            '[Type your feedback here]\n\n'
            '--- Diagnostic Data (Pay and contact info excluded) ---\n\n'
            '$prettyJsonData';
      } else {
        // Just a blank feedback email
        emailBody = 'Hi Developer,\n\n'
            'Please find my feedback below:\n\n'
            '[Type your feedback here]';
      }

      final Uri emailLaunchUri = Uri(
        scheme: 'mailto',
        path: emailTo,
        queryParameters: {
          'subject': emailSubject,
          'body': emailBody,
        },
      );

      if (!context.mounted) return;

      if (await canLaunchUrl(emailLaunchUri)) {
        await launchUrl(emailLaunchUri);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✉️ Feedback email opened. Please send when ready.'),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        // Fallback if no email client is available
        if (includeData) {
          final prefs = await SharedPreferences.getInstance();
          final allData = await _gatherData(prefs);
          String prettyJsonData = const JsonEncoder.withIndent('  ').convert(allData);
          await Clipboard.setData(ClipboardData(text: prettyJsonData));

          if (!context.mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Could not open email app. Data copied to clipboard.'),
              backgroundColor: Colors.orange,
            ),
          );
        } else {
          if (!context.mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Could not open email app. Please email cliff@themoneygigs.com'),
              backgroundColor: Colors.orange,
            ),
          );
        }
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error preparing feedback: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// Legacy export method - kept for backward compatibility
  /// Use sendFeedback() instead for new implementations
  Future<void> export(BuildContext context) async {
    await sendFeedback(context, includeData: true);
  }
}