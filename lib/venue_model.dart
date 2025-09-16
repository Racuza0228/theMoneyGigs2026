// lib/venue_model.dart (or your models/stored_location.dart)

import 'package:google_maps_flutter/google_maps_flutter.dart';

class StoredLocation {
  final String placeId;
  final String name;
  final String address;
  final LatLng coordinates;
  double rating;
  String? comment;
  bool isArchived; // <<< NEW FIELD

  StoredLocation({
    required this.placeId,
    required this.name,
    required this.address,
    required this.coordinates,
    this.rating = 0.0,
    this.comment,
    this.isArchived = false, // <<< Default to false
  });

  Map<String, dynamic> toJson() => {
    'placeId': placeId,
    'name': name,
    'address': address,
    'latitude': coordinates.latitude,
    'longitude': coordinates.longitude,
    'rating': rating,
    'comment': comment,
    'isArchived': isArchived, // <<< ADDED TO JSON
  };

  factory StoredLocation.fromJson(Map<String, dynamic> json) => StoredLocation(
    placeId: json['placeId'] ?? DateTime.now().millisecondsSinceEpoch.toString(),
    name: json['name'] ?? 'Unnamed Venue',
    address: json['address'] ?? 'No address',
    coordinates: LatLng(
      json['latitude'] ?? 0.0,
      json['longitude'] ?? 0.0,
    ),
    rating: (json['rating'] as num?)?.toDouble() ?? 0.0,
    comment: json['comment'] as String?,
    isArchived: json['isArchived'] as bool? ?? false, // <<< ADDED FROM JSON (default to false if missing)
  );

  // Helper method for easily creating a modified copy
  StoredLocation copyWith({
    String? placeId,
    String? name,
    String? address,
    LatLng? coordinates,
    double? rating,
    String? comment,
    bool? isArchived,
  }) {
    return StoredLocation(
      placeId: placeId ?? this.placeId,
      name: name ?? this.name,
      address: address ?? this.address,
      coordinates: coordinates ?? this.coordinates,
      rating: rating ?? this.rating,
      comment: comment ?? this.comment,
      isArchived: isArchived ?? this.isArchived,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
          other is StoredLocation &&
              runtimeType == other.runtimeType &&
              placeId == other.placeId;

  @override
  int get hashCode => placeId.hashCode;

  static StoredLocation get addNewVenuePlaceholder => StoredLocation(
    placeId: 'add_new_venue_placeholder',
    name: '--- Add New Venue ---',
    address: '',
    coordinates: const LatLng(0,0),
    isArchived: false, // Should not be archivable by default
  );
}
