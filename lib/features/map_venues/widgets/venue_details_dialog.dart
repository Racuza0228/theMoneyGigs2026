// lib/features/map_venues/widgets/venue_details_dialog.dart
import 'package:flutter/material.dart';
import 'package:flutter_rating_bar/flutter_rating_bar.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:the_money_gigs/core/services/auth_service.dart';
import 'package:the_money_gigs/features/app_demo/providers/demo_provider.dart';
import 'package:the_money_gigs/features/app_demo/widgets/simple_demo_overlay.dart';
import 'package:the_money_gigs/features/app_demo/widgets/venue_details_demo_overlay.dart';
import 'package:the_money_gigs/features/gigs/models/gig_model.dart';
import 'package:the_money_gigs/features/map_venues/models/venue_model.dart';
import 'package:the_money_gigs/features/map_venues/repositories/venue_repository.dart';
import 'package:the_money_gigs/features/map_venues/widgets/venue_tags_widget.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class VenueDetailsDialog extends StatefulWidget {
  final StoredLocation venue;
  final Gig? nextGig;
  final VoidCallback onArchive;
  final Function(StoredLocation) onBook;
  final Function(StoredLocation) onSave;
  final VoidCallback onEditContact;
  final VoidCallback onEditJamSettings;
  final VoidCallback? onDataChanged;
  final DemoStep? currentDemoStep;

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
    this.currentDemoStep,
  });

  @override
  State<VenueDetailsDialog> createState() => _VenueDetailsDialogState();
}

class _VenueDetailsDialogState extends State<VenueDetailsDialog> {
  // State variables remain the same
  late double _currentRating;
  late final TextEditingController _commentController;
  late bool _isPrivateVenue;
  late List<String> _instrumentTags;
  late List<String> _genreTags;
  final _venueRepository = VenueRepository();
  bool _isConnected = false;
  static const String _isConnectedKey = 'is_connected_to_network';
  List<Map<String, dynamic>> _recentComments = [];
  bool _loadingComments = true;
  int _currentCommentIndex = 0;

  // Keys for highlighting
  final GlobalKey _bookButtonKey = GlobalKey();
  final GlobalKey _nextGigKey = GlobalKey();
  final GlobalKey _saveCloseKey = GlobalKey();

  // This is our handle to the overlay entry so we can remove it later
  OverlayEntry? _overlayEntry;

