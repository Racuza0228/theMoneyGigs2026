// lib/features/map_venues/widgets/venue_details_dialog.dart
import 'package:flutter/material.dart';
import 'package:flutter_rating_bar/flutter_rating_bar.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:the_money_gigs/features/map_venues/repositories/venue_repository.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:the_money_gigs/features/gigs/models/gig_model.dart';
import 'package:the_money_gigs/features/map_venues/models/venue_model.dart';
import 'package:the_money_gigs/features/map_venues/widgets/venue_tags_widget.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:the_money_gigs/core/services/auth_service.dart';

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
  late List<String> _instrumentTags;
  late List<String> _genreTags;

  // Repository and connection state
  final _venueRepository = VenueRepository();
  bool _isConnected = false;
  static const String _isConnectedKey = 'is_connected_to_network';

  // State for average rating and comments
  List<Map<String, dynamic>> _recentComments = [];
  bool _loadingComments = true;
  int _currentCommentIndex = 0;

  @override
  void initState() {
    super.initState();
    // Non-async setup remains here
    _currentRating = widget.venue.rating;
    _commentController = TextEditingController(text: widget.venue.comment);
    _isPrivateVenue = widget.venue.isPrivate;
    _instrumentTags = List.from(widget.venue.instrumentTags);
    _genreTags = List.from(widget.venue.genreTags);

    // <<< 1. CALL THE NEW INITIALIZER METHOD >>>
    _initializeDialog();
  }

  Future<void> _initializeDialog() async {
    // First, await the connection status. This is the crucial change.
    await _checkConnectionStatus();

    // Now that _checkConnectionStatus has completed and _isConnected is correctly set,
    // we can safely call the methods that depend on it.
    // The internal guards in these methods will now work as expected.
    if (mounted) {
      _loadRecentComments();
      _loadUserRating();
    }
  }



  Future<void> _checkConnectionStatus() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _isConnected = prefs.getBool(_isConnectedKey) ?? false;
      });
    }
  }

  Future<void> _loadUserRating() async {
    // In standalone mode, skip Firebase operations
    if (!widget.venue.isPublic || !_isConnected) {
      print('ℹ️ Skipping Firebase rating load (standalone mode or not connected).');
      return;
    }

    try {
      final authService = AuthService();
      final userId = authService.isSignedIn ? authService.currentUserId : 'anonymous';
      final docId = '${widget.venue.placeId}_$userId';

      final doc = await FirebaseFirestore.instance
          .collection('venueRatings')
          .doc(docId)
          .get();

      if (doc.exists && mounted) {
        final data = doc.data()!;
        setState(() {
          _currentRating = (data['rating'] as num).toDouble();
          _commentController.text = data['comment'] as String? ?? '';
        });
        print('✅ Loaded user rating from Firebase: $_currentRating');
      } else {
        print('ℹ️ No existing rating found for this user');
      }
    } catch (e) {
      print('❌ Error loading user rating: $e');
    }
  }

  void _nextComment() {
    if (_currentCommentIndex < _recentComments.length - 1) {
      setState(() {
        _currentCommentIndex++;
      });
    }
  }

  void _previousComment() {
    if (_currentCommentIndex > 0) {
      setState(() {
        _currentCommentIndex--;
      });
    }
  }

  Future<void> _loadRecentComments() async {
    // In standalone mode, skip Firebase operations
    if (!widget.venue.isPublic || !_isConnected) {
      print('ℹ️ Skipping Firebase comments load (standalone mode or not connected).');
      if (mounted) {
        setState(() => _loadingComments = false);
      }
      return;
    }

    try {
      final comments = await _venueRepository.getRecentComments(
        placeId: widget.venue.placeId,
        limit: 10,
      );

      if (mounted) {
        setState(() {
          _recentComments = comments;
          _loadingComments = false;
          _currentCommentIndex = 0;
        });
      }
    } catch (e) {
      print('❌ Error loading comments: $e');
      if (mounted) {
        setState(() => _loadingComments = false);
      }
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
    print('🏷️ VenueDetailsDialog: Building updated venue');
    print('   - Current _instrumentTags: $_instrumentTags');
    print('   - Current _genreTags: $_genreTags');
    return widget.venue.copyWith(
      rating: _currentRating,
      comment: _commentController.text.trim().isEmpty ? null : _commentController.text.trim(),
      isPrivate: _isPrivateVenue,
      instrumentTags: _instrumentTags,
      genreTags: _genreTags,
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
        final authService = AuthService();
        final userId = authService.isSignedIn ? authService.currentUserId : 'anonymous';
        print("☁️ DEBUG: Preparing to save to Firebase...");
        print("   - userId: $userId");
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

          // 🏷️ NEW: Sync tags to Firebase if there are any
          if (updatedVenue.genreTags.isNotEmpty || updatedVenue.instrumentTags.isNotEmpty) {
            print("🏷️ DEBUG: Syncing tags to Firebase...");
            print("   - Genres: ${updatedVenue.genreTags}");
            print("   - Instruments: ${updatedVenue.instrumentTags}");

            try {
              await _venueRepository.syncLocalTagsToFirebase(
                placeId: updatedVenue.placeId,
                userId: userId,
                genreTags: updatedVenue.genreTags,
                instrumentTags: updatedVenue.instrumentTags,
              );
              print("✅ DEBUG: Tags synced to Firebase successfully!");
            } catch (e) {
              print("❌ DEBUG: Error syncing tags to Firebase: $e");
            }
          } else {
            print("ℹ️ DEBUG: No tags to sync to Firebase");
          }

          // Notify parent to refresh venues
          widget.onDataChanged?.call();
        } else {
          print("🔥 DEBUG: Firebase save verification FAILED!");
        }
      } catch (e) {
        print("❌ DEBUG: Error during Firebase save: $e");
      }
    } else {
      print("⏭️ DEBUG: Skipping Firebase save (offline or private venue).");
    }

    // 3. Close the dialog if requested.
    if (popOnSave && mounted) {
      Navigator.of(context).pop();
    }
  }

  void _handleBook() {
    final updatedVenue = _buildUpdatedVenue();
    widget.onBook(updatedVenue);
  }

  Widget _buildAverageRating() {
    // Only show if venue is public and has enough ratings
    if (!widget.venue.isPublic || widget.venue.totalRatings < 5) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8.0),
        child: Text(
          'Not enough reviews for an average rating yet.',
          style: TextStyle(fontStyle: FontStyle.italic, color: Colors.grey),
          textAlign: TextAlign.center,
        ),
      );
    }

    return Column(
      children: [
        const Text(
          'Average Rating:',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        // Changed to Column instead of Row to prevent overflow
        Column(
          children: [
            RatingBarIndicator(
              rating: widget.venue.averageRating,
              itemBuilder: (context, _) => const Icon(
                Icons.star,
                color: Colors.amber,
              ),
              itemCount: 5,
              itemSize: 24,
              direction: Axis.horizontal,
            ),
            const SizedBox(height: 4),
            Text(
              '${widget.venue.averageRating.toStringAsFixed(1)} (${widget.venue.totalRatings} reviews)',
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _buildRecentComments() {
    if (!widget.venue.isPublic) {
      return const SizedBox.shrink();
    }

    if (_loadingComments) {
      return const Padding(
        padding: EdgeInsets.all(16.0),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (_recentComments.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8.0),
        child: Text(
          'No comments yet. Be the first to leave one!',
          style: TextStyle(fontStyle: FontStyle.italic, color: Colors.grey),
          textAlign: TextAlign.center,
        ),
      );
    }

    // Show the current comment
    final commentData = _recentComments[_currentCommentIndex];
    final comment = commentData['comment'] as String;
    final rating = commentData['rating'] as double;
    final timestamp = commentData['updatedAt'] as Timestamp?;

    // Format date
    String dateStr = 'Recently';
    if (timestamp != null) {
      final date = timestamp.toDate();
      final now = DateTime.now();
      final diff = now.difference(date);

      if (diff.inDays == 0) {
        dateStr = 'Today';
      } else if (diff.inDays == 1) {
        dateStr = 'Yesterday';
      } else if (diff.inDays < 7) {
        dateStr = '${diff.inDays} days ago';
      } else if (diff.inDays < 30) {
        dateStr = '${(diff.inDays / 7).floor()} weeks ago';
      } else {
        dateStr = DateFormat('MMM d, yyyy').format(date);
      }
    }

    final hasMultipleComments = _recentComments.length > 1;
    final canGoBack = _currentCommentIndex > 0;
    final canGoForward = _currentCommentIndex < _recentComments.length - 1;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Recent Comments:',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            if (hasMultipleComments)
              Text(
                '${_currentCommentIndex + 1} of ${_recentComments.length}',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey.shade600,
                  fontStyle: FontStyle.italic,
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            // Left arrow
            if (hasMultipleComments)
              IconButton(
                icon: Icon(
                  Icons.arrow_back_ios,
                  color: canGoBack ? Colors.blue : Colors.grey.shade300,
                ),
                iconSize: 20,
                onPressed: canGoBack ? _previousComment : null,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              )
            else
              const SizedBox(width: 8),

            // Comment box
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.black,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Rating stars and date on same row - FIXED with Expanded
                    Row(
                      children: [
                        RatingBarIndicator(
                          rating: rating,
                          itemBuilder: (context, _) => const Icon(
                            Icons.star,
                            color: Colors.amber,
                          ),
                          itemCount: 5,
                          itemSize: 18,
                          direction: Axis.horizontal,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            dateStr,
                            textAlign: TextAlign.right,
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey.shade400,
                              fontStyle: FontStyle.italic,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    // Comment text
                    Text(
                      comment,
                      style: const TextStyle(
                        fontSize: 15,
                        height: 1.4,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Right arrow
            if (hasMultipleComments)
              IconButton(
                icon: Icon(
                  Icons.arrow_forward_ios,
                  color: canGoForward ? Colors.blue : Colors.grey.shade300,
                ),
                iconSize: 20,
                onPressed: canGoForward ? _nextComment : null,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              )
            else
              const SizedBox(width: 8),
          ],
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textTheme = theme.textTheme;

    return AlertDialog(
      titlePadding: EdgeInsets.zero,
      contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      actionsPadding: const EdgeInsets.fromLTRB(16.0, 0, 16.0, 12.0),
      // ✅ CHANGED: Wrap title in Column to add archived banner
      title: Column(
        children: [
          // ✅ ARCHIVED BANNER (if archived)
          if (widget.venue.isArchived)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                color: Colors.orange.shade700,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(4),
                  topRight: Radius.circular(4),
                ),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.archive, color: Colors.white, size: 18),
                  SizedBox(width: 8),
                  Text(
                    'ARCHIVED',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
          // Venue name
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
            child: Text(
              widget.venue.name,
              style: textTheme.headlineSmall,
              textAlign: TextAlign.center,
            ),
          ),
        ],
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
                    style: textTheme.bodyMedium?.copyWith(
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

                  _buildAverageRating(),
                  _buildRecentComments(),

                  const Divider(),
                  VenueTagsWidget(
                    venue: widget.venue,
                    isConnected: _isConnected,  // ← Pass connection status
                    onTagsChanged: (instruments, genres) {
                      print('🏷️ VenueDetailsDialog: Received tag changes from widget');
                      print('   - Instruments received: $instruments');
                      print('   - Genres received: $genres');
                      setState(() {
                        _instrumentTags = instruments;
                        _genreTags = genres;
                      });
                      print('   - _instrumentTags updated to: $_instrumentTags');
                      print('   - _genreTags updated to: $_genreTags');
                    },
                  ),

                  const Divider(height: 24),

                  // RATING (Your personal rating)
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

                  // COMMENTS (Your personal comment)
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
        // ✅ CHANGED: Archive button now toggles to Restore when archived
        if (!widget.venue.isPublic)
          TextButton(
            onPressed: widget.onArchive,
            child: widget.venue.isArchived
                ? const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.restore, size: 18, color: Colors.green),
                SizedBox(width: 4),
                Text('RESTORE', style: TextStyle(color: Colors.green)),
              ],
            )
                : Text('ARCHIVE', style: TextStyle(color: theme.colorScheme.error)),
          )
        else
          const SizedBox(), // Maintain alignment for public venues

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