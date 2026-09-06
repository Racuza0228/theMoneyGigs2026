// lib/features/day_of/day_of_screen.dart
//
// The day-of-gig networking screen — added 8/26/26, opened from the center
// FAB in main.dart on days there's a gig/jam on the calendar (see
// day_of_notifier.dart for how that FAB decides to show itself).
//
// Prototyped against the jam/open-mic workflow first, per Cliff's request:
// for a jam occurrence this shows the venue/session basics plus full
// Contacts CRUD. For a real paid gig it's the same Contacts CRUD (meeting
// people to network with isn't jam-specific) but the info pane above it is
// a placeholder for now — building that out is a later pass, not this one.
//
// Contacts are the GLOBAL address book (ContactRepository — local-only,
// SharedPreferences), not scoped to this gig. metAtGigId just tags where a
// contact was first met so this screen can filter to "people I met here" —
// see contact_model.dart's header.

import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import 'package:intl/intl.dart';
import 'package:the_money_gigs/core/models/person_model.dart';
import 'package:the_money_gigs/features/contacts/models/contact_model.dart';
import 'package:the_money_gigs/features/contacts/repositories/contact_repository.dart';
import 'package:the_money_gigs/features/gigs/models/gig_model.dart';
import 'package:the_money_gigs/features/bands/views/widgets/member_entry_form.dart'
    show kSuggestedInstruments;

class DayOfScreen extends StatefulWidget {
  final Gig gig;

  const DayOfScreen({super.key, required this.gig});

  @override
  State<DayOfScreen> createState() => _DayOfScreenState();
}

class _DayOfScreenState extends State<DayOfScreen> {
  final ContactRepository _contactRepository = ContactRepository();
  List<Contact> _contacts = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadContacts();
  }

  Future<void> _loadContacts() async {
    final contacts = await _contactRepository.getForGig(widget.gig.id);
    contacts.sort((a, b) => a.name.compareTo(b.name));
    if (!mounted) return;
    setState(() {
      _contacts = contacts;
      _isLoading = false;
    });
  }

  // Display-cleaned venue name — _generateAndSetDisplayedGigs() (gigs.dart)
  // prepends '[JAM]'/'[PRIVATE]' tags and appends notes for the My Gigs list
  // tile; this screen already shows session type and notes in their own
  // rows, so strip those back off here instead of showing them twice.
  String get _cleanVenueName {
    String name = widget.gig.venueName;
    name = name.replaceFirst('[PRIVATE] ', '');
    if (name.startsWith('[JAM] ')) {
      name = name.substring(6);
      final parenIndex = name.indexOf(' (');
      if (parenIndex != -1) name = name.substring(0, parenIndex);
    }
    return name;
  }

  Future<void> _openContactDialog({Contact? existing}) async {
    final result = await showDialog<Contact>(
      context: context,
      builder: (_) => _ContactDialog(existing: existing, gig: widget.gig),
    );
    if (result == null) return;
    if (existing == null) {
      await _contactRepository.add(result);
    } else {
      await _contactRepository.update(result);
    }
    await _loadContacts();
  }

  Future<void> _deleteContact(Contact contact) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete contact?'),
        content: Text('Remove ${contact.name} from your contacts.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _contactRepository.delete(contact.localId);
    await _loadContacts();
  }

  @override
  Widget build(BuildContext context) {
    final gig = widget.gig;
    return Scaffold(
      appBar: AppBar(title: const Text('Day of the Gig')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _buildInfoCard(gig),
                const SizedBox(height: 20),
                Text('People you\'ve met here',
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                if (_contacts.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      'No contacts yet. Tap + to add someone you meet today.',
                      style: TextStyle(color: Colors.grey),
                    ),
                  )
                else
                  ..._contacts.map((c) => Card(
                        child: ListTile(
                          leading: Icon(
                            c.isMusician
                                ? Icons.music_note
                                : Icons.favorite_border,
                            color: Colors.grey,
                          ),
                          title: Text(c.name),
                          subtitle: Text([
                            if (!c.isMusician) 'Fan',
                            if (c.instruments.isNotEmpty)
                              c.instruments.join(', '),
                            if (c.phone?.isNotEmpty ?? false) c.phone!,
                            if (c.email?.isNotEmpty ?? false) c.email!,
                          ].where((s) => s.isNotEmpty).join(' • ')),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.edit, size: 20),
                                tooltip: 'Edit',
                                onPressed: () =>
                                    _openContactDialog(existing: c),
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete_outline,
                                    size: 20),
                                tooltip: 'Delete',
                                onPressed: () => _deleteContact(c),
                              ),
                            ],
                          ),
                        ),
                      )),
              ],
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _openContactDialog(),
        tooltip: 'Add contact',
        child: const Icon(Icons.person_add),
      ),
    );
  }

  Widget _buildInfoCard(Gig gig) {
    final dateLabel = DateFormat('EEEE, MMM d • h:mm a').format(gig.dateTime);
    if (!gig.isJamOpenMic) {
      // Real-gig info pane — placeholder for now (see file header). The
      // Contacts section above still fully works on a paying-gig day.
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_cleanVenueName,
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 4),
              Text(dateLabel, style: const TextStyle(color: Colors.grey)),
              const SizedBox(height: 12),
              const Text(
                'Full gig-day info is coming soon — for now, use the + '
                'button below to log who you meet.',
                style: TextStyle(color: Colors.grey),
              ),
            ],
          ),
        ),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.mic_external_on,
                    color: Colors.deepOrange.shade400, size: 20),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(_cleanVenueName,
                      style: Theme.of(context).textTheme.titleLarge),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(dateLabel, style: const TextStyle(color: Colors.grey)),
            if (gig.address.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(gig.address, style: const TextStyle(color: Colors.grey)),
            ],
            if (gig.notes?.isNotEmpty ?? false) ...[
              const SizedBox(height: 8),
              Text('Style/notes: ${gig.notes}'),
            ],
          ],
        ),
      ),
    );
  }
}

