// lib/drive_time_display.dart
import 'package:flutter/material.dart';

class DriveTimeDisplay extends StatelessWidget {
  final bool isFetching;
  final String? duration;
  final String? distance;
  final String? userProfileAddress;

  const DriveTimeDisplay({
    super.key,
    required this.isFetching,
    this.duration,
    this.distance,
    this.userProfileAddress,
  });

  @override
  Widget build(BuildContext context) {
    // Don't show anything if the user has no address set in their profile
    if (userProfileAddress == null || userProfileAddress!.isEmpty) {
      return const SizedBox.shrink();
    }

    // Show a loading indicator while fetching data
    if (isFetching) {
      return const Padding(
        padding: EdgeInsets.only(top: 8.0, bottom: 8.0),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 8),
            Text(
              "Calculating drive time...",
              style: TextStyle(fontStyle: FontStyle.italic),
            ),
          ],
        ),
      );
    }

    // Show the drive time data if it exists
    if (duration != null && distance != null) {
      return Padding(
        padding: const EdgeInsets.only(top: 8.0, bottom: 8.0),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.yellow.withOpacity(0.15),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.yellow.shade700, width: 1),
          ),
          child: Text(
            "Est. Drive: $duration ($distance)",
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.yellow.shade800,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      );
    }

    // If not loading and no data, show nothing
    return const SizedBox.shrink();
  }
}
