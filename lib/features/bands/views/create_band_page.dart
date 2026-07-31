// lib/features/bands/views/create_band_page.dart
//
// Band/Project Expansion v3.0.0 — Sprint Task 5
//
// Full-screen pushed page rather than a dialog — there's a band name field
// plus an open-ended list of members, each with four fields, which is too
// much content for a modal AlertDialog.
//
// No FAB entry point: this app has no FloatingActionButton anywhere (checked
// gigs.dart and main.dart — "Add New Gig" is an AppBar IconButton, and the
// Insights/Export actions on the gigs tab are inline OutlinedButtons). Spec
// section 3 says "a '+' FAB on My Bands," but adding the app's first-ever FAB
// for one screen would be visually inconsistent, so this is launched from an
// inline "+ Create Band" button on MyBandsTab instead, matching how the app
// already does it elsewhere.
//
// The member-row form (name/email/phone/instruments + network-status check)
// lives in widgets/member_entry_form.dart, shared with Band Detail's Add
// Member flow (Task 6) — see that file for why the instrument list is a
// duplicate of tags_widget.dart's rather than an import.

import 'package:flutter/material.dart';
import 'package:the_money_gigs/core/utils/logger.dart';
import '../models/band_model.dart';
import '../repositories/band_repository.dart';
import 'widgets/member_entry_form.dart';

class CreateBandPage extends StatefulWidget {
  final String leaderId;

  const CreateBandPage({super.key, required this.leaderId});

  @override
  State<CreateBandPage> createState() => _CreateBandPageState();
}

class _CreateBandPageState extends State<CreateBandPage> {
  final BandRepository _bandRepository = BandRepository();
  final TextEditingController _bandNameController = TextEditingController();
  final List<MemberDraft> _memberDrafts = [MemberDraft()];
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    for (final draft in _memberDrafts) {
      _attachListener(draft);
    }
  }

  @override
  void dispose() {
    _bandNameController.dispose();
    for (final draft in _memberDrafts) {
      draft.dispose();
    }
    super.dispose();
  }

  void _attachListener(MemberDraft draft) {
    attachNetworkStatusListener(
      draft: draft,
      leaderId: widget.leaderId,
      bandRepository: _bandRepository,
      setState: setState,
      isMounted: () => mounted,
    );
  }

  void _addMemberRow() {
    setState(() {
      final draft = MemberDraft();
      _attachListener(draft);
      _memberDrafts.add(draft);
    });
  }

  void _removeMemberRow(MemberDraft draft) {
    setState(() {
      _memberDrafts.remove(draft);
    });
    draft.dispose();
  }

  Future<void> _saveBand() async {
    final bandName = _bandNameController.text.trim();
    if (bandName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Band name is required.')),
      );
      return;
    }

    // Only rows the leader actually filled in count as real members —
    // blank trailing rows (e.g. the default first row, left untouched) are
    // silently skipped rather than blocking save.
    final members = <BandMember>[];
    for (final draft in _memberDrafts) {
      if (draft.isBlank) continue;

      final name = draft.nameController.text.trim();
      final email = draft.emailController.text.trim();
      if (name.isEmpty || email.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Each member needs both a name and an email.'),
          ),
        );
        return;
      }

      members.add(BandMember(
        localId: draft.localId,
        name: name,
        email: email,
        phone: draft.phoneController.text.trim().isEmpty
            ? null
            : draft.phoneController.text.trim(),
        instruments: draft.instruments.toList(),
        networkMemberId: draft.networkMemberId,
        status: draft.networkMemberId != null ? 'active' : 'invited',
      ));
    }

    setState(() {
      _isSaving = true;
    });

    final band = await _bandRepository.createBand(
      name: bandName,
      leaderId: widget.leaderId,
      initialMembers: members,
    );

    if (!mounted) return;
    setState(() {
      _isSaving = false;
    });

    if (band == null) {
      log('❌ createBand returned null for "$bandName"');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not create the band. Try again.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // Pop the created BandProject itself, not just `true` — callers that
    // need to act on the new band (e.g. the booking dialog auto-selecting
    // it) shouldn't have to re-fetch immediately after creation.
    Navigator.of(context).pop(band);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Create Band')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _bandNameController,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Band / Project name',
              hintText: "e.g. 'Hat Trick'",
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 24),
          Text('Members', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          ..._memberDrafts.map((draft) => MemberDraftCard(
            key: ValueKey(draft.localId),
            draft: draft,
            onRemove: _memberDrafts.length > 1
                ? () => _removeMemberRow(draft)
                : null,
          )),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            icon: const Icon(Icons.person_add_alt),
            label: const Text('Add Member'),
            onPressed: _addMemberRow,
          ),
          const SizedBox(height: 32),
          ElevatedButton(
            onPressed: _isSaving ? null : _saveBand,
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            child: _isSaving
                ? const SizedBox(
              height: 20,
              width: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
                : const Text('Save Band'),
          ),
        ],
      ),
    );
  }
}
