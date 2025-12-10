// lib/features/map_venues/widgets/venue_details_dialog.dart
import 'package:flutter/material.dart';
import 'package:flutter_rating_bar/flutter_rating_bar.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:the_money_gigs/features/map_venues/repositories/venue_repository.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:the_money_gigs/features/gigs/models/gig_model.dart';
import 'package:the_money_gigs/features/map_venues/models/venue_model.dart';

class VenueDetailsDialog extends StatefulWidget {
  final StoredLocation venue;
  final Gig? nextGig;
  final VoidCallback onArchive;
  final Function(StoredLocation) onBook;
  final Function(StoredLocation) onSave;
  final VoidCallback onEditContact;
  final VoidCallback onEditJamSettings;
  final VoidCallback? onDataChanged;

  const VenueDetailsDialog({
    super.key,
    required this.venue,
    this.nextGig,
    required this.onArchive,
    required this.onBook,
    required this.onSave,
    required this.onEditContact,
    required this.onEditJamSettings,
    this.onDataChanged,
  });

  @override
  State<VenueDetailsDialog> createState() => _VenueDetailsDialogState();
}

class _VenueDetailsDialogState extends State<VenueDetailsDialog> {
  // State for editable fields
  late double _currentRating;
  late final TextEditingController _commentController;
  late bool _isPrivateVenue;

  // Repository and connection state
  final _venueRepository = VenueRepository();
  bool _isConnected = false;
  static const String _isConnectedKey = 'is_connected_to_network';

  @override
  void initState() {
    super.initState();
    print("--- 🔵 DEBUG: VenueDetailsDialog initState ---");
    print("   - Loading venue: ${widget.venue.name}");
    print("   - Initial isPublic: ${widget.venue.isPublic}");
    print("   - Initial isPrivate: ${widget.venue.isPrivate}");
    print("   - Initial rating: ${widget.venue.rating}");
    print("   - Initial comment: '${widget.venue.comment}'");

    _currentRating = widget.venue.rating;
    _commentController = TextEditingController(text: widget.venue.comment);
    _isPrivateVenue = widget.venue.isPrivate;
    _checkConnectionStatus();
  }

  Future<void> _checkConnectionStatus() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _isConnected = prefs.getBool(_isConnectedKey) ?? false;
      });
    }
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

  StoredLocation _buildUpdatedVenue() {
    return widget.venue.copyWith(
      rating: _currentRating,
      comment: _commentController.text.trim().isEmpty ? null : _commentController.text.trim(),
      isPrivate: _isPrivateVenue,
    );
  }

  void _handleSave({bool popOnSave = true}) async {
    final updatedVenue = _buildUpdatedVenue();
    print("--- 🔵 DEBUG: _handleSave triggered ---");

    // 1. Always save the complete venue object locally.
    widget.onSave(updatedVenue);
    print("💾 DEBUG: Local save callback (onSave) has been called.");

    // 2. If online and the venue is NOT marked as private, save relevant data to the cloud.
    if (_isConnected && !updatedVenue.isPrivate) {
      try {
        const String userId = 'current_user_id';
        print("☁️ DEBUG: Preparing to save to Firebase...");
        print("   - isConnected: $_isConnected");
        print("   - isPrivate: ${updatedVenue.isPrivate}");

        // 2a. If the venue wasn't already public, this user is submitting it.
        if (!widget.venue.isPublic) {
          print("-> This is a NEW public venue submission. Saving core venue data.");
          await _venueRepository.saveVenue(updatedVenue, userId);
        } else {
          print("-> This is an EXISTING public venue. Skipping core data save.");
        }

        // 2b. ALWAYS save the user's rating and comment for any non-private venue.
        print("   - Calling repository to save rating/comment with data:");
        print("     - userId: $userId");
        print("     - placeId: ${updatedVenue.placeId}");
        print("     - rating: ${updatedVenue.rating}");
        print("     - comment: ${updatedVenue.comment}");

        final bool saveVerified = await _venueRepository.saveVenueRating(
          userId: userId,
          placeId: updatedVenue.placeId,
          rating: updatedVenue.rating,
          comment: updatedVenue.comment,
        );
        if(saveVerified) {
          print("✅ DEBUG: Firebase save and verification successful!");

          // ← ADD THIS: Notify parent to refresh venues
          widget.onDataChanged?.call();
        } else {
          print("🔥 DEBUG: Firebase save verification FAILED!");
        }

      } catch (e) {
        print("❌ DEBUG: Firebase save operation threw an error: $e");
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error saving to cloud: $e'), backgroundColor: Colors.red),
          );
        }
      }
    }

    if (popOnSave && mounted) {
      Navigator.of(context).pop();
    }
  }

  void _handleBook() {
    _handleSave(popOnSave: false); // Save any pending changes before booking
    final venueToBook = _buildUpdatedVenue();
    widget.onBook(venueToBook);
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

            // --- "SHARED INFORMATION" BOX ---
            Container(
              padding: const EdgeInsets.all(12.0),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey.shade400),
                borderRadius: BorderRadius.circular(8.0),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Shared Information',
                    style: textTheme.titleMedium?.copyWith(color: theme.colorScheme.primary),
                  ),
                  const SizedBox(height: 12),

                  // RATING
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
                      onRatingUpdate: (rating) => setState(() => _currentRating = rating),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // COMMENTS
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

                  // JAM SESSION
                  const Text('Jam/Open Mic:', style: TextStyle(fontWeight: FontWeight.bold)),
                  Text(widget.venue.jamOpenMicDisplayString(context)),
                  Center(
                    child: TextButton(
                      onPressed: widget.onEditJamSettings,
                      child: const Text('Edit Jam/Open Mic Settings'),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            const Divider(),

            // --- "PRIVATE VENUE" SWITCH (Conditional) ---
            if (!widget.venue.isPublic)
              SwitchListTile(
                title: const Text('Private Venue'),
                subtitle: const Text('Will not be shared in the cloud'),
                value: _isPrivateVenue,
                onChanged: (bool value) => setState(() => _isPrivateVenue = value),
                contentPadding: EdgeInsets.zero,
                dense: true,
              ),

            // --- CONTACT INFO (Always Private) ---
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
          ],
        ),
      ),
      actionsAlignment: MainAxisAlignment.spaceBetween,
      actions: <Widget>[
        // --- "ARCHIVE" BUTTON (Conditional) ---
        if (!widget.venue.isPublic)
          TextButton(
            onPressed: widget.onArchive,
            child: Text('ARCHIVE', style: TextStyle(color: theme.colorScheme.error)),
          )
        else
          const SizedBox(), // Use a SizedBox to maintain the alignment

        // --- SAVE / BOOK BUTTONS ---
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
