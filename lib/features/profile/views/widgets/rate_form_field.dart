// lib/features/profile/views/widgets/rate_form_field.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class RateFormField extends StatelessWidget {
  final TextEditingController minHourlyRateController;
  final InputDecoration Function({
  required String labelText,
  String? hintText,
  IconData? icon,
  String? prefixText,
  }) formInputDecoration;

  const RateFormField({
    super.key,
    required this.minHourlyRateController,
    required this.formInputDecoration,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        TextFormField(
          controller: minHourlyRateController,
          style: const TextStyle(color: Colors.white, fontSize: 16),
          decoration: formInputDecoration(
            labelText: 'Minimum Hourly Rate',
            hintText: 'e.g., 25',
            prefixText: '\$ ',
            icon: Icons.price_change_outlined,
          ),
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          validator: (value) {
            if (value != null && value.isNotEmpty) {
              final rate = int.tryParse(value);
              if (rate == null) return 'Please enter a valid number';
              if (rate <= 0) return 'Rate must be > 0';
            }
            return null;
          },
        ),
        const SizedBox(height: 10),
      ],
    );
  }
}

