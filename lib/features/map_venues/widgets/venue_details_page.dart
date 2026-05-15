// lib/features/map_venues/widgets/venue_detail_page.dart
//
// Step 2: General tab fully populated.
// Business tab (Step 3) and Booking tab (Step 4) still stubbed.

import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_rating_bar/flutter_rating_bar.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:the_money_gigs/core/services/auth_service.dart';
import 'package:the_money_gigs/core/utils/logger.dart';
import 'package:the_money_gigs/features/app_demo/providers/demo_provider.dart';
import 'package:the_money_gigs/features/gigs/models/gig_model.dart';
import 'package:the_money_gigs/features/map_venues/models/venue_contact.dart';
import 'package:the_money_gigs/features/map_venues/models/venue_model.dart';
import 'package:the_money_gigs/features/map_venues/repositories/venue_repository.dart';
import 'package:the_money_gigs/features/map_venues/widgets/venue_contact_dialog.dart';
import 'package:the_money_gigs/features/map_venues/widgets/venue_tags_widget.dart';

// ─────────────────────────────────────────────────────────────────────────────
// VenueDetailPage
// ─────────────────────────────────────────────────────────────────────────────

class VenueDetailPage extends StatefulWidget {
  final StoredLocation venue;
  final Gig? nextGig;
  final DemoStep? currentDemoStep;

  final VoidCallback onArchive;
  final Function(StoredLocation) onBook;
  final Function(StoredLocation) onSave;
  final Function(VenueContact contact, BookingInfo? bookingInfo)? onContactSaved;
  final VoidCallback onEditJamSettings;
  final VoidCallback? onDataChanged;
  final VoidCallback? onNavigateToProfile;

  const VenueDetailPage({
    super.key,
    required this.venue,
    this.nextGig,
    this.currentDemoStep,
    required this.onArchive,
    required this.onBook,
    required this.onSave,
    this.onContactSaved,
    required this.onEditJamSettings,
    this.onDataChanged,
    this.onNavigateToProfile,
  });

  @override
  State<VenueDetailPage> createState() => _VenueDetailPageState();
}

