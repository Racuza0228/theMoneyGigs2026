// lib/features/gigs/models/monthly_separator.dart

/// Represents a monthly summary separator in the gigs list view.
///
/// This model holds aggregated data for a month including:
/// - Total number of gigs
/// - Total pay earned
/// - Average hourly rate across all gigs
class MonthlySeparator {
  final DateTime month;
  final int gigCount;
  final double totalPay;
  final double averagePayPerHour;

  const MonthlySeparator({
    required this.month,
    required this.gigCount,
    required this.totalPay,
    required this.averagePayPerHour,
  });

  /// Creates an empty separator for a given month
  factory MonthlySeparator.empty(DateTime month) {
    return MonthlySeparator(
      month: month,
      gigCount: 0,
      totalPay: 0,
      averagePayPerHour: 0,
    );
  }

  /// Returns true if this separator has any gigs
  bool get hasGigs => gigCount > 0;

  @override
  String toString() => 'MonthlySeparator(month: $month, gigCount: $gigCount, totalPay: $totalPay)';
}