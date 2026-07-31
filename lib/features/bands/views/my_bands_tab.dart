// lib/features/bands/views/my_bands_tab.dart
//
// Band/Project Expansion v3.0.0 — Sprint Task 4
//
// Presentational tab, same shape as VenuesListTab: GigsPage owns loading /
// fetching state and passes data + callbacks down. Standalone (non-network)
// users see a gate banner instead of the list — mirrors the gate pattern in
// venue_details_page.dart, same grey/lock-icon treatment.
//
// "+ Create Band" (Task 5) is an inline OutlinedButton, not a FAB — this app
// has no FloatingActionButton anywhere ("Add New Gig" is an AppBar
// IconButton), so a FAB here would be the odd one out visually. See
// create_band_page.dart's header comment for the full reasoning.
//
// Tapping a band card navigates to Band Detail (Task 6) via the
// onBandTapped callback — GigsPage owns navigation, same as onVenueTapped.

import 'package:flutter/material.dart';
import '../models/band_model.dart';

class MyBandsTab extends StatelessWidget {
  final bool isLoading;
  final bool isConnected;
  final List<BandProject> bands;
  final String currentUserId;
  final VoidCallback onCreateBand;
  final void Function(BandProject) onBandTapped;

  const MyBandsTab({
    super.key,
    required this.isLoading,
    required this.isConnected,
    required this.bands,
    required this.currentUserId,
    required this.onCreateBand,
    required this.onBandTapped,
  });

  @override
  Widget build(BuildContext context) {
    if (!isConnected) {
      return _buildUpgradeGate(context);
    }

    if (isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Create Band'),
              onPressed: onCreateBand,
            ),
          ),
        ),
        Expanded(
          child: bands.isEmpty
              ? _buildEmptyState(context)
              : ListView.builder(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            itemCount: bands.length,
            itemBuilder: (context, index) {
              final band = bands[index];
              return _BandCard(
                band: band,
                isLeader: band.isLeader(currentUserId),
                onTap: () => onBandTapped(band),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildUpgradeGate(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.grey.shade900,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.grey.shade700),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.lock_outline, color: Colors.grey.shade400, size: 20),
              const SizedBox(width: 12),
              Flexible(
                child: Text(
                  'Upgrade to the Network Edition to manage your bands and projects.',
                  style: TextStyle(color: Colors.grey.shade400, fontSize: 14),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.groups_outlined, size: 48, color: Colors.grey.shade600),
            const SizedBox(height: 12),
            Text(
              'No bands yet.',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              'Tap "Create Band" above to add your first one.',
              style: TextStyle(color: Colors.grey.shade500, fontSize: 13),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _BandCard extends StatelessWidget {
  final BandProject band;
  final bool isLeader;
  final VoidCallback onTap;

  const _BandCard({
    required this.band,
    required this.isLeader,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        leading: const Icon(Icons.groups),
        title: Text(
          band.name,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text(
          '${band.memberCount} member${band.memberCount == 1 ? '' : 's'}',
        ),
        trailing: Chip(
          label: Text(isLeader ? 'Leader' : 'Member'),
          backgroundColor: isLeader
              ? Theme.of(context).colorScheme.primaryContainer
              : Colors.grey.shade800,
          labelStyle: TextStyle(
            fontSize: 12,
            color: isLeader
                ? Theme.of(context).colorScheme.onPrimaryContainer
                : Colors.grey.shade300,
          ),
        ),
        onTap: onTap,
      ),
    );
  }
}