class _VenueDetailPageState extends State<VenueDetailPage>
    with SingleTickerProviderStateMixin {
  // ── Tab controller ────────────────────────────────────────────────────────
  late final TabController _tabController;

  // ── Shared state (survives tab switches) ──────────────────────────────────
  late double _currentRating;
  late final TextEditingController _commentController;
  late final TextEditingController _notesController;
  late final TextEditingController _urlController;
  late bool _isPrivateVenue;
  late List<String> _instrumentTags;
  late List<String> _genreTags;
  late List<String> _paymentMethodTags;
  late List<String> _taxArrangementTags;
  late BookingInfo _localBookingInfo;
  late VenueContact? _localContact;

  // ── Dirty tracking + booking tab key ─────────────────────────────────────
  bool _isDirty = false;
  final _bookingTabKey = GlobalKey<_BookingTabState>();

  // ── Connection ────────────────────────────────────────────────────────────
  bool _isConnected = false;
  static const String _isConnectedKey = 'is_connected_to_network';

  final VenueRepository _venueRepository = VenueRepository();

  // ─────────────────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _currentRating = widget.venue.rating;
    _commentController =
        TextEditingController(text: widget.venue.comment ?? '');
    _notesController =
        TextEditingController(text: widget.venue.venueNotes ?? '');
    _urlController =
        TextEditingController(text: widget.venue.venueNotesUrl ?? '');
    _isPrivateVenue = widget.venue.isPrivate;
    _instrumentTags = List.from(widget.venue.instrumentTags);
    _genreTags = List.from(widget.venue.genreTags);
    _paymentMethodTags = List.from(widget.venue.paymentMethodTags);
    _taxArrangementTags = List.from(widget.venue.taxArrangementTags);
    _localBookingInfo = widget.venue.bookingInfo ?? const BookingInfo();
    _localContact = widget.venue.contact;
    _initializePage();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _commentController.dispose();
    _notesController.dispose();
    _urlController.dispose();
    super.dispose();
  }

  // ── Init ──────────────────────────────────────────────────────────────────

  Future<void> _initializePage() async {
    await _checkConnectionStatus();
    if (mounted) _loadUserRating();
    // Dirty tracking for notes + URL fields
    _notesController.addListener(() => setState(() => _isDirty = true));
    _urlController.addListener(() => setState(() => _isDirty = true));
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

  // ── Venue helpers ─────────────────────────────────────────────────────────

  StoredLocation _buildUpdatedVenue() {
    return widget.venue.copyWith(
      rating: _currentRating,
      comment: _commentController.text.trim().isEmpty
          ? null
          : _commentController.text.trim(),
      isPrivate: _isPrivateVenue,
      instrumentTags: _instrumentTags,
      genreTags: _genreTags,
      paymentMethodTags: _paymentMethodTags,
      taxArrangementTags: _taxArrangementTags,
      bookingInfo: _localBookingInfo,
      venueNotes: () => _notesController.text.trim().isEmpty
          ? null : _notesController.text.trim(),
      venueNotesUrl: () => _urlController.text.trim().isEmpty
          ? null : _urlController.text.trim(),
    );
  }

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

  // ── Save / Book ───────────────────────────────────────────────────────────

  Future<void> _handleSave() async {
    // Also save contact/booking fields from the Booking tab
    await _bookingTabKey.currentState?.saveContact();

    final updatedVenue = _buildUpdatedVenue();
    widget.onSave(updatedVenue);

    if (_isConnected && !updatedVenue.isPrivate) {
      try {
        final authService = AuthService();
        final userId = authService.isSignedIn
            ? authService.currentUserId
            : 'anonymous';
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

    if (mounted) {
      setState(() => _isDirty = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Venue saved.'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  void _handleBook() {
    widget.onBook(_buildUpdatedVenue());
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      // ── AppBar ────────────────────────────────────────────────────────────
      appBar: AppBar(
        leading: const BackButton(),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.venue.name,
              style: theme.textTheme.titleMedium,
              overflow: TextOverflow.ellipsis,
            ),
            if (widget.venue.address.isNotEmpty)
              GestureDetector(
                onTap: _openInMaps,
                child: Text(
                  widget.venue.address,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.primary,
                    decoration: TextDecoration.underline,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
        ),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'General'),
            Tab(text: 'Business'),
            Tab(text: 'Booking'),
            Tab(text: 'Notes'),
          ],
        ),
      ),

      // ── Persistent bottom action bar ──────────────────────────────────────
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
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
                      style:
                      TextStyle(color: theme.colorScheme.error)),
                )
              else
                const SizedBox(),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    child: _isDirty
                        ? ElevatedButton(
                      key: const ValueKey('save-dirty'),
                      onPressed: _handleSave,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: theme.colorScheme.primary,
                        foregroundColor: theme.colorScheme.onPrimary,
                      ),
                      child: const Text('SAVE',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                    )
                        : OutlinedButton(
                      key: const ValueKey('save-clean'),
                      onPressed: _handleSave,
                      child: const Text('SAVE'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: _handleBook,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: theme.colorScheme.primary,
                      foregroundColor: theme.colorScheme.onPrimary,
                    ),
                    child: const Text('BOOK'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),

      // ── Tab content ───────────────────────────────────────────────────────
      body: TabBarView(
        controller: _tabController,
        children: [
          _GeneralTab(
            venue: widget.venue,
            nextGig: widget.nextGig,
            isConnected: _isConnected,
            currentRating: _currentRating,
            commentController: _commentController,
            instrumentTags: _instrumentTags,
            genreTags: _genreTags,
            isPrivateVenue: _isPrivateVenue,
            onRatingChanged: (r) => setState(() { _currentRating = r; _isDirty = true; }),
            onTagsChanged: (instruments, genres) => setState(() {
              _instrumentTags = instruments;
              _genreTags = genres;
              _isDirty = true;
            }),
            onPrivateChanged: (v) => setState(() { _isPrivateVenue = v; _isDirty = true; }),
            onEditJamSettings: widget.onEditJamSettings,
            onDirty: () => setState(() => _isDirty = true),
          ),
          _BusinessTab(
            venue: widget.venue,
            isConnected: _isConnected,
            localBookingInfo: _localBookingInfo,
            paymentMethodTags: _paymentMethodTags,
            taxArrangementTags: _taxArrangementTags,
            onDealTypesChanged: (types) =>
                setState(() { _localBookingInfo = _localBookingInfo.copyWith(dealTypes: types); _isDirty = true; }),
            onPaymentMethodTagsChanged: (tags) =>
                setState(() { _paymentMethodTags = tags; _isDirty = true; }),
            onTaxArrangementTagsChanged: (tags) =>
                setState(() { _taxArrangementTags = tags; _isDirty = true; }),
          ),
          _BookingTab(
            key: _bookingTabKey,
            venue: widget.venue,
            isConnected: _isConnected,
            localContact: _localContact,
            localBookingInfo: _localBookingInfo,
            onContactSaved: (contact, bookingInfo) {
              setState(() {
                _localContact = contact;
                _localBookingInfo = bookingInfo ?? _localBookingInfo;
              });
              widget.onContactSaved?.call(contact, bookingInfo);
            },
            onDirty: () => setState(() => _isDirty = true),
            onNavigateToProfile: widget.onNavigateToProfile,
          ),
          _NotesTab(
            venue: widget.venue,
            notesController: _notesController,
            urlController: _urlController,
            onDirty: () => setState(() => _isDirty = true),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// General Tab
// ─────────────────────────────────────────────────────────────────────────────

class _GeneralTab extends StatefulWidget {
  final StoredLocation venue;
  final Gig? nextGig;
  final bool isConnected;

  final double currentRating;
  final TextEditingController commentController;
  final List<String> instrumentTags;
  final List<String> genreTags;
  final bool isPrivateVenue;

  final ValueChanged<double> onRatingChanged;
  final Function(List<String> instruments, List<String> genres) onTagsChanged;
  final ValueChanged<bool> onPrivateChanged;
  final VoidCallback onEditJamSettings;
  final VoidCallback onDirty;

  const _GeneralTab({
    required this.venue,
    this.nextGig,
    required this.isConnected,
    required this.currentRating,
    required this.commentController,
    required this.instrumentTags,
    required this.genreTags,
    required this.isPrivateVenue,
    required this.onRatingChanged,
    required this.onTagsChanged,
    required this.onPrivateChanged,
    required this.onEditJamSettings,
    required this.onDirty,
  });

  @override
  State<_GeneralTab> createState() => _GeneralTabState();
}

class _GeneralTabState extends State<_GeneralTab>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  List<Map<String, dynamic>> _recentComments = [];
  bool _loadingComments = true;
  int _currentCommentIndex = 0;
  String? _currentUserId;

  final VenueRepository _venueRepository = VenueRepository();

  @override
  void initState() {
    super.initState();
    _loadRecentComments();
    _loadCurrentUserId();
    // Mark dirty when user types in the comment field
    widget.commentController.addListener(() => widget.onDirty());
  }

  @override
  void didUpdateWidget(_GeneralTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    // isConnected starts false and flips to true after async init.
    // initState already ran by then, so we reload comments here.
    if (!oldWidget.isConnected && widget.isConnected && _recentComments.isEmpty) {
      setState(() => _loadingComments = true);
      _loadRecentComments();
    }
  }

  Future<void> _loadCurrentUserId() async {
    try {
      final authService = AuthService();
      if (authService.isSignedIn) {
        setState(() => _currentUserId = authService.currentUserId);
      }
    } catch (_) {}
  }

  Future<void> _loadRecentComments() async {
    if (!widget.venue.isPublic || !widget.isConnected) {
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

  // ── Community widgets ─────────────────────────────────────────────────────

  Widget _buildAverageRating(ThemeData theme) {
    if (!widget.venue.isPublic || widget.venue.totalRatings < 3) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8.0),
        child: Text(
          'Not enough reviews for an average rating yet.',
          style: TextStyle(
              fontStyle: FontStyle.italic, color: Colors.grey.shade500),
          textAlign: TextAlign.center,
        ),
      );
    }
    return Column(
      children: [
        const Text('Community Average:',
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

  Widget _buildCommentsCarousel(ThemeData theme) {
    if (!widget.venue.isPublic) return const SizedBox.shrink();
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

    final commentData = _recentComments[_currentCommentIndex];
    final comment = commentData['comment'] as String;
    final rating = commentData['rating'] as double;
    final isYours = _currentUserId != null &&
        commentData['userId'] == _currentUserId;
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
                    border: Border.all(
                        color: isYours
                            ? theme.colorScheme.primary
                            : Colors.grey.shade300,
                        width: isYours ? 2 : 1)),
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
                        if (isYours)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.primary.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              'You',
                              style: TextStyle(
                                  fontSize: 11,
                                  color: theme.colorScheme.primary,
                                  fontWeight: FontWeight.bold),
                            ),
                          ),
                        const Spacer(),
                        Text(dateStr,
                            style: TextStyle(
                                fontSize: 11,
                                color: Colors.grey.shade400,
                                fontStyle: FontStyle.italic)),
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

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final theme = Theme.of(context);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Next Gig banner
          if (widget.nextGig != null) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                    color: theme.colorScheme.primary.withValues(alpha: 0.4)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Next Gig:',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  Text(
                    '${DateFormat.yMMMEd().format(widget.nextGig!.dateTime)} '
                        'at ${DateFormat.jm().format(widget.nextGig!.dateTime)}',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],

          // Your Rating (always visible, above community so it's the first action)
          Text('Your Rating',
              style: theme.textTheme.titleMedium
                  ?.copyWith(color: theme.colorScheme.primary)),
          const SizedBox(height: 12),
          Center(
            child: RatingBar.builder(
              initialRating: widget.currentRating,
              minRating: 0,
              direction: Axis.horizontal,
              allowHalfRating: true,
              itemCount: 5,
              itemPadding: const EdgeInsets.symmetric(horizontal: 4.0),
              itemBuilder: (context, _) =>
              const Icon(Icons.star, color: Colors.amber),
              onRatingUpdate: widget.onRatingChanged,
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: widget.commentController,
            decoration: const InputDecoration(
              labelText: 'Your Comment',
              hintText: 'e.g., Great sound, load-in info...',
              border: OutlineInputBorder(),
            ),
            maxLines: 3,
            textCapitalization: TextCapitalization.sentences,
          ),

          const Divider(height: 32),

          // Community section (connected + public venue)
          if (widget.isConnected && widget.venue.isPublic) ...[
            Text('Community',
                style: theme.textTheme.titleMedium
                    ?.copyWith(color: theme.colorScheme.primary)),
            const SizedBox(height: 12),
            _buildAverageRating(theme),
            _buildCommentsCarousel(theme),
            const Divider(height: 24),
            VenueTagsWidget(
              venue: widget.venue,
              isConnected: widget.isConnected,
              onTagsChanged: widget.onTagsChanged,
            ),
            const Divider(height: 32),
          ],

          // Jam / Open Mic
          Text('Jam / Open Mic',
              style: theme.textTheme.titleMedium
                  ?.copyWith(color: theme.colorScheme.primary)),
          const SizedBox(height: 8),
          Text(widget.venue.jamOpenMicDisplayString(context)),
          Center(
            child: TextButton(
              onPressed: widget.onEditJamSettings,
              child: const Text('Edit Jam/Open Mic Settings'),
            ),
          ),

          // Private venue toggle (standalone only)
          if (!widget.venue.isPublic) ...[
            const Divider(height: 24),
            SwitchListTile(
              title: const Text('Private Venue'),
              subtitle: const Text('Will not be shared in the cloud'),
              value: widget.isPrivateVenue,
              onChanged: widget.onPrivateChanged,
              contentPadding: EdgeInsets.zero,
              dense: true,
            ),
          ],

          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Business Tab — Step 3
// ─────────────────────────────────────────────────────────────────────────────

// ─────────────────────────────────────────────────────────────────────────────
// Business Tab
// ─────────────────────────────────────────────────────────────────────────────

class _BusinessTab extends StatefulWidget {
  final StoredLocation venue;
  final bool isConnected;
  final BookingInfo localBookingInfo;
  final List<String> paymentMethodTags;
  final List<String> taxArrangementTags;

  final ValueChanged<List<String>> onDealTypesChanged;
  final ValueChanged<List<String>> onPaymentMethodTagsChanged;
  final ValueChanged<List<String>> onTaxArrangementTagsChanged;

  const _BusinessTab({
    required this.venue,
    required this.isConnected,
    required this.localBookingInfo,
    required this.paymentMethodTags,
    required this.taxArrangementTags,
    required this.onDealTypesChanged,
    required this.onPaymentMethodTagsChanged,
    required this.onTaxArrangementTagsChanged,
  });

  @override
  State<_BusinessTab> createState() => _BusinessTabState();
}

class _BusinessTabState extends State<_BusinessTab>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final theme = Theme.of(context);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Deal Type ─────────────────────────────────────────────────────
          Text('Deal Type',
              style: theme.textTheme.titleMedium
                  ?.copyWith(color: theme.colorScheme.primary)),
          const SizedBox(height: 4),
          Text(
            'Select all that apply for this venue.',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            children: [
              _DealTypeChip(
                label: 'Guarantee',
                value: 'guarantee',
                selected: widget.localBookingInfo.dealTypes.contains('guarantee'),
                onTap: () {
                  final current = List<String>.from(widget.localBookingInfo.dealTypes);
                  if (current.contains('guarantee')) {
                    current.remove('guarantee');
                  } else {
                    current.add('guarantee');
                  }
                  widget.onDealTypesChanged(current);
                },
              ),
              _DealTypeChip(
                label: 'Door',
                value: 'door',
                selected: widget.localBookingInfo.dealTypes.contains('door'),
                onTap: () {
                  final current = List<String>.from(widget.localBookingInfo.dealTypes);
                  if (current.contains('door')) {
                    current.remove('door');
                  } else {
                    current.add('door');
                  }
                  widget.onDealTypesChanged(current);
                },
              ),
            ],
          ),

          const Divider(height: 32),

          // ── Standalone gate banner ─────────────────────────────────────────
          if (!widget.isConnected)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 20),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey.shade900,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey.shade700),
              ),
              child: Row(
                children: [
                  Icon(Icons.lock_outline, color: Colors.grey.shade400, size: 18),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Connect to access community data. Your entries stay private.',
                      style: TextStyle(color: Colors.grey.shade400, fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),

          // ── Payment Methods ───────────────────────────────────────────────
          _CategoryTagsSection(
            title: 'Payment Methods',
            tagCategory: 'paymentMethods',
            venue: widget.venue,
            isConnected: widget.isConnected,
            localTags: widget.paymentMethodTags,
            suggestions: const ['Cash', 'Check', 'Zelle', 'Venmo', 'PayPal'],
            onTagsChanged: widget.onPaymentMethodTagsChanged,
          ),

          const Divider(height: 32),

          // ── Tax Arrangement ───────────────────────────────────────────────
          _CategoryTagsSection(
            title: 'Tax Arrangement',
            tagCategory: 'taxArrangements',
            venue: widget.venue,
            isConnected: widget.isConnected,
            localTags: widget.taxArrangementTags,
            suggestions: const ['1099-NEC', 'W2'],
            onTagsChanged: widget.onTaxArrangementTagsChanged,
          ),

          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

// ── Deal Type chip ────────────────────────────────────────────────────────────

class _DealTypeChip extends StatelessWidget {
  final String label;
  final String value;
  final bool selected;
  final VoidCallback onTap;

  const _DealTypeChip({
    required this.label,
    required this.value,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        decoration: BoxDecoration(
          color: selected
              ? theme.colorScheme.primary.withValues(alpha: 0.85)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: selected
                ? theme.colorScheme.primary
                : Colors.grey.shade600,
            width: selected ? 2 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (selected) ...[
              const Icon(Icons.check, size: 16, color: Colors.white),
              const SizedBox(width: 6),
            ],
            Text(
              label,
              style: TextStyle(
                color: selected ? Colors.white : Colors.grey.shade300,
                fontWeight: selected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Reusable community tag section for Business tab ───────────────────────────

class _CategoryTagsSection extends StatefulWidget {
  final String title;
  final String tagCategory;
  final StoredLocation venue;
  final bool isConnected;
  final List<String> localTags;
  final List<String> suggestions;
  final ValueChanged<List<String>> onTagsChanged;

  const _CategoryTagsSection({
    required this.title,
    required this.tagCategory,
    required this.venue,
    required this.isConnected,
    required this.localTags,
    required this.suggestions,
    required this.onTagsChanged,
  });

  @override
  State<_CategoryTagsSection> createState() => _CategoryTagsSectionState();
}

class _CategoryTagsSectionState extends State<_CategoryTagsSection> {
  Map<String, Map<String, dynamic>> _firebaseTags = {};
  bool _isLoading = true;
  String? _currentUserId;
  final VenueRepository _venueRepository = VenueRepository();

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void didUpdateWidget(_CategoryTagsSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.isConnected && widget.isConnected) {
      _init();
    }
  }

  Future<void> _init() async {
    try {
      final authService = AuthService();
      if (authService.isSignedIn) {
        _currentUserId = authService.currentUserId;
      }
    } catch (_) {}

    if (widget.isConnected && _currentUserId != null) {
      await _loadFirebaseTags();
    } else {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadFirebaseTags() async {
    try {
      final tags = await _venueRepository.getVenueTagsByCategory(
        placeId: widget.venue.placeId,
        userId: _currentUserId!,
        tagCategory: widget.tagCategory,
      );
      if (mounted) setState(() { _firebaseTags = tags; _isLoading = false; });
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _toggleTag(String tag) async {
    final current = List<String>.from(widget.localTags);
    final isSelected = current.contains(tag);

    if (isSelected) {
      current.remove(tag);
    } else {
      current.add(tag);
    }
    widget.onTagsChanged(current);

    if (widget.isConnected && _currentUserId != null) {
      if (isSelected) {
        await _venueRepository.removeVoteForTagByCategory(
          placeId: widget.venue.placeId,
          userId: _currentUserId!,
          tagName: tag,
          tagCategory: widget.tagCategory,
        );
      } else {
        await _venueRepository.voteForTagByCategory(
          placeId: widget.venue.placeId,
          userId: _currentUserId!,
          tagName: tag,
          tagCategory: widget.tagCategory,
        );
      }
      await _loadFirebaseTags();
    }
  }

  Future<void> _showAddTagDialog() async {
    final TextEditingController controller = TextEditingController();
    final available = widget.suggestions
        .where((s) => !widget.localTags.contains(s))
        .toList();

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF3a3a3c),
        title: Text('Add ${widget.title}',
            style: const TextStyle(color: Colors.white)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: controller,
                autofocus: true,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  labelText: 'Custom entry',
                  labelStyle:
                  TextStyle(color: Colors.orangeAccent.shade100),
                  enabledBorder: OutlineInputBorder(
                      borderSide:
                      BorderSide(color: Colors.grey.shade600)),
                  focusedBorder: OutlineInputBorder(
                      borderSide: BorderSide(
                          color: Theme.of(context).colorScheme.primary)),
                ),
                onSubmitted: (value) {
                  if (value.trim().isNotEmpty) _toggleTag(value.trim());
                  Navigator.of(context).pop();
                },
              ),
              if (available.isNotEmpty) ...[
                const SizedBox(height: 16),
                Text('Suggestions',
                    style: TextStyle(
                        color: Colors.orangeAccent.shade100,
                        fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: available
                      .map((s) => ActionChip(
                    label: Text(s),
                    onPressed: () {
                      _toggleTag(s);
                      Navigator.of(context).pop();
                    },
                  ))
                      .toList(),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              if (controller.text.trim().isNotEmpty) {
                _toggleTag(controller.text.trim());
              }
              Navigator.of(context).pop();
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final allTags = <String>{
      ...widget.localTags,
      ...widget.suggestions,
      if (widget.isConnected) ..._firebaseTags.keys,
    }.toList();

    allTags.sort((a, b) {
      final aCount = _firebaseTags[a]?['count'] as int? ?? 0;
      final bCount = _firebaseTags[b]?['count'] as int? ?? 0;
      if (aCount != bCount) return bCount.compareTo(aCount);
      return a.compareTo(b);
    });

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(widget.title,
                style: theme.textTheme.titleMedium
                    ?.copyWith(color: theme.colorScheme.primary)),
            IconButton(
              icon: Icon(Icons.add_circle_outline,
                  color: Colors.orangeAccent.shade100),
              tooltip: 'Add custom',
              onPressed: _showAddTagDialog,
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (_isLoading)
          const Center(child: CircularProgressIndicator())
        else
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: allTags.map((tag) {
              final isSelected = widget.localTags.contains(tag);
              final voteCount =
                  _firebaseTags[tag]?['count'] as int? ?? 0;
              final showCount = widget.isConnected && voteCount > 0;

              return InputChip(
                label: Text(
                  showCount ? '$tag ($voteCount)' : tag,
                  style: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.bold),
                ),
                backgroundColor: isSelected
                    ? theme.colorScheme.primary.withValues(alpha: 0.8)
                    : Colors.orangeAccent.shade100.withValues(alpha: 0.6),
                selectedColor:
                theme.colorScheme.primary.withValues(alpha: 0.8),
                checkmarkColor: Colors.white,
                selected: isSelected,
                onSelected: (_) => _toggleTag(tag),
                onDeleted: isSelected ? () => _toggleTag(tag) : null,
                deleteIcon: isSelected
                    ? const Icon(Icons.cancel, size: 18)
                    : null,
                deleteIconColor: Colors.white70,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              );
            }).toList(),
          ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Booking Tab — Step 4
// ─────────────────────────────────────────────────────────────────────────────

// ─────────────────────────────────────────────────────────────────────────────
// Booking Tab
// ─────────────────────────────────────────────────────────────────────────────


// ─────────────────────────────────────────────────────────────────────────────
// Booking Tab  — profile-style inline edit, no dialog
// ─────────────────────────────────────────────────────────────────────────────

class _BookingTab extends StatefulWidget {
  final StoredLocation venue;
  final bool isConnected;
  final VenueContact? localContact;
  final BookingInfo localBookingInfo;
  final Function(VenueContact contact, BookingInfo? bookingInfo) onContactSaved;
  final VoidCallback onDirty;
  final VoidCallback? onNavigateToProfile;

  const _BookingTab({
    super.key,
    required this.venue,
    required this.isConnected,
    required this.localContact,
    required this.localBookingInfo,
    required this.onContactSaved,
    required this.onDirty,
    this.onNavigateToProfile,
  });

  @override
  State<_BookingTab> createState() => _BookingTabState();
}

class _BookingTabState extends State<_BookingTab>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  final _formKey = GlobalKey<FormState>();

  // ── Edit-mode flags (profile pattern) ─────────────────────────────────────
  bool _isEditingContact = false;
  bool _isEditingBooking = false;
  bool _isSaving = false;

  // ── Contact form state ─────────────────────────────────────────────────────
  late final TextEditingController _nameController;
  late final TextEditingController _phoneController;
  late final TextEditingController _emailController;
  late final TextEditingController _notesController;
  String? _preferredMethod;
  bool _isSharedWithNetwork = false;

  // ── Booking form state ─────────────────────────────────────────────────────
  late final TextEditingController _leadsOutController;
  DateTime? _bookingWindowStart;

  // ── Confirmation state ────────────────────────────────────────────────────
  bool _userHasConfirmedContact = false;
  bool _confirmationLoading = false;
  int _liveConfirmationCount = 0;

  final VenueRepository _venueRepository = VenueRepository();

  // ── Init / dispose ────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _initControllers();
    _liveConfirmationCount = widget.localContact?.confirmationCount ?? 0;
    _loadContactConfirmationState();
  }

  void _initControllers() {
    final c = widget.localContact;
    final hasContact = c != null && c.isNotEmpty;

    _nameController  = TextEditingController(text: c?.name ?? '');
    _phoneController = TextEditingController(text: c?.phone ?? '');
    _emailController = TextEditingController(text: c?.email ?? '');
    _notesController = TextEditingController(text: c?.notes ?? '');
    _preferredMethod = c?.preferredMethod;
    _isSharedWithNetwork = c?.isSharedWithNetwork ?? false;

    _leadsOutController = TextEditingController(
        text: widget.localBookingInfo.leadsOutMonths?.toString() ?? '');
    _bookingWindowStart = widget.localBookingInfo.bookingWindowStart;

    // Start in edit mode if no data yet — matches profile pattern
    _isEditingContact = !hasContact;
    _isEditingBooking = (widget.localBookingInfo.leadsOutMonths == null &&
        widget.localBookingInfo.bookingWindowStart == null);

    // Mark parent dirty when any field changes
    for (final c in [_nameController, _phoneController,
      _emailController, _notesController, _leadsOutController]) {
      c.addListener(() => widget.onDirty());
    }
  }

  @override
  void didUpdateWidget(_BookingTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.isConnected && widget.isConnected) {
      _loadContactConfirmationState();
    }
    // If parent pushed new contact data (e.g. Firebase sync), re-init
    if (oldWidget.localContact != widget.localContact) {
      _nameController.text  = widget.localContact?.name ?? '';
      _phoneController.text = widget.localContact?.phone ?? '';
      _emailController.text = widget.localContact?.email ?? '';
      _notesController.text = widget.localContact?.notes ?? '';
      setState(() {
        _preferredMethod     = widget.localContact?.preferredMethod;
        _isSharedWithNetwork = widget.localContact?.isSharedWithNetwork ?? false;
        _liveConfirmationCount = widget.localContact?.confirmationCount ?? 0;
        _userHasConfirmedContact = false;
      });
      _loadContactConfirmationState();
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _notesController.dispose();
    _leadsOutController.dispose();
    super.dispose();
  }

  // ── Confirmation ──────────────────────────────────────────────────────────

  Future<void> _loadContactConfirmationState() async {
    final c = widget.localContact;
    if (c == null || !c.isSharedWithNetwork || !widget.isConnected) return;
    try {
      final auth = AuthService();
      if (!auth.isSignedIn) return;
      final result = await _venueRepository.getContactConfirmationState(
          placeId: widget.venue.placeId, userId: auth.currentUserId);
      if (mounted) {
        setState(() {
          _userHasConfirmedContact = result['userConfirmed'] as bool? ?? false;
          _liveConfirmationCount   = result['count'] as int? ?? _liveConfirmationCount;
        });
      }
    } catch (e) {
      log('❌ Error loading confirmation: $e');
    }
  }

  Future<void> _toggleContactConfirmation() async {
    if (!widget.isConnected || _confirmationLoading) return;
    final auth = AuthService();
    if (!auth.isSignedIn) return;
    final wasConfirmed = _userHasConfirmedContact;
    setState(() {
      _confirmationLoading     = true;
      _userHasConfirmedContact = !wasConfirmed;
      _liveConfirmationCount  += wasConfirmed ? -1 : 1;
    });
    try {
      if (wasConfirmed) {
        await _venueRepository.removeContactConfirmation(
            placeId: widget.venue.placeId, userId: auth.currentUserId);
      } else {
        await _venueRepository.confirmVenueContact(
            placeId: widget.venue.placeId, userId: auth.currentUserId);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _userHasConfirmedContact = wasConfirmed;
          _liveConfirmationCount  += wasConfirmed ? 1 : -1;
        });
      }
    } finally {
      if (mounted) setState(() => _confirmationLoading = false);
    }
  }

  // ── Save ──────────────────────────────────────────────────────────────────

  Future<void> saveContact() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);

    final existing = widget.localContact;
    final auth = AuthService();
    final userId = auth.isSignedIn ? auth.currentUserId : null;

    final updatedContact = VenueContact(
      name:               _nameController.text.trim(),
      phone:              _phoneController.text.trim(),
      email:              _emailController.text.trim(),
      preferredMethod:    _preferredMethod,
      notes:              _notesController.text.trim().isEmpty
          ? null : _notesController.text.trim(),
      isSharedWithNetwork: _isSharedWithNetwork,
      sharedBy:           _isSharedWithNetwork
          ? (existing?.sharedBy ?? userId) : null,
      lastConfirmed:      existing?.lastConfirmed,
      lastConfirmedBy:    existing?.lastConfirmedBy,
      confirmationCount:  existing?.confirmationCount ?? 0,
    );

    final leadsOut = int.tryParse(_leadsOutController.text.trim());
    final updatedBookingInfo = BookingInfo(
      leadsOutMonths:    leadsOut,
      dealTypes:         widget.localBookingInfo.dealTypes,
      bookingWindowStart: _bookingWindowStart,
    );

    widget.onContactSaved(updatedContact, updatedBookingInfo);

    if (widget.isConnected && userId != null && _isSharedWithNetwork) {
      try {
        await _venueRepository.saveVenueContact(
          placeId:     widget.venue.placeId,
          userId:      userId,
          contact:     updatedContact,
          bookingInfo: updatedBookingInfo,
        );
      } catch (e) {
        log('❌ Error saving contact to Firebase: $e');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Saved locally. Cloud sync failed.'),
            backgroundColor: Colors.orange,
          ));
        }
      }
    }

    if (mounted) {
      setState(() {
        _isSaving           = false;
        _isEditingContact   = false;
        _isEditingBooking   = false;
      });
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  String _monthName(int month) {
    const names = ['', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return names[month];
  }

  Widget _sectionHeader(String title, ThemeData theme,
      {bool showPencil = false, VoidCallback? onEdit}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(title,
            style: theme.textTheme.titleMedium
                ?.copyWith(color: theme.colorScheme.primary)),
        if (showPencil)
          IconButton(
            icon: Icon(Icons.edit_outlined,
                size: 18, color: theme.colorScheme.primary),
            tooltip: 'Edit',
            onPressed: onEdit,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
      ],
    );
  }

  Widget _buildConfirmChip(ThemeData theme) {
    final confirmed = _userHasConfirmedContact;
    final count     = _liveConfirmationCount;
    final bgColor   = confirmed
        ? theme.colorScheme.primary.withValues(alpha: 0.85)
        : theme.colorScheme.surfaceContainerHighest;
    final fgColor   = confirmed
        ? theme.colorScheme.onPrimary
        : theme.colorScheme.onSurface;
    final label = count > 0
        ? (confirmed ? 'You confirmed ($count)' : 'Still accurate? ($count)')
        : (confirmed ? 'You confirmed' : 'Still accurate?');

    return InputChip(
      avatar: _confirmationLoading
          ? SizedBox(width: 14, height: 14,
          child: CircularProgressIndicator(strokeWidth: 1.5, color: fgColor))
          : Icon(confirmed ? Icons.check_circle : Icons.check_circle_outline,
          size: 16, color: fgColor),
      label: Text(label,
          style: TextStyle(color: fgColor,
              fontWeight: FontWeight.w600, fontSize: 13)),
      backgroundColor: bgColor,
      selectedColor:   bgColor,
      selected:        confirmed,
      checkmarkColor:  Colors.transparent,
      onSelected:      (_) => _toggleContactConfirmation(),
      padding: const EdgeInsets.symmetric(horizontal: 6),
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final theme    = Theme.of(context);
    final contact  = widget.localContact;
    final hasContact    = contact != null && contact.isNotEmpty;
    final isShared      = contact?.isSharedWithNetwork ?? false;
    final hasBookingData = widget.localBookingInfo.leadsOutMonths != null ||
        widget.localBookingInfo.bookingWindowStart != null;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [

            // ── Share with Network (TOP, prominent) ───────────────────────
            if (widget.isConnected)
              Container(
                decoration: BoxDecoration(
                  border: Border.all(
                    color: _isSharedWithNetwork
                        ? theme.colorScheme.primary
                        : theme.dividerColor,
                    width: _isSharedWithNetwork ? 1.5 : 1,
                  ),
                  borderRadius: BorderRadius.circular(10),
                  color: _isSharedWithNetwork
                      ? theme.colorScheme.primary.withValues(alpha: 0.08)
                      : Colors.transparent,
                ),
                child: SwitchListTile(
                  title: const Text('Share with Network',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text(
                    _isSharedWithNetwork
                        ? 'Contact & booking info visible to community members'
                        : 'Your contact info stays private',
                    style: TextStyle(
                        fontSize: 12,
                        color: theme.colorScheme.onSurface.withValues(alpha: 0.6)),
                  ),
                  value: _isSharedWithNetwork,
                  onChanged: (v) => setState(() => _isSharedWithNetwork = v),
                  contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                ),
              ),

            const SizedBox(height: 24),

            // ── Contact section ───────────────────────────────────────────
            _sectionHeader(
              'Booking Contact',
              theme,
              showPencil: hasContact && !_isEditingContact,
              onEdit: () => setState(() => _isEditingContact = true),
            ),
            const SizedBox(height: 12),

            // Display mode
            if (!_isEditingContact && hasContact) ...[
              Padding(
                padding: const EdgeInsets.only(left: 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (contact!.name.isNotEmpty)
                      Text(contact.name,
                          style: const TextStyle(
                              fontWeight: FontWeight.w500, fontSize: 15)),
                    if (contact.phone.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Row(children: [
                          const Icon(Icons.phone_outlined, size: 14),
                          const SizedBox(width: 6),
                          Text(contact.phone),
                          if (contact.preferredMethod == 'text' ||
                              contact.preferredMethod == 'call')
                            _preferredBadge(
                                contact.preferredMethod == 'text'
                                    ? 'Text' : 'Call', theme),
                        ]),
                      ),
                    if (contact.email.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Row(children: [
                          const Icon(Icons.email_outlined, size: 14),
                          const SizedBox(width: 6),
                          Text(contact.email),
                          if (contact.preferredMethod == 'email')
                            _preferredBadge('Email', theme),
                        ]),
                      ),
                    if (contact.notes != null &&
                        contact.notes!.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 8),
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
                                child: Text(contact.notes!,
                                    style: theme.textTheme.bodySmall?.copyWith(
                                        fontStyle: FontStyle.italic)),
                              ),
                            ],
                          ),
                        ),
                      ),
                    // Stale flag
                    if (contact.isStale && contact.lastConfirmed != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Row(children: [
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
                        ]),
                      )
                    else if (contact.lastConfirmed != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          'Confirmed ${DateFormat.yMMMd().format(contact.lastConfirmed!)}',
                          style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey.shade500,
                              fontStyle: FontStyle.italic),
                        ),
                      ),
                    // Confirm chip
                    if (isShared && widget.isConnected)
                      Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: _buildConfirmChip(theme),
                      ),
                  ],
                ),
              ),
            ],

            // Edit mode
            if (_isEditingContact) ...[
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'Contact Name',
                  icon: Icon(Icons.person_outline),
                ),
                textCapitalization: TextCapitalization.words,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _phoneController,
                decoration: const InputDecoration(
                  labelText: 'Phone Number',
                  icon: Icon(Icons.phone_outlined),
                ),
                keyboardType: TextInputType.phone,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _emailController,
                decoration: const InputDecoration(
                  labelText: 'Email Address',
                  icon: Icon(Icons.email_outlined),
                ),
                keyboardType: TextInputType.emailAddress,
                validator: (value) {
                  if (value == null || value.isEmpty) return null;
                  if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$')
                      .hasMatch(value)) {
                    return 'Enter a valid email address';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 20),
              // Preferred method chips
              Text('Preferred Contact',
                  style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.6))),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  ('text',  'Text',  Icons.sms_outlined),
                  ('call',  'Call',  Icons.phone_outlined),
                  ('email', 'Email', Icons.email_outlined),
                ].map((rec) {
                  final isSelected = _preferredMethod == rec.$1;
                  return ChoiceChip(
                    avatar: Icon(rec.$3, size: 16,
                        color: isSelected
                            ? theme.colorScheme.onPrimary
                            : theme.colorScheme.onSurface),
                    label: Text(rec.$2),
                    selected: isSelected,
                    selectedColor: theme.colorScheme.primary,
                    labelStyle: TextStyle(
                        color: isSelected
                            ? theme.colorScheme.onPrimary
                            : theme.colorScheme.onSurface),
                    onSelected: (_) => setState(() =>
                    _preferredMethod = isSelected ? null : rec.$1),
                  );
                }).toList(),
              ),
              const SizedBox(height: 20),
              TextFormField(
                controller: _notesController,
                decoration: const InputDecoration(
                  labelText: 'Notes',
                  hintText: 'e.g., "Daisy took over from Ed in March. Text first."',
                  icon: Icon(Icons.notes_outlined),
                  alignLabelWithHint: true,
                  border: OutlineInputBorder(),
                  helperText: 'Booking quirks, handoffs, anything useful',
                ),
                maxLines: 3,
                textCapitalization: TextCapitalization.sentences,
              ),
            ],

            const Divider(height: 32),

            // ── Booking Details section ───────────────────────────────────
            _sectionHeader(
              'Booking Details',
              theme,
              showPencil: widget.isConnected && hasBookingData && !_isEditingBooking,
              onEdit: () => setState(() => _isEditingBooking = true),
            ),
            const SizedBox(height: 12),

            if (!widget.isConnected) ...[
              // ── Gate: not connected ───────────────────────────────────────
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: theme.dividerColor),
                  color: theme.colorScheme.surfaceContainerHighest
                      .withValues(alpha: 0.3),
                ),
                child: Column(
                  children: [
                    Icon(Icons.lock_outline,
                        size: 32,
                        color: theme.colorScheme.onSurface.withValues(alpha: 0.4)),
                    const SizedBox(height: 12),
                    Text(
                      'Connect to the Community to see important booking details.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                      ),
                    ),
                    if (widget.onNavigateToProfile != null) ...[
                      const SizedBox(height: 16),
                      TextButton(
                        onPressed: widget.onNavigateToProfile,
                        child: const Text('Go to Profile to connect →'),
                      ),
                    ],
                  ],
                ),
              ),
            ] else ...[
              // Display mode
              if (!_isEditingBooking && hasBookingData)
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    if (widget.localBookingInfo.leadsOutMonths != null)
                      _infoChip(
                          Icons.calendar_today_outlined,
                          '${widget.localBookingInfo.leadsOutMonths} '
                              '${widget.localBookingInfo.leadsOutMonths == 1 ? 'month' : 'months'} out',
                          theme),
                    if (_bookingWindowStart != null)
                      _infoChip(
                          Icons.event_available_outlined,
                          'Window opens ${_monthName(_bookingWindowStart!.month)} '
                              '${_bookingWindowStart!.day}',
                          theme),
                  ],
                ),

              // Edit mode
              if (_isEditingBooking) ...[
                TextFormField(
                  controller: _leadsOutController,
                  decoration: const InputDecoration(
                    labelText: 'Leads out (months)',
                    hintText: 'e.g., 3',
                    icon: Icon(Icons.calendar_today_outlined),
                    helperText: 'How far in advance this venue books',
                  ),
                  keyboardType: TextInputType.number,
                  validator: (value) {
                    if (value == null || value.isEmpty) return null;
                    final n = int.tryParse(value);
                    if (n == null || n < 1 || n > 24) {
                      return 'Enter a number between 1 and 24';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 20),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.event_available_outlined),
                  title: Text(
                    _bookingWindowStart != null
                        ? 'Window opens: ${_monthName(_bookingWindowStart!.month)} '
                        '${_bookingWindowStart!.day}'
                        : 'Set booking window date',
                  ),
                  subtitle: const Text(
                      'Month/day the venue opens their calendar each year'),
                  trailing: TextButton(
                    onPressed: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: _bookingWindowStart ?? DateTime.now(),
                        firstDate: DateTime(2000, 1, 1),
                        lastDate: DateTime(2000, 12, 31),
                        helpText: 'Select booking window open date',
                      );
                      if (picked != null) {
                        setState(() => _bookingWindowStart = picked);
                      }
                    },
                    child: const Text('PICK DATE'),
                  ),
                ),
                if (_bookingWindowStart != null)
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: () =>
                          setState(() => _bookingWindowStart = null),
                      child: Text('Clear date',
                          style: TextStyle(color: theme.colorScheme.error)),
                    ),
                  ),
              ],
            ],

            // ── Save Contact button removed — use the SAVE button in the bottom bar ──

            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  // ── Small helper widgets ───────────────────────────────────────────────────

  Widget _preferredBadge(String label, ThemeData theme) {
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

  Widget _infoChip(IconData icon, String label, ThemeData theme) {
    return Chip(
      avatar: Icon(icon, size: 14,
          color: theme.colorScheme.onSecondaryContainer),
      label: Text(label,
          style: TextStyle(fontSize: 12,
              color: theme.colorScheme.onSecondaryContainer)),
      backgroundColor: theme.colorScheme.secondaryContainer,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      visualDensity: VisualDensity.compact,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Notes Tab
// ─────────────────────────────────────────────────────────────────────────────

class _NotesTab extends StatefulWidget {
  final StoredLocation venue;
  final TextEditingController notesController;
  final TextEditingController urlController;
  final VoidCallback onDirty;

  const _NotesTab({
    required this.venue,
    required this.notesController,
    required this.urlController,
    required this.onDirty,
  });

  @override
  State<_NotesTab> createState() => _NotesTabState();
}

class _NotesTabState extends State<_NotesTab>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  // ── URL editing ───────────────────────────────────────────────────────────
  bool _isEditingUrl = false;

  // ── Historical gig notes ──────────────────────────────────────────────────
  List<Gig> _historicalGigs = [];
  bool _loadingHistory = true;

  // ── Tax document state ────────────────────────────────────────────────────
  int _taxDocYear = DateTime.now().year;
  String? _taxDocType;

  // ─────────────────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _isEditingUrl = widget.urlController.text.isEmpty;
    _loadHistoricalGigs();
    _loadTaxDoc();
  }

  // ── Historical gigs ───────────────────────────────────────────────────────

  Future<void> _loadHistoricalGigs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final gigsJson = prefs.getString('gigs_list') ?? '[]';
      final all = Gig.decode(gigsJson);
      final filtered = all
          .where((g) =>
      g.placeId == widget.venue.placeId &&
          (g.notes?.isNotEmpty ?? false))
          .toList()
        ..sort((a, b) => b.dateTime.compareTo(a.dateTime));
      if (mounted) setState(() { _historicalGigs = filtered; _loadingHistory = false; });
    } catch (_) {
      if (mounted) setState(() => _loadingHistory = false);
    }
  }

  // ── Tax document helpers ──────────────────────────────────────────────────

  String _taxDocKey(int year) => 'tax_doc_${widget.venue.placeId}_$year';

  Future<void> _loadTaxDoc() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_taxDocKey(_taxDocYear));
    if (mounted) {
      setState(() {
        if (raw != null) {
          final data = jsonDecode(raw) as Map<String, dynamic>;
          _taxDocType = data['type'] as String?;
        } else {
          _taxDocType = null;
        }
      });
    }
  }

  Future<void> _saveTaxDoc(String? type) async {
    setState(() => _taxDocType = type);
    final prefs = await SharedPreferences.getInstance();
    final key = _taxDocKey(_taxDocYear);
    if (type == null) {
      await prefs.remove(key);
    } else {
      await prefs.setString(
        key,
        jsonEncode({'type': type, 'venueName': widget.venue.name}),
      );
    }
  }

  // ── URL launch ────────────────────────────────────────────────────────────

  Future<void> _launchUrl() async {
    final raw = widget.urlController.text.trim();
    if (raw.isEmpty) return;
    final uri = Uri.tryParse(raw.startsWith('http') ? raw : 'https://$raw');
    if (uri != null && await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not open: $raw'),
            backgroundColor: Colors.red),
      );
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final theme = Theme.of(context);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [

          // ── Venue Notes field ─────────────────────────────────────────────
          Text('Venue Notes',
              style: theme.textTheme.titleMedium
                  ?.copyWith(color: theme.colorScheme.primary)),
          const SizedBox(height: 12),
          TextField(
            controller: widget.notesController,
            maxLines: 6,
            minLines: 4,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              hintText: 'Gate codes, parking, sound engineer, load-in quirks…',
              border: OutlineInputBorder(),
            ),
          ),

          const Divider(height: 32),

          // ── Related Link ──────────────────────────────────────────────────
          Text('Related Link',
              style: theme.textTheme.titleMedium
                  ?.copyWith(color: theme.colorScheme.primary)),
          const SizedBox(height: 12),
          if (_isEditingUrl)
            TextField(
              controller: widget.urlController,
              decoration: const InputDecoration(
                labelText: 'URL (Optional)',
                hintText: 'e.g., venue-tech-specs.pdf or http://…',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.url,
            )
          else
            Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: _launchUrl,
                    child: Text(
                      widget.urlController.text.isEmpty
                          ? '(No link)'
                          : widget.urlController.text,
                      style: TextStyle(
                        color: widget.urlController.text.isEmpty
                            ? Colors.grey
                            : theme.colorScheme.primary,
                        decoration: widget.urlController.text.isEmpty
                            ? TextDecoration.none
                            : TextDecoration.underline,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.edit, size: 20),
                  onPressed: () => setState(() { _isEditingUrl = true; widget.onDirty(); }),
                  tooltip: 'Edit link',
                ),
              ],
            ),

          const Divider(height: 32),

          // ── Tax Documents ─────────────────────────────────────────────────
          Text('Tax Documents',
              style: theme.textTheme.titleMedium
                  ?.copyWith(color: theme.colorScheme.primary)),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Tax Year'),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(width: 28, height: 28,
                    child: IconButton(
                      padding: EdgeInsets.zero,
                      iconSize: 18,
                      icon: const Icon(Icons.chevron_left),
                      color: theme.colorScheme.primary,
                      onPressed: () {
                        setState(() => _taxDocYear--);
                        _loadTaxDoc();
                      },
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Text(
                      '$_taxDocYear',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: _taxDocYear == DateTime.now().year
                            ? theme.colorScheme.primary
                            : null,
                      ),
                    ),
                  ),
                  SizedBox(width: 28, height: 28,
                    child: IconButton(
                      padding: EdgeInsets.zero,
                      iconSize: 18,
                      icon: const Icon(Icons.chevron_right),
                      onPressed: _taxDocYear < DateTime.now().year
                          ? () { setState(() => _taxDocYear++); _loadTaxDoc(); }
                          : null,
                      color: _taxDocYear < DateTime.now().year
                          ? theme.colorScheme.primary
                          : theme.colorScheme.onSurface.withValues(alpha: 0.25),
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Did this venue send you a tax document for $_taxDocYear?',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            children: [
              for (final entry in [
                ('None', null),
                ('1099-NEC', '1099-NEC'),
                ('W2', 'W2'),
              ])
                ChoiceChip(
                  label: Text(entry.$1),
                  selected: _taxDocType == entry.$2,
                  onSelected: (_) => _saveTaxDoc(entry.$2),
                ),
            ],
          ),

          // ── Historical Gig Notes ──────────────────────────────────────────
          if (!_loadingHistory && _historicalGigs.isNotEmpty) ...[
            const Divider(height: 32),
            Text('Past Gig Notes at this Venue',
                style: theme.textTheme.titleMedium
                    ?.copyWith(color: theme.colorScheme.primary)),
            const SizedBox(height: 12),
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _historicalGigs.length,
              itemBuilder: (context, index) {
                final gig = _historicalGigs[index];
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Text(
                          DateFormat.yMMMEd().format(gig.dateTime),
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        if (gig.averageRating != null) ...[
                          const SizedBox(width: 8),
                          const Icon(Icons.star, size: 14, color: Colors.amber),
                          Text(
                            ' ${gig.averageRating!.toStringAsFixed(1)}',
                            style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                          ),
                        ],
                      ]),
                      const SizedBox(height: 4),
                      Text(gig.notes ?? ''),
                    ],
                  ),
                );
              },
            ),
          ],

        ],
      ),
    );
  }
}