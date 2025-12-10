// lib/features/profile/views/widgets/address_form_fields.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class AddressFormFields extends StatelessWidget {
  final TextEditingController address1Controller;
  final TextEditingController address2Controller;
  final TextEditingController cityController;
  final TextEditingController zipCodeController;
  final String? selectedState;
  final List<String> usStates;
  final ValueChanged<String?> onStateChanged;
  final InputDecoration Function({
  required String labelText,
  String? hintText,
  IconData? icon,
  }) formInputDecoration;

  const AddressFormFields({
    super.key,
    required this.address1Controller,
    required this.address2Controller,
    required this.cityController,
    required this.zipCodeController,
    required this.selectedState,
    required this.usStates,
    required this.onStateChanged,
    required this.formInputDecoration,
  });

  @override
  Widget build(BuildContext context) {
    const formTextColor = Colors.white;

    return Column(
      children: [
        TextFormField(
          controller: address1Controller,
          style: const TextStyle(color: formTextColor, fontSize: 16),
          decoration: formInputDecoration(
            labelText: 'Address 1',
            hintText: 'Street address, P.O. box, company name, c/o',
            icon: Icons.home_outlined,
          ),
          validator: (value) => null,
        ),
        const SizedBox(height: 16.0),
        TextFormField(
          controller: address2Controller,
          style: const TextStyle(color: formTextColor, fontSize: 16),
          decoration: formInputDecoration(
            labelText: 'Address 2 (Optional)',
            hintText: 'Apartment, suite, unit, building, floor, etc.',
            icon: Icons.apartment_outlined,
          ),
        ),
        const SizedBox(height: 16.0),
        TextFormField(
          controller: cityController,
          style: const TextStyle(color: formTextColor, fontSize: 16),
          decoration: formInputDecoration(
            labelText: 'City',
            icon: Icons.location_city_outlined,
          ),
        ),
        const SizedBox(height: 16.0),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(
              flex: 2,
              child: Theme(
                data: Theme.of(context).copyWith(canvasColor: Colors.grey[800]),
                child: DropdownButtonFormField<String>(
                  style: const TextStyle(color: formTextColor, fontSize: 16),
                  decoration: formInputDecoration(labelText: 'State'),
                  dropdownColor: Colors.grey[850],
                  value: selectedState,
                  hint:
                  const Text('Select', style: TextStyle(color: Colors.white70)),
                  isExpanded: true,
                  items: usStates.map<DropdownMenuItem<String>>((String value) {
                    return DropdownMenuItem<String>(
                      value: value,
                      child: Text(value, style: const TextStyle(color: formTextColor)),
                    );
                  }).toList(),
                  onChanged: onStateChanged,
                ),
              ),
            ),
            const SizedBox(width: 16.0),
            Expanded(
              flex: 3,
              child: TextFormField(
                controller: zipCodeController,
                style: const TextStyle(color: formTextColor, fontSize: 16),
                decoration: formInputDecoration(labelText: 'Zip Code'),
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(5),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16.0),
      ],
    );
  }
}
