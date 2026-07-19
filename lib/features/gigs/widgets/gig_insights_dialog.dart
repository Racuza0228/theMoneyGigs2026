// lib/features/gigs/widgets/gig_insights_dialog.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:the_money_gigs/features/gigs/models/gig_model.dart';
import 'package:the_money_gigs/features/gigs/services/gig_insights_service.dart';

Future<void> showGigInsightsDialog({
  required BuildContext context,
  required List<Gig> allGigs,
}) {
  return showDialog(
    context: context,
    builder: (_) => GigInsightsDialog(allGigs: allGigs),
  );
}

class GigInsightsDialog extends StatefulWidget {
  final List<Gig> allGigs;
  const GigInsightsDialog({super.key, required this.allGigs});

  @override
  State<GigInsightsDialog> createState() => _GigInsightsDialogState();
}

class _GigInsightsDialogState extends State<GigInsightsDialog> {
  GigInsightsSummary? _summary;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final minRate = await GigInsightsService.loadMinimumRate();
    final summary = GigInsightsService.compute(
      widget.allGigs,
      minimumRate: minRate,
    );
    if (context.mounted) {
      setState(() {
        _summary = summary;
        _isLoading = false;
      });
    }
  }

  // ── Formatting helpers ────────────────────────────────────────────────────

  String _fmt(double v) => '\$${v.toStringAsFixed(2)}';
  String _fmtRate(double v) => '\$${v.toStringAsFixed(2)}/hr';
  String _fmtHours(double v) => '${v.toStringAsFixed(1)}h';

  Color _rateColor(double rate, double? minimum, BuildContext ctx) {
    if (minimum == null) return Theme.of(ctx).colorScheme.primary;
    if (rate >= minimum) return Colors.green.shade400;
    if (rate >= minimum * 0.85) return Colors.amber.shade400;
    return Colors.red.shade400;
  }

  // ── Section header ────────────────────────────────────────────────────────

  Widget _sectionHeader(
      BuildContext ctx,
      IconData icon,
      String title,
      Color color,
      ) {
    return Padding(
      padding: const EdgeInsets.only(top: 24, bottom: 10),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              title,
              style: Theme.of(ctx).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
                color: Theme.of(ctx).colorScheme.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Metric card ───────────────────────────────────────────────────────────

  Widget _metricCard(
      BuildContext ctx, {
        required String label,
        required String value,
        String? sublabel,
        Color? valueColor,
      }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Theme.of(ctx).colorScheme.surfaceVariant.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Theme.of(ctx).textTheme.labelSmall?.copyWith(
              color: Theme.of(ctx).colorScheme.onSurfaceVariant,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: valueColor ?? Theme.of(ctx).colorScheme.onSurface,
            ),
          ),
          if (sublabel != null) ...[
            const SizedBox(height: 2),
            Text(
              sublabel,
              style: Theme.of(ctx).textTheme.labelSmall?.copyWith(
                color: Theme.of(ctx).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ── Insight 1: Rate vs minimum ────────────────────────────────────────────

  Widget _buildRateInsight(BuildContext ctx, GigInsightsSummary s) {
    final rateColor = _rateColor(s.averageTrueRate, s.minimumRate, ctx);
    final hasMinimum = s.minimumRate != null;
    final gap = s.rateGap;

    String gapLabel = '';
    Color gapColor = Colors.grey;
    if (gap != null) {
      if (gap >= 0) {
        gapLabel = '+${_fmtRate(gap)} above your minimum';
        gapColor = Colors.green.shade400;
      } else {
        gapLabel = '${_fmtRate(gap.abs())} below your minimum';
        gapColor = Colors.red.shade400;
      }
    }

    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _metricCard(ctx,
                  label: 'YOUR AVG TRUE RATE',
                  value: _fmtRate(s.averageTrueRate),
                  valueColor: rateColor),
            ),
            if (hasMinimum) ...[
              const SizedBox(width: 10),
              Expanded(
                child: _metricCard(ctx,
                    label: 'YOUR STATED MINIMUM',
                    value: _fmtRate(s.minimumRate!)),
              ),
            ],
          ],
        ),
        if (gap != null) ...[
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: gapColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: gapColor.withValues(alpha: 0.35)),
            ),
            child: Text(
              gapLabel,
              style: TextStyle(
                  color: gapColor,
                  fontWeight: FontWeight.w600,
                  fontSize: 13),
              textAlign: TextAlign.center,
            ),
          ),
        ],
        if (!hasMinimum)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'Set a minimum rate in your Profile to unlock the gap comparison.',
              style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
      ],
    );
  }

  // ── Insight 2: Time investment ────────────────────────────────────────────

  Widget _buildTimeInsight(BuildContext ctx, GigInsightsSummary s) {
    final ratio = s.investmentRatio;
    final ratioStr = ratio.toStringAsFixed(1);
    // e.g. 2.1 means "2.1 hours invested per hour on stage"

    // Stacked bar: proportions of each time type
    final total = s.totalInvestedHours;
    final stageP = total > 0 ? s.totalStageHours / total : 0.0;
    final driveP = total > 0 ? s.totalDriveSetupHours / total : 0.0;
    final rehearsalP = total > 0 ? s.totalRehearsalHours / total : 0.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: _metricCard(ctx,
                  label: 'TOTAL HOURS ON STAGE',
                  value: _fmtHours(s.totalStageHours)),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _metricCard(ctx,
                  label: 'TOTAL HOURS INVESTED',
                  value: _fmtHours(s.totalInvestedHours),
                  sublabel: '${ratioStr}× your stage time'),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // Stacked proportion bar
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: Row(
            children: [
              _barSegment(stageP, Colors.purple.shade400, 'Stage'),
              _barSegment(driveP, Colors.blue.shade400, 'Drive'),
              _barSegment(rehearsalP, Colors.teal.shade400, 'Rehearsal'),
            ],
          ),
        ),
        const SizedBox(height: 8),

        // Legend
        Wrap(
          spacing: 16,
          children: [
            _legendDot(Colors.purple.shade400,
                'Stage: ${_fmtHours(s.totalStageHours)}'),
            _legendDot(Colors.blue.shade400,
                'Drive/Setup: ${_fmtHours(s.totalDriveSetupHours)}'),
            _legendDot(Colors.teal.shade400,
                'Rehearsal: ${_fmtHours(s.totalRehearsalHours)}'),
          ],
        ),

        if (ratio > 2.5)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: _callout(ctx,
                Icons.directions_car,
                'You\'re spending ${ratioStr}× as long preparing and driving '
                    'as you are playing. High-drive gigs may be eroding your '
                    'effective income.',
                Colors.amber),
          ),
      ],
    );
  }

  Widget _barSegment(double proportion, Color color, String label) {
    return Expanded(
      flex: (proportion * 100).round().clamp(1, 100),
      child: Container(
        height: 22,
        color: color,
      ),
    );
  }

  Widget _legendDot(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration:
          BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(label,
            style: const TextStyle(fontSize: 11, color: Colors.grey)),
      ],
    );
  }

  // ── Insight 3: Venue rankings ─────────────────────────────────────────────

  Widget _buildVenueInsight(BuildContext ctx, GigInsightsSummary s) {
    if (s.venueRankings.isEmpty) {
      return Text('Play at multiple venues to see rankings.',
          style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
              fontStyle: FontStyle.italic,
              color: Theme.of(ctx).colorScheme.onSurfaceVariant));
    }

    final maxRate = s.venueRankings.first.averageTrueRate;
    // Show top 5 + bottom 2 if enough venues
    final show = s.venueRankings.length <= 5
        ? s.venueRankings
        : [
      ...s.venueRankings.take(5),
      if (s.venueRankings.length > 5) s.venueRankings.last,
    ];

    return Column(
      children: show.asMap().entries.map((entry) {
        final i = entry.key;
        final v = entry.value;
        final isLast = s.venueRankings.length > 5 &&
            i == show.length - 1 &&
            v == s.venueRankings.last;
        final barWidth = maxRate > 0 ? v.averageTrueRate / maxRate : 0.0;
        final barColor = _rateColor(v.averageTrueRate, s.minimumRate, ctx);

        return Column(
          children: [
            if (isLast) const Divider(height: 20),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(
                children: [
                  Expanded(
                    flex: 5,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          v.venueName,
                          style: const TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w500),
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          '${v.gigCount} gig${v.gigCount == 1 ? '' : 's'}'
                              '${v.averageRating > 0 ? ' · ★ ${v.averageRating.toStringAsFixed(1)}' : ''}',
                          style: TextStyle(
                              fontSize: 11, color: Colors.grey.shade500),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    flex: 6,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          _fmtRate(v.averageTrueRate),
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: barColor,
                          ),
                        ),
                        const SizedBox(height: 3),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(3),
                          child: LinearProgressIndicator(
                            value: barWidth.clamp(0.0, 1.0),
                            minHeight: 5,
                            backgroundColor: Colors.grey.shade800,
                            valueColor:
                            AlwaysStoppedAnimation<Color>(barColor),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      }).toList(),
    );
  }

  // ── Insight 4: Income trajectory ──────────────────────────────────────────

  Widget _buildIncomeInsight(BuildContext ctx, GigInsightsSummary s) {
    if (s.monthlyIncome.isEmpty) {
      return Text('No data yet.',
          style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
              fontStyle: FontStyle.italic,
              color: Theme.of(ctx).colorScheme.onSurfaceVariant));
    }

    final maxIncome =
    s.monthlyIncome.map((m) => m.totalEffectivePay).reduce(
          (a, b) => a > b ? a : b,
    );
    final monthFmt = DateFormat('MMM yy');

    // Trend: compare first vs last half
    String trendLabel = '';
    Color trendColor = Colors.grey;
    if (s.monthlyIncome.length >= 2) {
      final first = s.monthlyIncome.first.totalEffectivePay;
      final last = s.monthlyIncome.last.totalEffectivePay;
      if (last > first * 1.05) {
        trendLabel = '▲ Income trending up';
        trendColor = Colors.green.shade400;
      } else if (last < first * 0.95) {
        trendLabel = '▼ Income trending down';
        trendColor = Colors.red.shade400;
      } else {
        trendLabel = '→ Income holding steady';
        trendColor = Colors.amber.shade400;
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (trendLabel.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(trendLabel,
                style: TextStyle(
                    color: trendColor,
                    fontWeight: FontWeight.w600,
                    fontSize: 13)),
          ),

        // Bar chart
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: s.monthlyIncome.map((m) {
            final barH = maxIncome > 0
                ? ((m.totalEffectivePay / maxIncome) * 80).clamp(4.0, 80.0)
                : 4.0;
            return Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text(
                      _fmt(m.totalEffectivePay)
                          .replaceAll('\$', '\$')
                          .split('.')
                          .first,
                      style: const TextStyle(
                          fontSize: 9, color: Colors.grey),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 2),
                    Container(
                      height: barH,
                      decoration: BoxDecoration(
                        color: Theme.of(ctx).colorScheme.primary,
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(3),
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      monthFmt.format(m.month),
                      style: const TextStyle(
                          fontSize: 9, color: Colors.grey),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  // ── Insight 5: Regret index ───────────────────────────────────────────────

  Widget _buildRegretInsight(BuildContext ctx, GigInsightsSummary s) {
    final ratedCount = widget.allGigs
        .where((g) => !g.isJamOpenMic && g.averageRating != null)
        .length;

    if (ratedCount < 3) {
      return Text(
        'Rate at least 3 gigs in your retrospective to unlock this insight.',
        style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
          fontStyle: FontStyle.italic,
          color: Theme.of(ctx).colorScheme.onSurfaceVariant,
        ),
      );
    }

    if (s.regretGigs.isEmpty) {
      return _callout(
        ctx,
        Icons.thumb_up_outlined,
        'No regret gigs found. Every gig you\'ve rated was either '
            'above-average pay, above 2.5 stars, or both. Keep it up.',
        Colors.green,
      );
    }

    final dateFmt = DateFormat('MMM d, yy');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _callout(
          ctx,
          Icons.warning_amber_rounded,
          '${s.regretGigs.length} gig${s.regretGigs.length == 1 ? '' : 's'} '
              'were below-average pay AND rated under 2.5 stars — '
              '${_fmtHours(s.totalRegretHours)} you won\'t get back.',
          Colors.red,
        ),
        const SizedBox(height: 12),
        ...s.regretGigs.take(5).map((r) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      r.gig.venueName,
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w500),
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      dateFmt.format(r.gig.dateTime),
                      style: TextStyle(
                          fontSize: 11, color: Colors.grey.shade500),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    _fmtRate(r.trueRate),
                    style: TextStyle(
                        color: Colors.red.shade400,
                        fontWeight: FontWeight.bold,
                        fontSize: 12),
                  ),
                  Text(
                    '★ ${r.averageRating.toStringAsFixed(1)}  '
                        '${_fmtHours(r.hoursInvested)}',
                    style: TextStyle(
                        fontSize: 11, color: Colors.grey.shade500),
                  ),
                ],
              ),
            ],
          ),
        )),
      ],
    );
  }

  // ── Callout banner ────────────────────────────────────────────────────────

  Widget _callout(
      BuildContext ctx, IconData icon, String text, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(fontSize: 12, color: color),
            ),
          ),
        ],
      ),
    );
  }

  // ── BUILD ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      insetPadding:
      const EdgeInsets.symmetric(horizontal: 16, vertical: 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Header ────────────────────────────────────────────────────────
          Container(
            decoration: BoxDecoration(
              color: colorScheme.primary,
              borderRadius:
              const BorderRadius.vertical(top: Radius.circular(16)),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Row(
              children: [
                Icon(Icons.insights, color: colorScheme.onPrimary),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Your Gig Insights',
                    style: theme.textTheme.titleLarge?.copyWith(
                      color: colorScheme.onPrimary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.close, color: colorScheme.onPrimary),
                  onPressed: () => Navigator.of(context).pop(),
                  tooltip: 'Close',
                ),
              ],
            ),
          ),

          // ── Body ──────────────────────────────────────────────────────────
          Flexible(
            child: _isLoading
                ? const SizedBox(
              height: 200,
              child: Center(child: CircularProgressIndicator()),
            )
                : _buildBody(context, _summary!),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(BuildContext ctx, GigInsightsSummary s) {
    if (s.analyzedGigCount == 0) {
      return SizedBox(
        height: 200,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.bar_chart_outlined,
                    size: 48,
                    color: Theme.of(ctx).colorScheme.onSurfaceVariant),
                const SizedBox(height: 16),
                Text(
                  'No past gigs recorded yet.',
                  style: Theme.of(ctx).textTheme.titleSmall,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  'Book and complete a few gigs to unlock your insights report.',
                  style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                    color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Summary pill
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: Theme.of(ctx)
                      .colorScheme
                      .primaryContainer
                      .withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  'Based on ${s.analyzedGigCount} played gig${s.analyzedGigCount == 1 ? '' : 's'}',
                  style: Theme.of(ctx).textTheme.labelSmall?.copyWith(
                    color:
                    Theme.of(ctx).colorScheme.onPrimaryContainer,
                  ),
                ),
              ),
            ),
          ),

          if (!s.hasEnoughData)
            _callout(ctx, Icons.info_outline,
                'Some insights improve with more data. Keep logging gigs!',
                Colors.blue),

          // ── 1. Rate ───────────────────────────────────────────────────────
          _sectionHeader(ctx, Icons.attach_money, 'True rate vs your minimum',
              Colors.green.shade400),
          _buildRateInsight(ctx, s),

          // ── 2. Time ───────────────────────────────────────────────────────
          _sectionHeader(ctx, Icons.access_time_outlined,
              'Where your time goes', Colors.blue.shade400),
          _buildTimeInsight(ctx, s),

          // ── 3. Venues ─────────────────────────────────────────────────────
          _sectionHeader(ctx, Icons.location_on_outlined, 'Venues by true rate',
              Colors.purple.shade400),
          _buildVenueInsight(ctx, s),

          // ── 4. Income ─────────────────────────────────────────────────────
          _sectionHeader(ctx, Icons.trending_up, 'Income trajectory',
              Theme.of(ctx).colorScheme.primary),
          _buildIncomeInsight(ctx, s),

          // ── 5. Regret ─────────────────────────────────────────────────────
          _sectionHeader(ctx, Icons.sentiment_dissatisfied_outlined,
              'Gigs you might regret', Colors.red.shade400),
          _buildRegretInsight(ctx, s),
        ],
      ),
    );
  }
}