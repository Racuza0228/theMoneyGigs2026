// lib/features/gigs/widgets/tax_year_summary_card.dart
//
// Drop into gig_export_dialog.dart's scrollable body ABOVE the
// _SectionHeader('Spreadsheets') block.
//
// Usage in GigExportDialog.build():
//
//   TaxYearSummaryCard(allGigs: allGigs),
//   const SizedBox(height: 16),
//   _SectionHeader(icon: Icons.table_chart_outlined, ...),
//
// No other files need to change for Sprint 1 MVP.
// Fields marked TODO(sprint1) will populate once paymentType,
// is1099Received, and mileageKm are added to gig_model.dart.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:the_money_gigs/features/gigs/models/gig_model.dart';

class TaxYearSummaryCard extends StatefulWidget {
  final List<Gig> allGigs;

  const TaxYearSummaryCard({super.key, required this.allGigs});

  @override
  State<TaxYearSummaryCard> createState() => _TaxYearSummaryCardState();
}

class _TaxYearSummaryCardState extends State<TaxYearSummaryCard> {
  late int _selectedYear;

  @override
  void initState() {
    super.initState();
    _selectedYear = DateTime.now().year;
  }

  /// Payable, completed gigs for the selected year.
  /// Excludes: jam/open-mic, recurring templates (isRecurring=true),
  /// and gigs that haven't ended yet.
  List<Gig> get _yearGigs => widget.allGigs.where((g) {
    if (g.isJamOpenMic) return false;
    if (g.isRecurring) return false; // templates carry no real income
    if (!g.hasEnded) return false;
    return g.dateTime.year == _selectedYear;
  }).toList();

  String _buildSummaryCsv({
    required int gigCount,
    required double grossIncome,
    required double tips,
    required double expenses,
    required double netIncome,
    required double avgRate,
    required double totalHours,
    required int soloCount,
    required int bandCount,
  }) {
    final sb = StringBuffer();
    sb.writeln('Tax Year Summary — $_selectedYear');
    sb.writeln('Total Gigs,$gigCount');
    sb.writeln('Gross Income,${grossIncome.toStringAsFixed(2)}');
    sb.writeln('Tips,${tips.toStringAsFixed(2)}');
    sb.writeln('Expenses,${expenses.toStringAsFixed(2)}');
    sb.writeln('Net Income,${netIncome.toStringAsFixed(2)}');
    sb.writeln('Avg True Rate (per hr),${avgRate.toStringAsFixed(2)}');
    sb.writeln('Total Hours,${totalHours.toStringAsFixed(1)}');
    sb.writeln('Solo Gigs,$soloCount');
    sb.writeln('Band Gigs,$bandCount');
    sb.writeln('Est. Mileage,— (coming soon)');
    sb.writeln('W2 / 1099 / Cash,— / — / — (coming soon)');
    sb.writeln('1099s Received,— (coming soon)');
    return sb.toString();
  }

