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
import 'package:the_money_gigs/features/map_venues/models/venue_contact.dart';
import 'package:the_money_gigs/features/map_venues/models/venue_model.dart';
import 'package:the_money_gigs/features/map_venues/repositories/venue_repository.dart';
import 'package:the_money_gigs/features/map_venues/widgets/venue_contact_dialog.dart';
import 'package:the_money_gigs/features/map_venues/widgets/venue_tags_widget.dart';
import 'package:the_money_gigs/core/utils/logger.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class VenueDetailsDialog extends StatefulWidget {
  final StoredLocation venue;
  final Gig? nextGig;
  final VoidCallback onArchive;
  final Function(StoredLocation) onBook;
  final Function(StoredLocation) onSave;

  /// Called after the user saves a contact from within this dialog.
  /// Replaces the old onEditContact VoidCallback — the parent no longer
  /// needs to open VenueContactDialog itself; it only receives the result.
  final Function(VenueContact contact, BookingInfo? bookingInfo)? onContactSaved;

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
    this.onContactSaved,
    required this.onEditJamSettings,
    this.onDataChanged,
    this.currentDemoStep,
  });

  @override
  State<VenueDetailsDialog> createState() => _VenueDetailsDialogState();
}

class _VenueDetailsDialogState extends State<VenueDetailsDialog> {
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

  // ── Contact confirmation state ────────────────────────────────────────────
  // _localContact and _localBookingInfo are mutable copies that update
  // immediately after a save, so reopening the edit form within the same
  // dialog instance always shows the latest data rather than the stale
  // widget.venue.contact (which is final and never changes).
  late VenueContact? _localContact;
  late BookingInfo? _localBookingInfo;
  bool _userHasConfirmedContact = false;
  bool _confirmationLoading = false;
  int _liveConfirmationCount = 0;

  final GlobalKey _bookButtonKey = GlobalKey();
  final GlobalKey _nextGigKey = GlobalKey();
  final GlobalKey _saveCloseKey = GlobalKey();

  OverlayEntry? _overlayEntry;

  @override
  void initState() {
    super.initState();
    _currentRating = widget.venue.rating;
    _commentController = TextEditingController(text: widget.venue.comment);
    _isPrivateVenue = widget.venue.isPrivate;
    _instrumentTags = List.from(widget.venue.instrumentTags);
    _genreTags = List.from(widget.venue.genreTags);
    _liveConfirmationCount = widget.venue.contact?.confirmationCount ?? 0;
    _localContact = widget.venue.contact;
    _localBookingInfo = widget.venue.bookingInfo;
    _initializeDialog();

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await Future.delayed(const Duration(milliseconds: 300));
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
    _removeOverlay();
    _commentController.dispose();
    super.dispose();
  }

  // ── Overlays ──────────────────────────────────────────────────────────────

  void _showOverlayForBook() {
    _overlayEntry = OverlayEntry(
      builder: (context) => VenueDetailsDemoOverlay(
        bookButtonKey: _bookButtonKey,
        onExit: _removeOverlay,
      ),
    );
    Overlay.of(context).insert(_overlayEntry!);
  }

  void _showOverlayForConfirmation() {
    _overlayEntry = OverlayEntry(
      builder: (context) => SimpleDemoOverlay(
        title: 'Gig Booked!',
        message:
        "Here you can see you now have a gig coming up at this venue. Let's click SAVE/CLOSE below.",
        highlightKeys: [_nextGigKey, _saveCloseKey],
        showNextButton: false,
        onExit: _removeOverlay,
      ),
    );
    Overlay.of(context).insert(_overlayEntry!);
  }

  void _removeOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  // ── Initialisation ────────────────────────────────────────────────────────

  Future<void> _initializeDialog() async {
    await _checkConnectionStatus();
    if (mounted) {
      _loadRecentComments();
      _loadUserRating();
      _loadContactConfirmationState();
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
    if (!widget.venue.isPublic || !_isConnected) return;
    try {
      final authService = AuthService();
      final userId =
      authService.isSignedIn ? authService.currentUserId : 'anonymous';
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
      }
    } catch (e) {
      log('❌ Error loading user rating: $e');
    }
  }

