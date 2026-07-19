// lib/features/notes/views/notes_page.dart
//
// Three-tab layout for gig notes:
//   Tab 0 — Notes    : text notes, URL, retrospective ratings/tips
//   Tab 1 — Events   : ImpactEventsSection (Ticketmaster + holidays)
//   Tab 2 — Setlist  : embedded SetlistPage via nested Navigator
//
// Venue notes mode uses a single Notes tab (no Events, no Setlist).
// The Save/Cancel bar is only visible on the Notes tab.
// The Events tab label shows a live count badge when events are present.

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:the_money_gigs/features/gigs/models/gig_model.dart';
import 'package:the_money_gigs/features/gigs/models/gig_rating.dart';
import 'package:the_money_gigs/features/gigs/widgets/gig_retrospective_widget.dart';
import 'package:the_money_gigs/global_refresh_notifier.dart';
import 'package:the_money_gigs/features/map_venues/models/venue_model.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:convert';

import 'package:the_money_gigs/features/setlists/views/setlist_page.dart';
import 'package:the_money_gigs/features/gigs/widgets/impact_events_section.dart';
import 'package:the_money_gigs/features/gigs/models/impact_event.dart';
import 'package:the_money_gigs/core/utils/logger.dart';

class NotesPage extends StatefulWidget {
  final String? editingGigId;
  final String? editingVenueId;
  final bool scrollToImpact;
  final List<ImpactEvent> initialImpactEvents;

  const NotesPage({
    super.key,
    this.editingGigId,
    this.editingVenueId,
    this.scrollToImpact = false,
    this.initialImpactEvents = const [],
  }) : assert(editingGigId != null || editingVenueId != null,
  'Either editingGigId or editingVenueId must be provided.');

  @override
  State<NotesPage> createState() => _NotesPageState();
}

