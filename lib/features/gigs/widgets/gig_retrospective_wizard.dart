// lib/features/gigs/widgets/gig_retrospective_wizard.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_rating_bar/flutter_rating_bar.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:the_money_gigs/features/gigs/models/gig_model.dart';
import 'package:the_money_gigs/features/gigs/models/gig_rating.dart';
import 'package:the_money_gigs/features/gigs/services/gig_retrospective_service.dart';
import 'package:share_plus/share_plus.dart';

/// A conversational, wizard-style dialog that walks users through rating a gig
/// one dimension at a time, then asks for overall notes.
class GigRetrospectiveWizard extends StatefulWidget {
  final Gig gig;
  final VoidCallback? onComplete;
  final VoidCallback? onSkip;

  const GigRetrospectiveWizard({
    super.key,
    required this.gig,
    this.onComplete,
    this.onSkip,
  });

  @override
  State<GigRetrospectiveWizard> createState() => _GigRetrospectiveWizardState();
}

class _GigRetrospectiveWizardState extends State<GigRetrospectiveWizard>
    with SingleTickerProviderStateMixin {
  static const String _keyActiveDimensions = 'retrospective_active_dimensions';

  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;

  List<String> _dimensions = [];
  int _currentDimensionIndex = 0;
  bool _isOnNotesStep = false;
  bool _isComplete = false;

  final Map<String, double> _ratings = {};
  final TextEditingController _notesController = TextEditingController();

  bool _isLoading = true;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeIn),
    );
    _loadDimensions();
  }

  Future<void> _loadDimensions() async {
    final prefs = await SharedPreferences.getInstance();
    final savedDimensions = prefs.getStringList(_keyActiveDimensions);

    if (savedDimensions != null && savedDimensions.isNotEmpty) {
      _dimensions = savedDimensions;
    } else {
      _dimensions = List.from(DefaultGigDimensions.all);
    }

    // Pre-populate with existing ratings if any
    if (widget.gig.gigRatings != null) {
      for (final rating in widget.gig.gigRatings!) {
        _ratings[rating.dimension] = rating.rating;
      }
    }

    // Pre-populate notes
    if (widget.gig.notes != null) {
      _notesController.text = widget.gig.notes!;
    }

    if (mounted) {
      setState(() => _isLoading = false);
      _animationController.forward();
    }
  }

  @override
  void dispose() {
    _animationController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  String get _currentDimension => _dimensions[_currentDimensionIndex];

  void _nextStep() {
    if (_currentDimensionIndex < _dimensions.length - 1) {
      setState(() {
        _currentDimensionIndex++;
        _animationController.reset();
      });
      _animationController.forward();
    } else {
      setState(() {
        _isOnNotesStep = true;
        _animationController.reset();
      });
      _animationController.forward();
    }
  }

  void _previousStep() {
    if (_isOnNotesStep) {
      setState(() {
        _isOnNotesStep = false;
        _animationController.reset();
      });
      _animationController.forward();
    } else if (_currentDimensionIndex > 0) {
      setState(() {
        _currentDimensionIndex--;
        _animationController.reset();
      });
      _animationController.forward();
    }
  }

  void _skipCurrentRating() {
    _ratings.remove(_currentDimension);
    _nextStep();
  }

  void _setRating(double rating) {
    setState(() {
      _ratings[_currentDimension] = rating;
    });
  }

  Future<void> _skipEntireReview() async {
    // Mark this gig as skipped
    await GigRetrospectiveService.skipGigRetrospective(widget.gig.id);

    if (mounted) {
      Navigator.of(context).pop();
      widget.onSkip?.call();
    }
  }

  Future<void> _saveAndComplete() async {
    if (_isSaving) return;

    setState(() => _isSaving = true);

    try {
      // Build list of ratings
      final List<GigRating> ratings = [];
      for (final entry in _ratings.entries) {
        ratings.add(GigRating(
          dimension: entry.key,
          rating: entry.value,
          category: DefaultGigDimensions.getCategoryFor(entry.key),
        ));
      }

      // Update the gig
      final prefs = await SharedPreferences.getInstance();
      final gigsJsonString = prefs.getString('gigs_list') ?? '[]';
      final List<Gig> allGigs = Gig.decode(gigsJsonString);
      final gigIndex = allGigs.indexWhere((g) => g.id == widget.gig.id);

      if (gigIndex != -1) {
        allGigs[gigIndex] = allGigs[gigIndex].copyWith(
          gigRatings: ratings,
          notes: _notesController.text.trim().isEmpty
              ? null
              : _notesController.text.trim(),
          retrospectiveCompleted: true,
        );

        await prefs.setString('gigs_list', Gig.encode(allGigs));
      }

      if (mounted) {
        setState(() {
          _isComplete = true;
          _isSaving = false;
        });

        // Show completion message briefly, then close
        await Future.delayed(const Duration(milliseconds: 800));

        if (mounted) {
          Navigator.of(context).pop(allGigs[gigIndex]);
          widget.onComplete?.call();
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error saving review: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _exportReview() async {
    final dateFormat = DateFormat('MMMM d, yyyy \'at\' h:mm a');
    final avgRating = _ratings.values.isEmpty
        ? 0.0
        : _ratings.values.reduce((a, b) => a + b) / _ratings.values.length;

    final buffer = StringBuffer();
    buffer.writeln('🎸 GIG REVIEW: ${widget.gig.venueName}');
    buffer.writeln('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    buffer.writeln('');
    buffer.writeln('📅 Date: ${dateFormat.format(widget.gig.dateTime)}');
    buffer.writeln('📍 Venue: ${widget.gig.venueName}');
    buffer.writeln('💰 Pay: \$${widget.gig.pay.toStringAsFixed(2)}');
    buffer.writeln('⏱️  Duration: ${widget.gig.gigLengthHours.toStringAsFixed(1)} hours');
    buffer.writeln('');
    buffer.writeln('⭐ OVERALL RATING: ${avgRating.toStringAsFixed(1)}/5.0');
    buffer.writeln('');
    buffer.writeln('📊 DIMENSION RATINGS:');
    buffer.writeln('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');

    for (final entry in _ratings.entries) {
      final stars = '★' * entry.value.round() + '☆' * (5 - entry.value.round());
      buffer.writeln('• ${entry.key}: ${entry.value.toStringAsFixed(1)}/5.0 $stars');
    }

    if (_notesController.text.trim().isNotEmpty) {
      buffer.writeln('');
      buffer.writeln('📝 NOTES:');
      buffer.writeln('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
      buffer.writeln(_notesController.text.trim());
    }

    buffer.writeln('');
    buffer.writeln('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    buffer.writeln('Generated by The Money Gigs app');

    try {
      await Share.share(
        buffer.toString(),
        subject: 'Gig Review: ${widget.gig.venueName}',
      );
    } catch (e) {
      if (mounted) {
        // Fallback: copy to clipboard
        await Clipboard.setData(ClipboardData(text: buffer.toString()));
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Review copied to clipboard!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    }
  }

  Widget _buildRatingStep() {
    final dimension = _currentDimension;
    final currentRating = _ratings[dimension];
    final progress = (_currentDimensionIndex + 1) / _dimensions.length;
    final category = DefaultGigDimensions.getCategoryFor(dimension);

    return FadeTransition(
      opacity: _fadeAnimation,
      child: Column(
        children: [
          // Progress indicator
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24.0),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Step ${_currentDimensionIndex + 1} of ${_dimensions.length}',
                      style: TextStyle(
                        color: Colors.grey.shade500,
                        fontSize: 12,
                      ),
                    ),
                    Text(
                      '${(progress * 100).toInt()}%',
                      style: TextStyle(
                        color: Colors.grey.shade500,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 6,
                    backgroundColor: Colors.grey.shade800,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 32),

          // Conversational prompt
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24.0),
            child: Column(
              children: [
                if (category != null)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primary.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      category.toUpperCase(),
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.primary,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ),
                const SizedBox(height: 16),
                Text(
                  'How was the',
                  style: TextStyle(
                    color: Colors.grey.shade400,
                    fontSize: 18,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  dimension,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  'at ${widget.gig.venueName}?',
                  style: TextStyle(
                    color: Colors.grey.shade400,
                    fontSize: 18,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),

          const SizedBox(height: 40),

          // Rating bar
          RatingBar.builder(
            initialRating: currentRating ?? 0,
            minRating: 0,
            direction: Axis.horizontal,
            allowHalfRating: true,
            itemCount: 5,
            itemSize: 56,
            unratedColor: Colors.grey.shade700,
            glowColor: Colors.amber.withOpacity(0.3),
            itemBuilder: (context, _) => const Icon(
              Icons.star,
              color: Colors.amber,
            ),
            onRatingUpdate: (rating) {
              HapticFeedback.mediumImpact();
              _setRating(rating);
            },
          ),

          if (currentRating != null) ...[
            const SizedBox(height: 16),
            Text(
              '${currentRating.toStringAsFixed(1)} / 5.0',
              style: TextStyle(
                color: Colors.grey.shade400,
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],

          const Spacer(),

          // Navigation buttons
          Padding(
            padding: const EdgeInsets.all(24.0),
            child: Row(
              children: [
                // Back button
                if (_currentDimensionIndex > 0)
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _previousStep,
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      child: const Text('BACK'),
                    ),
                  ),
                if (_currentDimensionIndex > 0) const SizedBox(width: 12),

                // Skip button
                Expanded(
                  child: OutlinedButton(
                    onPressed: _skipCurrentRating,
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      side: BorderSide(color: Colors.grey.shade600),
                    ),
                    child: const Text('SKIP'),
                  ),
                ),

                const SizedBox(width: 12),

                // Next button
                Expanded(
                  flex: 2,
                  child: ElevatedButton(
                    onPressed: currentRating != null ? _nextStep : null,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      backgroundColor: Theme.of(context).colorScheme.primary,
                    ),
                    child: Text(
                      _currentDimensionIndex == _dimensions.length - 1
                          ? 'ADD NOTES'
                          : 'NEXT',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNotesStep() {
    final avgRating = _ratings.values.isEmpty
        ? 0.0
        : _ratings.values.reduce((a, b) => a + b) / _ratings.values.length;

    return FadeTransition(
      opacity: _fadeAnimation,
      child: Column(
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              children: [
                const Icon(
                  Icons.edit_note,
                  size: 48,
                  color: Colors.white,
                ),
                const SizedBox(height: 16),
                const Text(
                  'Any other thoughts?',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  'Add some notes about how this gig went',
                  style: TextStyle(
                    color: Colors.grey.shade400,
                    fontSize: 16,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.green.shade900.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: Colors.green.shade700.withOpacity(0.5),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.star,
                        color: Colors.amber,
                        size: 24,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Average Rating: ${avgRating.toStringAsFixed(1)}/5.0',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Notes field
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24.0),
              child: TextField(
                controller: _notesController,
                maxLines: null,
                expands: true,
                textAlignVertical: TextAlignVertical.top,
                style: const TextStyle(fontSize: 16),
                decoration: InputDecoration(
                  hintText: 'What stood out? What could be improved? Any memorable moments?\n\n(Optional - you can export this to use with AI tools like Rosebud)',
                  hintStyle: TextStyle(color: Colors.grey.shade600),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  contentPadding: const EdgeInsets.all(16),
                ),
              ),
            ),
          ),

          // Action buttons
          Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _previousStep,
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                        child: const Text('BACK'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: ElevatedButton(
                        onPressed: _isSaving ? null : _saveAndComplete,
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          backgroundColor: Colors.green.shade700,
                        ),
                        child: _isSaving
                            ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                            : const Text(
                          'COMPLETE REVIEW',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextButton.icon(
                  onPressed: _exportReview,
                  icon: const Icon(Icons.share, size: 18),
                  label: const Text('Export Review to Share/Copy'),
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.grey.shade400,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCompletionStep() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.check_circle,
            size: 80,
            color: Colors.green.shade400,
          ),
          const SizedBox(height: 24),
          const Text(
            'Review Complete!',
            style: TextStyle(
              color: Colors.white,
              fontSize: 28,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Thanks for sharing your thoughts',
            style: TextStyle(
              color: Colors.grey.shade400,
              fontSize: 16,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_isComplete) {
      return Scaffold(
        body: _buildCompletionStep(),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Gig Review'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () async {
            final shouldExit = await showDialog<bool>(
              context: context,
              builder: (context) => AlertDialog(
                title: const Text('Exit Review?'),
                content: const Text(
                  'Your progress will be saved, but you can come back to finish this review later.',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    child: const Text('CANCEL'),
                  ),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(true),
                    child: const Text('SKIP FOR NOW'),
                  ),
                ],
              ),
            );

            if (shouldExit == true) {
              await _skipEntireReview();
            }
          },
        ),
        actions: [
          if (!_isOnNotesStep)
            TextButton(
              onPressed: () {
                setState(() {
                  _isOnNotesStep = true;
                  _animationController.reset();
                });
                _animationController.forward();
              },
              child: const Text('SKIP TO NOTES'),
            ),
        ],
      ),
      body: SafeArea(
        child: _isOnNotesStep ? _buildNotesStep() : _buildRatingStep(),
      ),
    );
  }
}