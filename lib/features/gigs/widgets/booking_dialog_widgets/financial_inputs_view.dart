import 'package:flutter/material.dart';

class FinancialInputsView extends StatelessWidget {
  final Key? payKey;
  final Key? gigLengthKey;
  final Key? driveSetupKey;
  final Key? rehearsalKey;
  final Key? otherExpensesKey;
  final Key? rateDisplayKey;
  final FocusNode? payFocusNode;

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
    this.payKey,
    this.gigLengthKey,
    this.driveSetupKey,
    this.rehearsalKey,
    this.otherExpensesKey,
    this.rateDisplayKey,
    this.payFocusNode,
    required this.payController,
    required this.otherExpensesController,
    required this.gigLengthController,
    required this.driveSetupController,
    required this.rehearsalController,
    required this.showDynamicRate,
    required this.dynamicRateString,
    required this.dynamicRateResultColor,
  });

  // Helper to create a consistent small decoration
  InputDecoration _getSmallDecoration(String label, {String? hint}) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      isDense: true, // 🎯 Reduces height of the box
      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10), // 🎯 Reduces internal padding
      labelStyle: const TextStyle(fontSize: 14), // 🎯 Smaller label font
      border: const OutlineInputBorder(),
    );
  }

  @override
  Widget build(BuildContext context) {
    const double spacing = 6.0; // 🎯 Reduced from 8.0
    const TextStyle inputStyle = TextStyle(fontSize: 14); // 🎯 Smaller input font

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextFormField(
          key: payKey,
          focusNode: payFocusNode,
          controller: payController,
          style: inputStyle,
          decoration: _getSmallDecoration('Total Pay (\$)*'),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          validator: (value) => (value == null || value.trim().isEmpty || double.tryParse(value) == null) ? 'Required' : null,
        ),
        const SizedBox(height: spacing),
        TextFormField(
          key: gigLengthKey,
          controller: gigLengthController,
          style: inputStyle,
          decoration: _getSmallDecoration('Gig Length (hours)*'),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          validator: (value) => (value == null || value.trim().isEmpty || double.tryParse(value) == null) ? 'Required' : null,
        ),
        const SizedBox(height: spacing),
        TextFormField(
          key: driveSetupKey,
          controller: driveSetupController,
          style: inputStyle,
          decoration: _getSmallDecoration('Drive/Setup (hours)'),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
        ),
        const SizedBox(height: spacing),
        TextFormField(
          key: rehearsalKey,
          controller: rehearsalController,
          style: inputStyle,
          decoration: _getSmallDecoration('Rehearsal (hours)'),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
        ),
        const SizedBox(height: spacing),
        TextFormField(
          key: otherExpensesKey,
          controller: otherExpensesController,
          style: inputStyle,
          decoration: _getSmallDecoration('Other Expenses (\$)', hint: 'e.g., Gas, parking'),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
        ),
        if (showDynamicRate)
          Padding(
            key: rateDisplayKey,
            padding: const EdgeInsets.only(top: 8.0), // 🎯 Reduced from 12.0
            child: Center(
              child: Text(
                dynamicRateString,
                style: TextStyle(
                  fontSize: 14, // 🎯 Reduced from 16
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