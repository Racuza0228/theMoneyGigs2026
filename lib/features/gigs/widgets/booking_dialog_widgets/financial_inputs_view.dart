// lib/features/gigs/widgets/booking_dialog_widgets/financial_inputs_view.dart
import 'package:flutter/material.dart';

class FinancialInputsView extends StatelessWidget {
  final TextEditingController payController;
  final TextEditingController gigLengthController;
  final TextEditingController driveSetupController;
  final TextEditingController rehearsalController;
  final bool showDynamicRate;
  final String dynamicRateString;
  final Color dynamicRateResultColor;

  const FinancialInputsView({
    super.key,
    required this.payController,
    required this.gigLengthController,
    required this.driveSetupController,
    required this.rehearsalController,
    required this.showDynamicRate,
    required this.dynamicRateString,
    required this.dynamicRateResultColor,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextFormField(
          controller: payController,
          decoration: const InputDecoration(labelText: 'Total Pay (\$)*', border: OutlineInputBorder(), prefixText: '\$'),
          keyboardType: const TextInputType.numberWithOptions(decimal: false),
          validator: (value) {
            if (value == null || value.isEmpty) return 'Pay is required';
            final pay = double.tryParse(value);
            if (pay == null) return 'Invalid number for pay';
            if (pay <= 0) return 'Pay must be positive';
            return null;
          },
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: gigLengthController,
          decoration: const InputDecoration(labelText: 'Gig Length (hours)*', border: OutlineInputBorder(), suffixText: 'hrs'),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          validator: (value) {
            if (value == null || value.isEmpty) return 'Gig length is required';
            final length = double.tryParse(value);
            if (length == null) return 'Invalid number for length';
            if (length <= 0) return 'Length must be positive';
            return null;
          },
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: driveSetupController,
          decoration: const InputDecoration(labelText: 'Drive/Setup (hours)', border: OutlineInputBorder(), suffixText: 'hrs'),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          validator: (value) {
            if (value != null && value.isNotEmpty) {
              final driveTime = double.tryParse(value);
              if (driveTime == null) return 'Invalid number for drive/setup';
              if (driveTime < 0) return 'Drive/Setup cannot be negative';
            }
            return null;
          },
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: rehearsalController,
          decoration: const InputDecoration(labelText: 'Rehearsal (hours)', border: OutlineInputBorder(), suffixText: 'hrs'),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          validator: (value) {
            if (value != null && value.isNotEmpty) {
              final rehearsalTime = double.tryParse(value);
              if (rehearsalTime == null) return 'Invalid number for rehearsal';
              if (rehearsalTime < 0) return 'Rehearsal cannot be negative';
            }
            return null;
          },
        ),
        if (showDynamicRate && dynamicRateString.isNotEmpty) ...[
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerRight,
            child: Text(
              dynamicRateString,
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: dynamicRateResultColor),
            ),
          ),
        ],
      ],
    );
  }
}
