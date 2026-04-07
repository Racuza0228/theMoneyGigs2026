// lib/features/gigs/services/gig_insights_service.dart
import 'package:shared_preferences/shared_preferences.dart';
import 'package:the_money_gigs/features/gigs/models/gig_model.dart';

// ── Data classes ─────────────────────────────────────────────────────────────

class VenueInsight {
  final String venueName;
  final String? placeId;
  final int gigCount;
  final double averageTrueRate;
  final double totalEffectivePay;
  final double averageRating; // null-safe: 0.0 if no ratings

  const VenueInsight({
    required this.venueName,
    required this.placeId,
    required this.gigCount,
    required this.averageTrueRate,
    required this.totalEffectivePay,
    required this.averageRating,
  });
}

class MonthlyIncome {
  final DateTime month; // first day of month
  final double totalEffectivePay;
  final int gigCount;
  final double averageTrueRate;

  const MonthlyIncome({
    required this.month,
    required this.totalEffectivePay,
    required this.gigCount,
    required this.averageTrueRate,
  });
}

class RegretGig {
  final Gig gig;
  final double hoursInvested;
  final double trueRate;
  final double averageRating;

  const RegretGig({
    required this.gig,
    required this.hoursInvested,
    required this.trueRate,
    required this.averageRating,
  });
}

class GigInsightsSummary {
  // ── Insight 1: Rate vs minimum ─────────────────────────────────────────────
  final double averageTrueRate;
  final double? minimumRate; // null = not set in profile
  // positive = above minimum, negative = below, null = no minimum set
  final double? rateGap;

  // ── Insight 2: Time investment ─────────────────────────────────────────────
  final double totalStageHours;
  final double totalDriveSetupHours;
  final double totalRehearsalHours;
  final double totalInvestedHours;
  // Hours invested per hour on stage (>1 means more prep than performance)
  final double investmentRatio;

  // ── Insight 3: Venue rankings ──────────────────────────────────────────────
  // Sorted best → worst by averageTrueRate. Only venues with ≥2 gigs shown.
  final List<VenueInsight> venueRankings;
  final double globalAverageRate; // baseline for bar chart scaling

  // ── Insight 4: Income trajectory ───────────────────────────────────────────
  // Last 6 months with data, sorted oldest → newest
  final List<MonthlyIncome> monthlyIncome;

  // ── Insight 5: Regret index ────────────────────────────────────────────────
  final List<RegretGig> regretGigs;
  final double totalRegretHours;

  // ── Meta ───────────────────────────────────────────────────────────────────
  final int analyzedGigCount; // gigs that contributed to these stats
  final bool hasEnoughData;   // false when < 3 played gigs

  const GigInsightsSummary({
    required this.averageTrueRate,
    required this.minimumRate,
    required this.rateGap,
    required this.totalStageHours,
    required this.totalDriveSetupHours,
    required this.totalRehearsalHours,
    required this.totalInvestedHours,
    required this.investmentRatio,
    required this.venueRankings,
    required this.globalAverageRate,
    required this.monthlyIncome,
    required this.regretGigs,
    required this.totalRegretHours,
    required this.analyzedGigCount,
    required this.hasEnoughData,
  });
}

// ── Service ───────────────────────────────────────────────────────────────────

class GigInsightsService {
  // The key used by the Profile page to store the musician's minimum hourly
  // rate. Update this constant if the profile page uses a different key.
  // Common candidates: 'work_preference_min_rate', 'min_hourly_rate',
  // 'musician_min_rate', 'minimum_rate'
  static const _candidateRateKeys = [
    'work_preference_min_rate',
    'min_hourly_rate',
    'minimum_hourly_rate',
    'musician_min_rate',
    'minimum_rate',
    'minRate',
    'workPreferenceRate',
  ];

  /// Reads the minimum hourly rate from SharedPreferences.
  /// Tries several candidate key names in order and returns the first hit.
  static Future<double?> loadMinimumRate() async {
    final prefs = await SharedPreferences.getInstance();
    for (final key in _candidateRateKeys) {
      final value = prefs.get(key);
      if (value is double) return value;
      if (value is int) return value.toDouble();
      if (value is String) {
        final parsed = double.tryParse(value);
        if (parsed != null) return parsed;
      }
    }
    return null;
  }