  @override
  void initState() {
    super.initState();
    _currentRating = widget.venue.rating;
    _commentController = TextEditingController(text: widget.venue.comment);
    _isPrivateVenue = widget.venue.isPrivate;
    _instrumentTags = List.from(widget.venue.instrumentTags);
    _genreTags = List.from(widget.venue.genreTags);
    _initializeDialog();

    // We now use the post frame callback to MANUALLY INSERT the overlay
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      final demoProvider = Provider.of<DemoProvider>(context, listen: false);
      final currentStep = demoProvider.currentStep;

      if (currentStep == DemoStep.mapBookGig) {
        _showOverlayForBook();
      } else if (currentStep == DemoStep.venueDetailsConfirmation) {
        _showOverlayForConfirmation();
      }
    });
  }

  @override
  void dispose() {
    // IMPORTANT: Clean up the overlay when the dialog is disposed
    _removeOverlay();
    _commentController.dispose();
    super.dispose();
  }

  // New helper methods to show and hide the overlay
  void _showOverlayForBook() {
    _overlayEntry = OverlayEntry(
      builder: (context) => VenueDetailsDemoOverlay(bookButtonKey: _bookButtonKey),
    );
    Overlay.of(context).insert(_overlayEntry!);
  }

  void _showOverlayForConfirmation() {
    _overlayEntry = OverlayEntry(
      builder: (context) => SimpleDemoOverlay(
        title: "Gig Booked!",
        message: "Here you can see you now have a gig coming up at this venue. Let's click Save.",
        highlightKeys: [_nextGigKey, _saveCloseKey],
        showNextButton: false,
      ),
    );
    Overlay.of(context).insert(_overlayEntry!);
  }

  void _removeOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  // All other helper methods (_initializeDialog, etc.)
  Future<void> _initializeDialog() async {
    await _checkConnectionStatus();
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
    if (!widget.venue.isPublic || !_isConnected) {
      return;
    }
    try {
      final authService = AuthService();
      final userId = authService.isSignedIn ? authService.currentUserId : 'anonymous';
      final docId = '${widget.venue.placeId}_$userId';
      final doc = await FirebaseFirestore.instance.collection('venueRatings').doc(docId).get();
      if (doc.exists && mounted) {
        final data = doc.data()!;
        setState(() {
          _currentRating = (data['rating'] as num).toDouble();
          _commentController.text = data['comment'] as String? ?? '';
        });
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
    if (!widget.venue.isPublic || !_isConnected) {
      if (mounted) {
        setState(() => _loadingComments = false);
      }
      return;
    }
    try {
      final comments = await _venueRepository.getRecentComments(placeId: widget.venue.placeId, limit: 10);
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
      instrumentTags: _instrumentTags,
      genreTags: _genreTags,
    );
  }

  void _handleSave({bool popOnSave = true}) {
    final demoProvider = Provider.of<DemoProvider>(context, listen: false);
    if (demoProvider.currentStep == DemoStep.venueDetailsConfirmation) {
      demoProvider.nextStep();
    }
    _removeOverlay();

    final updatedVenue = _buildUpdatedVenue();
    widget.onSave(updatedVenue);
    if (_isConnected && !updatedVenue.isPrivate) {
      try {
        final authService = AuthService();
        final userId = authService.isSignedIn ? authService.currentUserId : 'anonymous';
        if (!widget.venue.isPublic) {
          _venueRepository.saveVenue(updatedVenue, userId);
        }
        _venueRepository.saveVenueRating(
          userId: userId,
          placeId: updatedVenue.placeId,
          rating: updatedVenue.rating,
          comment: updatedVenue.comment,
        ).then((saveVerified) {
          if (saveVerified) {
            if (updatedVenue.genreTags.isNotEmpty || updatedVenue.instrumentTags.isNotEmpty) {
              _venueRepository.syncLocalTagsToFirebase(
                placeId: updatedVenue.placeId,
                userId: userId,
                genreTags: updatedVenue.genreTags,
                instrumentTags: updatedVenue.instrumentTags,
              ).catchError((e) => print("❌ DEBUG: Error syncing tags to Firebase: $e"));
            }
            widget.onDataChanged?.call();
          }
        });
      } catch (e) {
        print("❌ DEBUG: Error during Firebase save: $e");
      }
    }
    if (popOnSave && mounted) {
      Navigator.of(context).pop();
    }
  }

  void _handleBook() {
    final demoProvider = Provider.of<DemoProvider>(context, listen: false);
    if (demoProvider.isDemoModeActive && demoProvider.currentStep == DemoStep.mapBookGig) {
      demoProvider.nextStep();
    }
    _removeOverlay();
    final updatedVenue = _buildUpdatedVenue();
    widget.onBook(updatedVenue);
  }

  Widget _buildAverageRating() {
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
        const Text('Average Rating:', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Column(
          children: [
            RatingBarIndicator(
              rating: widget.venue.averageRating,
              itemBuilder: (context, _) => const Icon(Icons.star, color: Colors.amber),
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
      return const Padding(padding: EdgeInsets.all(16.0), child: Center(child: CircularProgressIndicator()));
    }
    if (_recentComments.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8.0),
        child: Text('No comments yet. Be the first to leave one!', style: TextStyle(fontStyle: FontStyle.italic, color: Colors.grey), textAlign: TextAlign.center),
      );
    }
    final commentData = _recentComments[_currentCommentIndex];
    final comment = commentData['comment'] as String;
    final rating = commentData['rating'] as double;
    final timestamp = commentData['updatedAt'] as Timestamp?;
    String dateStr = 'Recently';
    if (timestamp != null) {
      final date = timestamp.toDate();
      final now = DateTime.now();
      final diff = now.difference(date);
      if (diff.inDays == 0) dateStr = 'Today';
      else if (diff.inDays == 1) dateStr = 'Yesterday';
      else if (diff.inDays < 7) dateStr = '${diff.inDays} days ago';
      else if (diff.inDays < 30) dateStr = '${(diff.inDays / 7).floor()} weeks ago';
      else dateStr = DateFormat('MMM d, yyyy').format(date);
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
            const Text('Recent Comments:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            if (hasMultipleComments)
              Text('${_currentCommentIndex + 1} of ${_recentComments.length}', style: TextStyle(fontSize: 12, color: Colors.grey.shade600, fontStyle: FontStyle.italic)),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            if (hasMultipleComments)
              IconButton(
                icon: Icon(Icons.arrow_back_ios, color: canGoBack ? Colors.blue : Colors.grey.shade300),
                iconSize: 20,
                onPressed: canGoBack ? _previousComment : null,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              )
            else const SizedBox(width: 8),
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey.shade300)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        RatingBarIndicator(
                          rating: rating,
                          itemBuilder: (context, _) => const Icon(Icons.star, color: Colors.amber),
                          itemCount: 5,
                          itemSize: 18,
                          direction: Axis.horizontal,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(dateStr, textAlign: TextAlign.right, style: TextStyle(fontSize: 11, color: Colors.grey.shade400, fontStyle: FontStyle.italic), overflow: TextOverflow.ellipsis),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(comment, style: const TextStyle(fontSize: 15, height: 1.4, color: Colors.white)),
                  ],
                ),
              ),
            ),
            if (hasMultipleComments)
              IconButton(
                icon: Icon(Icons.arrow_forward_ios, color: canGoForward ? Colors.blue : Colors.grey.shade300),
                iconSize: 20,
                onPressed: canGoForward ? _nextComment : null,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              )
            else const SizedBox(width: 8),
          ],
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    // The build method is now SIMPLE. It just builds the dialog. No stacks, no consumers.
    final theme = Theme.of(context);
    final textTheme = theme.textTheme;

    return AlertDialog(
      titlePadding: EdgeInsets.zero,
      contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      actionsPadding: const EdgeInsets.fromLTRB(16.0, 0, 16.0, 12.0),
      title: Column(
        children: [
          if (widget.venue.isArchived)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                color: Colors.orange.shade700,
                borderRadius: const BorderRadius.only(topLeft: Radius.circular(4), topRight: Radius.circular(4)),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.archive, color: Colors.white, size: 18),
                  SizedBox(width: 8),
                  Text('ARCHIVED', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
            child: Text(widget.venue.name, style: textTheme.headlineSmall, textAlign: TextAlign.center),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: ListBody(
          children: <Widget>[
            if (widget.venue.address.isNotEmpty)
              InkWell(
                onTap: _openInMaps,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 16.0),
                  child: Text(
                    widget.venue.address,
                    textAlign: TextAlign.center,
                    style: textTheme.bodyMedium?.copyWith(color: theme.colorScheme.primary, decoration: TextDecoration.underline),
                  ),
                ),
              ),
            // Assign the key for highlighting
            if (widget.nextGig != null)
              Column(
                key: _nextGigKey,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Next Gig:', style: TextStyle(fontWeight: FontWeight.bold)),
                  Text('${DateFormat.yMMMEd().format(widget.nextGig!.dateTime)} at ${DateFormat.jm().format(widget.nextGig!.dateTime)}'),
                  const SizedBox(height: 16),
                ],
              ),

            Container(
              padding: const EdgeInsets.all(12.0),
              decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade400), borderRadius: BorderRadius.circular(8.0)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Shared Information', style: textTheme.titleMedium?.copyWith(color: theme.colorScheme.primary)),
                  const SizedBox(height: 12),
                  _buildAverageRating(),
                  _buildRecentComments(),
                  const Divider(),
                  VenueTagsWidget(
                    venue: widget.venue,
                    isConnected: _isConnected,
                    onTagsChanged: (instruments, genres) {
                      setState(() {
                        _instrumentTags = instruments;
                        _genreTags = genres;
                      });
                    },
                  ),
                  const Divider(height: 24),
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
                  const Text('Your Comments:', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _commentController,
                    decoration: const InputDecoration(hintText: 'e.g., Great sound, load-in info...', border: OutlineInputBorder()),
                    maxLines: 2,
                    textCapitalization: TextCapitalization.sentences,
                  ),
                  const SizedBox(height: 16),
                  const Text('Jam/Open Mic:', style: TextStyle(fontWeight: FontWeight.bold)),
                  Text(widget.venue.jamOpenMicDisplayString(context)),
                  Center(child: TextButton(onPressed: widget.onEditJamSettings, child: const Text('Edit Jam/Open Mic Settings'))),
                ],
              ),
            ),
            const SizedBox(height: 16),
            const Divider(),
            if (!widget.venue.isPublic)
              SwitchListTile(
                title: const Text('Private Venue'),
                subtitle: const Text('Will not be shared in the cloud'),
                value: _isPrivateVenue,
                onChanged: (bool value) => setState(() => _isPrivateVenue = value),
                contentPadding: EdgeInsets.zero,
                dense: true,
              ),
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
          const SizedBox(),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            OutlinedButton(
              key: _saveCloseKey,
              onPressed: () => _handleSave(popOnSave: true), // Updated onPressed
              child: const Text('SAVE/CLOSE'),
            ),
            const SizedBox(width: 8),
            ElevatedButton(
              key: _bookButtonKey,
              onPressed: _handleBook,
              style: ElevatedButton.styleFrom(backgroundColor: theme.colorScheme.primary, foregroundColor: theme.colorScheme.onPrimary),
              child: const Text('BOOK'),
            ),
          ],
        )
      ],
    );
  }
}
