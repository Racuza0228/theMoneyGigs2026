// lib/features/gigs/widgets/gig_retrospective_widget.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_rating_bar/flutter_rating_bar.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:the_money_gigs/features/gigs/models/gig_rating.dart';
import 'package:the_money_gigs/features/gigs/models/gig_model.dart';
import 'package:share_plus/share_plus.dart';

/// A widget that allows users to rate various dimensions of a completed gig.
///
/// This widget displays a list of dimensions (Energy, Tips, Creative Fulfillment, etc.)
/// with star rating bars. Users can rate each dimension and add custom dimensions.
///
/// Usage:
/// ```dart
/// GigRetrospectiveWidget(
///   existingRatings: gig.gigRatings,
///   onRatingsChanged: (ratings) {
///     // Update gig with new ratings
///   },
/// )
/// ```
class GigRetrospectiveWidget extends StatefulWidget {
  /// Existing ratings to pre-populate (if editing a previously rated gig)
  final List<GigRating>? existingRatings;

  /// Callback fired whenever ratings change
  final Function(List<GigRating>) onRatingsChanged;

  /// Optional: venue name for context in the header
  final String? venueName;

  /// Optional: the gig being reviewed (needed for export)
  final Gig? gig;

  const GigRetrospectiveWidget({
    super.key,
    this.existingRatings,
    required this.onRatingsChanged,
    this.venueName,
    this.gig,
  });

  @override
  State<GigRetrospectiveWidget> createState() => _GigRetrospectiveWidgetState();
}

class _GigRetrospectiveWidgetState extends State<GigRetrospectiveWidget> {
  // SharedPreferences key for user's active dimensions
  static const String _keyActiveDimensions = 'retrospective_active_dimensions';

  // Map of dimension name to current rating (null = not yet rated)
  final Map<String, double?> _ratings = {};

  // List of all dimensions to display (user's active list)
  List<String> _allDimensions = [];

  bool _isLoading = true;
  bool _isExpanded = true;

  @override
  void initState() {
    super.initState();
    _loadDimensions();
  }