  void _nextComment() {
    if (_currentCommentIndex < _recentComments.length - 1) {
      setState(() => _currentCommentIndex++);
    }
  }

  void _previousComment() {
    if (_currentCommentIndex > 0) {
      setState(() => _currentCommentIndex--);
    }
  }

  Future<void> _loadRecentComments() async {
    if (!widget.venue.isPublic || !_isConnected) {
      if (mounted) setState(() => _loadingComments = false);
      return;
    }
    try {
      final comments = await _venueRepository.getRecentComments(
          placeId: widget.venue.placeId, limit: 10);
      if (mounted) {
        setState(() {
          _recentComments = comments;
          _loadingComments = false;
          _currentCommentIndex = 0;
        });
      }
    } catch (e) {
      log('❌ Error loading comments: $e');
      if (mounted) setState(() => _loadingComments = false);
    }
  }

  Future<void> _loadContactConfirmationState() async {
    final contact = _localContact;
    if (contact == null || !contact.isSharedWithNetwork || !_isConnected) {
      return;
    }
    try {
      final authService = AuthService();
      if (!authService.isSignedIn) return;
      final userId = authService.currentUserId;
      final result = await _venueRepository.getContactConfirmationState(
        placeId: widget.venue.placeId,
        userId: userId,
      );
      if (mounted) {
        setState(() {
          _userHasConfirmedContact = result['userConfirmed'] as bool? ?? false;
          _liveConfirmationCount =
              result['count'] as int? ?? _liveConfirmationCount;
        });
      }
    } catch (e) {
      log('❌ Error loading confirmation state: $e');
    }
  }