  /// Computes all insights from [allGigs] (the raw master list from
  /// SharedPreferences). Pass the result of [loadMinimumRate] as
  /// [minimumRate], or null if the musician hasn't set one.
  static GigInsightsSummary compute(
      List<Gig> allGigs, {
        double? minimumRate,
      }) {
    final now = DateTime.now();

    // ── Filter to "played" gigs only ────────────────────────────────────────
    // A played gig is either:
    //   (a) a non-recurring, non-jam gig that has ended, OR
    //   (b) a materialized recurring instance (saved when reviewed/noted)
    // Recurring templates (isRecurring: true) are excluded — they're the
    // series definition, not an actual performance.
    final played = allGigs.where((g) {
      if (g.isJamOpenMic) return false;
      if (g.isRecurring) return false; // template, not a performance
      final endTime = g.dateTime
          .add(Duration(minutes: (g.gigLengthHours * 60).toInt()));
      return endTime.isBefore(now);
    }).toList();

    final count = played.length;
    final hasEnough = count >= 3;

    if (count == 0) {
      return GigInsightsSummary(
        averageTrueRate: 0,
        minimumRate: minimumRate,
        rateGap: null,
        totalStageHours: 0,
        totalDriveSetupHours: 0,
        totalRehearsalHours: 0,
        totalInvestedHours: 0,
        investmentRatio: 0,
        venueRankings: [],
        globalAverageRate: 0,
        monthlyIncome: [],
        regretGigs: [],
        totalRegretHours: 0,
        analyzedGigCount: 0,
        hasEnoughData: false,
      );
    }

    // ── Insight 1: Rate vs minimum ───────────────────────────────────────────
    final avgRate = played.isEmpty
        ? 0.0
        : played.map((g) => g.trueHourlyRate).reduce((a, b) => a + b) / count;
    final rateGap = minimumRate != null ? avgRate - minimumRate : null;

    // ── Insight 2: Time investment ───────────────────────────────────────────
    final totalStage =
    played.fold<double>(0, (s, g) => s + g.gigLengthHours);
    final totalDrive =
    played.fold<double>(0, (s, g) => s + g.driveSetupTimeHours);
    final totalRehearsal =
    played.fold<double>(0, (s, g) => s + g.rehearsalLengthHours);
    final totalInvested = totalStage + totalDrive + totalRehearsal;
    // Ratio: hours invested per hour on stage
    final investmentRatio =
    totalStage > 0 ? totalInvested / totalStage : 0.0;

    // ── Insight 3: Venue rankings ────────────────────────────────────────────
    // Group by placeId (or venueName as fallback)
    final Map<String, List<Gig>> byVenue = {};
    for (final g in played) {
      final key = g.placeId ?? g.venueName;
      byVenue.putIfAbsent(key, () => []).add(g);
    }

    final venueInsights = byVenue.entries.map((entry) {
      final gigs = entry.value;
      final venueAvgRate = gigs
          .map((g) => g.trueHourlyRate)
          .reduce((a, b) => a + b) /
          gigs.length;
      final totalPay = gigs.fold<double>(
          0,
              (s, g) =>
          s + g.pay + (g.tipsAmount ?? 0.0) - (g.otherExpenses ?? 0.0));
      final ratedGigs =
      gigs.where((g) => g.averageRating != null).toList();
      final avgRating = ratedGigs.isEmpty
          ? 0.0
          : ratedGigs.map((g) => g.averageRating!).reduce((a, b) => a + b) /
          ratedGigs.length;

      return VenueInsight(
        venueName: gigs.first.venueName,
        placeId: gigs.first.placeId,
        gigCount: gigs.length,
        averageTrueRate: venueAvgRate,
        totalEffectivePay: totalPay,
        averageRating: avgRating,
      );
    }).toList();

    // Sort best → worst. Show all venues (even single-gig ones when <4 venues)
    venueInsights.sort((a, b) => b.averageTrueRate.compareTo(a.averageTrueRate));

    // ── Insight 4: Income trajectory ─────────────────────────────────────────
    // Group into calendar months, last 12 months with any data
    final cutoff = DateTime(now.year - 1, now.month, 1);
    final recentPlayed =
    played.where((g) => g.dateTime.isAfter(cutoff)).toList();

    final Map<DateTime, List<Gig>> byMonth = {};
    for (final g in recentPlayed) {
      final monthKey = DateTime(g.dateTime.year, g.dateTime.month, 1);
      byMonth.putIfAbsent(monthKey, () => []).add(g);
    }

    final monthlyIncome = byMonth.entries.map((entry) {
      final gigs = entry.value;
      final total = gigs.fold<double>(
          0,
              (s, g) =>
          s + g.pay + (g.tipsAmount ?? 0.0) - (g.otherExpenses ?? 0.0));
      final monthAvgRate = gigs
          .map((g) => g.trueHourlyRate)
          .reduce((a, b) => a + b) /
          gigs.length;
      return MonthlyIncome(
        month: entry.key,
        totalEffectivePay: total,
        gigCount: gigs.length,
        averageTrueRate: monthAvgRate,
      );
    }).toList()
      ..sort((a, b) => a.month.compareTo(b.month));

    // ── Insight 5: Regret index ──────────────────────────────────────────────
    // Gigs that were BOTH below-average rate AND rated below 2.5 stars
    final ratedPlayed = played.where((g) => g.averageRating != null).toList();
    final List<RegretGig> regretGigs = [];

    if (ratedPlayed.isNotEmpty) {
      for (final g in ratedPlayed) {
        final isBelowRate = g.trueHourlyRate < avgRate;
        final isBelowRating = g.averageRating! < 2.5;
        if (isBelowRate && isBelowRating) {
          final hours =
              g.gigLengthHours + g.driveSetupTimeHours + g.rehearsalLengthHours;
          regretGigs.add(RegretGig(
            gig: g,
            hoursInvested: hours,
            trueRate: g.trueHourlyRate,
            averageRating: g.averageRating!,
          ));
        }
      }
      regretGigs.sort(
              (a, b) => b.hoursInvested.compareTo(a.hoursInvested));
    }

    final totalRegretHours =
    regretGigs.fold<double>(0, (s, r) => s + r.hoursInvested);

    return GigInsightsSummary(
      averageTrueRate: avgRate,
      minimumRate: minimumRate,
      rateGap: rateGap,
      totalStageHours: totalStage,
      totalDriveSetupHours: totalDrive,
      totalRehearsalHours: totalRehearsal,
      totalInvestedHours: totalInvested,
      investmentRatio: investmentRatio,
      venueRankings: venueInsights,
      globalAverageRate: avgRate,
      monthlyIncome: monthlyIncome,
      regretGigs: regretGigs,
      totalRegretHours: totalRegretHours,
      analyzedGigCount: count,
      hasEnoughData: hasEnough,
    );
  }
}