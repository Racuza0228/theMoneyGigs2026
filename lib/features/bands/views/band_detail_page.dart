// lib/features/bands/views/band_detail_page.dart
//
// Band/Project Expansion v3.0.0 — Sprint Task 6
//
// Renders instantly from the BandProject the caller already has (from the
// My Bands list), then kicks off a background refetch so the screen isn't
// blank while loading but also isn't stale if something changed elsewhere.
//
// Rename / add member / remove member are gated to the band's leader.
// Not explicitly called out in the spec's one-line Task 6 description, but
// consistent with the leader/member distinction confirmed earlier: a plain
// member viewing this screen shouldn't be able to rename the band or manage
// its roster.

import 'package:flutter/material.dart';
import 'package:the_money_gigs/core/utils/logger.dart';
import '../models/band_model.dart';
import '../repositories/band_repository.dart';
import 'widgets/add_member_dialog.dart';

class BandDetailPage extends StatefulWidget {
  final BandProject initialBand;
  final String currentUserId;

  const BandDetailPage({
    super.key,
    required this.initialBand,
    required this.currentUserId,
  });

  @override
  State<BandDetailPage> createState() => _BandDetailPageState();
}

class _BandDetailPageState extends State<BandDetailPage> {
  final BandRepository _bandRepository = BandRepository();
  late BandProject _band;
  bool _isBusy = false;

  bool get _isLeader => _band.isLeader(widget.currentUserId);

  @override
  void initState() {
    super.initState();
    _band = widget.initialBand;
    _refresh(); // background — don't block first paint on it
  }

  Future<void> _refresh() async {
    final fresh = await _bandRepository.getBand(_band.bandId);
    if (!mounted || fresh == null) return;
    setState(() {
      _band = fresh;
    });
  }

  Future<void> _renameBand() async {
    final controller = TextEditingController(text: _band.name);
    final newName = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Rename Band'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Band / Project name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (newName == null || newName.isEmpty || newName == _band.name) return;

    setState(() => _isBusy = true);
    final success = await _bandRepository.renameBand(
      bandId: _band.bandId,
      newName: newName,
    );
    if (!mounted) return;
    setState(() => _isBusy = false);

    if (success) {
      setState(() {
        _band = _band.copyWith(name: newName);
      });
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not rename the band. Try again.'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _addMember() async {
    final newMember = await showAddMemberDialog(
      context: context,
      leaderId: _band.leaderId,
      bandRepository: _bandRepository,
    );
    if (newMember == null) return;

    setState(() => _isBusy = true);
    final success = await _bandRepository.addMember(
      bandId: _band.bandId,
      member: newMember,
    );
    if (!mounted) return;
    setState(() => _isBusy = false);

    if (success) {
      await _refresh();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not add that member. Try again.'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _removeMember(BandMember member) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Remove Member'),
        content: Text('Remove ${member.name} from ${_band.name}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.errorContainer,
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _isBusy = true);
    final success = await _bandRepository.removeMember(
      bandId: _band.bandId,
      memberLocalId: member.localId,
    );
    if (!mounted) return;
    setState(() => _isBusy = false);

    if (success) {
      await _refresh();
    } else {
      log('❌ removeMember failed for ${member.localId}');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not remove that member. Try again.'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_band.name),
        actions: [
          if (_isLeader)
            IconButton(
              icon: const Icon(Icons.edit),
              tooltip: 'Rename band',
              onPressed: _isBusy ? null : _renameBand,
            ),
        ],
      ),
      body: Column(
        children: [
          if (_isBusy) const LinearProgressIndicator(minHeight: 2),
          Expanded(
            child: _band.members.isEmpty
                ? Center(
              child: Text(
                'No members yet.',
                style: TextStyle(color: Colors.grey.shade500),
              ),
            )
                : ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: _band.members.length,
              itemBuilder: (context, index) {
                final member = _band.members[index];
                return _MemberTile(
                  member: member,
                  canRemove: _isLeader,
                  onRemove: () => _removeMember(member),
                );
              },
            ),
          ),
          if (_isLeader)
            Padding(
              padding: const EdgeInsets.all(12),
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.person_add_alt),
                  label: const Text('Add Member'),
                  onPressed: _isBusy ? null : _addMember,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _MemberTile extends StatelessWidget {
  final BandMember member;
  final bool canRemove;
  final VoidCallback onRemove;

  const _MemberTile({
    required this.member,
    required this.canRemove,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final isActive = member.isActive;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        leading: CircleAvatar(
          child: Text(
            member.name.isNotEmpty ? member.name[0].toUpperCase() : '?',
          ),
        ),
        title: Text(member.name),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(member.email),
            if (member.phone != null) Text(member.phone!),
            if (member.instruments.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Wrap(
                  spacing: 4,
                  children: member.instruments
                      .map((i) => Chip(
                    label: Text(i, style: const TextStyle(fontSize: 11)),
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                  ))
                      .toList(),
                ),
              ),
          ],
        ),
        isThreeLine: member.instruments.isNotEmpty || member.phone != null,
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Chip(
              label: Text(isActive ? 'Active' : 'Invited'),
              backgroundColor: isActive
                  ? Colors.green.withValues(alpha: 0.2)
                  : Colors.grey.withValues(alpha: 0.2),
              labelStyle: TextStyle(
                fontSize: 11,
                color: isActive ? Colors.green : Colors.grey,
              ),
            ),
            if (canRemove)
              IconButton(
                icon: const Icon(Icons.close, size: 18),
                tooltip: 'Remove',
                onPressed: onRemove,
              ),
          ],
        ),
      ),
    );
  }
}
