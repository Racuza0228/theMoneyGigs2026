// lib/features/map_venues/widgets/venue_details_dialog.dart
import 'package:flutter/material.dart';
import 'package:flutter_rating_bar/flutter_rating_bar.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:the_money_gigs/features/gigs/models/gig_model.dart';
import 'package:the_money_gigs/features/map_venues/models/venue_model.dart';

class VenueDetailsDialog extends StatefulWidget {
  final StoredLocation venue;
  final Gig? nextGig;
  final VoidCallback onArchive;
  // MODIFIED: onBook now passes back the venue to be saved and booked.
  final Function(StoredLocation) onBook;
  final Function(StoredLocation) onSave;
  final VoidCallback onEditContact;
  final VoidCallback onEditJamSettings;

  const VenueDetailsDialog({
    super.key,
    required this.venue,
    this.nextGig,
    required this.onArchive,
    required this.onBook,
    required this.onSave,
    required this.onEditContact,
    required this.onEditJamSettings,
  });

  @override
  State<VenueDetailsDialog> createState() => _VenueDetailsDialogState();
}

class _VenueDetailsDialogState extends State<VenueDetailsDialog> {
  late double _currentRating;
  late final TextEditingController _commentController;

  @override
  void initState() {
    super.initState();
    _currentRating = widget.venue.rating;
    _commentController = TextEditingController(text: widget.venue.comment);
  }

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  Future<void> _openInMaps() async {
    final lat = widget.venue.coordinates.latitude;
    final lng = widget.venue.coordinates.longitude;
    final query = Uri.encodeComponent(widget.venue.address.isNotEmpty ? widget.venue.address : widget.venue.name);
    final webUrl = 'https://www.google.com/maps/search/?api=1&query=$query&query_place_id=${widget.venue.placeId}';
    final Uri uri = Uri.parse('geo:$lat,$lng?q=$query');

    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else {
      await launchUrl(Uri.parse(webUrl));
    }
  }

  void _handleSave({bool popOnSave = true}) {
    final newRating = _currentRating;
    final newComment = _commentController.text.trim();
    final newCommentOrNull = newComment.isEmpty ? null : newComment;

    final bool hasRatingChanged = newRating != widget.venue.rating;
    final bool hasCommentChanged = newCommentOrNull != widget.venue.comment;

    // Only save if a change was made
    if (hasRatingChanged || hasCommentChanged) {
      final updatedVenue = widget.venue.copyWith(
        rating: newRating,
        comment: newCommentOrNull,
      );
      widget.onSave(updatedVenue);
    }

    if (popOnSave && mounted) {
      Navigator.of(context).pop();
    }
  }

  // *** THE FIX IS HERE ***
  // This method now ensures the venue is saved before booking.
  void _handleBook() {
    // Create an updated venue object with any pending UI changes.
    final venueWithPendingChanges = widget.venue.copyWith(
      rating: _currentRating,
      comment: _commentController.text.trim().isEmpty ? null : _commentController.text.trim(),
    );
    // Pass this venue to the onBook callback. The parent widget will now be
    // responsible for saving it and launching the booking flow.
    widget.onBook(venueWithPendingChanges);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textTheme = theme.textTheme;

    return AlertDialog(
      titlePadding: EdgeInsets.zero,
      contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      actionsPadding: const EdgeInsets.fromLTRB(16.0, 0, 16.0, 12.0),
      title: Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
        child: Text(widget.venue.name, style: textTheme.headlineSmall, textAlign: TextAlign.center),
      ),
      content: SingleChildScrollView(
        child: ListBody(
          children: <Widget>[
            // Address
            if (widget.venue.address.isNotEmpty)
              InkWell(
                onTap: _openInMaps,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 16.0),
                  child: Text(
                    widget.venue.address,
                    textAlign: TextAlign.center,
                    style: textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.primary,
                      decoration: TextDecoration.underline,
                    ),
                  ),
                ),
              ),

            // Next Gig
            if (widget.nextGig != null) ...[
              const Text('Next Gig:', style: TextStyle(fontWeight: FontWeight.bold)),
              Text('${DateFormat.yMMMEd().format(widget.nextGig!.dateTime)} at ${DateFormat.jm().format(widget.nextGig!.dateTime)}'),
              const SizedBox(height: 16),
            ],

            // Rating
            const Text('Your Rating:', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Center(
              child: RatingBar.builder(
                initialRating: _currentRating,
                minRating: 0,
                direction: Axis.horizontal,
                allowHalfRating: true,
                itemCount: 5,
                itemPadding: const EdgeInsets.symmetric(horizontal: 4.0),
                itemBuilder: (context, _) => const Icon(Icons.star, color: Colors.amber),
                onRatingUpdate: (rating) {
                  setState(() {
                    _currentRating = rating;
                  });
                },
              ),
            ),
            const SizedBox(height: 16),

            // Comment
            const Text('Your Comments:', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            TextField(
              controller: _commentController,
              decoration: const InputDecoration(
                hintText: 'e.g., Great sound, load-in info...',
                border: OutlineInputBorder(),
              ),
              maxLines: 2,
              textCapitalization: TextCapitalization.sentences,
            ),
            const SizedBox(height: 16),
            const Divider(),

            // Contact Person
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Contact:', style: TextStyle(fontWeight: FontWeight.bold)),
                IconButton(
                  icon: const Icon(Icons.edit_outlined),
                  iconSize: 20.0,
                  color: theme.colorScheme.primary,
                  tooltip: 'Edit Contact Info',
                  onPressed: widget.onEditContact,
                )
              ],
            ),
            if (widget.venue.contact?.isNotEmpty ?? false)
              Padding(
                padding: const EdgeInsets.only(left: 8.0, bottom: 8.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (widget.venue.contact!.name.isNotEmpty) Text(widget.venue.contact!.name),
                    if (widget.venue.contact!.phone.isNotEmpty) Text(widget.venue.contact!.phone),
                    if (widget.venue.contact!.email.isNotEmpty) Text(widget.venue.contact!.email),
                  ],
                ),
              )
            else
              const Padding(
                padding: EdgeInsets.only(left: 8.0, bottom: 8.0),
                child: Text('No contact saved.', style: TextStyle(fontStyle: FontStyle.italic)),
              ),
            const SizedBox(height: 8),

            // Jam/Open Mic Setup
            const Text('Jam/Open Mic:', style: TextStyle(fontWeight: FontWeight.bold)),
            Text(widget.venue.jamOpenMicDisplayString(context)),
            Center(
              child: TextButton(
                child: const Text('Edit Jam/Open Mic Settings'),
                onPressed: widget.onEditJamSettings,
              ),
            ),
          ],
        ),
      ),
      actionsAlignment: MainAxisAlignment.spaceBetween,
      actions: <Widget>[
        // Buttons
        TextButton(
          onPressed: widget.onArchive,
          child: Text('ARCHIVE', style: TextStyle(color: theme.colorScheme.error)),
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            OutlinedButton(onPressed: _handleSave, child: const Text('SAVE/CLOSE')),
            const SizedBox(width: 8),
            ElevatedButton(
              onPressed: _handleBook,
              style: ElevatedButton.styleFrom(
                  backgroundColor: theme.colorScheme.primary,
                  foregroundColor: theme.colorScheme.onPrimary),
              child: const Text('BOOK'),
            ),
          ],
        )
      ],
    );
  }
}
