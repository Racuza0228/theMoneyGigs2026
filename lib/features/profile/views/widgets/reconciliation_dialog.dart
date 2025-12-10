import 'package:flutter/material.dart';
import 'package:flutter_rating_bar/flutter_rating_bar.dart';
import 'package:the_money_gigs/features/map_venues/models/venue_model.dart';

class ReconciliationDialog extends StatefulWidget {
  final StoredLocation venue;
  final Function(StoredLocation) onKeepPrivate;
  final Function(StoredLocation) onPublish;

  const ReconciliationDialog({
    super.key,
    required this.venue,
    required this.onKeepPrivate,
    required this.onPublish,
  });

  @override
  State<ReconciliationDialog> createState() => _ReconciliationDialogState();
}

class _ReconciliationDialogState extends State<ReconciliationDialog> {
  late double _currentRating;
  late final TextEditingController _commentController;

  @override
  void initState() {
    super.initState();
    _currentRating = widget.venue.rating;
    _commentController = TextEditingController(text: widget.venue.comment);
  }

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  StoredLocation _buildUpdatedVenue() {
    return widget.venue.copyWith(
      rating: _currentRating,
      comment: _commentController.text.trim().isEmpty
          ? null
          : _commentController.text.trim(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textTheme = theme.textTheme;

    return AlertDialog(
      title: Text(widget.venue.name,
          style: textTheme.headlineSmall, textAlign: TextAlign.center),
      content: SingleChildScrollView(
        child: ListBody(
          children: <Widget>[
            if (widget.venue.address.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 16.0),
                child: Text(
                  widget.venue.address,
                  textAlign: TextAlign.center,
                  style: textTheme.bodySmall,
                ),
              ),
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
                itemPadding: const EdgeInsets.symmetric(horizontal: 4.0),
                itemBuilder: (context, _) =>
                const Icon(Icons.star, color: Colors.amber),
                onRatingUpdate: (rating) {
                  setState(() {
                    _currentRating = rating;
                  });
                },
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
                border: OutlineInputBorder(),
              ),
              maxLines: 2,
              textCapitalization: TextCapitalization.sentences,
            ),
          ],
        ),
      ),
      actionsAlignment: MainAxisAlignment.spaceEvenly,
      actions: <Widget>[
        OutlinedButton(
          onPressed: () => widget.onKeepPrivate(_buildUpdatedVenue()),
          child: const Text('Keep Private'),
        ),
        ElevatedButton(
          onPressed: () => widget.onPublish(_buildUpdatedVenue()),
          style: ElevatedButton.styleFrom(
              backgroundColor: theme.colorScheme.primary,
              foregroundColor: theme.colorScheme.onPrimary),
          child: const Text('Publish'),
        ),
      ],
    );
  }
}
