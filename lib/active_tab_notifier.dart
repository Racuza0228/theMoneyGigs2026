// lib/active_tab_notifier.dart
//
// Tracks which bottom-nav tab is currently visible (0=Map, 1=Gig Calculator,
// 2=My Gigs, 3=Profile). Tabs are built eagerly and kept alive in an
// IndexedStack, so widgets can't rely on their own initState/build to know
// whether they're actually on screen. Expensive per-tab work (e.g. the
// Ticketmaster impact-event lookups on the My Gigs tab) should gate on this
// instead of firing unconditionally at construction time.
import 'package:flutter/material.dart';

final ValueNotifier<int> activeTabIndexNotifier = ValueNotifier<int>(0);
