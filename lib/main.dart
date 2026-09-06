// lib/main.dart
import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:url_launcher/url_launcher.dart'; // ✅ Added for email support
import 'package:the_money_gigs/core/utils/logger.dart';

import 'firebase_options.dart';
import 'core/services/analytics_service.dart';
import 'core/services/app_update_service.dart';
import 'core/services/notification_service.dart';
import 'core/services/revenuecat_gate.dart';
import 'features/app_demo/providers/demo_provider.dart';
// ✅ NEW: Use the simplified onboarding flow
import 'features/app_demo/widgets/onboarding_flow.dart';
import 'features/gigs/views/gig_calculator_page.dart';
// ✅ MOVED: Map is now the primary tab (index 0)
import 'features/map_venues/views/map.dart';
import 'features/gigs/views/gigs.dart';
import 'features/profile/views/profile.dart';
import 'core/widgets/page_background_wrapper.dart';
import 'global_refresh_notifier.dart';
import 'active_tab_notifier.dart';
import 'features/gigs/widgets/booking_dialog.dart';
import 'features/gigs/models/gig_model.dart';
import 'features/gigs/services/gig_retrospective_service.dart';
import 'features/gigs/widgets/retrospective_notification_banner.dart';
import 'package:upgrader/upgrader.dart';
import 'features/gigs/services/auto_backup_service.dart';
import 'package:the_money_gigs/features/app_demo/widgets/invite_code_reentry_dialog.dart';
import 'features/day_of/day_of_notifier.dart';
import 'features/day_of/day_of_screen.dart';

/// Holds the most recent captured error + stack so the in-app crash screen
/// can offer to email it to Cliff. Set by the global error handlers in main().
String? lastCapturedError;

void main() {
  // Run the entire startup inside a guarded zone. Any error that would
  // previously escape main() and SIGTRAP the app on launch now lands in
  // the handler below and the app keeps running.
  runZonedGuarded<Future<void>>(() async {
    final binding = WidgetsFlutterBinding.ensureInitialized();

    // Replace Flutter's default red/grey crash box with a friendly screen
    // that lets the user email the details straight to Cliff.
    ErrorWidget.builder = (FlutterErrorDetails details) {
      lastCapturedError =
      '${details.exceptionAsString()}\n\n${details.stack ?? ''}';
      return FriendlyErrorScreen(details: lastCapturedError!);
    };

    // Framework (widget) errors.
    FlutterError.onError = (FlutterErrorDetails details) {
      lastCapturedError =
      '${details.exceptionAsString()}\n\n${details.stack ?? ''}';
      FlutterError.presentError(details);
      log('🔥 FlutterError: ${details.exceptionAsString()}');
      // Ship it off-device. Guarded so a pre-Firebase-init error can't throw
      // here and defeat your keep-alive design.
      try {
        FirebaseCrashlytics.instance.recordFlutterError(details);
      } catch (_) {}
    };

    // Engine/platform + uncaught async errors. Returning true = "handled,
    // don't crash."
    binding.platformDispatcher.onError = (Object error, StackTrace stack) {
      lastCapturedError = '$error\n\n$stack';
      log('🔥 Platform error (handled, not crashing): $error\n$stack');
      try {
        FirebaseCrashlytics.instance.recordError(error, stack, fatal: false);
      } catch (_) {}
      return true;
    };

    await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

    // Firebase — never let init failure abort the launch.
    try {
      await Firebase.initializeApp(
          options: DefaultFirebaseOptions.currentPlatform);
      log('✅ Firebase Initialized');
      // Collect on every build, debug included, so you can test the wiring
      // now and still get Dad's and Iqui's real crashes in production.
      await FirebaseCrashlytics.instance
          .setCrashlyticsCollectionEnabled(true);
    } catch (e, s) {
      log('❌ Firebase init failed — continuing without it: $e\n$s');
    }

    // ── PRIME SUSPECT ──────────────────────────────────────────────────
    // Runs only on the reinstall / cleared-data path — i.e. exactly the
    // scenario where the launch crash was reproducing. Guard it hard.
    try {
      await AutoBackupService.restoreIfNeeded();
    } catch (e, s) {
      log('❌ restoreIfNeeded failed — continuing without restore: $e\n$s');
    }
    try {
      // Snapshot current state — fire-and-forget, never blocks startup.
      AutoBackupService.saveBackup();
    } catch (e, s) {
      log('❌ saveBackup failed — continuing: $e\n$s');
    }

    bool hasEverConnected = false;
    try {
      final prefs = await SharedPreferences.getInstance();
      hasEverConnected = prefs.getBool('is_connected_to_network') ?? false;
    } catch (e, s) {
      log('❌ prefs read failed — continuing as standalone: $e\n$s');
    }

    // Silent, best-effort usage signal — never blocks or fails launch.
    // See analytics_service.dart for the "must not know / must not fail"
    // guarantees (8/9). Standalone installs are tagged too: Firebase is
    // already initialized above for everyone, account or not.
    unawaited(AnalyticsService.setUserType(hasEverConnected));
    unawaited(AnalyticsService.logAppOpen());

    if (hasEverConnected) {
      log("👤 Network user — configuring RevenueCat at startup.");
      await ensureRevenueCatConfigured();
    } else {
      // Not configured here on purpose — a brand-new install has nothing
      // to check yet. auth_service.dart and subscription_service.dart
      // each call ensureRevenueCatConfigured() themselves before touching
      // Purchases, so first-time invite code redemption is covered too.
      log("👤 Standalone user — RevenueCat will configure on first network action.");
    }

    runApp(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => DemoProvider()),
          ChangeNotifierProvider.value(value: globalRefreshNotifier),
          // Day-of-gig FAB (see features/day_of/) — populated by GigsPage,
          // read by MainPage's build() below.
          ChangeNotifierProvider(create: (_) => DayOfNotifier()),
        ],
        child: const MyApp(),
      ),
    );
  }, (Object error, StackTrace stack) {
    // Last-resort net. Anything that still escapes lands here instead of
    // killing the app on launch. THIS is the line that will print the real
    // root-cause error once Iqui (or you) runs the new build.
    lastCapturedError = '$error\n\n$stack';
    log('🔥🔥 UNCAUGHT (zone) — app kept alive: $error\n$stack');
    try {
      FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
    } catch (_) {}
  });
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'The Money Gigs',
      theme: ThemeData(
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.deepPurple,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: UpgradeAlert(child: const MainPage()),
      debugShowCheckedModeBanner: false,
    );
  }
}