class _NotesPageState extends State<NotesPage>
    with SingleTickerProviderStateMixin {
  // ── Controllers ───────────────────────────────────────────────────────────
  late final TextEditingController _notesController;
  late final TextEditingController _urlController;
  late final TabController _tabController;

  // ── Gig state ─────────────────────────────────────────────────────────────
  Gig? _currentGig;
  String _displayName = '';
  String? _displaySubtext;
  String? _initialNotes;
  String? _initialUrl;

  // Venue-only
  List<Gig> _historicalGigsForVenue = [];
  int _taxDocYear = DateTime.now().year;
  String? _taxDocType;

  // ── UI state ──────────────────────────────────────────────────────────────
  bool _isLoading = true;
  String _errorMessage = '';
  bool _isEditingUrl = false;
  bool _isSaving = false;
  bool _hasChanges = false;

  // ── Retrospective state ───────────────────────────────────────────────────
  List<GigRating> _currentRatings = [];
  List<GigRating>? _initialRatings;
  double? _currentTipsAmount;
  double? _initialTipsAmount;

  bool get _isEditingGig => widget.editingGigId != null;
  bool get _canShowRetrospective =>
      _isEditingGig && _currentGig != null && _currentGig!.hasEnded;
  int get _tabCount => _isEditingGig ? 3 : 1;
  int get _eventsTabIndex => 1;

  // ── Init / dispose ────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _notesController = TextEditingController();
    _urlController = TextEditingController();
    _tabController = TabController(length: _tabCount, vsync: this);
    _loadDetails();

    // If caller asked to scroll to impact, jump to Events tab instead
    if (widget.scrollToImpact && _isEditingGig) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _tabController.animateTo(_eventsTabIndex);
      });
    }
  }

  @override
  void dispose() {
    _notesController.removeListener(_onTextChanged);
    _urlController.removeListener(_onTextChanged);
    _notesController.dispose();
    _urlController.dispose();
    _tabController.dispose();
    super.dispose();
  }

  // ── Data loading ──────────────────────────────────────────────────────────

  Future<void> _loadDetails() async {
    try {
      if (_isEditingGig) {
        await _loadGigDetails();
      } else {
        await _loadVenueDetails();
      }
      if (context.mounted) {
        setState(() {
          _notesController.text = _initialNotes ?? '';
          _urlController.text = _initialUrl ?? '';
          _isEditingUrl = _initialUrl == null || _initialUrl!.isEmpty;
          _isLoading = false;
          _notesController.addListener(_onTextChanged);
          _urlController.addListener(_onTextChanged);
        });
      }
    } catch (e) {
      if (context.mounted) {
        setState(() {
          _errorMessage = 'Error loading details: $e';
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _loadGigDetails() async {
    final prefs = await SharedPreferences.getInstance();
    final gigsJsonString = prefs.getString('gigs_list') ?? '[]';
    final List<Gig> allGigs = Gig.decode(gigsJsonString);

    final gigIndex = allGigs.indexWhere((g) => g.id == widget.editingGigId);

    if (gigIndex != -1) {
      final gig = allGigs[gigIndex];
      _currentGig = gig;
      _displayName = gig.venueName;
      _displaySubtext = DateFormat.yMMMEd().add_jm().format(gig.dateTime);
      _initialNotes = gig.notes;
      _initialUrl = gig.notesUrl;
      _initialRatings =
      gig.gigRatings != null ? List.from(gig.gigRatings!) : null;
      _currentRatings =
      gig.gigRatings != null ? List.from(gig.gigRatings!) : [];
      _initialTipsAmount = gig.tipsAmount;
      _currentTipsAmount = gig.tipsAmount;
    } else {
      // Materialization: reconstruct from recurring template
      String baseId = widget.editingGigId!;
      if (widget.editingGigId!.contains('_')) {
        final parts = widget.editingGigId!.split('_');
        baseId = parts.sublist(0, parts.length - 1).join('_');
      }

      final template = allGigs.firstWhere(
            (g) => g.id == baseId,
        orElse: () =>
        throw Exception('Template Gig not found for ID: $baseId'),
      );

      DateTime instanceDate = template.dateTime;
      if (widget.editingGigId!.contains('_')) {
        final datePart = widget.editingGigId!.split('_').last;
        if (datePart.length == 8) {
          try {
            final int year = int.parse(datePart.substring(0, 4));
            final int month = int.parse(datePart.substring(4, 6));
            final int day = int.parse(datePart.substring(6, 8));
            instanceDate = DateTime(
              year, month, day,
              template.dateTime.hour,
              template.dateTime.minute,
            );
          } catch (e) {
            log('Error parsing instance date: $e');
          }
        }
      }

      _currentGig = template.copyWith(
        id: widget.editingGigId,
        dateTime: instanceDate,
        isRecurring: false,
        isFromRecurring: true,
      );
      // ⚠️ copyWith() can't null a field — any param you omit falls back to
      // the template's existing value, never to null. If the template ever
      // carries retrospective data (see gigs.dart _openNotesPage bug), every
      // freshly-materialized occurrence would silently inherit it. Force a
      // clean slate explicitly since these fields are mutable, not final.
      _currentGig!.gigRatings = null;
      _currentGig!.tipsAmount = null;
      _currentGig!.retrospectiveCompleted = null;
      _displayName = template.venueName;
      _displaySubtext =
          DateFormat.yMMMEd().add_jm().format(instanceDate);
      _initialNotes = null;
      _initialUrl = null;
      _initialRatings = null;
      _currentRatings = [];
    }

    // Hydrate impact events — never persisted in gig JSON, passed by caller
    if (widget.initialImpactEvents.isNotEmpty) {
      _currentGig = _currentGig?.copyWith(
        impactEvents: widget.initialImpactEvents,
      );
    }
  }

  Future<void> _loadVenueDetails() async {
    final prefs = await SharedPreferences.getInstance();
    final venuesJson = prefs.getStringList('saved_locations') ?? [];
    final allVenues = venuesJson
        .map((v) => StoredLocation.fromJson(jsonDecode(v)))
        .toList();
    final venueIndex =
    allVenues.indexWhere((v) => v.placeId == widget.editingVenueId);

    if (venueIndex != -1) {
      final venue = allVenues[venueIndex];
      _displayName = venue.name;
      _displaySubtext = venue.address;
      _initialNotes = venue.venueNotes;
      _initialUrl = venue.venueNotesUrl;

      final gigsJsonString = prefs.getString('gigs_list') ?? '[]';
      final List<Gig> allGigs = Gig.decode(gigsJsonString);
      _historicalGigsForVenue = allGigs
          .where((gig) =>
      gig.placeId == widget.editingVenueId &&
          (gig.notes?.isNotEmpty ?? false))
          .toList()
        ..sort((a, b) => b.dateTime.compareTo(a.dateTime));

      await _loadTaxDoc();
    } else {
      throw Exception('Venue not found.');
    }
  }

  // ── Change tracking ───────────────────────────────────────────────────────

  void _onTextChanged() => _checkForChanges();

  void _onRatingsChanged(List<GigRating> ratings) {
    _currentRatings = ratings;
    _checkForChanges();
  }

  void _onTipsChanged(double? amount) {
    _currentTipsAmount = amount;
    _checkForChanges();
  }

  void _checkForChanges() {
    final hasChanges =
        _notesController.text.trim() != (_initialNotes ?? '') ||
            _urlController.text.trim() != (_initialUrl ?? '') ||
            _hasRatingsChanged() ||
            _currentTipsAmount != _initialTipsAmount;
    if (context.mounted && hasChanges != _hasChanges) {
      setState(() => _hasChanges = hasChanges);
    }
  }

  bool _hasRatingsChanged() {
    if (_initialRatings == null && _currentRatings.isEmpty) return false;
    if (_initialRatings == null && _currentRatings.isNotEmpty) return true;
    if (_initialRatings!.length != _currentRatings.length) return true;
    for (final r in _currentRatings) {
      final init = _initialRatings!
          .where((i) => i.dimension == r.dimension)
          .firstOrNull;
      if (init == null || init.rating != r.rating) return true;
    }
    for (final i in _initialRatings!) {
      if (_currentRatings
          .where((r) => r.dimension == i.dimension)
          .isEmpty) {
        return true;
      }
    }
    return false;
  }

  // ── Save ──────────────────────────────────────────────────────────────────

  Future<void> _saveNotesAndClose() async {
    if (!context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    setState(() => _isSaving = true);
    try {
      Gig? gigToReturn;
      if (_isEditingGig) {
        gigToReturn = await _saveGigNotes();
      } else {
        await _saveVenueNotes();
      }
      if (!mounted) return;
      messenger.showSnackBar(
        const SnackBar(
            content: Text('Notes saved successfully!'),
            backgroundColor: Colors.green),
      );
      navigator.pop(gigToReturn ?? _currentGig);
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
            content: Text('Error saving notes: $e'),
            backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<Gig?> _saveGigNotes() async {
    final prefs = await SharedPreferences.getInstance();
    final String gigsJsonString = prefs.getString('gigs_list') ?? '[]';
    List<Gig> currentGigs = Gig.decode(gigsJsonString);
    final gigIndex =
    currentGigs.indexWhere((g) => g.id == widget.editingGigId);
    final newNotes = _notesController.text.trim();
    final newUrl = _urlController.text.trim();
    final bool retrospectiveCompleted =
        _currentRatings.isNotEmpty || _currentTipsAmount != null;

    if (gigIndex == -1 &&
        newNotes.isEmpty &&
        newUrl.isEmpty &&
        _currentRatings.isEmpty &&
        _currentTipsAmount == null) {
      return _currentGig;
    }

    Gig updatedGig;
    if (gigIndex != -1) {
      updatedGig = currentGigs[gigIndex].copyWith(
        notes: newNotes.isEmpty ? null : newNotes,
        notesUrl: newUrl.isEmpty ? null : newUrl,
        gigRatings: _currentRatings.isEmpty ? null : _currentRatings,
        tipsAmount: _currentTipsAmount,
        retrospectiveCompleted: retrospectiveCompleted,
      );
      currentGigs[gigIndex] = updatedGig;
    } else {
      updatedGig = _currentGig!.copyWith(
        id: widget.editingGigId,
        notes: newNotes.isEmpty ? null : newNotes,
        notesUrl: newUrl.isEmpty ? null : newUrl,
        gigRatings: _currentRatings.isEmpty ? null : _currentRatings,
        tipsAmount: _currentTipsAmount,
        retrospectiveCompleted: retrospectiveCompleted,
        isRecurring: false,
        isFromRecurring: true,
      );
      currentGigs.add(updatedGig);
    }

    await prefs.setString('gigs_list', Gig.encode(currentGigs));
    globalRefreshNotifier.notify();
    return updatedGig;
  }

  Future<void> _saveVenueNotes() async {
    final prefs = await SharedPreferences.getInstance();
    final List<String> venuesJson =
        prefs.getStringList('saved_locations') ?? [];
    List<StoredLocation> currentVenues = venuesJson
        .map((v) => StoredLocation.fromJson(jsonDecode(v)))
        .toList();
    final venueIndex = currentVenues
        .indexWhere((v) => v.placeId == widget.editingVenueId);
    if (venueIndex != -1) {
      final newNotes = _notesController.text.trim();
      final newUrl = _urlController.text.trim();
      currentVenues[venueIndex] = currentVenues[venueIndex].copyWith(
        venueNotes: () => newNotes.isEmpty ? null : newNotes,
        venueNotesUrl: () => newUrl.isEmpty ? null : newUrl,
      );
      await prefs.setStringList(
        'saved_locations',
        currentVenues.map((v) => jsonEncode(v.toJson())).toList(),
      );
      globalRefreshNotifier.notify();
    } else {
      throw Exception('Could not find venue to update.');
    }
  }

  // ── Tax doc helpers ───────────────────────────────────────────────────────

  String _taxDocKey(int year) => 'tax_doc_${widget.editingVenueId}_$year';

  Future<void> _loadTaxDoc() async {
    if (widget.editingVenueId == null) return;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_taxDocKey(_taxDocYear));
    if (context.mounted) {
      setState(() {
        _taxDocType = raw != null
            ? (jsonDecode(raw) as Map<String, dynamic>)['type'] as String?
            : null;
      });
    }
  }

  Future<void> _saveTaxDoc(String? type) async {
    if (widget.editingVenueId == null) return;
    setState(() => _taxDocType = type);
    final prefs = await SharedPreferences.getInstance();
    final key = _taxDocKey(_taxDocYear);
    if (type == null) {
      await prefs.remove(key);
    } else {
      await prefs.setString(
          key, jsonEncode({'type': type, 'venueName': _displayName}));
    }
  }

  // ── URL launcher ──────────────────────────────────────────────────────────

  Future<void> _launchUrl() async {
    final urlString = _urlController.text.trim();
    if (urlString.isEmpty) return;
    final messenger = ScaffoldMessenger.of(context);
    final Uri? uri = Uri.tryParse(
        urlString.startsWith('http') ? urlString : 'https://$urlString');
    if (uri != null && await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else if (mounted) {
      messenger.showSnackBar(
        SnackBar(
            content: Text('Could not open link: $urlString'),
            backgroundColor: Colors.red),
      );
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  String _formatGigDate(DateTime? dt) {
    if (dt == null) return '';
    return DateFormat('EEE M/d h a').format(dt);
  }

  String _formatGigDuration(double? hours) {
    if (hours == null || hours <= 0) return '';
    if (hours == hours.truncate()) {
      return '(${hours.toInt()} hr${hours == 1 ? '' : 's'})';
    }
    // e.g. 2.5 → (2h 30m)
    final int h = hours.floor();
    final int m = ((hours - h) * 60).round();
    return h > 0 ? '(${h}h ${m}m)' : '(${m}m)';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Location — prominent
            if (!_isLoading && _displayName.isNotEmpty)
              Text(
                _displayName,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
            // Date + duration — second line, smaller
            if (!_isLoading && _currentGig != null)
              Text(
                '${_formatGigDate(_currentGig!.dateTime)} ${_formatGigDuration(_currentGig!.gigLengthHours)}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withValues(alpha: 0.65),
                ),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              )
            // Venue notes: show address as subtitle
            else if (!_isLoading && _displaySubtext != null && !_isEditingGig)
              Text(
                _displaySubtext!,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withValues(alpha: 0.65),
                ),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
          ],
        ),
        centerTitle: true,
        leading: BackButton(
          onPressed: () =>
              Navigator.of(context).pop(_hasChanges ? _currentGig : null),
        ),
        // Only show TabBar for gig mode
        bottom: _isEditingGig
            ? TabBar(
          controller: _tabController,
          tabs: [
            const Tab(text: 'Notes'),
            Tab(
              child: _buildEventsTabLabel(),
            ),
            const Tab(text: 'Setlist'),
          ],
        )
            : null,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage.isNotEmpty
          ? Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Text(_errorMessage,
              style: const TextStyle(color: Colors.red)),
        ),
      )
          : _isEditingGig
          ? _buildTabView()
          : _buildVenueBody(),
      bottomNavigationBar: _buildBottomBar(),
    );
  }

  // ── Events tab label with count badge ────────────────────────────────────

  Widget _buildEventsTabLabel() {
    final count = _currentGig?.impactEventCount ?? 0;
    if (count == 0) return const Text('Events');
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text('Events'),
        const SizedBox(width: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
          decoration: BoxDecoration(
            color: const Color(0xFFB8860B),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            '$count',
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
        ),
      ],
    );
  }

  // ── Tab view ──────────────────────────────────────────────────────────────

  Widget _buildTabView() {
    return TabBarView(
      controller: _tabController,
      children: [
        _buildNotesTab(),
        _buildEventsTab(),
        _buildSetlistTab(),
      ],
    );
  }

  // ── Tab 0: Notes ──────────────────────────────────────────────────────────

  Widget _buildNotesTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16.0, 16.0, 16.0, 120.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [

          // Retrospective (past gigs only)
          if (_canShowRetrospective) ...[
            const SizedBox(height: 20),
            GigRetrospectiveWidget(
              existingRatings: _currentGig?.gigRatings,
              venueName: _displayName,
              gig: _currentGig,
              onRatingsChanged: _onRatingsChanged,
              onTipsChanged: _onTipsChanged,
            ),
          ],

          // Notes text field
          const SizedBox(height: 20),
          TextField(
            controller: _notesController,
            autofocus: !_canShowRetrospective,
            maxLines: 8,
            minLines: 5,
            decoration: InputDecoration(
              labelText: 'Gig-Specific Notes',
              hintText: 'Load-in details, sound engineer name, etc.',
              border: const OutlineInputBorder(),
            ),
          ),

          // Related Link
          const SizedBox(height: 24),
          const Text('Related Link',
              style:
              TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const Divider(),
          if (_isEditingUrl)
            TextField(
              controller: _urlController,
              decoration: const InputDecoration(
                labelText: 'URL (Optional)',
                hintText: 'e.g., venue-tech-specs.pdf',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.url,
            )
          else
            Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: _launchUrl,
                    child: Text(
                      _urlController.text.isEmpty
                          ? '(No link)'
                          : _urlController.text,
                      style: TextStyle(
                        color: _urlController.text.isEmpty
                            ? Colors.grey
                            : Theme.of(context).colorScheme.primary,
                        decoration: _urlController.text.isEmpty
                            ? TextDecoration.none
                            : TextDecoration.underline,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.edit, size: 20),
                  onPressed: () => setState(() {
                    _isEditingUrl = true;
                    _onTextChanged();
                  }),
                  tooltip: 'Edit Link',
                ),
              ],
            ),
        ],
      ),
    );
  }

  // ── Tab 1: Events ─────────────────────────────────────────────────────────

  Widget _buildEventsTab() {
    final count = _currentGig?.impactEventCount ?? 0;

    if (count == 0) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.event_available,
                  size: 48,
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withValues(alpha: 0.3)),
              const SizedBox(height: 16),
              Text(
                'No nearby events found\nin the 5 days before this gig.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withValues(alpha: 0.5),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: ImpactEventsSection(gig: _currentGig!),
    );
  }

  // ── Tab 2: Setlist ────────────────────────────────────────────────────────
  //
  // SetlistPage is a full Scaffold widget. We embed it in a nested Navigator
  // so its internal back/close actions don't pop NotesPage.
  // When SetlistPage returns a Gig, we update _currentGig so setlistId
  // is preserved if the user then saves notes.

  Widget _buildSetlistTab() {
    if (_currentGig == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return Navigator(
      onGenerateRoute: (_) => MaterialPageRoute(
        builder: (ctx) => SetlistPage(
          gig: _currentGig!,
          isEmbedded: true,
        ),
      ),
    );
  }

  // ── Venue body (single scroll, no tabs) ───────────────────────────────────

  Widget _buildVenueBody() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16.0, 16.0, 16.0, 120.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [

          // Notes
          const SizedBox(height: 20),
          TextField(
            controller: _notesController,
            autofocus: true,
            maxLines: 8,
            minLines: 5,
            decoration: const InputDecoration(
              labelText: 'General Venue Notes',
              hintText: 'Gate codes, parking info, regular contact...',
              border: OutlineInputBorder(),
            ),
          ),

          // Related Link
          const SizedBox(height: 24),
          const Text('Related Link',
              style:
              TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const Divider(),
          if (_isEditingUrl)
            TextField(
              controller: _urlController,
              decoration: const InputDecoration(
                labelText: 'URL (Optional)',
                hintText: 'e.g., venue-tech-specs.pdf',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.url,
            )
          else
            Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: _launchUrl,
                    child: Text(
                      _urlController.text.isEmpty
                          ? '(No link)'
                          : _urlController.text,
                      style: TextStyle(
                        color: _urlController.text.isEmpty
                            ? Colors.grey
                            : Theme.of(context).colorScheme.primary,
                        decoration: _urlController.text.isEmpty
                            ? TextDecoration.none
                            : TextDecoration.underline,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.edit, size: 20),
                  onPressed: () => setState(() {
                    _isEditingUrl = true;
                    _onTextChanged();
                  }),
                  tooltip: 'Edit Link',
                ),
              ],
            ),

          // Tax Documents
          const SizedBox(height: 24),
          const Text('Tax Documents',
              style:
              TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const Divider(),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Tax Year'),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 28,
                    height: 28,
                    child: IconButton(
                      padding: EdgeInsets.zero,
                      iconSize: 18,
                      icon: const Icon(Icons.chevron_left),
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
                            ? Theme.of(context).colorScheme.primary
                            : null,
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 28,
                    height: 28,
                    child: IconButton(
                      padding: EdgeInsets.zero,
                      iconSize: 18,
                      icon: const Icon(Icons.chevron_right),
                      onPressed: _taxDocYear < DateTime.now().year
                          ? () {
                        setState(() => _taxDocYear++);
                        _loadTaxDoc();
                      }
                          : null,
                      color: _taxDocYear < DateTime.now().year
                          ? Theme.of(context).colorScheme.primary
                          : Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withValues(alpha: 0.25),
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'Did this venue send you a tax document for $_taxDocYear?',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context)
                  .colorScheme
                  .onSurface
                  .withValues(alpha: 0.7),
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

          // Historical gig notes
          if (_historicalGigsForVenue.isNotEmpty) ...[
            const SizedBox(height: 32),
            const Text('Past Gig Notes at this Venue',
                style: TextStyle(
                    fontWeight: FontWeight.bold, fontSize: 16)),
            const Divider(),
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _historicalGigsForVenue.length,
              itemBuilder: (context, index) {
                final gig = _historicalGigsForVenue[index];
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            DateFormat.yMMMEd().format(gig.dateTime),
                            style: const TextStyle(
                                fontWeight: FontWeight.bold),
                          ),
                          if (gig.averageRating != null) ...[
                            const SizedBox(width: 8),
                            const Icon(Icons.star,
                                size: 14, color: Colors.amber),
                            Text(
                              ' ${gig.averageRating!.toStringAsFixed(1)}',
                              style: TextStyle(
                                color: Colors.grey.shade600,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(gig.notes ?? 'No notes for this gig.'),
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

  // ── Bottom bar (Notes tab only, or venue mode) ────────────────────────────

  Widget? _buildBottomBar() {
    // Hide save bar when on Events or Setlist tab
    if (_isEditingGig) {
      return AnimatedBuilder(
        animation: _tabController,
        builder: (context, _) {
          if (_tabController.index != 0) return const SizedBox.shrink();
          return _saveBar();
        },
      );
    }
    return _saveBar();
  }

  Widget _saveBar() {
    return Container(
      padding: const EdgeInsets.all(12.0),
      color: Theme.of(context)
          .scaffoldBackgroundColor
          .withValues(alpha: 0.95),
      child: SafeArea(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(
              onPressed: _isSaving
                  ? null
                  : () => Navigator.of(context)
                  .pop(_hasChanges ? _currentGig : null),
              child: const Text('CANCEL'),
            ),
            const SizedBox(width: 12),
            ElevatedButton(
              onPressed:
              (_hasChanges && !_isSaving && !_isLoading)
                  ? _saveNotesAndClose
                  : null,
              style: ElevatedButton.styleFrom(
                backgroundColor:
                Theme.of(context).colorScheme.primary,
                foregroundColor:
                Theme.of(context).colorScheme.onPrimary,
                padding: const EdgeInsets.symmetric(
                    horizontal: 24.0, vertical: 12.0),
                textStyle: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.bold),
              ).copyWith(
                backgroundColor:
                WidgetStateProperty.resolveWith<Color?>(
                      (Set<WidgetState> states) {
                    if (states.contains(WidgetState.disabled)) {
                      return Colors.grey.shade700;
                    }
                    return Theme.of(context).colorScheme.primary;
                  },
                ),
              ),
              child: _isSaving
                  ? const SizedBox(
                height: 20,
                width: 20,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.white),
              )
                  : Text(_hasChanges ? 'SAVE CHANGES' : 'Notes Saved'),
            ),
          ],
        ),
      ),
    );
  }
}