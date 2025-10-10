// tool/validate_jams.dart
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

// --- IMPORTANT: PASTE YOUR GOOGLE API KEY HERE ---
// It's safe to do this here because this script is only run locally by you.
const String googleApiKey = "AIzaSyCjyQbNWIXnY5L9AHXhZrhzqsDwYAZPKVo";
// ----------------------------------------------------

Future<void> main() async {
  if (googleApiKey == "YOUR_GOOGLE_API_KEY_HERE" || googleApiKey.isEmpty) {
    print("\nERROR: Please paste your Google API Key into the googleApiKey variable in this script.\n");
    return;
  }

  // Define file paths
  final inputFile = File('assets/jam_sessions.json');
  final outputFile = File('assets/jam_sessions_corrected.json');

  if (!await inputFile.exists()) {
    print("Error: `assets/jam_sessions.json` not found!");
    return;
  }

  print("Starting validation process...");

  // Read the source JSON file
  final jsonString = await inputFile.readAsString();
  final List<dynamic> venues = jsonDecode(jsonString);
  final List<Map<String, dynamic>> correctedVenues = [];
  int corrections = 0;
  int errors = 0;

  // Process each venue one by one
  for (int i = 0; i < venues.length; i++) {
    final venue = Map<String, dynamic>.from(venues[i]);
    final name = venue['name'] as String;
    final address = venue['address'] as String;

    // Construct the query for Google Places API
    // We combine name and address for a more accurate search
    final query = Uri.encodeComponent('$name, $address');
    final url = 'https://maps.googleapis.com/maps/api/place/findplacefromtext/json?input=$query&inputtype=textquery&fields=place_id,geometry,name&key=$googleApiKey';

    try {
      stdout.write("Processing (${i + 1}/${venues.length}): $name...");
      final response = await http.get(Uri.parse(url));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        if (data['status'] == 'OK' && data['candidates'] != null && (data['candidates'] as List).isNotEmpty) {
          // We found a good match!
          final candidate = data['candidates'][0];
          final newPlaceId = candidate['place_id'] as String;
          final newLat = candidate['geometry']['location']['lat'] as double;
          final newLng = candidate['geometry']['location']['lng'] as double;

          bool wasCorrected = false;
          // Check if any data needs correction
          if (venue['placeID'] != newPlaceId ||
              (venue['latitude'] as num).toDouble() != newLat ||
              (venue['longitude'] as num).toDouble() != newLng) {
            wasCorrected = true;
            corrections++;
          }

          // Update the venue data with the corrected values
          venue['placeID'] = newPlaceId;
          venue['latitude'] = newLat;
          venue['longitude'] = newLng;

          stdout.writeln(wasCorrected ? " CORRECTED" : " OK");

        } else {
          // Google couldn't find a match
          errors++;
          stdout.writeln(" FAILED TO FIND (${data['status']})");
        }
      } else {
        errors++;
        stdout.writeln(" API ERROR (${response.statusCode})");
      }
      correctedVenues.add(venue);

      // Add a small delay to avoid hitting API rate limits
      await Future.delayed(const Duration(milliseconds: 50));

    } catch (e) {
      errors++;
      stdout.writeln(" SCRIPT ERROR ($e)");
      correctedVenues.add(venue); // Add the original back on error
    }
  }

  // Write the new, corrected file
  final encoder = JsonEncoder.withIndent('  '); // Pretty-print the JSON
  await outputFile.writeAsString(encoder.convert(correctedVenues));

  print("\n------------------------------------");
  print("Validation Complete!");
  print("Corrections made: $corrections");
  print("Errors/Not Found: $errors");
  print("A new file has been created at: ${outputFile.path}");
  print("------------------------------------");
}
