// lib/features/gigs/widgets/booking_dialog_widgets/venue_selection_view.dart
import 'package:flutter/material.dart';
import 'package:the_money_gigs/features/map_venues/models/venue_model.dart';

class VenueSelectionView extends StatelessWidget {
  final bool isStaticDisplay; // Determines if we show a dropdown or static text
  final bool isLoading;
  final StoredLocation? selectedVenue;
  final List<StoredLocation> selectableVenues;
  final StoredLocation addNewVenuePlaceholder;
  final ValueChanged<StoredLocation?> onVenueSelected;

  const VenueSelectionView({
    super.key,
    required this.isStaticDisplay,
    required this.isLoading,
    this.selectedVenue,
    required this.selectableVenues,
    required this.addNewVenuePlaceholder,
    required this.onVenueSelected,
  });

  @override
  Widget build(BuildContext context) {
    if (isStaticDisplay) {
      if (selectedVenue == null) {
        return const Text("Venue information missing.", style: TextStyle(color: Colors.red, fontStyle: FontStyle.italic));
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(selectedVenue!.name, style: Theme.of(context).textTheme.titleMedium),
          Text(selectedVenue!.address, style: Theme.of(context).textTheme.bodySmall ?? const TextStyle()),
          if (selectedVenue!.isArchived)
            Padding(
              padding: const EdgeInsets.only(top: 4.0),
              child: Text("(This venue is archived)", style: TextStyle(color: Colors.orange.shade700, fontStyle: FontStyle.italic, fontSize: 12)),
            ),
          const SizedBox(height: 8),
        ],
      );
    }

    if (isLoading) {
      return const Center(child: Padding(padding: EdgeInsets.all(16.0), child: CircularProgressIndicator()));
    }

    return DropdownButtonFormField<StoredLocation>(
      decoration: const InputDecoration(labelText: 'Select or Add Venue', border: OutlineInputBorder()),
      initialValue: selectedVenue,
      isExpanded: true,
      items: selectableVenues.map<DropdownMenuItem<StoredLocation>>((StoredLocation venue) {
        bool isEnabled = !venue.isArchived || venue.placeId == addNewVenuePlaceholder.placeId;
        return DropdownMenuItem<StoredLocation>(
          value: venue,
          enabled: isEnabled,
          child: Text(
            venue.name + (venue.isArchived && venue.placeId != addNewVenuePlaceholder.placeId ? " (Archived)" : ""),
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: isEnabled ? null : Colors.grey.shade500),
          ),
        );
      }).toList(),
      onChanged: (StoredLocation? newValue) {
        if (newValue == null) return;
        if (newValue.isArchived && newValue.placeId != addNewVenuePlaceholder.placeId) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("${newValue.name} is archived and cannot be selected."), backgroundColor: Colors.orange),
          );
          return;
        }
        onVenueSelected(newValue);
      },
      validator: (value) {
        if (value == null) return 'Please select a venue option.';
        if (value.isArchived && value.placeId != addNewVenuePlaceholder.placeId) {
          return 'Archived venues cannot be booked.';
        }
        return null;
      },
    );
  }
}
