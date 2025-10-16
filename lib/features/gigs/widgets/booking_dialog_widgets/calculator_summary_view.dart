// lib/features/gigs/widgets/booking_dialog_widgets/calculator_summary_view.dart
import 'package:flutter/material.dart';

class CalculatorSummaryView extends StatelessWidget {
  final double? totalPay;final double? gigLengthHours;
  final double? driveSetupTimeHours;
  final double? rehearsalTimeHours;
  final String? calculatedHourlyRate;

  const CalculatorSummaryView({
    super.key,
    required this.totalPay,
    required this.gigLengthHours,
    required this.driveSetupTimeHours,
    required this.rehearsalTimeHours,
    required this.calculatedHourlyRate,
  });

  @override
  Widget build(BuildContext context) {
    final detailLabelStyle = const TextStyle(fontWeight: FontWeight.bold);
    final detailValueStyle = TextStyle(color: Colors.lightBlue, fontSize: 14);
    final rateValueStyle = const TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 16);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        //const Text("Review Calculated Details:", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        const Divider(height: 10, thickness: 1),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text('Total Pay:', style: detailLabelStyle), Text('\$${totalPay?.toStringAsFixed(0) ?? 'N/A'}', style: detailValueStyle)]),
        const SizedBox(height: 4),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text('Gig Length:', style: detailLabelStyle), Text('${gigLengthHours?.toStringAsFixed(1) ?? 'N/A'} hrs', style: detailValueStyle)]),
        const SizedBox(height: 4),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text('Drive/Setup:', style: detailLabelStyle), Text('${driveSetupTimeHours?.toStringAsFixed(1) ?? 'N/A'} hrs', style: detailValueStyle)]),
        const SizedBox(height: 4),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text('Rehearsal:', style: detailLabelStyle), Text('${rehearsalTimeHours?.toStringAsFixed(1) ?? 'N/A'} hrs', style: detailValueStyle)]),
        const SizedBox(height: 8),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text('Hourly Rate:', style: detailLabelStyle), Text(calculatedHourlyRate ?? 'N/A', style: rateValueStyle)]),
        const Divider(height: 24, thickness: 1),
      ],
    );
  }
}
