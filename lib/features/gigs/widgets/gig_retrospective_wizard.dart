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

  // Step flags — tips is always the FIRST step
  bool _isOnTipsStep = true;
  bool _isOnNotesStep = false;
  bool _isComplete = false;

  // Tips state
  final TextEditingController _tipsController = TextEditingController();
  double? _tipsAmount;

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
      // Silently filter out legacy 'Tips' star-rating dimension
      _dimensions = savedDimensions
          .where((d) => !DefaultGigDimensions.reservedAsFields.contains(d))
          .toList();
    } else {
      _dimensions = List.from(DefaultGigDimensions.all);
    }

    // Pre-populate star ratings if editing
    if (widget.gig.gigRatings != null) {
      for (final rating in widget.gig.gigRatings!) {
        if (!DefaultGigDimensions.reservedAsFields.contains(rating.dimension)) {
          _ratings[rating.dimension] = rating.rating;
        }
      }
    }

    // Pre-populate tips if already recorded
    if (widget.gig.tipsAmount != null) {
      _tipsAmount = widget.gig.tipsAmount;
      _tipsController.text = widget.gig.tipsAmount!.toStringAsFixed(2);
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
    _tipsController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  String get _currentDimension => _dimensions[_currentDimensionIndex];

  // ── NAVIGATION ────────────────────────────────────────────────────────────

  /// Advance from the tips step to the first dimension (or notes if none).
  void _advanceFromTips() {
    setState(() {
      _isOnTipsStep = false;
      if (_dimensions.isEmpty) {
        _isOnNotesStep = true;
      }
      _animationController.reset();
    });
    _animationController.forward();
  }

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
        if (_dimensions.isEmpty) {
          // No star dimensions — go back to tips step
          _isOnTipsStep = true;
        }
        _animationController.reset();
      });
      _animationController.forward();
    } else if (_currentDimensionIndex > 0) {
      setState(() {
        _currentDimensionIndex--;
        _animationController.reset();
      });
      _animationController.forward();
    } else {
      // First dimension — go back to tips step
      setState(() {
        _isOnTipsStep = true;
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
    setState(() => _ratings[_currentDimension] = rating);
  }

  Future<void> _skipEntireReview() async {
    await GigRetrospectiveService.skipGigRetrospective(widget.gig.id);
    if (mounted) {
      Navigator.of(context).pop();
      widget.onSkip?.call();
    }
  }

  // ── SAVE ──────────────────────────────────────────────────────────────────

  Future<void> _saveAndComplete() async {
    if (_isSaving) return;
    setState(() => _isSaving = true);

    try {
      final List<GigRating> ratings = [];
      for (final entry in _ratings.entries) {
        ratings.add(GigRating(
          dimension: entry.key,
          rating: entry.value,
          category: DefaultGigDimensions.getCategoryFor(entry.key),
        ));
      }

      final prefs = await SharedPreferences.getInstance();
      final gigsJsonString = prefs.getString('gigs_list') ?? '[]';
      final List<Gig> allGigs = Gig.decode(gigsJsonString);

      final gigIndex = allGigs.indexWhere((g) => g.id == widget.gig.id);

      Gig updatedGig;

      if (gigIndex != -1) {
        // Standalone gig — update in place
        allGigs[gigIndex] = allGigs[gigIndex].copyWith(
          gigRatings: ratings,
          tipsAmount: _tipsAmount,
          notes: _notesController.text.trim().isEmpty
              ? null
              : _notesController.text.trim(),
          retrospectiveCompleted: true,
        );
        updatedGig = allGigs[gigIndex];
      } else {
        // Virtual recurring instance — materialize into a real record
        updatedGig = widget.gig.copyWith(
          gigRatings: ratings,
          tipsAmount: _tipsAmount,
          notes: _notesController.text.trim().isEmpty
              ? null
              : _notesController.text.trim(),
          retrospectiveCompleted: true,
          isRecurring: false,
          isFromRecurring: true,
        );
        allGigs.add(updatedGig);
      }

      await prefs.setString('gigs_list', Gig.encode(allGigs));

      if (mounted) {
        setState(() {
          _isComplete = true;
          _isSaving = false;
        });
        await Future.delayed(const Duration(milliseconds: 800));
        if (mounted) {
          Navigator.of(context).pop(updatedGig);
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

  // ── EXPORT ────────────────────────────────────────────────────────────────

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
    if (_tipsAmount != null) {
      buffer.writeln('💵 Tips: \$${_tipsAmount!.toStringAsFixed(2)}');
      buffer.writeln(
          '💰 Total take-home: \$${(widget.gig.pay + _tipsAmount!).toStringAsFixed(2)}');
    }
    buffer.writeln('⏱️  Duration: ${widget.gig.gigLengthHours.toStringAsFixed(1)} hours');

    if (_ratings.isNotEmpty) {
      buffer.writeln('');
      buffer.writeln('⭐ OVERALL RATING: ${avgRating.toStringAsFixed(1)}/5.0');
      buffer.writeln('');
      buffer.writeln('📊 DIMENSION RATINGS:');
      buffer.writeln('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
      for (final entry in _ratings.entries) {
        final stars =
            '★' * entry.value.round() + '☆' * (5 - entry.value.round());
        buffer.writeln(
            '• ${entry.key}: ${entry.value.toStringAsFixed(1)}/5.0 $stars');
      }
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

  // ── BUILD STEPS ───────────────────────────────────────────────────────────

  /// Step 0 — Tips. Always shown first. The musician must enter an amount OR
  /// tap "No tips" to advance. This is the forcing function that ensures
  /// tipsAmount is always populated when a retrospective is completed.
  Widget _buildTipsStep(BuildContext context) {
    final canAdvance = _tipsController.text.trim().isNotEmpty;

    return SingleChildScrollView(
      child: FadeTransition(
        opacity: _fadeAnimation,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minHeight: MediaQuery.of(context).size.height -
                (Scaffold.of(context).appBarMaxHeight ?? 0) -
                MediaQuery.of(context).padding.top -
                MediaQuery.of(context).padding.bottom,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // ── Question ─────────────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 48, 24, 0),
                child: Column(
                  children: [
                    Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        color: Colors.green.shade900.withOpacity(0.4),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.attach_money,
                        size: 44,
                        color: Colors.greenAccent.shade400,
                      ),
                    ),
                    const SizedBox(height: 28),
                    const Text(
                      'Any tips tonight?',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'at ${widget.gig.venueName}',
                      style: TextStyle(
                        color: Colors.grey.shade400,
                        fontSize: 18,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 40),

                    // ── Dollar input ──────────────────────────────────────
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 28, vertical: 20),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade900,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.grey.shade700),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Text(
                            '\$',
                            style: TextStyle(
                              color: Colors.greenAccent.shade400,
                              fontSize: 36,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(width: 8),
                          SizedBox(
                            width: 150,
                            child: TextField(
                              controller: _tipsController,
                              autofocus: false,
                              keyboardType:
                              const TextInputType.numberWithOptions(
                                  decimal: true),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 36,
                                fontWeight: FontWeight.bold,
                              ),
                              textAlign: TextAlign.center,
                              decoration: InputDecoration(
                                border: InputBorder.none,
                                hintText: '0.00',
                                hintStyle: TextStyle(
                                  color: Colors.grey.shade700,
                                  fontSize: 36,
                                ),
                              ),
                              onChanged: (value) {
                                setState(() {
                                  _tipsAmount = double.tryParse(value);
                                });
                              },
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 12),
                    Text(
                      'Enter the dollar amount collected',
                      style: TextStyle(
                          color: Colors.grey.shade600, fontSize: 13),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),

              // ── Buttons ───────────────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  children: [
                    // NEXT — enabled only when a valid number is typed
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: canAdvance ? _advanceFromTips : null,
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          backgroundColor:
                          Theme.of(context).colorScheme.primary,
                        ),
                        child: const Text(
                          'NEXT',
                          style: TextStyle(
                              fontWeight: FontWeight.bold, color: Colors.black),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // NO TIPS — always enabled; sets to $0 and advances
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton(
                        onPressed: () {
                          setState(() {
                            _tipsAmount = 0.0;
                            _tipsController.text = '0';
                          });
                          _advanceFromTips();
                        },
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          side: BorderSide(color: Colors.grey.shade600),
                        ),
                        child: const Text('NO TIPS'),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRatingStep(BuildContext context) {
    final dimension = _currentDimension;
    final currentRating = _ratings[dimension];
    final progress = (_currentDimensionIndex + 1) / _dimensions.length;
    final category = DefaultGigDimensions.getCategoryFor(dimension);

    return SingleChildScrollView(
      child: FadeTransition(
        opacity: _fadeAnimation,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minHeight: MediaQuery.of(context).size.height -
                (Scaffold.of(context).appBarMaxHeight ?? 0) -
                MediaQuery.of(context).padding.top -
                MediaQuery.of(context).padding.bottom,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24.0, 24.0, 24.0, 0),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Step ${_currentDimensionIndex + 1} of ${_dimensions.length}',
                              style: TextStyle(
                                  color: Colors.grey.shade500, fontSize: 12),
                            ),
                            Text(
                              '${(progress * 100).toInt()}%',
                              style: TextStyle(
                                  color: Colors.grey.shade500, fontSize: 12),
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
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24.0),
                    child: Column(
                      children: [
                        if (category != null)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: Theme.of(context)
                                  .colorScheme
                                  .primary
                                  .withOpacity(0.2),
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
                              color: Colors.grey.shade400, fontSize: 18),
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
                              color: Colors.grey.shade400, fontSize: 18),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 40),
                  RatingBar.builder(
                    initialRating: currentRating ?? 0,
                    minRating: 0,
                    direction: Axis.horizontal,
                    allowHalfRating: true,
                    itemCount: 5,
                    itemSize: 56,
                    unratedColor: Colors.grey.shade700,
                    glowColor: Colors.amber.withOpacity(0.3),
                    itemBuilder: (context, _) =>
                    const Icon(Icons.star, color: Colors.amber),
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
                ],
              ),
              Padding(
                padding: const EdgeInsets.all(24.0),
                child: Row(
                  children: [
                    // Back button (always present on dimension steps — goes
                    // back to tips step from the first dimension)
                    Flexible(
                      flex: 2,
                      child: OutlinedButton(
                        onPressed: _previousStep,
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                        child: const Text('BACK'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Flexible(
                      flex: 2,
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
                    Flexible(
                      flex: 3,
                      child: ElevatedButton(
                        onPressed: currentRating != null ? _nextStep : null,
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          backgroundColor:
                          Theme.of(context).colorScheme.primary,
                        ),
                        child: Text(
                          _currentDimensionIndex == _dimensions.length - 1
                              ? 'ADD NOTES'
                              : 'NEXT',
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, color: Colors.black),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNotesStep(BuildContext context) {
    final avgRating = _ratings.values.isEmpty
        ? 0.0
        : _ratings.values.reduce((a, b) => a + b) / _ratings.values.length;

    return SingleChildScrollView(
      child: FadeTransition(
        opacity: _fadeAnimation,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minHeight: MediaQuery.of(context).size.height -
                (Scaffold.of(context).appBarMaxHeight ?? 0) -
                MediaQuery.of(context).padding.top -
                MediaQuery.of(context).padding.bottom,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  children: [
                    const Icon(Icons.edit_note, size: 48, color: Colors.white),
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
                      style:
                      TextStyle(color: Colors.grey.shade400, fontSize: 16),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),

                    // Summary row — shows tips + avg rating
                    Wrap(
                      spacing: 12,
                      runSpacing: 8,
                      alignment: WrapAlignment.center,
                      children: [
                        if (_tipsAmount != null && _tipsAmount! > 0)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 10),
                            decoration: BoxDecoration(
                              color: Colors.green.shade900.withOpacity(0.35),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                  color: Colors.green.shade700.withOpacity(0.5)),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.attach_money,
                                    color: Colors.greenAccent.shade400,
                                    size: 20),
                                const SizedBox(width: 4),
                                Text(
                                  '\$${_tipsAmount!.toStringAsFixed(2)} tips',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        if (_ratings.isNotEmpty)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 10),
                            decoration: BoxDecoration(
                              color: Colors.green.shade900.withOpacity(0.3),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                  color:
                                  Colors.green.shade700.withOpacity(0.5)),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.star,
                                    color: Colors.amber, size: 20),
                                const SizedBox(width: 8),
                                Text(
                                  'Avg: ${avgRating.toStringAsFixed(1)}/5.0',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),

              SizedBox(
                height: 200,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24.0),
                  child: TextField(
                    controller: _notesController,
                    maxLines: null,
                    expands: true,
                    textAlignVertical: TextAlignVertical.top,
                    style: const TextStyle(fontSize: 16),
                    decoration: InputDecoration(
                      hintText:
                      'What stood out? What could be improved? Any memorable moments?\n\n(Optional — you can export this to use with AI tools like Rosebud)',
                      hintStyle: TextStyle(color: Colors.grey.shade600),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      contentPadding: const EdgeInsets.all(16),
                    ),
                  ),
                ),
              ),

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
                              padding:
                              const EdgeInsets.symmetric(vertical: 16),
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
                              padding:
                              const EdgeInsets.symmetric(vertical: 16),
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
                              style: TextStyle(
                                  fontWeight: FontWeight.bold),
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
        ),
      ),
    );
  }

  Widget _buildCompletionStep() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.check_circle, size: 80, color: Colors.green.shade400),
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
            style: TextStyle(color: Colors.grey.shade400, fontSize: 16),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (_isComplete) {
      return Scaffold(body: _buildCompletionStep());
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
                    'Your progress will be saved if you exit now. You can resume later.'),
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
            if (shouldExit == true) await _skipEntireReview();
          },
        ),
        actions: [
          // "Skip to Notes" bypasses both tips and star ratings entirely.
          // Shown on tips step and all dimension steps — not on notes step.
          if (_isOnTipsStep || !_isOnNotesStep)
            TextButton(
              onPressed: () {
                setState(() {
                  _isOnTipsStep = false;
                  _isOnNotesStep = true;
                  _animationController.reset();
                });
                _animationController.forward();
              },
              child: const Text('SKIP TO NOTES'),
            ),
        ],
      ),
      body: Builder(
        builder: (scaffoldContext) {
          return SafeArea(
            child: _isOnTipsStep
                ? _buildTipsStep(scaffoldContext)
                : _isOnNotesStep
                ? _buildNotesStep(scaffoldContext)
                : _buildRatingStep(scaffoldContext),
          );
        },
      ),
    );
  }
}