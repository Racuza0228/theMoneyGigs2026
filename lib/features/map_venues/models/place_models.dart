// lib/models/place_models.dart
import 'package:google_maps_flutter/google_maps_flutter.dart';

/// Model for a single result from the Google Places Autocomplete API.
class PlaceAutocompleteResult {
  final String placeId;
  final String mainText;
  final String secondaryText;

  PlaceAutocompleteResult({
    required this.placeId,
    required this.mainText,
    required this.secondaryText,
  });

  factory PlaceAutocompleteResult.fromJson(Map<String, dynamic> json) {
    return PlaceAutocompleteResult(
      placeId: json['place_id'] ?? '',
      mainText: json['structured_formatting']?['main_text'] ?? 'Unknown Place',
      secondaryText: json['structured_formatting']?['secondary_text'] ?? '',
    );
  }
}

/// Model for the detailed result from the Google Places Details or Nearby Search API.
class PlaceApiResult {
  final String placeId;
  final String name;
  final String address;
  final LatLng coordinates;
  final List<String> types;

  PlaceApiResult({
    required this.placeId,
    required this.name,
    required this.address,
    required this.coordinates,
    required this.types,
  });

  factory PlaceApiResult.fromJson(Map<String, dynamic> json, {bool isNearbySearch = true}) {
    String address = json['vicinity'] ?? json['formatted_address'] ?? 'Address not available';
    // A fallback for cases where address is missing but name/geometry exist
    if (address == 'Address not available' && json['name'] != null && json['geometry'] != null) {
      address = json['name'];
    }
    return PlaceApiResult(
      placeId: json['place_id'] ?? 'api_error_${DateTime.now().millisecondsSinceEpoch}',
      name: json['name'] ?? 'Unnamed Place',
      address: address,
      coordinates: LatLng(
        (json['geometry']?['location']?['lat'] as num?)?.toDouble() ?? 0.0,
        (json['geometry']?['location']?['lng'] as num?)?.toDouble() ?? 0.0,
      ),
      types: List<String>.from(json['types'] ?? []),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
          other is PlaceApiResult &&
              runtimeType == other.runtimeType &&
              placeId == other.placeId;

  @override
  int get hashCode => placeId.hashCode;
}
