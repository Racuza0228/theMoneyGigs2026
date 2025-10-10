// lib/services/gig_embed_service.dart
import 'package:intl/intl.dart';
import 'package:the_money_gigs/features/gigs/models/gig_model.dart';

class GigEmbedService {
  /// Generates an HTML string to be embedded on a website.
  ///
  /// This method takes a list of [Gig] objects, filters for upcoming,
  /// non-jam session gigs, and formats them into an HTML snippet.
  static String generateEmbedCode(List<Gig> allGigs) {
    // 1. Filter for only upcoming, non-jam gigs and sort them by date.
    final now = DateTime.now();
    final upcomingGigs = allGigs
        .where((gig) => !gig.isJamOpenMic && gig.dateTime.isAfter(now))
        .toList();

    // Sort gigs chronologically
    upcomingGigs.sort((a, b) => a.dateTime.compareTo(b.dateTime));

    // If there are no upcoming gigs, return a simple message.
    if (upcomingGigs.isEmpty) {
      return '<div class="gigs-container"><p>No upcoming shows. Check back soon!</p></div>';
    }

    // 2. Generate the HTML for each gig.
    final gigListItems = upcomingGigs.map((gig) {
      // Format the date and time for display.
      final date = DateFormat.yMMMEd().format(gig.dateTime);
      final time = DateFormat.jm().format(gig.dateTime);
      final googleMapsUrl =
          'https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(gig.address)}';

      return '''
        <div class="gig-item">
            <p class="gig-date"><strong>When:</strong> $date at $time</p>
            <p class="gig-venue"><strong>Where:</strong> ${gig.venueName}</p>
            <p class="gig-address"><a href="$googleMapsUrl" target="_blank" rel="noopener noreferrer">${gig.address}</a></p>
        </div>''';
    }).join('\n'); // Join each gig's HTML with a newline.

    // 3. Combine CSS styles and the gig list into a final HTML block.
    return '''
<style>
    .gigs-container {
        font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif;
        border: 1px solid #ddd;
        border-radius: 8px;
        padding: 16px;
        max-width: 600px;
        margin: 20px auto;
        background-color: #f9f9f9;
    }
    .gigs-header {
        font-size: 24px;
        font-weight: bold;
        margin-bottom: 16px;
        color: #333;
    }
    .gig-item {
        border-bottom: 1px solid #eee;
        padding: 12px 0;
    }
    .gig-item:last-child {
        border-bottom: none;
    }
    .gig-item p {
        margin: 4px 0;
        color: #555;
    }
    .gig-item .gig-date, .gig-item .gig-venue {
        font-size: 16px;
    }
    .gig-item .gig-address a {
        color: #007bff;
        text-decoration: none;
    }
    .gig-item .gig-address a:hover {
        text-decoration: underline;
    }
</style>
<div class="gigs-container">
    <h2 class="gigs-header">Upcoming Shows</h2>
    $gigListItems
</div>
''';
  }
}
