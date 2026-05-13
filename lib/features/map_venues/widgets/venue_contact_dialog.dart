// lib/features/map_venues/widgets/venue_contact_dialog.dart
import 'package:flutter/material.dart';
import 'package:the_money_gigs/features/map_venues/models/venue_contact.dart';
import 'package:the_money_gigs/features/map_venues/models/venue_model.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Result
// ─────────────────────────────────────────────────────────────────────────────

class VenueContactSaveResult {
  final VenueContact contact;
  final BookingInfo? bookingInfo;

  const VenueContactSaveResult({
    required this.contact,
    this.bookingInfo,
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// Dialog
// ─────────────────────────────────────────────────────────────────────────────

class VenueContactDialog extends StatefulWidget {
  final StoredLocation venue;
  final bool isConnected;
  final String? currentUserId;

  const VenueContactDialog({
    super.key,
    required this.venue,
    this.isConnected = false,
    this.currentUserId,
  });

  @override
  State<VenueContactDialog> createState() => _VenueContactDialogState();
}

class _VenueContactDialogState extends State<VenueContactDialog> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _nameController;
  late final TextEditingController _phoneController;
  late final TextEditingController _emailController;
  late final TextEditingController _notesController;

  String? _preferredMethod;
  late bool _isSharedWithNetwork;

  // Booking fields
  int? _leadsOutMonths;       // null = unknown/not specified
  String? _dealType;
  DateTime? _bookingWindowStart;

  @override
  void initState() {
    super.initState();
    final contact = widget.venue.contact ?? const VenueContact();
    _nameController = TextEditingController(text: contact.name);
    _phoneController = TextEditingController(text: contact.phone);
    _emailController = TextEditingController(text: contact.email);
    _notesController = TextEditingController(text: contact.notes ?? '');
    _preferredMethod = contact.preferredMethod;
    _isSharedWithNetwork = contact.isSharedWithNetwork;

    final booking = widget.venue.bookingInfo;
    if (booking != null) {
      _leadsOutMonths = booking.leadsOutMonths != null
          ? booking.leadsOutMonths!.clamp(1, 12)
          : null;
      _dealType = booking.dealType;
      _bookingWindowStart = booking.bookingWindowStart;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  void _onSave() {
    if (!_formKey.currentState!.validate()) return;

    final existing = widget.venue.contact;

    final updatedContact = VenueContact(
      name: _nameController.text.trim(),
      phone: _phoneController.text.trim(),
      email: _emailController.text.trim(),
      preferredMethod: _preferredMethod,
      notes: _notesController.text.trim().isEmpty
          ? null
          : _notesController.text.trim(),
      isSharedWithNetwork: _isSharedWithNetwork,
      sharedBy: _isSharedWithNetwork
          ? (existing?.sharedBy ?? widget.currentUserId)
          : null,
      // Preserve timestamps — confirmations handled by repository
      lastConfirmed: existing?.lastConfirmed,
      lastConfirmedBy: existing?.lastConfirmedBy,
      confirmationCount: existing?.confirmationCount ?? 0,
    );

    final bookingInfo = _isSharedWithNetwork
        ? BookingInfo(
      leadsOutMonths: _leadsOutMonths,
      dealType: _dealType,
      bookingWindowStart: _bookingWindowStart,
    )
        : null;

    Navigator.of(context).pop(
      VenueContactSaveResult(contact: updatedContact, bookingInfo: bookingInfo),
    );
  }

  String get _dialogTitle {
    final base = 'Contact — ${widget.venue.name}';
    return _isSharedWithNetwork ? '$base  |  Shared' : base;
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AlertDialog(
      title: AnimatedSwitcher(
        duration: const Duration(milliseconds: 200),
        child: Text(
          _dialogTitle,
          key: ValueKey(_isSharedWithNetwork),
          style: theme.textTheme.titleLarge,
        ),
      ),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Core contact fields ────────────────────────────────────
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
                  if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(value)) {
                    return 'Please enter a valid email address';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 20),

              // ── Preferred contact method ───────────────────────────────
              _buildPreferredMethodRow(theme),
              const SizedBox(height: 20),

              // ── Notes ─────────────────────────────────────────────────
              TextFormField(
                controller: _notesController,
                decoration: const InputDecoration(
                  labelText: 'Notes',
                  hintText: 'e.g., "Daisy took over from Ed in March. Text first."',
                  icon: Icon(Icons.notes_outlined),
                  alignLabelWithHint: true,
                  border: OutlineInputBorder(),
                  helperText: 'Booking quirks, handoffs, anything useful',
                  helperMaxLines: 1,
                ),
                maxLines: 3,
                textCapitalization: TextCapitalization.sentences,
              ),
              const SizedBox(height: 20),

              // ── Share toggle + community fields (connected users only) ─
              if (widget.isConnected) ...[
                _buildShareToggle(theme),
                AnimatedSize(
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeInOut,
                  child: _isSharedWithNetwork
                      ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 12),
                      _buildDealTypeBox(theme),
                      const SizedBox(height: 12),
                      _buildBookingWindowBox(theme),
                    ],
                  )
                      : const SizedBox(width: double.infinity),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('CANCEL'),
        ),
        ElevatedButton(
          onPressed: _onSave,
          child: const Text('SAVE CONTACT'),
        ),
      ],
    );
  }

  // ── Sub-widgets ───────────────────────────────────────────────────────────

