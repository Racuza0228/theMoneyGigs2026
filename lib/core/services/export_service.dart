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
  /// Sensitive data like hourly rates and pay amounts are obfuscated.
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

    // 2. Gather and Obfuscate Gigs Data
    final String? gigsJsonString = prefs.getString(_keyGigsList);
    List<dynamic> gigsList = gigsJsonString != null && gigsJsonString.isNotEmpty
        ? jsonDecode(gigsJsonString)
        : [];

    // <<< START OF CHANGE >>>
    // Iterate through each gig to obfuscate the 'pay' field.
    List<dynamic> obfuscatedGigsList = [];
    if (gigsList.isNotEmpty) {
      obfuscatedGigsList = gigsList.map((gig) {
        if (gig is Map<String, dynamic>) {
          // Create a mutable copy of the gig map
          final newGig = Map<String, dynamic>.from(gig);
          // Check if the 'pay' field exists and has a value
          if (newGig.containsKey('pay') && newGig['pay'] != null) {
            // Replace the actual amount with the static placeholder
            newGig['pay'] = "\$PAY";
          }
          return newGig;
        }
        return gig; // Return non-map items as-is (though they shouldn't exist)
      }).toList();
    }
    // <<< END OF CHANGE >>>

    // 3. Gather Venues Data
    final List<String>? venuesJsonStringList = prefs.getStringList(_keySavedLocations);
    final List<dynamic> venuesList = venuesJsonStringList != null
        ? venuesJsonStringList.map((v) => jsonDecode(v)).toList()
        : [];

    // 4. Combine all data into a single map
    return {
      'profile': profileData,
      // Use the new obfuscated list for the export
      'gigs': obfuscatedGigsList,
      'venues': venuesList,
      'exported_at': DateTime.now().toIso8601String(),
      'app_version': '1.0.0', // TODO: Replace with a dynamic app version loader if possible
    };
  }

  /// Main method to trigger the export process.
  /// It gathers data, formats it as JSON, and attempts to open the user's email client.
  Future<void> export(BuildContext context) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final allData = await _gatherData(prefs);

      // Convert the data map to a nicely formatted JSON string.
      String prettyJsonData = const JsonEncoder.withIndent('  ').convert(allData);

      // Prepare the 'mailto' link with the recipient, subject, and body.
      final String emailTo = 'clifford.adams.ii@gmail.com';
      final String emailSubject = 'MoneyGigs App - User Data Export';
      final Uri emailLaunchUri = Uri(
        scheme: 'mailto',
        path: emailTo,
        queryParameters: {
          'subject': emailSubject,
          'body': 'Hi Developer,\n\nPlease find my app data attached below for troubleshooting purposes:\n\n$prettyJsonData',
        },
      );

      if (!context.mounted) return;

      if (await canLaunchUrl(emailLaunchUri)) {
        await launchUrl(emailLaunchUri);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please send the prepared email.')),
        );
      } else {
        // Fallback if no email client is available: copy to clipboard.
        await Clipboard.setData(ClipboardData(text: prettyJsonData));
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not open email app. Data copied to clipboard.'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error exporting data: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }
}