class MainPage extends StatefulWidget {
  const MainPage({super.key});

  @override
  State<MainPage> createState() => _MainPageState();
}

class _MainPageState extends State<MainPage> with WidgetsBindingObserver {
  // ✅ Start on Venues (Map) tab — index 0
  int _selectedIndex = 0;
  bool _isInitializingLocalServices = true;
  bool _showOnboardingFlow = false;

  final List<Widget?> _widgetInstances = List.generate(4, (_) => null);

  // Defaulted (not `late`) so build() can NEVER hit an uninitialized field
  // if _initializeSettings throws. A crash one frame after the spinner
  // clears looks identical to a launch crash to the user.
  List<String?> _pageBackgroundPaths = List<String?>.filled(4, null);
  List<Color?> _pageBackgroundColors = List<Color?>.filled(4, null);
  List<double> _pageBackgroundOpacities =
  List<double>.filled(4, _defaultOpacity);

  // Retrospective notification state
  Gig? _gigNeedingReview;
  int _totalGigsNeedingReview = 0;
  bool _showRetrospectiveBanner = false;

  // ✅ TAB ORDER: Venues first, then Pay, then Gigs, then Profile
  static const List<String> _pageTitles = [
    'Venues',   // 0
    'Gig Pay',  // 1
    'My Gigs',  // 2
    'Profile',  // 3
  ];
  static const List<String?> _defaultBackgroundImages = [null, null, null, null];
  static const double _defaultOpacity = 0.7;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeAppServices();

    Provider.of<GlobalRefreshNotifier>(context, listen: false)
        .addListener(_onSettingsChanged);
    Provider.of<DemoProvider>(context, listen: false)
        .addListener(_onDemoStateChanged);

