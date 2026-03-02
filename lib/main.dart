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

// Your app's specific imports
import 'firebase_options.dart';
import 'core/services/app_update_service.dart';
import 'core/services/notification_service.dart';
import 'features/app_demo/providers/demo_provider.dart';
import 'features/app_demo/widgets/coaching_demo_flow.dart'; // NEW: Coaching flow
import 'features/gigs/views/gig_calculator_page.dart';
import 'features/map_venues/views/map.dart';
import 'features/gigs/views/gigs.dart';
import 'features/profile/views/profile.dart';
import 'core/widgets/page_background_wrapper.dart';
import 'global_refresh_notifier.dart';
import 'features/gigs/widgets/booking_dialog.dart'; // For Add Gig button
import 'features/gigs/models/gig_model.dart'; // For existing gigs
import 'features/gigs/services/gig_retrospective_service.dart';
import 'features/gigs/widgets/retrospective_notification_banner.dart';

import 'package:the_money_gigs/features/app_demo/widgets/email_capture_screen.dart';

bool _areNetworkServicesInitialized = false;

String _getRevenueCatApiKey() {
  if (kDebugMode) {
    // TEST/DEVELOPMENT - Use Test Store key
    // This key works for sandbox purchases on both platforms
    return 'test_sFBpSvZPjpQyWyuLyPobraUtyfL';
  } else {
    // PRODUCTION - Use platform-specific keys
    // Click "Show key" next to each app in RevenueCat → API keys
    if (Platform.isIOS) {
      return 'appl_epUaEdlDadBKMraKrhAnthTlRen'; // TODO: Replace with actual iOS key
    } else {
      return 'goog_yRlYImMZVYNNvyxpsoGSDNsaaaJ'; // TODO: Replace with actual Android key
    }
  }
}

