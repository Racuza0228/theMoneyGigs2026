// lib/services/places_service.dart
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

// Import our newly created models
import 'package:the_money_gigs/features/map_venues/models/place_models.dart';

class PlacesService {
  final String apiKey;
  final Uuid _uuid = const Uuid();
  String? _sessionToken;

  PlacesService({required this.apiKey});

  /// Starts a new autocomplete session for billing purposes.
  /// Call this when the user starts a new search interaction.
  void startSession() {
    _sessionToken = _uuid.v4();
  }

  /// Ends the current session. Call this after a place is selected or the search is cancelled.
  void endSession() {
    _sessionToken = null;
  }

  /// Fetches autocomplete suggestions from the Google Places API.
  Future<List<PlaceAutocompleteResult>> fetchAutocompleteResults(String input) async {
    if (apiKey.isEmpty || input.isEmpty) return [];

    // Ensure a session token exists for this request.
    _sessionToken ??= _uuid.v4();

    final url = 'https://maps.googleapis.com/maps/api/place/autocomplete/json'
        '?input=${Uri.encodeComponent(input)}'
        '&key=$apiKey'
        '&sessiontoken=$_sessionToken';

    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['status'] == 'OK' && data['predictions'] != null) {
          final List predictions = data['predictions'];
          return predictions.map((p) => PlaceAutocompleteResult.fromJson(p)).toList();
        }
      }
    } catch (e) {
      print("PlacesService (Autocomplete) Error: $e");
    }
    return []; // Return empty list on error
  }

  /// Fetches detailed information for a specific place using its placeId.
  Future<PlaceApiResult?> fetchPlaceDetails(String placeId) async {
    if (apiKey.isEmpty) return null;

    final currentSessionToken = _sessionToken;
    // A session is consumed after a details request. End it now.
    endSession();

    final url = 'https://maps.googleapis.com/maps/api/place/details/json'
        '?place_id=$placeId'
        '&key=$apiKey'
        '&fields=name,geometry,formatted_address,place_id,vicinity,types'
        '&sessiontoken=$currentSessionToken';

    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['status'] == 'OK' && data['result'] != null) {
          return PlaceApiResult.fromJson(data['result'], isNearbySearch: false);
        }
      }
    } catch (e) {
      print("PlacesService (Details) Error: $e");
    }
    return null; // Return null on error
  }
}