  void _copyAndShowSnackbar(BuildContext context, String csv) {
    Clipboard.setData(ClipboardData(text: csv));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$_selectedYear tax summary copied to clipboard!'),
        backgroundColor: Colors.green,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final currency = NumberFormat.currency(symbol: '\$', decimalDigits: 2);
    final gigs = _yearGigs;

    // ── Computed stats ────────────────────────────────────────────────────────
    final gigCount = gigs.length;
    final grossIncome = gigs.fold<double>(0, (s, g) => s + g.pay);
    final tips = gigs.fold<double>(0, (s, g) => s + (g.tipsAmount ?? 0.0));
    final expenses = gigs.fold<double>(0, (s, g) => s + (g.otherExpenses ?? 0.0));
    final netIncome = grossIncome + tips - expenses;
    final totalHours = gigs.fold<double>(
        0,
            (s, g) =>
        s + g.gigLengthHours + g.driveSetupTimeHours + g.rehearsalLengthHours);
    final avgRate = (netIncome > 0 && totalHours > 0) ? netIncome / totalHours : 0.0;
    final soloCount = gigs.where((g) => g.bandName == null || g.bandName!.isEmpty).length;
    final bandCount = gigCount - soloCount;

    final hasData = gigCount > 0;

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: cs.primary.withOpacity(0.35),
          width: 1.5,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header row with year selector ─────────────────────────────────
            Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: cs.primary.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(Icons.receipt_long, color: cs.primary, size: 20),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Tax Year Summary',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                // ── Year picker ───────────────────────────────────────────────
                _YearPicker(
                  year: _selectedYear,
                  onChanged: (y) => setState(() => _selectedYear = y),
                ),
              ],
            ),

            const SizedBox(height: 14),

            if (!hasData)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  'No completed gigs logged for $_selectedYear.',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: cs.onSurfaceVariant),
                ),
              )
            else ...[
              // ── Primary stats: 2-column grid ─────────────────────────────────
              _StatGrid(rows: [
                _StatRow('Total Gigs', '$gigCount'),
                _StatRow('Gross Income', currency.format(grossIncome)),
                _StatRow('Tips', currency.format(tips)),
                _StatRow('Expenses', '${currency.format(expenses)}',
                      ),
                _StatRow('Net Income', currency.format(netIncome),
                    bold: true, valueColor: cs.primary),
                _StatRow('Avg True Rate',
                    '\$${avgRate.toStringAsFixed(2)}/hr'),
                _StatRow('Total Hours', '${totalHours.toStringAsFixed(1)} hrs'),
                _StatRow('Solo / Band', '$soloCount / $bandCount'),
              ]),

              const SizedBox(height: 12),
              Divider(color: cs.outlineVariant),
              const SizedBox(height: 8),

              // ── Sprint 1 stubs ────────────────────────────────────────────────
              Text(
                'COMING IN NEXT UPDATE',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: cs.onSurfaceVariant,
                  letterSpacing: 1.0,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              _StatGrid(rows: [
                _StatRow('Est. Mileage', '—',
                    stub: true,
                    hint: 'Add home address in Settings'),
                _StatRow('W2 / 1099 / Cash', '— / — / —',
                    stub: true,
                    hint: 'Log payment type per gig'),
                _StatRow('1099s Received', '—',
                    stub: true,
                    hint: 'Flag per gig at tax time'),
              ]),

              const SizedBox(height: 14),

              // ── Export button ────────────────────────────────────────────────
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.tonal(
                  onPressed: () => _copyAndShowSnackbar(
                    context,
                    _buildSummaryCsv(
                      gigCount: gigCount,
                      grossIncome: grossIncome,
                      tips: tips,
                      expenses: expenses,
                      netIncome: netIncome,
                      avgRate: avgRate,
                      totalHours: totalHours,
                      soloCount: soloCount,
                      bandCount: bandCount,
                    ),
                  ),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.copy, size: 14),
                      SizedBox(width: 6),
                      Text('Copy Summary CSV',
                          style: TextStyle(fontSize: 12)),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// YEAR PICKER  (<  2025  >)
// ─────────────────────────────────────────────────────────────────────────────

class _YearPicker extends StatelessWidget {
  final int year;
  final ValueChanged<int> onChanged;

  const _YearPicker({required this.year, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final currentYear = DateTime.now().year;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _ArrowBtn(
          icon: Icons.chevron_left,
          onPressed: () => onChanged(year - 1),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text(
            '$year',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: year == currentYear ? cs.primary : cs.onSurface,
            ),
          ),
        ),
        _ArrowBtn(
          icon: Icons.chevron_right,
          // Don't let the user navigate into the future
          onPressed: year < currentYear ? () => onChanged(year + 1) : null,
        ),
      ],
    );
  }
}

class _ArrowBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onPressed;

  const _ArrowBtn({required this.icon, this.onPressed});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 28,
      height: 28,
      child: IconButton(
        padding: EdgeInsets.zero,
        iconSize: 18,
        icon: Icon(icon),
        onPressed: onPressed,
        color: onPressed != null
            ? Theme.of(context).colorScheme.primary
            : Theme.of(context).colorScheme.onSurface.withOpacity(0.25),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// STAT GRID  — 2-column label/value layout
// ─────────────────────────────────────────────────────────────────────────────

class _StatRow {
  final String label;
  final String value;
  final bool bold;
  final Color? valueColor;
  final bool stub;
  final String? hint;

  const _StatRow(
      this.label,
      this.value, {
        this.bold = false,
        this.valueColor,
        this.stub = false,
        this.hint,
      });
}

class _StatGrid extends StatelessWidget {
  final List<_StatRow> rows;
  const _StatGrid({required this.rows});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Column(
      children: rows.map((row) {
        final labelStyle = theme.textTheme.bodySmall?.copyWith(
          color: row.stub ? cs.onSurfaceVariant.withOpacity(0.6) : cs.onSurfaceVariant,
        );
        final valueStyle = theme.textTheme.bodySmall?.copyWith(
          fontWeight: row.bold ? FontWeight.bold : FontWeight.w500,
          color: row.stub
              ? cs.onSurfaceVariant.withOpacity(0.45)
              : (row.valueColor ?? cs.onSurface),
        );

        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(
            children: [
              Expanded(
                flex: 5,
                child: Text(row.label, style: labelStyle),
              ),
              Expanded(
                flex: 4,
                child: Text(
                  row.value,
                  style: valueStyle,
                  textAlign: TextAlign.right,
                ),
              ),
              if (row.stub && row.hint != null) ...[
                const SizedBox(width: 6),
                Tooltip(
                  message: row.hint!,
                  child: Icon(
                    Icons.info_outline,
                    size: 13,
                    color: cs.onSurfaceVariant.withOpacity(0.4),
                  ),
                ),
              ] else
                const SizedBox(width: 19), // Keeps alignment consistent
            ],
          ),
        );
      }).toList(),
    );
  }
}