/// Add/edit dialog for one Contact. Returns the built Contact via
/// Navigator.pop, or null if cancelled.
class _ContactDialog extends StatefulWidget {
  final Contact? existing;
  final Gig gig;

  const _ContactDialog({this.existing, required this.gig});

  @override
  State<_ContactDialog> createState() => _ContactDialogState();
}

class _ContactDialogState extends State<_ContactDialog> {
  late final TextEditingController _nameController;
  late final TextEditingController _phoneController;
  late final TextEditingController _emailController;
  late final TextEditingController _styleController;
  late final Set<String> _instruments;
  late bool _isMusician;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _nameController = TextEditingController(text: existing?.name ?? '');
    _phoneController = TextEditingController(text: existing?.phone ?? '');
    _emailController = TextEditingController(text: existing?.email ?? '');
    _styleController = TextEditingController(text: existing?.style ?? '');
    _instruments = {...?existing?.instruments};
    // Editing an existing contact keeps whatever it already was. A brand
    // new one defaults off the gig's own type — most people you meet at a
    // jam are musicians; a regular paying gig is more likely where you're
    // starting a fan/audience contact instead. Either way it's just a
    // starting guess — the toggle below is right there to flip it.
    _isMusician = existing?.isMusician ?? widget.gig.isJamOpenMic;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _styleController.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Name is required.')),
      );
      return;
    }

    final existing = widget.existing;
    final person = Person(
      localId: existing?.localId ?? const Uuid().v4(),
      name: name,
      email: _emailController.text.trim().isEmpty
          ? null
          : _emailController.text.trim(),
      phone: _phoneController.text.trim().isEmpty
          ? null
          : _phoneController.text.trim(),
      // Instrument chips are hidden (not just disabled) when the musician
      // toggle is off — force the field itself empty here too, so flipping
      // the toggle off actually clears a previous musician-mode selection
      // instead of silently keeping it around unseen.
      instruments: _isMusician ? _instruments.toList() : const [],
    );

    Navigator.of(context).pop(Contact(
      person: person,
      isMusician: _isMusician,
      style: !_isMusician || _styleController.text.trim().isEmpty
          ? null
          : _styleController.text.trim(),
      metAtVenueName: existing?.metAtVenueName ?? widget.gig.venueName,
      metAtPlaceId: existing?.metAtPlaceId ?? widget.gig.placeId,
      metAtGigId: existing?.metAtGigId ?? widget.gig.id,
      metAtDate: existing?.metAtDate,
      deviceContactId: existing?.deviceContactId,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.existing == null ? 'Add Contact' : 'Edit Contact'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(labelText: 'Name'),
            ),
            TextField(
              controller: _phoneController,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(labelText: 'Phone (optional)'),
            ),
            TextField(
              controller: _emailController,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(labelText: 'Email (optional)'),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Musician'),
              subtitle: const Text(
                'Off = just a contact (e.g. a fan) — no style/instrument.',
                style: TextStyle(fontSize: 12),
              ),
              value: _isMusician,
              onChanged: (value) => setState(() => _isMusician = value),
            ),
            if (_isMusician) ...[
              TextField(
                controller: _styleController,
                decoration:
                    const InputDecoration(labelText: 'Style/genre (optional)'),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: kSuggestedInstruments.map((instrument) {
                  final selected = _instruments.contains(instrument);
                  return FilterChip(
                    label:
                        Text(instrument, style: const TextStyle(fontSize: 12)),
                    selected: selected,
                    onSelected: (isSelected) {
                      setState(() {
                        if (isSelected) {
                          _instruments.add(instrument);
                        } else {
                          _instruments.remove(instrument);
                        }
                      });
                    },
                  );
                }).toList(),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _submit,
          child: Text(widget.existing == null ? 'Add' : 'Save'),
        ),
      ],
    );
  }
}
