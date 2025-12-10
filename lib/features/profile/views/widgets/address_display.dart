// lib/features/profile/views/widgets/address_display.dart

import 'package:flutter/material.dart';

class AddressDisplay extends StatelessWidget {
  final String address1;
  final String? address2;
  final String city;
  final String? state;
  final String zip;

  const AddressDisplay({
    super.key,
    required this.address1,
    this.address2,
    required this.city,
    this.state,
    required this.zip,
  });

  @override
  Widget build(BuildContext context) {
    if (address1.isEmpty &&
        (address2 == null || address2!.isEmpty) &&
        city.isEmpty &&
        (state == null || state!.isEmpty) &&
        zip.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 8.0),
          child: Text("No address information available. Tap edit to add.",
              style: TextStyle(color: Colors.white70)),
        ),
      );
    }

    const textStyle = TextStyle(color: Colors.white, fontSize: 16, height: 1.5);
    final displayAddress2 = address2 ?? '';
    final displayState = state ?? '';

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 4.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (address1.isNotEmpty) Text(address1, style: textStyle),
          if (displayAddress2.isNotEmpty) Text(displayAddress2, style: textStyle),
          if (city.isNotEmpty || displayState.isNotEmpty || zip.isNotEmpty)
            Text(
              "${city.isNotEmpty ? city : ''}"
                  "${(city.isNotEmpty && displayState.isNotEmpty) ? ', ' : ''}"
                  "$displayState ${zip.isNotEmpty ? zip : ''}"
                  .trim(),
              style: textStyle,
            ),
          const SizedBox(height: 10),
        ],
      ),
    );
  }
}
