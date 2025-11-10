// lib/features/venues/views/venues_list_tab.dart
import 'package:flutter/material.dart';
import 'package:the_money_gigs/features/gigs/models/gig_model.dart';
import 'package:the_money_gigs/features/map_venues/models/venue_model.dart';
import 'package:the_money_gigs/features/notes/views/notes_page.dart';

class VenuesListTab extends StatelessWidget {
  final bool isLoading;
  final List<StoredLocation> displayableVenues;
  final List<Gig> displayedGigs;
  final Future<void> Function(StoredLocation) onVenueTapped;

  const VenuesListTab({
    super.key,
    required this.isLoading,
    required this.displayableVenues,
    required this.displayedGigs,
    required this.onVenueTapped,
  });

  // Helper function to count upcoming gigs for a specific venue
  int _getGigsCountForVenue(StoredLocation venue) {
    DateTime comparisonDate = DateTime.now();
    return displayedGigs.where((gig) {
      bool venueMatch = (gig.placeId != null && gig.placeId!.isNotEmpty && gig.placeId == venue.placeId) ||
          (gig.placeId == null && gig.venueName.toLowerCase().contains(venue.name.toLowerCase()));

      if (!venueMatch) return false;

      // Check if the gig is in the future
      DateTime gigDayStart = DateTime(gig.dateTime.year, gig.dateTime.month, gig.dateTime.day);
      DateTime todayStart = DateTime(comparisonDate.year, comparisonDate.month, comparisonDate.day);
      bool dateMatch = !gigDayStart.isBefore(todayStart);

      return dateMatch && !gig.isJamOpenMic;
    }).length;
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading && displayableVenues.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (displayableVenues.isEmpty) {
      return const Center(
        child: Text(
          "No venues saved yet. Add a new venue when booking a gig!",
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 16, color: Colors.grey),
        ),
      );
    }

    // Sort venues alphabetically by name for consistent display
    List<StoredLocation> sortedDisplayableVenues = List.from(displayableVenues)
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

    return ListView.builder(
      itemCount: sortedDisplayableVenues.length,
      itemBuilder: (context, index) {
        final venue = sortedDisplayableVenues[index];
        final int futureGigsCount = _getGigsCountForVenue(venue);
        final bool hasVenueNotes = (venue.venueNotes?.isNotEmpty ?? false) || (venue.venueNotesUrl?.isNotEmpty ?? false);
        final venueContact = venue.contact;

        String venueDisplayName = venue.isPrivate ? '[PRIVATE] ${venue.name}' : venue.name;

        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
          child: ListTile(
            leading: Icon(Icons.business, color: Theme.of(context).colorScheme.secondary),
            title: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    venueDisplayName,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (futureGigsCount > 0)
                  Text(
                    ' ($futureGigsCount upcoming)',
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.primary,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
              ],
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  venue.address.isNotEmpty ? venue.address : 'Address not specified',
                  style: TextStyle(color: Colors.grey.shade600),
                ),
                if (venueContact != null && venueContact.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    '${venueContact.name} ${venueContact.phone}'.trim(),
                    style: const TextStyle(fontSize: 12, fontStyle: FontStyle.italic),
                  ),
                  if (venueContact.email.isNotEmpty)
                    Text(
                      venueContact.email,
                      style: const TextStyle(fontSize: 12, fontStyle: FontStyle.italic),
                    ),
                ]
              ],
            ),
            trailing: IconButton(
              icon: Icon(
                hasVenueNotes ? Icons.speaker_notes : Icons.speaker_notes_off_outlined,
                color: hasVenueNotes ? Theme.of(context).colorScheme.primary : Colors.grey,
              ),
              tooltip: 'View/Edit Venue Notes',
              onPressed: () {
                Navigator.of(context).push(MaterialPageRoute(
                  builder: (context) => NotesPage(editingVenueId: venue.placeId),
                ));
              },
            ),
            onTap: () => onVenueTapped(venue),
          ),
        );
      },
    );
  }
}
