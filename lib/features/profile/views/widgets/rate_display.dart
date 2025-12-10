// lib/features/profile/views/widgets/rate_display.dart

import 'package:flutter/material.dart';

class RateDisplay extends StatelessWidget {
  final String rate;

  const RateDisplay({super.key, required this.rate});

  @override
  Widget build(BuildContext context) {
    if (rate.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 8.0),
          child: Text("No minimum rate set. Tap edit to add.",
              style: TextStyle(color: Colors.white70)),
        ),
      );
    }
    const textStyle = TextStyle(color: Colors.white, fontSize: 16, height: 1.5);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 4.0),
      child: Text("\$ $rate per hour", style: textStyle),
    );
  }
}
