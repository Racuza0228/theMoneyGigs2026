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
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:url_launcher/url_launcher.dart'; // ✅ Added for email support
import 'package:the_money_gigs/core/utils/logger.dart';

import 'firebase_options.dart';
import 'core/services/app_update_service.dart';
import 'core/services/notification_service.dart';
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
import 'features/gigs/widgets/booking_dialog.dart';
import 'features/gigs/models/gig_model.dart';
import 'features/gigs/services/gig_retrospective_service.dart';
import 'features/gigs/widgets/retrospective_notification_banner.dart';
import 'package:the_money_gigs/features/app_demo/services/demo_tracking_service.dart';
import 'package:upgrader/upgrader.dart';
import 'features/gigs/services/auto_backup_service.dart';

/// Holds the most recent captured error + stack so the in-app crash screen
/// can offer to email it to Cliff. Set by the global error handlers in main().
String? lastCapturedError;

bool _areNetworkServicesInitialized = false;

String _getRevenueCatApiKey() {
  if (kDebugMode) {
    return 'test_sFBpSvZPjpQyWyuLyPobraUtyfL';
  } else {
    if (Platform.isIOS) {
      return 'appl_epUaEdlDadBKMraKrhAnthTlRen';
    } else {
      return 'goog_yRlYImMZVYNNvyxpsoGSDNsaaaJ';
    }
  }
}

Future<void> initializeNetworkServices() async {
  if (_areNetworkServicesInitialized) return;
  log("🚀 Initializing Network Services...");
  try {
    String apiKey = _getRevenueCatApiKey();
    await Purchases.configure(PurchasesConfiguration(apiKey));
    log('✅ RevenueCat initialized (${kDebugMode ? 'TEST' : 'PRODUCTION'})');
  } catch (e) {
    log('❌ Error initializing RevenueCat: $e');
  }
  _areNetworkServicesInitialized = true;
}

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
    };

    // Engine/platform + uncaught async errors. Returning true = "handled,
    // don't crash."
    binding.platformDispatcher.onError = (Object error, StackTrace stack) {
      lastCapturedError = '$error\n\n$stack';
      log('🔥 Platform error (handled, not crashing): $error\n$stack');
      return true;
    };

    await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

    // Firebase — never let init failure abort the launch.
    try {
      await Firebase.initializeApp(
          options: DefaultFirebaseOptions.currentPlatform);
      log('✅ Firebase Initialized');
    } catch (e, s) {
      log('❌ Firebase init failed — continuing without it: $e\n$s');
    }

    DemoTrackingService().syncPendingData().catchError((e) {
      log('⚠️ DemoTrackingService sync failed silently: $e');
    });

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

    if (hasEverConnected) {
      log("👤 Network user — initializing RevenueCat at startup.");
      await initializeNetworkServices();
    } else {
      log("👤 Standalone user — skipping RevenueCat initialization.");
    }

    runApp(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => DemoProvider()),
          ChangeNotifierProvider.value(value: globalRefreshNotifier),
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

class _MainPageState extends State<MainPage> {
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
    _initializeAppServices();

    Provider.of<GlobalRefreshNotifier>(context, listen: false)
        .addListener(_onSettingsChanged);
    Provider.of<DemoProvider>(context, listen: false)
        .addListener(_onDemoStateChanged);

    _checkFirstLaunch();
  }

  Future<void> _checkFirstLaunch() async {
    log('🎬 Main: _checkFirstLaunch() called');
    final prefs = await SharedPreferences.getInstance();
    const bool forceDemoForTesting = false;

    final hasSeenIntro =
    forceDemoForTesting ? false : (prefs.getBool(DemoProvider.hasSeenIntroKey) ?? false);

    log('🎬 Main: hasSeenIntro=$hasSeenIntro, mounted=$mounted');

    if (!hasSeenIntro && mounted) {
      log('🎬 Main: First launch — starting onboarding...');
      await Provider.of<DemoProvider>(context, listen: false)
          .startDemo(force: forceDemoForTesting);
    }
  }

  Future<void> _initializeAppServices() async {
    Gig? pendingGigResult;
    try {
      final results = await Future.wait([
        _initializeSettings(),
        Platform.isAndroid ? _checkForAppUpdate() : Future.value(null),
        GigRetrospectiveService.checkForRetrospectiveOnStartup(),
      ]);

      pendingGigResult = results[2] as Gig?;

      tz.initializeTimeZones();
      final notificationService = NotificationService();
      // init() must run at startup — sets up timezone + plugin so that
      // already-scheduled gig reminders fire correctly.
      await notificationService.init();
      await notificationService.debugPendingNotifications();
      // requestPermissions() is intentionally NOT called here.
      // The user opts in from the Profile page so they understand why
      // we are asking before the OS dialog appears.
    } catch (e, s) {
      // A startup-service failure must never prevent the UI from showing.
      log('❌ _initializeAppServices failed — showing app anyway: $e\n$s');
    } finally {
      // ALWAYS clear the loading flag, success or failure, so the app can
      // never get stuck on the spinner.
      if (mounted) {
        setState(() {
          if (pendingGigResult != null) {
            _gigNeedingReview = pendingGigResult;
            GigRetrospectiveService.getGigsNeedingRetrospective().then((allGigs) {
              if (mounted) {
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
    if (gigsNeedingReview.isNotEmpty && mounted) {
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
    if (!mounted) return;
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
          if (_selectedIndex != 0) setState(() => _selectedIndex = 0);
          break;
      // My Gigs stays at index 2
        case DemoStep.gigListView:
          if (_selectedIndex != 2) setState(() => _selectedIndex = 2);
          break;
      // Profile stays at index 3
        case DemoStep.profileConnect:
          if (_selectedIndex != 3) setState(() => _selectedIndex = 3);
          break;
        default:
          break;
      }
    }
  }

  void _onSettingsChanged() => _initializeSettings();
  void _onItemTapped(int index) => setState(() => _selectedIndex = index);

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
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not open email app')),
          );
        }
      }
    } catch (e) {
      log('Error launching email: $e');
    }
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

      if (mounted) {
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
          globalRefreshNotifier.notify();
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                content: Text('Gig booked successfully!'),
                backgroundColor: Colors.green));
          }
        }
      }
    } catch (e) {
      log('Error opening Add Gig dialog: $e');
      if (mounted) {
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
            },
          );
        }

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
                  tooltip: 'Contact Cliff',
                  onPressed: _sendFeedbackEmail,
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
                        provider = path.startsWith('/')
                            ? FileImage(File(path))
                            : AssetImage(path);
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
          bottomNavigationBar: BottomNavigationBar(
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
            selectedItemColor: Theme.of(context).colorScheme.primary,
            unselectedItemColor: Colors.grey,
            onTap: _onItemTapped,
            type: BottomNavigationBarType.fixed,
            backgroundColor: Colors.grey[850],
          ),
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