    _checkFirstLaunch();

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _maybeCheckInviteCodeReentry();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Covers the realistic path: tap "Request a Code" → switch to Mail
    // to send it → come back. Android rarely actually kills a
    // backgrounded app, so relying on cold boot alone means this
    // almost never fires for real users. maybeShowInviteCodeReentry()
    // is still self-guarding (only shows once, ever), so it's safe to
    // check on every resume.
    if (state == AppLifecycleState.resumed) {
      _maybeCheckInviteCodeReentry();
    }
    // Best-effort "session end" proxy — true termination isn't reliably
    // observable on mobile, so `paused` (backgrounded) is the standard
    // substitute every analytics SDK uses. See analytics_service.dart.
    if (state == AppLifecycleState.paused) {
      unawaited(AnalyticsService.logAppClose());
    }
  }

  Future<void> _maybeCheckInviteCodeReentry() async {
    if (!context.mounted) return;
    final demoProvider = Provider.of<DemoProvider>(context, listen: false);
    if (!demoProvider.isDemoModeActive) {
      await maybeShowInviteCodeReentry(context);
    }
  }

  Future<void> _checkFirstLaunch() async {
    log('🎬 Main: _checkFirstLaunch() called');
    final prefs = await SharedPreferences.getInstance();
    const bool forceDemoForTesting = false;

    final hasSeenIntro =
    forceDemoForTesting ? false : (prefs.getBool(DemoProvider.hasSeenIntroKey) ?? false);

    log('🎬 Main: hasSeenIntro=$hasSeenIntro, context.mounted=${context.mounted}');

    if (!hasSeenIntro && context.mounted) {
      log('🎬 Main: First launch — starting onboarding...');
      await Provider.of<DemoProvider>(context, listen: false)
          .startDemo(force: forceDemoForTesting);
    }
  }

  Future<void> _initializeAppServices() async {
    Gig? pendingGigResult;
    final prefs = await SharedPreferences.getInstance();

    try {
      final results = await Future.wait([
        _initializeSettings(),
        Platform.isAndroid ? _checkForAppUpdate() : Future.value(null),
        GigRetrospectiveService.checkForRetrospectiveOnStartup(),
      ]);

      pendingGigResult = results[2] as Gig?;

      tz.initializeTimeZones();
      final notificationService = NotificationService();
      await notificationService.init();

// One-time cleanup of stale notifications scheduled with the old
// per-gig ID formula. Runs once after this patch ships.
      final bool notifCleanupDone =
          prefs.getBool('notification_cleanup_v1') ?? false;
      if (!notifCleanupDone) {
        log('🧹 Running one-time notification cleanup...');
        try {
          await notificationService.updateAllGigNotifications();
          await prefs.setBool('notification_cleanup_v1', true);
          log('🧹 Notification cleanup complete.');
        } catch (e) {
          log('⚠️ Notification cleanup failed — will retry next launch: $e');
        }
      }

      await notificationService.debugPendingNotifications();

      final bool gigDataCleanupDone =
          prefs.getBool('gig_data_cleanup_v1') ?? false;
      if (!gigDataCleanupDone) {
        log('🧹 Running one-time gig data cleanup...');
        try {
          final String? gigsJson = prefs.getString('gigs_list');
          if (gigsJson != null) {
            List<Gig> gigs = Gig.decode(gigsJson);
            bool changed = false;
            gigs = gigs.map((g) {
              // Reset retrospectiveCompleted on recurring parent templates only
              if (g.isRecurring && g.retrospectiveCompleted == true) {
                changed = true;
                log('🧹 Resetting retrospectiveCompleted on parent: ${g.id} ${g.venueName}');
                return g.copyWith(retrospectiveCompleted: false);
              }
              return g;
            }).toList();
            if (changed) {
              await prefs.setString('gigs_list', Gig.encode(gigs));
              log('🧹 Gig data cleanup complete.');
            }
          }
          await prefs.setBool('gig_data_cleanup_v1', true);
        } catch (e) {
          log('⚠️ Gig data cleanup failed — will retry next launch: $e');
        }
      }
    } catch (e, s) {
      // A startup-service failure must never prevent the UI from showing.
      log('❌ _initializeAppServices failed — showing app anyway: $e\n$s');
    } finally {
      // ALWAYS clear the loading flag, success or failure, so the app can
      // never get stuck on the spinner.
      if (context.mounted) {
        setState(() {
          if (pendingGigResult != null) {
            _gigNeedingReview = pendingGigResult;
            GigRetrospectiveService.getGigsNeedingRetrospective().then((allGigs) {
              if (context.mounted) {
                setState(() => _totalGigsNeedingReview = allGigs.length);
              }
            });
            _showRetrospectiveBanner = true;
          }
          _isInitializingLocalServices = false;
        });
      }
    }
  }

  void _skipAndDismissBanner() async {
    if (_gigNeedingReview == null) return;
    await GigRetrospectiveService.skipGigRetrospective(_gigNeedingReview!.id);
    setState(() => _showRetrospectiveBanner = false);
  }

  void _showNextRetrospectiveBanner() async {
    setState(() => _showRetrospectiveBanner = false);
    await Future.delayed(const Duration(milliseconds: 50));
    final gigsNeedingReview =
    await GigRetrospectiveService.getGigsNeedingRetrospective();
    if (gigsNeedingReview.isNotEmpty && context.mounted) {
      setState(() {
        _gigNeedingReview = gigsNeedingReview.first;
        _totalGigsNeedingReview = gigsNeedingReview.length;
        _showRetrospectiveBanner = true;
      });
    }
  }

  void _onRetrospectiveComplete() {
    globalRefreshNotifier.notify();
    _showNextRetrospectiveBanner();
  }

  Future<void> _initializeSettings() async {
    final prefs = await SharedPreferences.getInstance();
    if (!context.mounted) return;
    final backgroundPaths =
    List.generate(4, (i) => prefs.getString('background_image_$i'));
    final backgroundColors = List.generate(4, (i) {
      final colorVal = prefs.getInt('background_color_$i');
      return colorVal != null ? Color(colorVal) : null;
    });
    final backgroundOpacities = List.generate(
        4, (i) => prefs.getDouble('background_opacity_$i') ?? _defaultOpacity);
    setState(() {
      _pageBackgroundPaths = backgroundPaths;
      _pageBackgroundColors = backgroundColors;
      _pageBackgroundOpacities = backgroundOpacities;
    });
  }

  Future<void> _checkForAppUpdate() async {
    if (Platform.isAndroid) {
      await AppUpdateService().checkForUpdate();
    }
  }

  void _onDemoStateChanged() {
    final demoProvider = Provider.of<DemoProvider>(context, listen: false);
    log(
        '🎬 Main: Demo state — active:${demoProvider.isDemoModeActive} step:${demoProvider.currentStep}');

    // Show or hide the full-screen onboarding overlay
    final shouldShow = demoProvider.isDemoModeActive &&
        demoProvider.currentStep == DemoStep.onboardingWelcome;

    if (shouldShow != _showOnboardingFlow) {
      setState(() => _showOnboardingFlow = shouldShow);
    }

    // ── Legacy tab navigation for any future guided tour steps ──────────────
    if (demoProvider.isDemoModeActive) {
      switch (demoProvider.currentStep) {
      // ✅ Map is now index 0
        case DemoStep.mapVenueSearch:
        case DemoStep.mapAddVenue:
        case DemoStep.mapBookGig:
          if (_selectedIndex != 0) _setSelectedIndex(0);
          break;
      // My Gigs stays at index 2
        case DemoStep.gigListView:
          if (_selectedIndex != 2) _setSelectedIndex(2);
          break;
      // Profile stays at index 3
        case DemoStep.profileConnect:
          if (_selectedIndex != 3) _setSelectedIndex(3);
          break;
        default:
          break;
      }
    }
  }

  void _onSettingsChanged() => _initializeSettings();

  // Single choke point for tab changes so activeTabIndexNotifier always
  // reflects what's actually on screen (tabs live in an IndexedStack and
  // are built eagerly, so widgets can't infer visibility from build/initState).
  void _setSelectedIndex(int index) {
    setState(() => _selectedIndex = index);
    activeTabIndexNotifier.value = index;
    // One event, tab_name as the dimension — covers all four tabs
    // (Venues/Gig Pay/My Gigs/Profile) without a separate call each.
    unawaited(AnalyticsService.logMainNavAccess(_pageTitles[index]));
  }

  void _onItemTapped(int index) => _setSelectedIndex(index);

  /// The notched bottom bar shown in place of the plain BottomNavigationBar
  /// on a day there's a gig/jam (see build()'s `todaysGig` check). Same 4
  /// destinations, same tap behavior and highlight color — just split
  /// around the FAB's notch instead of laid out as one row.
  Widget _buildNotchedNavBar() {
    Widget navIcon(int index, IconData icon, String tooltip) {
      final bool selected = _selectedIndex == index;
      return IconButton(
        icon: Icon(icon),
        color: selected ? Colors.deepOrange.shade400 : Colors.grey,
        tooltip: tooltip,
        onPressed: () => _onItemTapped(index),
      );
    }

    return BottomAppBar(
      shape: const CircularNotchedRectangle(),
      notchMargin: 8,
      color: Colors.grey[850],
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          navIcon(0, Icons.map_rounded, 'Venues'),
          navIcon(1, Icons.attach_money_rounded, 'Gig Pay'),
          const SizedBox(width: 40), // reserved for the FAB's notch
          navIcon(2, Icons.list_alt_rounded, 'My Gigs'),
          navIcon(3, Icons.person_rounded, 'Profile'),
        ],
      ),
    );
  }

  Future<void> _sendFeedbackEmail() async {
    final Uri emailLaunchUri = Uri(
      scheme: 'mailto',
      path: 'cliff@themoneygigs.com',
      queryParameters: {
        'subject': 'Questions or Comments for Cliff',
      },
    );

    try {
      if (await canLaunchUrl(emailLaunchUri)) {
        await launchUrl(emailLaunchUri);
      } else {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not open email app')),
          );
        }
      }
    } catch (e) {
      log('Error launching email: $e');
    }
  }

  // ✅ NEW: Opens the Help Videos YouTube playlist in the browser/YouTube app.
  Future<void> _openHelpVideos() async {
    final Uri helpVideosUri =
    Uri.parse('https://www.youtube.com/playlist?list=PLaiWq3b5YIi8');

    try {
      if (await canLaunchUrl(helpVideosUri)) {
        await launchUrl(helpVideosUri, mode: LaunchMode.externalApplication);
      } else {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not open Help Videos')),
          );
        }
      }
    } catch (e) {
      log('Error launching Help Videos: $e');
    }
  }

  // ✅ NEW: Bottom sheet shown when the "?" icon is tapped — lets the user
  // choose between emailing Cliff and watching the Help Videos playlist.
  void _showHelpMenu() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.grey[850],
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.only(top: 12, bottom: 4),
                child: Text(
                  'How can we help?',
                  style: TextStyle(
                      color: Colors.white70,
                      fontSize: 14,
                      fontWeight: FontWeight.w600),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.email_outlined, color: Colors.white),
                title:
                const Text('Email Cliff', style: TextStyle(color: Colors.white)),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _sendFeedbackEmail();
                },
              ),
              ListTile(
                leading:
                const Icon(Icons.play_circle_outline, color: Colors.white),
                title: const Text('Help Videos',
                    style: TextStyle(color: Colors.white)),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _openHelpVideos();
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  Future<void> _openAddGigDialog() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String? gigsJsonString = prefs.getString('gigs_list');
      List<Gig> existingGigs = [];
      if (gigsJsonString != null && gigsJsonString.isNotEmpty) {
        existingGigs = Gig.decode(gigsJsonString);
      }

      const String googleApiKey = String.fromEnvironment('GOOGLE_API_KEY');

      if (context.mounted) {
        final GigEditResult? result = await showDialog<GigEditResult>(
          context: context,
          builder: (context) => BookingDialog(
            googleApiKey: googleApiKey,
            existingGigs: existingGigs,
          ),
        );

        if (result != null &&
            result.action == GigEditResultAction.updated &&
            result.gig != null) {
          existingGigs.add(result.gig!);
          await prefs.setString('gigs_list', Gig.encode(existingGigs));

          final notificationService = NotificationService();
          await notificationService.init();
          await notificationService.updateAllGigNotifications();

          globalRefreshNotifier.notify();
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                content: Text('Gig booked successfully!'),
                backgroundColor: Colors.green));
          }
        }
      }
    } catch (e) {
      log('Error opening Add Gig dialog: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Could not open gig form: $e')));
      }
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    if (_isInitializingLocalServices) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    Widget buildPage(int index) {
      if (_widgetInstances[index] == null) {
        switch (index) {
          case 0: _widgetInstances[index] = const MapPage(); break;
          case 1: _widgetInstances[index] = const GigCalculator(); break;
          case 2: _widgetInstances[index] = const GigsPage(); break;
          case 3: _widgetInstances[index] = const ProfilePage(); break;
        }
      }
      return _widgetInstances[index]!;
    }

    return Consumer<DemoProvider>(
      builder: (context, demoProvider, child) {
        if (_showOnboardingFlow &&
            demoProvider.currentStep == DemoStep.onboardingWelcome) {
          return OnboardingFlow(
            onComplete: () {
              log('🎬 Main: Onboarding complete — entering app');
              demoProvider.nextStep();
              // Always land on the Map (Venues) tab after onboarding,
              // regardless of which tab was active when replay was triggered.
              _setSelectedIndex(0);
            },
          );
        }

        // Day-of-gig FAB (see features/day_of/day_of_notifier.dart) — watched
        // so the nav shell below rebuilds the moment GigsPage determines
        // there is (or no longer is) a gig/jam today.
        final dayOfNotifier = Provider.of<DayOfNotifier>(context);
        final Gig? todaysGig = dayOfNotifier.todaysGig;

        return Scaffold(
          appBar: AppBar(
            backgroundColor: Colors.black87,
            elevation: 0,
            leading: Padding(
              padding: const EdgeInsets.all(8.0),
              child: Image.asset('assets/app_icon.png'),
            ),
            title: Text(_pageTitles[_selectedIndex]),
            actions: [
              Padding(
                padding: const EdgeInsets.only(right: 4.0),
                child: IconButton(
                  icon: Container(
                    decoration: BoxDecoration(
                      color: Colors.orange.shade700,
                      shape: BoxShape.circle,
                    ),
                    padding: const EdgeInsets.all(8),
                    child: const Icon(Icons.add, color: Colors.white, size: 24),
                  ),
                  tooltip: 'Add New Gig',
                  onPressed: _openAddGigDialog,
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(right: 8.0),
                child: IconButton(
                  icon: Container(
                    decoration: BoxDecoration(
                      color: Colors.blueGrey.shade700,
                      shape: BoxShape.circle,
                    ),
                    padding: const EdgeInsets.all(8),
                    child: const Icon(Icons.question_mark, color: Colors.white, size: 24),
                  ),
                  // ✅ CHANGED: was _sendFeedbackEmail directly — now opens a
                  // choice between emailing Cliff and the Help Videos playlist.
                  tooltip: 'Help',
                  onPressed: _showHelpMenu,
                ),
              ),
            ],
          ),
          body: Column(
            children: [
              if (_showRetrospectiveBanner && _gigNeedingReview != null)
                RetrospectiveNotificationBanner(
                  gig: _gigNeedingReview!,
                  totalPendingCount: _totalGigsNeedingReview,
                  onDismiss: _skipAndDismissBanner,
                  onComplete: _onRetrospectiveComplete,
                ),
              Expanded(
                child: IndexedStack(
                  index: _selectedIndex,
                  children: List.generate(4, (index) {
                    final color = _pageBackgroundColors[index];
                    ImageProvider? provider;
                    Color? bgColor;
                    if (color != null) {
                      bgColor = color;
                    } else {
                      final path = _pageBackgroundPaths[index];
                      final defaultPath = _defaultBackgroundImages[index];
                      if (path != null) {
                        if (path == 'USE_STAGE_DEFAULT') {
                          provider = const AssetImage('assets/background1.png');
                        } else if (path.startsWith('/')) {
                          provider = FileImage(File(path));
                        } else {
                          provider = AssetImage(path);
                        }
                      } else if (defaultPath != null) {
                        provider = AssetImage(defaultPath);
                      }
                      bgColor ??= Colors.black12;
                    }
                    return PageBackgroundWrapper(
                      imageProvider: provider,
                      backgroundColor: bgColor,
                      backgroundOpacity: _pageBackgroundOpacities[index],
                      child: buildPage(index),
                    );
                  }),
                ),
              ),
            ],
          ),
          // ── Day-of-gig nav shell (8/26/26) ─────────────────────────────
          // On an ordinary day this is the same plain BottomNavigationBar
          // as always. On a day with a gig/jam on the calendar, it swaps to
          // a notched bar with a raised center FAB (Cliff's choice — see
          // day_of_notifier.dart) that opens DayOfScreen for that
          // occurrence. The FAB fully appears/disappears rather than
          // staying present-but-disabled, per Cliff's "appears only on gig
          // days" answer.
          bottomNavigationBar: todaysGig == null
              ? BottomNavigationBar(
                  items: const [
                    BottomNavigationBarItem(
                      icon: Icon(Icons.map_rounded),
                      label: 'Venues',
                    ),
                    BottomNavigationBarItem(
                      icon: Icon(Icons.attach_money_rounded),
                      label: 'Gig Pay',
                    ),
                    BottomNavigationBarItem(
                      icon: Icon(Icons.list_alt_rounded),
                      label: 'My Gigs',
                    ),
                    BottomNavigationBarItem(
                      icon: Icon(Icons.person_rounded),
                      label: 'Profile',
                    ),
                  ],
                  currentIndex: _selectedIndex,
                  // Brand accent (8/26 color consolidation) — was
                  // colorScheme.primary, which is a purple auto-generated by
                  // the deepPurple ColorScheme.fromSeed() below. That purple
                  // was coincidentally also showing up as an arbitrary
                  // avatar-circle color elsewhere (gig_list_tile.dart),
                  // making it read like two unrelated things shared one
                  // color by accident. Orange is now the one intentional
                  // accent used for nav highlight, buttons, and badges
                  // app-wide.
                  selectedItemColor: Colors.deepOrange.shade400,
                  unselectedItemColor: Colors.grey,
                  onTap: _onItemTapped,
                  type: BottomNavigationBarType.fixed,
                  backgroundColor: Colors.grey[850],
                )
              : _buildNotchedNavBar(),
          floatingActionButton: todaysGig == null
              ? null
              : FloatingActionButton(
                  tooltip: 'Day of the gig',
                  backgroundColor: Colors.deepOrange.shade400,
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => DayOfScreen(gig: todaysGig),
                      ),
                    );
                  },
                  child: ClipOval(
                    child: Image.asset(
                      'assets/app_icon.png',
                      fit: BoxFit.cover,
                      width: 40,
                      height: 40,
                    ),
                  ),
                ),
          floatingActionButtonLocation:
              FloatingActionButtonLocation.centerDocked,
        );
      },
    );
  }
}
/// Opens the user's mail app with the crash details pre-filled, addressed to
/// Cliff. Used by the in-app crash screen below.
Future<void> emailErrorToCliff(String details) async {
  // Keep the body short enough that mail clients don't truncate the link.
  final String trimmed =
  details.length > 1500 ? details.substring(0, 1500) : details;
  final Uri uri = Uri(
    scheme: 'mailto',
    path: 'cliff@themoneygigs.com',
    queryParameters: {
      'subject': 'MoneyGigs Crash Report',
      'body':
      'Hi Cliff,\n\nThe app ran into a problem. Here are the details '
          '(sending these helps a lot):\n\n$trimmed',
    },
  );
  try {
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  } catch (e) {
    log('Could not open mail app for crash report: $e');
  }
}

