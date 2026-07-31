// lib/features/bands/views/widgets/add_member_dialog.dart
//
// Band/Project Expansion v3.0.0 — Sprint Task 6
//
// A single-member version of Create Band's member row, shown as a dialog
// (adding one person to an existing band is a lighter action than the
// multi-member Create Band flow, so a modal fits here where it didn't there).
// Returns a BandMember via Navigator.pop, or null if cancelled.

import 'package:flutter/material.dart';
import '../../models/band_model.dart';
import '../../repositories/band_repository.dart';
import 'member_entry_form.dart';

Future<BandMember?> showAddMemberDialog({
  required BuildContext context,
  required String leaderId,
  required BandRepository bandRepository,
}) {
  return showDialog<BandMember>(
    context: context,
    builder: (_) => _AddMemberDialog(
      leaderId: leaderId,
      bandRepository: bandRepository,
    ),
  );
}

class _AddMemberDialog extends StatefulWidget {
  final String leaderId;
  final BandRepository bandRepository;

  const _AddMemberDialog({
    required this.leaderId,
    required this.bandRepository,
  });

  @override
  State<_AddMemberDialog> createState() => _AddMemberDialogState();
}

class _AddMemberDialogState extends State<_AddMemberDialog> {
  late final MemberDraft _draft;

  @override
  void initState() {
    super.initState();
    _draft = MemberDraft();
    attachNetworkStatusListener(
      draft: _draft,
      leaderId: widget.leaderId,
      bandRepository: widget.bandRepository,
      setState: setState,
      isMounted: () => mounted,
    );
  }

  @override
  void dispose() {
    _draft.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _draft.nameController.text.trim();
    final email = _draft.emailController.text.trim();
    if (name.isEmpty || email.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Name and email are both required.')),
      );
      return;
    }

    Navigator.of(context).pop(BandMember(
      localId: _draft.localId,
      name: name,
      email: email,
      phone: _draft.phoneController.text.trim().isEmpty
          ? null
          : _draft.phoneController.text.trim(),
      instruments: _draft.instruments.toList(),
      networkMemberId: _draft.networkMemberId,
      status: _draft.networkMemberId != null ? 'active' : 'invited',
    ));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add Member'),
      content: SingleChildScrollView(
        child: MemberDraftCard(draft: _draft),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _submit,
          child: const Text('Add'),
        ),
      ],
    );
  }
}
