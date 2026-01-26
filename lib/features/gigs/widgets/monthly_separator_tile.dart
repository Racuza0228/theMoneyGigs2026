// lib/features/gigs/widgets/monthly_separator_tile.dart

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:the_money_gigs/features/gigs/models/monthly_separator.dart';

/// A widget that displays a monthly summary separator in the gigs list.
///
/// Shows the month/year, gig count, total pay, and average hourly rate.
class MonthlySeparatorTile extends StatelessWidget {
  final MonthlySeparator separator;

  const MonthlySeparatorTile({
    super.key,
    required this.separator,
  });

  @override
  Widget build(BuildContext context) {
    if (!separator.hasGigs) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
      margin: const EdgeInsets.only(top: 16, left: 8, right: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).primaryColor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: Theme.of(context).primaryColor.withOpacity(0.2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            DateFormat.yMMMM().format(separator.month),
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 16,
              color: Theme.of(context).primaryColorLight,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('${separator.gigCount} Gigs'),
              Text(
                '\$${separator.totalPay.toStringAsFixed(0)}',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              Text('Avg. \$${separator.averagePayPerHour.toStringAsFixed(2)}/hr'),
            ],
          ),
        ],
      ),
    );
  }
}