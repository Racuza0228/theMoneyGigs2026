// lib/features/day_of/day_of_notifier.dart
//
// App-wide "is there a gig today" signal — added 8/26/26 to drive the
// day-of FAB in main.dart (see that file's build() method).
//
// Deliberately a dumb ChangeNotifier that only HOLDS state; it does not
// compute recurrence itself. GigsPage._generateAndSetDisplayedGigs()
// already runs the one correct occurrence-generation pass (weekly/
// biweekly/nth-day/monthly recurring jams + one-off gigs, deduped against
// materialized instances) every time the gigs list loads or refreshes —
// duplicating that math here would just create a second place for the
// two to drift apart. So GigsPage pushes today's soonest gig/jam into
// this notifier as a side effect of its existing pass; main.dart only
// reads it. Because GigsPage's page instance is built immediately at app
// launch (see main.dart's IndexedStack — all 4 tabs are instantiated up
// front, not lazily on tap), this fires without the user needing to open
// My Gigs first.
//
// Multiple gigs today → soonest by start time wins (Cliff confirmed no
// picker is needed for this).

import 'package:flutter/material.dart';
import 'package:the_money_gigs/features/gigs/models/gig_model.dart';

class DayOfNotifier extends ChangeNotifier {
  Gig? _todaysGig;

  Gig? get todaysGig => _todaysGig;
  bool get hasGigToday => _todaysGig != null;

  void setTodaysGig(Gig? gig) {
    // Compare by id, not identity — GigsPage rebuilds fresh Gig objects on
    // every pass, so an identical day would otherwise notify listeners
    // (and rebuild main.dart's whole Scaffold) on every unrelated refresh.
    if (gig?.id == _todaysGig?.id) return;
    _todaysGig = gig;
    notifyListeners();
  }
}