  Widget _buildPreferredMethodRow(ThemeData theme) {
    const methods = [
      ('text',  'Text',  Icons.sms_outlined),
      ('call',  'Call',  Icons.phone_outlined),
      ('email', 'Email', Icons.email_outlined),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Preferred Contact',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: methods.map((rec) {
            final isSelected = _preferredMethod == rec.$1;
            return ChoiceChip(
              avatar: Icon(
                rec.$3,
                size: 16,
                color: isSelected
                    ? theme.colorScheme.onPrimary
                    : theme.colorScheme.onSurface,
              ),
              label: Text(rec.$2),
              selected: isSelected,
              selectedColor: theme.colorScheme.primary,
              labelStyle: TextStyle(
                color: isSelected
                    ? theme.colorScheme.onPrimary
                    : theme.colorScheme.onSurface,
              ),
              onSelected: (_) => setState(() {
                _preferredMethod = isSelected ? null : rec.$1;
              }),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildShareToggle(ThemeData theme) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: theme.dividerColor),
        borderRadius: BorderRadius.circular(8),
      ),
      child: SwitchListTile(
        title: const Text('Share with network'),
        subtitle: const Text('Visible to all community members'),
        value: _isSharedWithNetwork,
        onChanged: (v) => setState(() => _isSharedWithNetwork = v),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        dense: true,
      ),
    );
  }

  // ── Deal Type ─────────────────────────────────────────────────────────────

  Widget _buildDealTypeBox(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: theme.dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Deal Type',
            style: theme.textTheme.titleSmall
                ?.copyWith(color: theme.colorScheme.primary),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            children: [
              ('guarantee', 'Guarantee'),
              ('door',      'Door'),
              ('both',      'Both'),
            ].map((rec) {
              final isSelected = _dealType == rec.$1;
              return ChoiceChip(
                label: Text(rec.$2),
                selected: isSelected,
                selectedColor: theme.colorScheme.primary,
                labelStyle: TextStyle(
                  color: isSelected
                      ? theme.colorScheme.onPrimary
                      : theme.colorScheme.onSurface,
                ),
                onSelected: (_) =>
                    setState(() => _dealType = isSelected ? null : rec.$1),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  // ── Booking Window ────────────────────────────────────────────────────────

  Widget _buildBookingWindowBox(ThemeData theme) {
    final windowLabel = _bookingWindowStart != null
        ? '${_monthName(_bookingWindowStart!.month)} ${_bookingWindowStart!.day}'
        : 'Pick a date';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: theme.dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Booking Window',
            style: theme.textTheme.titleSmall
                ?.copyWith(color: theme.colorScheme.primary),
          ),
          const SizedBox(height: 16),

          // ── Leads out stepper (months) ─────────────────────────────────
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'How far out do they book?',
                style: theme.textTheme.bodyMedium
                    ?.copyWith(fontWeight: FontWeight.w500),
              ),
              if (_leadsOutMonths != null)
                GestureDetector(
                  onTap: () => setState(() => _leadsOutMonths = null),
                  child: Text(
                    'Clear',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.primary,
                      decoration: TextDecoration.underline,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.remove_circle_outline),
                color: theme.colorScheme.primary,
                onPressed: _leadsOutMonths != null && _leadsOutMonths! > 1
                    ? () => setState(() => _leadsOutMonths = _leadsOutMonths! - 1)
                    : null,
              ),
              SizedBox(
                width: 120,
                child: _leadsOutMonths == null
                    ? TextButton(
                  style: TextButton.styleFrom(padding: EdgeInsets.zero),
                  onPressed: () => setState(() => _leadsOutMonths = 1),
                  child: Text(
                    'Tap + to set',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurface
                          .withValues(alpha: 0.4),
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                )
                    : Text(
                  '$_leadsOutMonths '
                      '${_leadsOutMonths == 1 ? 'month' : 'months'} out',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyLarge
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.add_circle_outline),
                color: theme.colorScheme.primary,
                onPressed: _leadsOutMonths == null
                    ? () => setState(() => _leadsOutMonths = 1)
                    : _leadsOutMonths! < 12
                    ? () => setState(
                        () => _leadsOutMonths = _leadsOutMonths! + 1)
                    : null,
              ),
            ],
          ),

          const Divider(height: 28),

          // ── Booking window start date ──────────────────────────────────
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Window opens on',
                style: theme.textTheme.bodyMedium
                    ?.copyWith(fontWeight: FontWeight.w500),
              ),
              if (_bookingWindowStart != null)
                GestureDetector(
                  onTap: () => setState(() => _bookingWindowStart = null),
                  child: Text(
                    'Clear',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.primary,
                      decoration: TextDecoration.underline,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            icon: const Icon(Icons.calendar_month_outlined, size: 18),
            label: Text(windowLabel),
            onPressed: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: _bookingWindowStart ?? DateTime.now(),
                firstDate: DateTime(2000),
                lastDate: DateTime(2100),
                helpText: 'When does booking open?',
              );
              if (picked != null) {
                setState(() => _bookingWindowStart = picked);
              }
            },
          ),

          // ── Computed next window — display only ───────────────────────
          if (_bookingWindowStart != null && _leadsOutMonths != null) ...[
            const SizedBox(height: 12),
            _buildNextWindowPreview(theme),
          ],
        ],
      ),
    );
  }

  // ── Next window preview ───────────────────────────────────────────────────

  Widget _buildNextWindowPreview(ThemeData theme) {
    final now = DateTime.now();
    var candidate = _bookingWindowStart!;
    while (!candidate.isAfter(now)) {
      candidate = DateTime(
        candidate.year,
        candidate.month + _leadsOutMonths!,
        candidate.day,
      );
    }
    final formatted =
        '${_monthName(candidate.month)} ${candidate.day}, ${candidate.year}';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        children: [
          Icon(Icons.event_available_outlined,
              size: 16, color: theme.colorScheme.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Next window: $formatted',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _monthName(int month) => const [
    '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ][month];
}