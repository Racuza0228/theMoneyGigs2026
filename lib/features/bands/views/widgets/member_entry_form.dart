// lib/features/bands/views/widgets/member_entry_form.dart
//
// Band/Project Expansion v3.0.0 — shared between Task 5 (Create Band) and
// Task 6 (Band Detail's Add Member). Extracted here instead of living
// privately in create_band_page.dart so Band Detail doesn't have to
// reimplement the same name/email/phone/instruments + network-status-check
// row.
//
// Instrument suggestions are duplicated from tags_widget.dart's
// _suggestedInstruments (a private field on _TagsWidgetState, not exported)
// rather than imported. If that list is ever promoted to a shared constant,
// this should switch to importing it instead of carrying its own copy — this
// is now the ONE copy shared by both band screens, not a second duplicate.

import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../../repositories/band_repository.dart';

const List<String> kSuggestedInstruments = [
  'Vocals', 'Acoustic Guitar', 'Electric Guitar', 'Bass Guitar', 'Drums',
  'Percussion', 'Keyboard', 'Piano', 'Saxophone', 'Trumpet', 'Violin', 'Cello'
];

/// One in-progress member row. Not a BandMember yet — holds live UI /
/// network-check state until the caller reads it out.
class MemberDraft {
  final String localId;
  final TextEditingController nameController = TextEditingController();
  final TextEditingController emailController = TextEditingController();
  final TextEditingController phoneController = TextEditingController();
  final FocusNode emailFocusNode = FocusNode();
  final Set<String> instruments = {};

  bool isCheckingNetwork = false;
  String? networkMemberId; // set once a match is found
  bool alreadyInLeadersBands = false; // spec section 8's third state

  MemberDraft({String? localId}) : localId = localId ?? const Uuid().v4();

  bool get isBlank =>
      nameController.text.trim().isEmpty && emailController.text.trim().isEmpty;

  void dispose() {
    nameController.dispose();
    emailController.dispose();
    phoneController.dispose();
    emailFocusNode.dispose();
  }
}

/// Wires up the email-blur network-status lookup (spec section 8) for a
/// [MemberDraft]. Call once, right after creating the draft.
void attachNetworkStatusListener({
  required MemberDraft draft,
  required String leaderId,
  required BandRepository bandRepository,
  required void Function(void Function()) setState,
  required bool Function() isMounted,
}) {
  draft.emailFocusNode.addListener(() async {
    if (draft.emailFocusNode.hasFocus) return; // only fires on blur
    final email = draft.emailController.text.trim();
    if (email.isEmpty || !email.contains('@')) return;

    setState(() {
      draft.isCheckingNetwork = true;
    });

    final networkMemberId = await bandRepository.checkNetworkStatusForEmail(email);
    bool alreadyInLeadersBands = false;
    if (networkMemberId != null) {
      alreadyInLeadersBands = await bandRepository.isEmailInLeadersBands(
        leaderId: leaderId,
        email: email,
      );
    }

    if (!isMounted()) return;
    setState(() {
      draft.networkMemberId = networkMemberId;
      draft.alreadyInLeadersBands = alreadyInLeadersBands;
      draft.isCheckingNetwork = false;
    });
  });
}

/// The name/email/phone/instruments card for one [MemberDraft]. Manages its
/// own chip-selection and network-status-badge repaints; the parent only
/// needs to rebuild when a row is added/removed.
class MemberDraftCard extends StatefulWidget {
  final MemberDraft draft;
  final VoidCallback? onRemove;

  const MemberDraftCard({super.key, required this.draft, this.onRemove});

  @override
  State<MemberDraftCard> createState() => _MemberDraftCardState();
}

class _MemberDraftCardState extends State<MemberDraftCard> {
  @override
  Widget build(BuildContext context) {
    final draft = widget.draft;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: draft.nameController,
                    decoration: const InputDecoration(labelText: 'Name'),
                  ),
                ),
                if (widget.onRemove != null)
                  IconButton(
                    icon: const Icon(Icons.close, size: 20),
                    tooltip: 'Remove member',
                    onPressed: widget.onRemove,
                  ),
              ],
            ),
            TextField(
              controller: draft.emailController,
              focusNode: draft.emailFocusNode,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(labelText: 'Email'),
              onChanged: (_) {
                // Clear a stale match if the leader edits the email again
                // after a lookup already ran.
                if (draft.networkMemberId != null) {
                  setState(() {
                    draft.networkMemberId = null;
                    draft.alreadyInLeadersBands = false;
                  });
                }
              },
            ),
            if (draft.isCheckingNetwork)
              const Padding(
                padding: EdgeInsets.only(top: 4),
                child: Text('Checking...',
                    style: TextStyle(fontSize: 12, color: Colors.grey)),
              )
            else if (draft.networkMemberId != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Row(
                  children: [
                    const Icon(Icons.check_circle, size: 14, color: Colors.green),
                    const SizedBox(width: 4),
                    Text(
                      draft.alreadyInLeadersBands
                          ? 'Already in your network'
                          : 'Already on MoneyGigs ✓',
                      style: const TextStyle(fontSize: 12, color: Colors.green),
                    ),
                  ],
                ),
              ),
            TextField(
              controller: draft.phoneController,
              keyboardType: TextInputType.phone,
              decoration:
              const InputDecoration(labelText: 'Phone (optional)'),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: kSuggestedInstruments.map((instrument) {
                final selected = draft.instruments.contains(instrument);
                return FilterChip(
                  label: Text(instrument, style: const TextStyle(fontSize: 12)),
                  selected: selected,
                  onSelected: (isSelected) {
                    setState(() {
                      if (isSelected) {
                        draft.instruments.add(instrument);
                      } else {
                        draft.instruments.remove(instrument);
                      }
                    });
                  },
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }
}