/// Initializes all network-dependent services.
/// This function is called on-demand from the Profile page.
Future<void> initializeNetworkServices() async {
  if (_areNetworkServicesInitialized) return;
  print("🚀 Initializing Network Services for the first time...");

  try {
    String apiKey = _getRevenueCatApiKey();
    await Purchases.configure(PurchasesConfiguration(apiKey));
    print('✅ RevenueCat initialized with ${kDebugMode ? 'TEST' : 'PRODUCTION'} key');
  } catch (e) {
    print('❌ Error initializing RevenueCat: $e');
  }

  _areNetworkServicesInitialized = true;
  print("✅ Network Services Initialization Complete.");
}
// --- END OF GLOBAL SECTION ---

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Set orientations
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
  ]);

  // --- START: MODIFIED CONDITIONAL INITIALIZATION ---

  // 1. Always initialize Firebase
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  print('✅ Firebase Initialized');

  // 2. Check if the user has EVER connected to the network
  final prefs = await SharedPreferences.getInstance();
  final bool hasEverConnected = prefs.getBool('is_connected_to_network') ?? false;

  // 3. ONLY initialize RevenueCat at startup if they are a network user
  if (hasEverConnected) {
    print("👤 User is part of the network, initializing RevenueCat at startup.");
    await initializeNetworkServices(); // This now configures RevenueCat
  } else {
    print("👤 User is not part of the network, skipping RevenueCat initialization.");
  }
  // --- END: MODIFIED CONDITIONAL INITIALIZATION ---

  // Run the app immediately. All other initializations are deferred.
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => DemoProvider()),
        // Use the global singleton instead of creating a new instance
        ChangeNotifierProvider.value(value: globalRefreshNotifier),
      ],
      child: const MyApp(),
    ),
  );
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
      home: const MainPage(),
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
  int _selectedIndex = 0;
  bool _isInitializingLocalServices = true;
  bool _showCoachingFlow = false; // NEW: Track coaching flow visibility

  final List<Widget?> _widgetInstances = List.generate(4, (_) => null);

  late List<String?> _pageBackgroundPaths;
  late List<Color?> _pageBackgroundColors;
  late List<double> _pageBackgroundOpacities;

  // Retrospective notification state
  Gig? _gigNeedingReview;
  int _totalGigsNeedingReview = 0;
  bool _showRetrospectiveBanner = false;

  static const List<String> _pageTitles = [ 'Gig Pay', 'Venues', 'My Gigs', 'Profile', ];
  static const List<String?> _defaultBackgroundImages = [ null, null, null, null, ];
  static const double _defaultOpacity = 0.7;

  @override
  void initState() {
    super.initState();
    _initializeAppServices();

    Provider.of<GlobalRefreshNotifier>(context, listen: false).addListener(_onSettingsChanged);
    Provider.of<DemoProvider>(context, listen: false).addListener(_onDemoStateChanged);

    // NEW: Check if we should show coaching flow on first launch
    _checkFirstLaunch();
  }

  // NEW: Check if this is first launch and should show coaching
  Future<void> _checkFirstLaunch() async {
    print('🎬 Main: _checkFirstLaunch() called');
    final prefs = await SharedPreferences.getInstance();
    const bool forceDemoForTesting = false;

    final hasSeenIntro = prefs.getBool(DemoProvider.hasSeenIntroKey) ?? false;
    print('🎬 Main: hasSeenIntro = $hasSeenIntro, mounted = $mounted, Forcing Demo: $forceDemoForTesting');

    if ((!hasSeenIntro || forceDemoForTesting) && mounted) {
      print('🎬 Main: Launch condition met, starting coaching demo...');
      final demoProvider = Provider.of<DemoProvider>(context, listen: false);

      // 🎯 THE FIX: Pass the 'force' parameter to the startDemo() call.
      await demoProvider.startDemo(force: forceDemoForTesting);

      print('🎬 Main: startDemo() call completed');
    } else {
      print('🎬 Main: Not starting demo (hasSeenIntro=$hasSeenIntro, mounted=$mounted)');
    }
  }

  Future<void> _initializeAppServices() async {
    print("✅ BANNER_DEBUG: _initializeAppServices started.");

    // These services are local and required for the app to function.
    // They are fast and don't require network.
    final results = await Future.wait([
      _initializeSettings(),
      _checkForAppUpdate(),
      GigRetrospectiveService.checkForRetrospectiveOnStartup(),
    ]);

    final pendingGigResult = results[2] as Gig?;
    print("✅ BANNER_DEBUG: checkForRetrospectiveOnStartup returned: ${pendingGigResult?.venueName ?? 'null'}");

    tz.initializeTimeZones();
    final notificationService = NotificationService();
    await notificationService.init();
    await notificationService.debugPendingNotifications();
    await notificationService.requestPermissions();

    // These can run in parallel.
    if (mounted) {
      print("✅ BANNER_DEBUG: Component is mounted, proceeding to setState.");

      setState(() {
        if (pendingGigResult != null) {
          print("✅ BANNER_DEBUG: pendingGigResult is NOT null. Setting state for banner.");

          _gigNeedingReview = pendingGigResult;
          // We need to get the total count separately as the startup check only gets one.
          // This can be a fire-and-forget call for now to update the count later.
          GigRetrospectiveService.getGigsNeedingRetrospective().then((allGigs) {
            if (mounted) {
              print("✅ BANNER_DEBUG: Fetched total gigs needing review: ${allGigs.length}");
              setState(() {
                _totalGigsNeedingReview = allGigs.length;
              });
            }
          });
          _showRetrospectiveBanner = true;
        }

        // Mark initialization as complete to hide the loading spinner.
        _isInitializingLocalServices = false;
        print("✅ BANNER_DEBUG: setState complete. _isInitializingLocalServices=false, _showRetrospectiveBanner=$_showRetrospectiveBanner");

      });
    } else {
      print("❌ BANNER_DEBUG: Component was unmounted before setState could be called.");

    }
  }

  void _skipAndDismissBanner() async {
    if (_gigNeedingReview == null) return;
    print("✅ BANNER_DEBUG: User clicked 'X'. Skipping gig: '${_gigNeedingReview!.venueName}'");

    // Tell the service to ignore this gig for the rest of the session.
    await GigRetrospectiveService.skipGigRetrospective(_gigNeedingReview!.id);

    // Simply hide the banner. Do NOT check for more.
    setState(() {
      _showRetrospectiveBanner = false;
    });
  }
  void _showNextRetrospectiveBanner() async {
    // Hide the current banner first
    setState(() {
      _showRetrospectiveBanner = false;
    });

    // Give the UI a frame to update
    await Future.delayed(const Duration(milliseconds: 50));

    // Check if there are more gigs to review
    final gigsNeedingReview = await GigRetrospectiveService.getGigsNeedingRetrospective();
    if (gigsNeedingReview.isNotEmpty && mounted) {
      print("✅ BANNER_DEBUG: Showing next banner for: '${gigsNeedingReview.first.venueName}'");
      setState(() {
        _gigNeedingReview = gigsNeedingReview.first;
        _totalGigsNeedingReview = gigsNeedingReview.length;
        _showRetrospectiveBanner = true; // Show the next banner
      });
    } else {
      print("✅ BANNER_DEBUG: No more gigs to review.");
    }
  }

  void _onRetrospectiveComplete() {
    print("✅ BANNER_DEBUG: Review completed.");
    // Refresh any UI that depends on gig data
    globalRefreshNotifier.notify();
    // Advance to the next banner
    _showNextRetrospectiveBanner();
  }

  Future<void> _initializeSettings() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    final backgroundPaths = List.generate(4, (i) => prefs.getString('background_image_$i'));
    final backgroundColors = List.generate(4, (i) {
      final colorVal = prefs.getInt('background_color_$i');
      return colorVal != null ? Color(colorVal) : null;
    });
    final backgroundOpacities = List.generate(4, (i) => prefs.getDouble('background_opacity_$i') ?? _defaultOpacity);
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
    print('🎬 Main: Demo state changed - Active: ${demoProvider.isDemoModeActive}, Step: ${demoProvider.currentStep}');

    if (demoProvider.isDemoModeActive && demoProvider.currentStep == DemoStep.coachingIntro) {
      setState(() {
        _showCoachingFlow = true;
      });
    } else if (_showCoachingFlow) {
      setState(() {
        _showCoachingFlow = false;
      });
    }

    // NEW: Auto-navigate to appropriate tab based on demo step
    if (demoProvider.isDemoModeActive) {
      switch (demoProvider.currentStep) {
        case DemoStep.mapVenueSearch:
        case DemoStep.mapAddVenue:
        case DemoStep.mapBookGig:
        // Navigate to Venues tab (index 1)
          if (_selectedIndex != 1) {
            setState(() {
              _selectedIndex = 1;
            });
          }
          break;
        case DemoStep.gigListView:
        // Navigate to My Gigs tab (index 2)
          if (_selectedIndex != 2) {
            setState(() {
              _selectedIndex = 2;
            });
          }
          break;
        case DemoStep.profileConnect:
        // Navigate to Profile tab (index 3)
          if (_selectedIndex != 3) {
            setState(() {
              _selectedIndex = 3;
            });
          }
          break;
        case DemoStep.emailCapture:
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (context) => const EmailCaptureScreen(),
            ),
          );
          break;case DemoStep.none:
        case DemoStep.complete:
        case DemoStep.coachingIntro:
        default:
          break;
      }
    }
  }

  void _onSettingsChanged() => _initializeSettings();

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
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
        // 1. Capture the result from the dialog
        final GigEditResult? result = await showDialog<GigEditResult>(
          context: context,
          builder: (context) {
            return BookingDialog(
              googleApiKey: googleApiKey,
              existingGigs: existingGigs,
            );
          },
        );

        // 2. Handle the result and save to SharedPreferences
        if (result != null && result.action == GigEditResultAction.updated && result.gig != null) {
          // Add the new gig to the list
          existingGigs.add(result.gig!);

          // Save the updated list back to SharedPreferences
          await prefs.setString('gigs_list', Gig.encode(existingGigs));

          // 3. Notify the app to refresh UI (My Gigs tab, etc.)
          globalRefreshNotifier.notify();

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Gig booked successfully!'), backgroundColor: Colors.green),
            );
          }
        }
      }
    } catch (e) {
      print('Error opening Add Gig dialog: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open gig form: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    print("✅ BANNER_DEBUG: Main page build running. _isInitializing: $_isInitializingLocalServices, _showBanner: $_showRetrospectiveBanner");

    if (_isInitializingLocalServices) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    // This function ensures a page's initState() is only called when it's first needed.
    Widget buildPage(int index) {
      if (_widgetInstances[index] == null) {
        print("Building page $index for the first time.");
        switch (index) {
          case 0: _widgetInstances[index] = const GigCalculator(); break;
          case 1: _widgetInstances[index] = const MapPage(); break;
          case 2: _widgetInstances[index] = const GigsPage(); break;
          case 3: _widgetInstances[index] = const ProfilePage(); break;
        }
      }
      return _widgetInstances[index]!;
    }

    return Consumer<DemoProvider>(
      builder: (context, demoProvider, child) {
        // NEW: If in coaching intro step, show full-screen coaching flow
        if (_showCoachingFlow && demoProvider.currentStep == DemoStep.coachingIntro) {
          return Scaffold(
            backgroundColor: Colors.black,
            body: CoachingDemoFlow(
              onComplete: () {
                print('🎬 Main: Coaching flow complete, advancing to map demo');
                demoProvider.nextStep();
                // Navigation will happen automatically via _onDemoStateChanged
              },
            ),
          );
        }

        // Otherwise show normal app with demo overlays
        return Scaffold(
          extendBodyBehindAppBar: true,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            leading: Padding( padding: const EdgeInsets.all(8.0), child: Image.asset('assets/app_icon.png'), ),
            title: Text(_pageTitles[_selectedIndex]),
            actions: [
              // Add Gig button in top right
              Padding(
                padding: const EdgeInsets.only(right: 8.0),
                child: IconButton(
                  icon: Container(
                    decoration: BoxDecoration(
                      color: Colors.orange.shade700,
                      shape: BoxShape.circle,
                    ),
                    padding: const EdgeInsets.all(8),
                    child: const Icon(
                      Icons.add,
                      color: Colors.white,
                      size: 24,
                    ),
                  ),
                  tooltip: 'Add New Gig',
                  onPressed: _openAddGigDialog,
                ),
              ),
            ],
          ),
          body: Column(
            children: <Widget>[
              // Retrospective notification banner
              if (_showRetrospectiveBanner && _gigNeedingReview != null)
                RetrospectiveNotificationBanner(
                  gig: _gigNeedingReview!,
                  totalPendingCount: _totalGigsNeedingReview,
                  onDismiss: _skipAndDismissBanner,
                  onComplete: _onRetrospectiveComplete,
                ),

              // The main page content
              Expanded(
                child: IndexedStack(
                  index: _selectedIndex,
                  // The children are now built on demand
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
                        provider = path.startsWith('/') ? FileImage(File(path)) : AssetImage(path);
                      } else if (defaultPath != null) {
                        provider = AssetImage(defaultPath);
                      }
                      bgColor ??= Colors.black12;
                    }
                    return PageBackgroundWrapper(
                      imageProvider: provider,
                      backgroundColor: bgColor,
                      backgroundOpacity: _pageBackgroundOpacities[index],
                      child: buildPage(index), // Use the lazy builder
                    );
                  }),
                ),
              ),
            ],
          ),
          bottomNavigationBar: BottomNavigationBar(
            items: const <BottomNavigationBarItem>[
              BottomNavigationBarItem(icon: Icon(Icons.attach_money_rounded), label: 'Pay'),
              BottomNavigationBarItem(icon: Icon(Icons.map), label: 'Venues'),
              BottomNavigationBarItem(icon: Icon(Icons.list), label: 'My Gigs'),
              BottomNavigationBarItem(icon: Icon(Icons.person), label: 'Profile'),
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