  Future<void> _loadDimensions() async {
    final prefs = await SharedPreferences.getInstance();
    final savedDimensions = prefs.getStringList(_keyActiveDimensions);

    // If user has saved dimensions, use those; otherwise use defaults
    if (savedDimensions != null && savedDimensions.isNotEmpty) {
      _allDimensions = savedDimensions;
    } else {
      // First time - use all default dimensions
      _allDimensions = List.from(DefaultGigDimensions.all);
      await _saveDimensions();
    }

    // Pre-populate ratings from existing data
    if (widget.existingRatings != null) {
      for (final rating in widget.existingRatings!) {
        _ratings[rating.dimension] = rating.rating;
        // If this dimension isn't in our list, add it
        if (!_allDimensions.contains(rating.dimension)) {
          _allDimensions.add(rating.dimension);
        }
      }
    }

    if (mounted) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _saveDimensions() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_keyActiveDimensions, _allDimensions);
  }

  void _updateRating(String dimension, double rating) {
    setState(() {
      _ratings[dimension] = rating;
    });
    _notifyRatingsChanged();
  }

  void _clearRating(String dimension) {
    setState(() {
      _ratings.remove(dimension);
    });
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
                    borderSide: BorderSide(color: Theme.of(context).colorScheme.primary),
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

    if (result != null && result.isNotEmpty && !_allDimensions.contains(result)) {
      setState(() {
        _allDimensions.add(result);
      });
      await _saveDimensions();
    }
  }

  Future<void> _confirmRemoveDimension(String dimension) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF2c2c2e),
        title: const Text('Remove Dimension?', style: TextStyle(color: Colors.white)),
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
            child: Text('Remove', style: TextStyle(color: Theme.of(context).colorScheme.error)),
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
    if (widget.gig == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Cannot export: gig information not available'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final dateFormat = DateFormat('MMMM d, yyyy \'at\' h:mm a');
    final avgRating = _ratings.values.where((r) => r != null).isEmpty
        ? 0.0
        : _ratings.values.whereType<double>().reduce((a, b) => a + b) /
        _ratings.values.whereType<double>().length;

    final buffer = StringBuffer();
    buffer.writeln('🎸 GIG REVIEW: ${widget.gig!.venueName}');
    buffer.writeln('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    buffer.writeln('');
    buffer.writeln('📅 Date: ${dateFormat.format(widget.gig!.dateTime)}');
    buffer.writeln('📍 Venue: ${widget.gig!.venueName}');
    buffer.writeln('💰 Pay: \$${widget.gig!.pay.toStringAsFixed(2)}');
    buffer.writeln('⏱️  Duration: ${widget.gig!.gigLengthHours.toStringAsFixed(1)} hours');
    buffer.writeln('');

    if (_ratings.values.whereType<double>().isNotEmpty) {
      buffer.writeln('⭐ OVERALL RATING: ${avgRating.toStringAsFixed(1)}/5.0');
      buffer.writeln('');
      buffer.writeln('📊 DIMENSION RATINGS:');
      buffer.writeln('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');

      for (final entry in _ratings.entries) {
        if (entry.value != null) {
          final stars = '★' * entry.value!.round() + '☆' * (5 - entry.value!.round());
          buffer.writeln('• ${entry.key}: ${entry.value!.toStringAsFixed(1)}/5.0 $stars');
        }
      }
    }

    if (widget.gig!.notes != null && widget.gig!.notes!.isNotEmpty) {
      buffer.writeln('');
      buffer.writeln('📝 NOTES:');
      buffer.writeln('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
      buffer.writeln(widget.gig!.notes!);
    }

    buffer.writeln('');
    buffer.writeln('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    buffer.writeln('Generated by The Money Gigs app');

    try {
      await Share.share(
        buffer.toString(),
        subject: 'Gig Review: ${widget.gig!.venueName}',
      );
    } catch (e) {
      // Fallback: copy to clipboard
      await Clipboard.setData(ClipboardData(text: buffer.toString()));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Review copied to clipboard!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    }
  }

  Widget _buildDimensionRow(String dimension) {
    final rating = _ratings[dimension];
    final category = DefaultGigDimensions.getCategoryFor(dimension);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        children: [
          // Dimension label
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
          // Rating bar
          Expanded(
            flex: 3,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (rating != null)
                  IconButton(
                    icon: Icon(Icons.clear, size: 18, color: Colors.grey.shade500),
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
                  itemBuilder: (context, _) => const Icon(
                    Icons.star,
                    color: Colors.amber,
                  ),
                  onRatingUpdate: (newRating) => _updateRating(dimension, newRating),
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
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    final ratedCount = _ratings.values.where((r) => r != null).length;
    final totalCount = _allDimensions.length;

    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade700),
        borderRadius: BorderRadius.circular(8.0),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header (tappable to expand/collapse)
          InkWell(
            onTap: () => setState(() => _isExpanded = !_isExpanded),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(8.0)),
            child: Container(
              padding: const EdgeInsets.all(12.0),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
                borderRadius: BorderRadius.vertical(
                  top: const Radius.circular(8.0),
                  bottom: _isExpanded ? Radius.zero : const Radius.circular(8.0),
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
                        if (ratedCount > 0)
                          Text(
                            '$ratedCount of $totalCount rated',
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

          // Expandable content
          if (_isExpanded) ...[
            const Divider(height: 1, color: Colors.grey),
            Padding(
              padding: const EdgeInsets.all(12.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Dimension rows
                  ..._allDimensions.map(_buildDimensionRow),

                  const SizedBox(height: 8),

                  // Add custom dimension button
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

                  // Export button (if there are ratings)
                  if (_ratings.values.whereType<double>().isNotEmpty)
                    Center(
                      child: TextButton.icon(
                        onPressed: _exportReview,
                        icon: const Icon(
                          Icons.share,
                          size: 18,
                        ),
                        label: const Text('Export Review'),
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.grey.shade400,
                        ),
                      ),
                    ),

                  // Hint text
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