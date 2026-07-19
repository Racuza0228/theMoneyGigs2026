// lib/features/gigs/widgets/gig_retrospective_widget.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_rating_bar/flutter_rating_bar.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:the_money_gigs/features/gigs/models/gig_rating.dart';
import 'package:the_money_gigs/features/gigs/models/gig_model.dart';
import 'package:share_plus/share_plus.dart';

class GigRetrospectiveWidget extends StatefulWidget {
  /// Existing star ratings to pre-populate (if editing a previously rated gig)
  final List<GigRating>? existingRatings;

  /// Callback fired whenever star ratings change
  final Function(List<GigRating>) onRatingsChanged;

  /// Callback fired whenever the tips dollar amount changes.
  /// null = field cleared, 0.0 = explicitly "no tips", >0 = amount entered.
  final Function(double?)? onTipsChanged;

  /// Optional: venue name for context in the header
  final String? venueName;

  /// Optional: the gig being reviewed (needed for export and tips pre-fill)
  final Gig? gig;

  const GigRetrospectiveWidget({
    super.key,
    this.existingRatings,
    required this.onRatingsChanged,
    this.onTipsChanged,
    this.venueName,
    this.gig,
  });

  @override
  State<GigRetrospectiveWidget> createState() => _GigRetrospectiveWidgetState();
}

class _GigRetrospectiveWidgetState extends State<GigRetrospectiveWidget> {
  static const String _keyActiveDimensions = 'retrospective_active_dimensions';

  final Map<String, double?> _ratings = {};
  List<String> _allDimensions = [];

  // Tips dollar amount — separate from star ratings
  final TextEditingController _tipsController = TextEditingController();
  double? _tipsAmount;

  bool _isLoading = true;
  bool _isExpanded = true;

  @override
  void initState() {
    super.initState();
    _loadDimensions();
  }

  @override
  void dispose() {
    _tipsController.dispose();
    super.dispose();
  }

