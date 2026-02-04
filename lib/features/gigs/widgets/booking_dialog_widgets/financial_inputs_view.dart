import 'package:flutter/material.dart';

class FinancialInputsView extends StatelessWidget {
  // 1. Add the keys as optional parameters
  final Key? payKey;
  final Key? gigLengthKey;
  final Key? driveSetupKey;
  final Key? rehearsalKey;
  final Key? otherExpensesKey; // 🎯 ADD THIS KEY
  final Key? rateDisplayKey;

  final TextEditingController payController;
  final TextEditingController otherExpensesController;
  final TextEditingController gigLengthController;
  final TextEditingController driveSetupController;
  final TextEditingController rehearsalController;
  final bool showDynamicRate;
  final String dynamicRateString;
  final Color dynamicRateResultColor;

  const FinancialInputsView({
    super.key,
    // 2. Add them to the constructor
    this.payKey,
    this.gigLengthKey,
    this.driveSetupKey,
    this.rehearsalKey,
    this.otherExpensesKey,
    this.rateDisplayKey,
    required this.payController,
    required this.otherExpensesController,
    required this.gigLengthController,
    required this.driveSetupController,
    required this.rehearsalController,
    required this.showDynamicRate,
    required this.dynamicRateString,
    required this.dynamicRateResultColor,
  });

  @override
  Widget build(BuildContext context) {
    // This Column structure places each input on its own line.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextFormField(
          key: payKey, // Assign the key
          controller: payController,
          decoration: const InputDecoration(labelText: 'Total Pay (\$)*', border: OutlineInputBorder()),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          validator: (value) => (value == null || value.trim().isEmpty || double.tryParse(value) == null) ? 'Required' : null,
        ),
        const SizedBox(height: 12),
        TextFormField(
          key: gigLengthKey, // Assign the key
          controller: gigLengthController,
          decoration: const InputDecoration(labelText: 'Gig Length (hours)*', border: OutlineInputBorder()),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          validator: (value) => (value == null || value.trim().isEmpty || double.tryParse(value) == null) ? 'Required' : null,
        ),
        const SizedBox(height: 12),
        TextFormField(
          key: driveSetupKey, // Assign the key
          controller: driveSetupController,
          decoration: const InputDecoration(labelText: 'Drive/Setup (hours)', border: OutlineInputBorder()),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
        ),
        const SizedBox(height: 12),
        TextFormField(
          key: rehearsalKey, // Assign the key
          controller: rehearsalController,
          decoration: const InputDecoration(labelText: 'Rehearsal (hours)', border: OutlineInputBorder()),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
        ),
        const SizedBox(height: 12),
        TextFormField(
          key: otherExpensesKey, // 🎯 ASSIGN THE KEY HERE
          controller: otherExpensesController,
          decoration: const InputDecoration(labelText: 'Other Expenses (\$)', hintText: 'e.g., Gas, parking, strings', border: OutlineInputBorder()),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
        ),
        if (showDynamicRate)
          Padding(
            key: rateDisplayKey,
            padding: const EdgeInsets.only(top: 12.0),
            child: Center(
              child: Text(
                dynamicRateString,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: dynamicRateResultColor,
                ),
              ),
            ),
          ),
      ],
    );
  }
}