/// Friendly full-screen error UI shown in place of Flutter's default crash
/// box. Wrapped in Directionality + Material so it renders even when the
/// error happens high in the widget tree. The "Email this to Cliff" button
/// opens a pre-filled crash report.
class FriendlyErrorScreen extends StatelessWidget {
  final String details;
  const FriendlyErrorScreen({super.key, required this.details});

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Material(
        color: Colors.black,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 12),
                const Icon(Icons.error_outline,
                    color: Colors.orangeAccent, size: 48),
                const SizedBox(height: 16),
                const Text(
                  'Something went wrong',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                const Text(
                  "This one's on the app, not you. Tapping below opens an "
                      "email with the technical details already filled in — "
                      "sending it to Cliff helps get this fixed fast.",
                  style: TextStyle(color: Colors.white70, fontSize: 15),
                ),
                const SizedBox(height: 24),
                ElevatedButton.icon(
                  onPressed: () => emailErrorToCliff(details),
                  icon: const Icon(Icons.email_outlined),
                  label: const Text('Email this to Cliff'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.deepPurple,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 14),
                  ),
                ),
                const SizedBox(height: 20),
                const Text(
                  'Technical details:',
                  style: TextStyle(color: Colors.white54, fontSize: 12),
                ),
                const SizedBox(height: 6),
                Expanded(
                  child: SingleChildScrollView(
                    child: Text(
                      details,
                      style: const TextStyle(
                          color: Colors.white38, fontSize: 11, height: 1.4),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}