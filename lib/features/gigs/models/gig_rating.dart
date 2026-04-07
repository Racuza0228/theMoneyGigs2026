// lib/features/gigs/models/gig_rating.dart

/// Represents a single rated dimension for a gig.
///
/// Each rating captures how well a particular aspect of the gig went,
/// on a scale of 0.0 to 5.0 (supporting half-star ratings).
///
/// NOTE: Tips are no longer a GigRating dimension. They are stored as
/// [Gig.tipsAmount] (a dollar amount) so they contribute directly to
/// the true hourly rate calculation.
class GigRating {
  final String dimension;
  final double rating;
  final String? category;

  const GigRating({
    required this.dimension,
    required this.rating,
    this.category,
  });

  GigRating copyWith({
    String? dimension,
    double? rating,
    String? category,
  }) {
    return GigRating(
      dimension: dimension ?? this.dimension,
      rating: rating ?? this.rating,
      category: category ?? this.category,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'dimension': dimension,
      'rating': rating,
      if (category != null) 'category': category,
    };
  }

  factory GigRating.fromJson(Map<String, dynamic> json) {
    return GigRating(
      dimension: json['dimension'] as String,
      rating: (json['rating'] as num).toDouble(),
      category: json['category'] as String?,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
          other is GigRating &&
              runtimeType == other.runtimeType &&
              dimension == other.dimension;

  @override
  int get hashCode => dimension.hashCode;

  @override
  String toString() =>
      'GigRating(dimension: $dimension, rating: $rating, category: $category)';
}

/// Default dimensions available for rating gigs.
/// Users can add custom dimensions beyond these.
///
/// 'Tips' has been removed from this list — it is now tracked as a dollar
/// amount on the Gig model ([Gig.tipsAmount]) rather than a 1–5 star rating.
/// Existing saved dimension lists that still contain 'Tips' are silently
/// filtered out when loaded in the widget and wizard.
class DefaultGigDimensions {
  static const List<String> performance = [
    'Crowd Size/Energy',
  ];

  // Tips removed — now Gig.tipsAmount
  static const List<String> financial = [];

  static const List<String> venue = [
    'Parking',
    'Physical Comfort',
    'Venue Staff',
    'Venue Sound',
  ];

  static const List<String> personal = [
    'Creativity',
    'Social',
  ];

  /// All default dimensions in a flat list
  static List<String> get all => [
    ...performance,
    ...financial,
    ...venue,
    ...personal,
  ];

  /// Dimensions that should never appear as star ratings.
  /// Used to silently migrate old saved dimension lists.
  static const List<String> reservedAsFields = ['Tips'];

  /// Get the category for a given dimension
  static String? getCategoryFor(String dimension) {
    if (performance.contains(dimension)) return 'performance';
    if (financial.contains(dimension)) return 'financial';
    if (venue.contains(dimension)) return 'venue';
    if (personal.contains(dimension)) return 'personal';
    return null;
  }
}