  Future<void> _toggleContactConfirmation() async {
    if (!_isConnected || _confirmationLoading) return;
    final authService = AuthService();
    if (!authService.isSignedIn) return;
    final userId = authService.currentUserId;

    final wasConfirmed = _userHasConfirmedContact;

    setState(() {
      _confirmationLoading = true;
      _userHasConfirmedContact = !wasConfirmed;
      _liveConfirmationCount += wasConfirmed ? -1 : 1;
    });

    try {
      if (wasConfirmed) {
        await _venueRepository.removeContactConfirmation(
          placeId: widget.venue.placeId,
          userId: userId,
        );
      } else {
        await _venueRepository.confirmVenueContact(
          placeId: widget.venue.placeId,
          userId: userId,
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _userHasConfirmedContact = wasConfirmed;
          _liveConfirmationCount += wasConfirmed ? 1 : -1;
        });
      }
      log('❌ Error toggling contact confirmation: $e');
    } finally {
      if (mounted) setState(() => _confirmationLoading = false);
    }
  }

  Future<void> _openContactDialog() async {
    final authService = AuthService();
    final userId =
    authService.isSignedIn ? authService.currentUserId : null;

    final result = await showDialog<VenueContactSaveResult>(
      context: context,
      builder: (_) => VenueContactDialog(
        venue: widget.venue.copyWith(
          contact: _localContact,
          bookingInfo: _localBookingInfo,
        ),
        isConnected: _isConnected,
        currentUserId: userId,
      ),
    );

    if (result == null) return;

    // Update local state immediately so reopening the form within the same
    // dialog instance shows the just-saved data.
    setState(() {
      _localContact = result.contact;
      _localBookingInfo = result.bookingInfo;
    });

    // (a) Notify parent — handles SharedPreferences persistence
    widget.onContactSaved?.call(result.contact, result.bookingInfo);

    // (b) Save to Firebase only if connected AND user opted to share
    if (_isConnected && userId != null && result.contact.isSharedWithNetwork) {
      try {
        await _venueRepository.saveVenueContact(
          placeId: widget.venue.placeId,
          userId: userId,
          contact: result.contact,
          bookingInfo: result.bookingInfo,
        );
        log('✅ Contact saved to Firebase for ${widget.venue.name}');
      } catch (e) {
        log('❌ Error saving contact to Firebase: \$e');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Contact saved locally. Cloud sync failed — will retry on next save.'),
              backgroundColor: Colors.orange,
            ),
          );
        }
      }
    }
  }

  // ── Venue helpers ─────────────────────────────────────────────────────────

  Future<void> _openInMaps() async {
    final lat = widget.venue.coordinates.latitude;
    final lng = widget.venue.coordinates.longitude;
    final query = Uri.encodeComponent(widget.venue.address.isNotEmpty
        ? widget.venue.address
        : widget.venue.name);
    final webUrl =
        'https://www.google.com/maps/search/?api=1&query=$query&query_place_id=${widget.venue.placeId}';
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
      comment: _commentController.text.trim().isEmpty
          ? null
          : _commentController.text.trim(),
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
        final userId =
        authService.isSignedIn ? authService.currentUserId : 'anonymous';
        if (!widget.venue.isPublic) {
          _venueRepository.saveVenue(updatedVenue, userId);
        }
        _venueRepository
            .saveVenueRating(
          userId: userId,
          placeId: updatedVenue.placeId,
          rating: updatedVenue.rating,
          comment: updatedVenue.comment,
        )
            .then((saveVerified) {
          if (saveVerified) {
            if (updatedVenue.genreTags.isNotEmpty ||
                updatedVenue.instrumentTags.isNotEmpty) {
              _venueRepository
                  .syncLocalTagsToFirebase(
                placeId: updatedVenue.placeId,
                userId: userId,
                genreTags: updatedVenue.genreTags,
                instrumentTags: updatedVenue.instrumentTags,
              )
                  .catchError(
                      (e) => log('❌ Error syncing tags to Firebase: $e'));
            }
            widget.onDataChanged?.call();
          }
        });
      } catch (e) {
        log('❌ Error during Firebase save: $e');
      }
    }

    if (popOnSave && mounted) Navigator.of(context).pop();
  }

  void _handleBook() {
    final demoProvider = Provider.of<DemoProvider>(context, listen: false);
    if (demoProvider.isDemoModeActive &&
        demoProvider.currentStep == DemoStep.mapBookGig) {
      demoProvider.nextStep();
    }
    _removeOverlay();
    widget.onBook(_buildUpdatedVenue());
  }

  // ── Shared info sub-widgets ───────────────────────────────────────────────

  Widget _buildAverageRating() {
    if (!widget.venue.isPublic || widget.venue.totalRatings < 3) {
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
        const Text('Average Rating:',
            style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        RatingBarIndicator(
          rating: widget.venue.averageRating,
          itemBuilder: (context, _) =>
          const Icon(Icons.star, color: Colors.amber),
          itemCount: 5,
          itemSize: 24,
          direction: Axis.horizontal,
        ),
        const SizedBox(height: 4),
        Text(
          '${widget.venue.averageRating.toStringAsFixed(1)} (${widget.venue.totalRatings} reviews)',
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _buildRecentComments() {
    if (!widget.venue.isPublic) return const SizedBox.shrink();
    if (_loadingComments) {
      return const Padding(
          padding: EdgeInsets.all(16.0),
          child: Center(child: CircularProgressIndicator()));
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

    final commentData = _recentComments[_currentCommentIndex];
    final comment = commentData['comment'] as String;
    final rating = commentData['rating'] as double;
    final timestamp = commentData['updatedAt'] as Timestamp?;

    String dateStr = 'Recently';
    if (timestamp != null) {
      final date = timestamp.toDate();
      final diff = DateTime.now().difference(date);
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

    final hasMultiple = _recentComments.length > 1;
    final canBack = _currentCommentIndex > 0;
    final canForward = _currentCommentIndex < _recentComments.length - 1;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Recent Comments:',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            if (hasMultiple)
              Text(
                '${_currentCommentIndex + 1} of ${_recentComments.length}',
                style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade600,
                    fontStyle: FontStyle.italic),
              ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            if (hasMultiple)
              IconButton(
                icon: Icon(Icons.arrow_back_ios,
                    color: canBack ? Colors.blue : Colors.grey.shade300),
                iconSize: 20,
                onPressed: canBack ? _previousComment : null,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              )
            else
              const SizedBox(width: 8),
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                    color: Colors.black,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey.shade300)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        RatingBarIndicator(
                          rating: rating,
                          itemBuilder: (context, _) =>
                          const Icon(Icons.star, color: Colors.amber),
                          itemCount: 5,
                          itemSize: 18,
                          direction: Axis.horizontal,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(dateStr,
                              textAlign: TextAlign.right,
                              style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey.shade400,
                                  fontStyle: FontStyle.italic),
                              overflow: TextOverflow.ellipsis),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(comment,
                        style: const TextStyle(
                            fontSize: 15, height: 1.4, color: Colors.white)),
                  ],
                ),
              ),
            ),
            if (hasMultiple)
              IconButton(
                icon: Icon(Icons.arrow_forward_ios,
                    color: canForward ? Colors.blue : Colors.grey.shade300),
                iconSize: 20,
                onPressed: canForward ? _nextComment : null,
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

  // ── Contact section ───────────────────────────────────────────────────────

  Widget _buildContactSection(ThemeData theme) {
    final contact = _localContact;
    final isShared = contact?.isSharedWithNetwork ?? false;
    final hasContact = contact != null && contact.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Section title (no edit control here) ──────────────────────────
        Row(
          children: [
            Text(
              'Booking & Contact Information',
              style: theme.textTheme.bodyMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            if (isShared) ...[
              const SizedBox(width: 6),
              Tooltip(
                message: 'Community-shared contact',
                child: Icon(Icons.people_alt_outlined,
                    size: 16, color: theme.colorScheme.primary),
              ),
            ],
          ],
        ),
        const SizedBox(height: 10),

        // ── Empty state — dotted placeholder, full tap ─────────────────────
        if (!hasContact)
          GestureDetector(
            onTap: _openContactDialog,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.25),
                  width: 1.5,
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.add_circle_outline,
                      size: 18,
                      color: theme.colorScheme.onSurface
                          .withValues(alpha: 0.4)),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      'Tap to add contact & booking info',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurface
                            .withValues(alpha: 0.5),
                        fontStyle: FontStyle.italic,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),

        // ── Populated state ────────────────────────────────────────────────
        if (hasContact) ...[
          Padding(
            padding: const EdgeInsets.only(left: 8.0, bottom: 4.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (contact!.name.isNotEmpty)
                  Text(contact.name,
                      style: const TextStyle(fontWeight: FontWeight.w500)),
                const SizedBox(height: 2),
                _buildContactReachLine(contact, theme),
              ],
            ),
          ),

          // ── Notes ──────────────────────────────────────────────────────
          if (contact.notes != null && contact.notes!.isNotEmpty)
            Padding(
              padding:
              const EdgeInsets.only(left: 8.0, bottom: 6.0, top: 2.0),
              child: Container(
                padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest
                      .withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: theme.dividerColor),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.notes_outlined,
                        size: 14,
                        color: theme.colorScheme.onSurface
                            .withValues(alpha: 0.5)),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        contact.notes!,
                        style: theme.textTheme.bodySmall?.copyWith(
                            fontStyle: FontStyle.italic,
                            color: theme.colorScheme.onSurface
                                .withValues(alpha: 0.8)),
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // ── Stale-data flag ─────────────────────────────────────────────
          if (contact.isStale && contact.lastConfirmed != null)
            Padding(
              padding:
              const EdgeInsets.only(left: 8.0, top: 4.0, bottom: 4.0),
              child: Row(
                children: [
                  Icon(Icons.access_time_outlined,
                      size: 14, color: Colors.orange.shade700),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      'Last confirmed ${DateFormat.yMMMd().format(contact.lastConfirmed!)} — still accurate?',
                      style: TextStyle(
                          fontSize: 12,
                          fontStyle: FontStyle.italic,
                          color: Colors.orange.shade700),
                    ),
                  ),
                ],
              ),
            )
          else if (contact.lastConfirmed != null && !contact.isStale)
            Padding(
              padding:
              const EdgeInsets.only(left: 8.0, top: 2.0, bottom: 4.0),
              child: Text(
                'Confirmed ${DateFormat.yMMMd().format(contact.lastConfirmed!)}',
                style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey.shade500,
                    fontStyle: FontStyle.italic),
              ),
            ),

          // ── Confirm chip ────────────────────────────────────────────────
          if (isShared && _isConnected)
            Padding(
              padding:
              const EdgeInsets.only(left: 8.0, top: 6.0, bottom: 2.0),
              child: _buildConfirmChip(theme),
            ),

          // ── Booking info chips ──────────────────────────────────────────
          if (isShared && _localBookingInfo != null)
            _buildBookingInfoDisplay(_localBookingInfo!, theme),

          // ── Edit link — bottom right ────────────────────────────────────
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: GestureDetector(
              onTap: _openContactDialog,
              child: Text(
                'Edit',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.primary,
                  decoration: TextDecoration.underline,
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }



  /// Shows the single most useful line for reaching the contact:
  /// phone (with text/call badge) when that's preferred or when no email exists,
  /// email when that's preferred or when no phone exists.
  Widget _buildContactReachLine(VenueContact contact, ThemeData theme) {
    final method = contact.preferredMethod; // "text" | "call" | "email" | null
    final hasPhone = contact.phone.isNotEmpty;
    final hasEmail = contact.email.isNotEmpty;

    // Decide which value to show
    final showPhone = method == 'text' ||
        method == 'call' ||
        (method == null && hasPhone) ||
        (method == 'email' && !hasEmail && hasPhone);
    final showEmail = !showPhone && hasEmail;

    if (!showPhone && !showEmail) return const SizedBox.shrink();

    if (showPhone) {
      String? badgeLabel;
      if (method == 'text') badgeLabel = 'Text';
      if (method == 'call') badgeLabel = 'Call';

      return Row(
        children: [
          Text(contact.phone),
          if (badgeLabel != null) _buildPreferredBadge(badgeLabel, theme),
        ],
      );
    }

    return Text(contact.email);
  }

  Widget _buildConfirmChip(ThemeData theme) {
    final confirmed = _userHasConfirmedContact;
    final count = _liveConfirmationCount;

    final bgColor = confirmed
        ? theme.colorScheme.primary.withValues(alpha: 0.85)
        : theme.colorScheme.surfaceContainerHighest;

    final fgColor =
    confirmed ? theme.colorScheme.onPrimary : theme.colorScheme.onSurface;

    final label = count > 0
        ? (confirmed ? 'You confirmed ($count)' : 'Still accurate? ($count)')
        : (confirmed ? 'You confirmed' : 'Still accurate?');

    return InputChip(
      avatar: _confirmationLoading
          ? SizedBox(
        width: 14,
        height: 14,
        child: CircularProgressIndicator(
            strokeWidth: 1.5, color: fgColor),
      )
          : Icon(
        confirmed ? Icons.check_circle : Icons.check_circle_outline,
        size: 16,
        color: fgColor,
      ),
      label: Text(label,
          style: TextStyle(
              color: fgColor, fontWeight: FontWeight.w600, fontSize: 13)),
      backgroundColor: bgColor,
      selectedColor: bgColor,
      selected: confirmed,
      checkmarkColor: Colors.transparent,
      onSelected: (_) => _toggleContactConfirmation(),
      padding: const EdgeInsets.symmetric(horizontal: 6),
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }

  Widget _buildPreferredBadge(String label, ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.only(left: 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: theme.colorScheme.primaryContainer,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 10,
                color: theme.colorScheme.onPrimaryContainer)),
      ),
    );
  }

  Widget _buildBookingInfoDisplay(BookingInfo info, ThemeData theme) {
    final monthsLabel = info.leadsOutMonths != null
        ? '${info.leadsOutMonths} ${info.leadsOutMonths == 1 ? 'month' : 'months'} out'
        : null;
    final dealLabel = switch (info.dealType) {
      'guarantee' => 'Guarantee',
      'door' => 'Door deal',
      'both' => 'Guarantee or door',
      _ => null,
    };

    String? windowLabel;
    final next = info.nextBookingWindowDate;
    if (next != null) {
      windowLabel = 'Books from ${DateFormat('MMM d').format(next)}';
    } else if (info.bookingWindowStart != null) {
      windowLabel =
      'Window: ${DateFormat('MMM d').format(info.bookingWindowStart!)}';
    }

    return Padding(
      padding: const EdgeInsets.only(left: 8.0, top: 8.0),
      child: Wrap(
        spacing: 8,
        runSpacing: 4,
        children: [
          if (monthsLabel != null)
            _buildInfoChip(Icons.calendar_today_outlined, monthsLabel, theme),
          if (windowLabel != null)
            _buildInfoChip(Icons.event_available_outlined, windowLabel, theme),
          if (dealLabel != null)
            _buildInfoChip(Icons.attach_money_outlined, dealLabel, theme),
        ],
      ),
    );
  }

  Widget _buildInfoChip(IconData icon, String label, ThemeData theme) {
    return Chip(
      avatar: Icon(icon,
          size: 14, color: theme.colorScheme.onSecondaryContainer),
      label: Text(label,
          style: TextStyle(
              fontSize: 12, color: theme.colorScheme.onSecondaryContainer)),
      backgroundColor: theme.colorScheme.secondaryContainer,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      visualDensity: VisualDensity.compact,
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
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
                borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(4),
                    topRight: Radius.circular(4)),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.archive, color: Colors.white, size: 18),
                  SizedBox(width: 8),
                  Text('ARCHIVED',
                      style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 14)),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
            child: Text(widget.venue.name,
                style: textTheme.headlineSmall,
                textAlign: TextAlign.center),
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
                    style: textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.primary,
                        decoration: TextDecoration.underline),
                  ),
                ),
              ),
            if (widget.nextGig != null)
              Column(
                key: _nextGigKey,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Next Gig:',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  Text(
                      '${DateFormat.yMMMEd().format(widget.nextGig!.dateTime)} at ${DateFormat.jm().format(widget.nextGig!.dateTime)}'),
                  const SizedBox(height: 16),
                ],
              ),

            // ── Shared information box ──────────────────────────────────
            Container(
              padding: const EdgeInsets.all(12.0),
              decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade400),
                  borderRadius: BorderRadius.circular(8.0)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Shared Information',
                      style: textTheme.titleMedium
                          ?.copyWith(color: theme.colorScheme.primary)),
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
                  const Text('Your Rating:',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Center(
                    child: RatingBar.builder(
                      initialRating: _currentRating,
                      minRating: 0,
                      direction: Axis.horizontal,
                      allowHalfRating: true,
                      itemCount: 5,
                      itemPadding:
                      const EdgeInsets.symmetric(horizontal: 4.0),
                      itemBuilder: (context, _) =>
                      const Icon(Icons.star, color: Colors.amber),
                      onRatingUpdate: (r) =>
                          setState(() => _currentRating = r),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text('Your Comments:',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _commentController,
                    decoration: const InputDecoration(
                        hintText: 'e.g., Great sound, load-in info...',
                        border: OutlineInputBorder()),
                    maxLines: 2,
                    textCapitalization: TextCapitalization.sentences,
                  ),
                  const SizedBox(height: 16),
                  const Text('Jam/Open Mic:',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  Text(widget.venue.jamOpenMicDisplayString(context)),
                  Center(
                    child: TextButton(
                        onPressed: widget.onEditJamSettings,
                        child:
                        const Text('Edit Jam/Open Mic Settings')),
                  ),
                  const Divider(height: 24),
                  _buildContactSection(theme),
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
                onChanged: (v) => setState(() => _isPrivateVenue = v),
                contentPadding: EdgeInsets.zero,
                dense: true,
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
                Text('RESTORE',
                    style: TextStyle(color: Colors.green)),
              ],
            )
                : Text('ARCHIVE',
                style: TextStyle(color: theme.colorScheme.error)),
          )
        else
          const SizedBox(),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            OutlinedButton(
              key: _saveCloseKey,
              onPressed: () => _handleSave(popOnSave: true),
              child: const Text('SAVE/CLOSE'),
            ),
            const SizedBox(width: 8),
            ElevatedButton(
              key: _bookButtonKey,
              onPressed: _handleBook,
              style: ElevatedButton.styleFrom(
                  backgroundColor: theme.colorScheme.primary,
                  foregroundColor: theme.colorScheme.onPrimary),
              child: const Text('BOOK'),
            ),
          ],
        ),
      ],
    );
  }
}