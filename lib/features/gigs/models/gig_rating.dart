// lib/features/gigs/models/gig_rating.dart

/// Represents a single rated dimension for a gig.
///
/// Each rating captures how well a particular aspect of the gig went,
/// on a scale of 0.0 to 5.0 (supporting half-star ratings).
///
/// Examples:
///   - GigRating(dimension: 'Energy', rating: 4.5)
///   - GigRating(dimension: 'Tips', rating: 2.0)
///   - GigRating(dimension: 'Creative Fulfillment', rating: 5.0)
class GigRating {
  /// The name of the dimension being rated (e.g., 'Energy', 'Tips', 'Sound Quality')
  final String dimension;

  /// The rating value from 0.0 to 5.0 (supports half-stars)
  final double rating;

  /// Optional category for grouping dimensions
  /// (e.g., 'performance', 'financial', 'logistics', 'personal')
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
  String toString() => 'GigRating(dimension: $dimension, rating: $rating, category: $category)';
}

/// Default dimensions available for rating gigs.
/// Users can add custom dimensions beyond these.
class DefaultGigDimensions {
  static const List<String> performance = [
    'Crowd Size/Energy',
  ];

  static const List<String> financial = [
    'Tips',
  ];

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

  /// Get the category for a given dimension
  static String? getCategoryFor(String dimension) {
    if (performance.contains(dimension)) return 'performance';
    if (financial.contains(dimension)) return 'financial';
    if (venue.contains(dimension)) return 'venue';
    if (personal.contains(dimension)) return 'personal';
    return null;
  }
}