  Future<void> _loadDimensions() async {
    final prefs = await SharedPreferences.getInstance();
    final savedDimensions = prefs.getStringList(_keyActiveDimensions);

    if (savedDimensions != null && savedDimensions.isNotEmpty) {
      // Silently filter out 'Tips' (and any other reserved fields) from old
      // saved lists so existing users don't see a duplicate tips entry.
      _allDimensions = savedDimensions
          .where((d) => !DefaultGigDimensions.reservedAsFields.contains(d))
          .toList();
    } else {
      _allDimensions = List.from(DefaultGigDimensions.all);
      await _saveDimensions();
    }

    // Pre-populate star ratings from existing data
    if (widget.existingRatings != null) {
      for (final rating in widget.existingRatings!) {
        // Skip any legacy 'Tips' star rating — it's now a dollar field
        if (DefaultGigDimensions.reservedAsFields.contains(rating.dimension)) {
          continue;
        }
        _ratings[rating.dimension] = rating.rating;
        if (!_allDimensions.contains(rating.dimension)) {
          _allDimensions.add(rating.dimension);
        }
      }
    }

    // Pre-populate tips from gig model
    if (widget.gig?.tipsAmount != null) {
      _tipsAmount = widget.gig!.tipsAmount;
      _tipsController.text = widget.gig!.tipsAmount!.toStringAsFixed(2);
    }

    if (context.mounted) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _saveDimensions() async {
    final prefs = await SharedPreferences.getInstance();
    // Persist without reserved fields so the migration sticks
    await prefs.setStringList(
      _keyActiveDimensions,
      _allDimensions
          .where((d) => !DefaultGigDimensions.reservedAsFields.contains(d))
          .toList(),
    );
  }

  void _updateRating(String dimension, double rating) {
    setState(() => _ratings[dimension] = rating);
    _notifyRatingsChanged();
  }

  void _clearRating(String dimension) {
    setState(() => _ratings.remove(dimension));
    _notifyRatingsChanged();
  }

  void _notifyRatingsChanged() {
    final List<GigRating> ratings = [];
    for (final entry in _ratings.entries) {
      if (entry.value != null) {
        ratings.add(GigRating(
          dimension: entry.key,
          rating: entry.value!,
          category: DefaultGigDimensions.getCategoryFor(entry.key),
        ));
      }
    }
    widget.onRatingsChanged(ratings);
  }

  void _onTipsChanged(String value) {
    final parsed = double.tryParse(value);
    setState(() => _tipsAmount = parsed);
    widget.onTipsChanged?.call(parsed);
  }

  Future<void> _showAddDimensionDialog() async {
    final TextEditingController controller = TextEditingController();

    final result = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF2c2c2e),
          title: const Text(
            'Add Custom Dimension',
            style: TextStyle(color: Colors.white),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'What else do you want to track?',
                style: TextStyle(color: Colors.grey.shade400),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                autofocus: true,
                style: const TextStyle(color: Colors.white),
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(
                  hintText: 'e.g., Weather, Parking, Sound Check',
                  hintStyle: TextStyle(color: Colors.grey.shade600),
                  enabledBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: Colors.grey.shade600),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderSide: BorderSide(
                        color: Theme.of(context).colorScheme.primary),
                  ),
                ),
                onSubmitted: (value) {
                  if (value.trim().isNotEmpty) {
                    Navigator.of(context).pop(value.trim());
                  }
                },
              ),
              const SizedBox(height: 16),
              Text(
                'This dimension will be available for all future gigs.',
                style: TextStyle(
                  color: Colors.grey.shade500,
                  fontSize: 12,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              child: const Text('Cancel'),
              onPressed: () => Navigator.of(context).pop(),
            ),
            ElevatedButton(
              child: const Text('Add'),
              onPressed: () {
                if (controller.text.trim().isNotEmpty) {
                  Navigator.of(context).pop(controller.text.trim());
                }
              },
            ),
          ],
        );
      },
    );

    if (result != null &&
        result.isNotEmpty &&
        !_allDimensions.contains(result) &&
        !DefaultGigDimensions.reservedAsFields.contains(result)) {
      setState(() => _allDimensions.add(result));
      await _saveDimensions();
    }
  }

  Future<void> _confirmRemoveDimension(String dimension) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF2c2c2e),
        title: const Text('Remove Dimension?',
            style: TextStyle(color: Colors.white)),
        content: Text(
          'Remove "$dimension" from your tracking dimensions?\n\nThis won\'t affect ratings already saved to past gigs.',
          style: TextStyle(color: Colors.grey.shade300),
        ),
        actions: [
          TextButton(
            child: const Text('Cancel'),
            onPressed: () => Navigator.of(context).pop(false),
          ),
          TextButton(
            child: Text('Remove',
                style:
                TextStyle(color: Theme.of(context).colorScheme.error)),
            onPressed: () => Navigator.of(context).pop(true),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      setState(() {
        _allDimensions.remove(dimension);
        _ratings.remove(dimension);
      });
      await _saveDimensions();
      _notifyRatingsChanged();
    }
  }

  Future<void> _exportReview() async {
    final gig = widget.gig;
    final dateFormat = DateFormat('MMMM d, yyyy \'at\' h:mm a');

    final buffer = StringBuffer();
    buffer.writeln('🎸 GIG REVIEW: ${widget.venueName ?? gig?.venueName ?? 'Unknown Venue'}');
    buffer.writeln('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    buffer.writeln('');
    if (gig != null) {
      buffer.writeln('📅 Date: ${dateFormat.format(gig.dateTime)}');
      buffer.writeln('📍 Venue: ${gig.venueName}');
      buffer.writeln('💰 Pay: \$${gig.pay.toStringAsFixed(2)}');
      if (_tipsAmount != null) {
        buffer.writeln('💵 Tips: \$${_tipsAmount!.toStringAsFixed(2)}');
      }
      buffer.writeln('⏱️  Duration: ${gig.gigLengthHours.toStringAsFixed(1)} hours');
    }
    buffer.writeln('');

    if (_ratings.isNotEmpty) {
      final avgRating = _ratings.values
          .whereType<double>()
          .fold<double>(0, (a, b) => a + b) /
          _ratings.values.whereType<double>().length;
      buffer.writeln('⭐ OVERALL RATING: ${avgRating.toStringAsFixed(1)}/5.0');
      buffer.writeln('');
      buffer.writeln('📊 DIMENSION RATINGS:');
      buffer.writeln('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
      for (final entry in _ratings.entries) {
        if (entry.value == null) continue;
        final stars =
            '★' * entry.value!.round() + '☆' * (5 - entry.value!.round());
        buffer.writeln(
            '• ${entry.key}: ${entry.value!.toStringAsFixed(1)}/5.0 $stars');
      }
    }

    buffer.writeln('');
    buffer.writeln('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    buffer.writeln('Generated by The Money Gigs app');

    try {
      await SharePlus.instance.share(
        ShareParams(
          text: buffer.toString(),
          subject:
          'Gig Review: ${widget.venueName ?? gig?.venueName ?? 'Unknown Venue'}',
        ),
      );
    } catch (e) {
      await Clipboard.setData(ClipboardData(text: buffer.toString()));
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Review copied to clipboard!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    }
  }

  // ── TIPS ROW ─────────────────────────────────────────────────────────────

  Widget _buildTipsRow() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.attach_money,
                  size: 16, color: Colors.greenAccent.shade400),
              const SizedBox(width: 6),
              Text(
                'Tips collected',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w500,
                  fontSize: 14,
                ),
              ),
              const Spacer(),
              SizedBox(
                width: 110,
                child: TextField(
                  controller: _tipsController,
                  keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                  textAlign: TextAlign.right,
                  decoration: InputDecoration(
                    prefixText: '\$ ',
                    prefixStyle: TextStyle(color: Colors.greenAccent.shade400),
                    hintText: '0.00',
                    hintStyle: TextStyle(color: Colors.grey.shade700),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 8),
                    enabledBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: Colors.grey.shade700),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderSide:
                      BorderSide(color: Colors.greenAccent.shade400),
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  onChanged: _onTipsChanged,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Divider(color: Colors.grey.shade800, height: 1),
        ],
      ),
    );
  }

  // ── STAR DIMENSION ROW ───────────────────────────────────────────────────

  Widget _buildDimensionRow(String dimension) {
    final rating = _ratings[dimension];
    final category = DefaultGigDimensions.getCategoryFor(dimension);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: GestureDetector(
              onLongPress: () => _confirmRemoveDimension(dimension),
              child: Row(
                children: [
                  if (category != null)
                    Padding(
                      padding: const EdgeInsets.only(right: 6.0),
                      child: Icon(
                        _getCategoryIcon(category),
                        size: 16,
                        color: Colors.grey.shade500,
                      ),
                    ),
                  Flexible(
                    child: Text(
                      dimension,
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w500,
                        fontSize: 14,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            flex: 3,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (rating != null)
                  IconButton(
                    icon:
                    Icon(Icons.clear, size: 18, color: Colors.grey.shade500),
                    onPressed: () => _clearRating(dimension),
                    tooltip: 'Clear rating',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                const SizedBox(width: 4),
                RatingBar.builder(
                  initialRating: rating ?? 0,
                  minRating: 0,
                  direction: Axis.horizontal,
                  allowHalfRating: true,
                  itemCount: 5,
                  itemSize: 24,
                  unratedColor: Colors.grey.shade700,
                  itemBuilder: (context, _) =>
                  const Icon(Icons.star, color: Colors.amber),
                  onRatingUpdate: (newRating) =>
                      _updateRating(dimension, newRating),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  IconData _getCategoryIcon(String category) {
    switch (category) {
      case 'performance':
        return Icons.music_note;
      case 'financial':
        return Icons.attach_money;
      case 'venue':
        return Icons.store;
      case 'personal':
        return Icons.favorite_outline;
      default:
        return Icons.star_outline;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Center(child: CircularProgressIndicator());

    final ratedCount = _ratings.values.where((r) => r != null).length;
    final totalCount = _allDimensions.length;
    final tipsEntered = _tipsAmount != null;

    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade700),
        borderRadius: BorderRadius.circular(8.0),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header ────────────────────────────────────────────────────────
          InkWell(
            onTap: () => setState(() => _isExpanded = !_isExpanded),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(8.0)),
            child: Container(
              padding: const EdgeInsets.all(12.0),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.vertical(
                  top: const Radius.circular(8.0),
                  bottom:
                  _isExpanded ? Radius.zero : const Radius.circular(8.0),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.rate_review,
                    color: Theme.of(context).colorScheme.primary,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          "How'd it go?",
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        // Show tips and star rating progress in subtitle
                        if (tipsEntered || ratedCount > 0)
                          Text(
                            [
                              if (tipsEntered)
                                '\$${_tipsAmount!.toStringAsFixed(2)} tips',
                              if (ratedCount > 0)
                                '$ratedCount of $totalCount rated',
                            ].join(' · '),
                            style: TextStyle(
                              color: Colors.grey.shade400,
                              fontSize: 12,
                            ),
                          ),
                      ],
                    ),
                  ),
                  Icon(
                    _isExpanded ? Icons.expand_less : Icons.expand_more,
                    color: Colors.grey.shade400,
                  ),
                ],
              ),
            ),
          ),

          // ── Expandable content ────────────────────────────────────────────
          if (_isExpanded) ...[
            const Divider(height: 1, color: Colors.grey),
            Padding(
              padding: const EdgeInsets.all(12.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Tips dollar input — always first
                  _buildTipsRow(),

                  // Star rating dimensions
                  ..._allDimensions.map(_buildDimensionRow),

                  const SizedBox(height: 8),

                  // Add custom dimension
                  Center(
                    child: TextButton.icon(
                      onPressed: _showAddDimensionDialog,
                      icon: Icon(
                        Icons.add_circle_outline,
                        color: Colors.orangeAccent.shade100,
                        size: 20,
                      ),
                      label: Text(
                        'Add Custom Dimension',
                        style: TextStyle(color: Colors.orangeAccent.shade100),
                      ),
                    ),
                  ),

                  // Export (only if there's something to export)
                  if (_ratings.values.whereType<double>().isNotEmpty ||
                      tipsEntered)
                    Center(
                      child: TextButton.icon(
                        onPressed: _exportReview,
                        icon: const Icon(Icons.share, size: 18),
                        label: const Text('Export Review'),
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.grey.shade400,
                        ),
                      ),
                    ),

                  Padding(
                    padding: const EdgeInsets.only(top: 8.0),
                    child: Text(
                      'Tip: Long-press any dimension to remove it.',
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: 11,
                        fontStyle: FontStyle.italic,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}