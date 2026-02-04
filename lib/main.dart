// lib/main.dart
import 'package:in_app_review/in_app_review.dart';
import 'dart:async';
import 'dart:convert'; // For json.decode
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
import 'package:url_launcher/url_launcher.dart';
import 'global_refresh_notifier.dart';
import 'features/gigs/widgets/booking_dialog.dart'; // For Add Gig button
import 'features/gigs/models/gig_model.dart'; // For existing gigs
import 'features/gigs/services/gig_retrospective_service.dart';
import 'features/gigs/widgets/retrospective_notification_banner.dart';

// --- 1. GLOBAL STATE AND LAZY INITIALIZER ---
// This global flag ensures network services are only initialized once.
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
  // If already initialized, do nothing.
  if (_areNetworkServicesInitialized) return;
  print("🚀 Initializing Network Services for the first time...");

  // Initialize Firebase
  // This needs to be done before any other Firebase services are used.
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  print('✅ Firebase Initialized');

  // Initialize RevenueCat for subscriptions.
  try {
    // Get appropriate RevenueCat API key based on platform and build mode
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

  // Set preferred orientations. This is fast and can stay.
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
  ]);

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
  static const List<String?> _defaultBackgroundImages = [ 'assets/background1.png', null, 'assets/background2.png', 'assets/background3.png', ];
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
    const bool forceDemoForTesting = true;

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
    // These services are local and required for the app to function.
    // They are fast and don't require network.
    tz.initializeTimeZones();
    final notificationService = NotificationService();
    await notificationService.init();
    await notificationService.debugPendingNotifications();

    // The permission request is a blocking UI popup, so it happens here.
    await notificationService.requestPermissions();

    // These can run in parallel.
    await Future.wait([
      _initializeSettings(),
      _checkForAppUpdate(),
    ]);

    // Check for retrospectives
    await _checkForPendingRetrospectives();

    if (mounted) {
      setState(() {
        _isInitializingLocalServices = false;
      });
    }
  }

  Future<void> _checkForPendingRetrospectives() async {
    try {
      final gigNeedingReview = await GigRetrospectiveService.checkForRetrospectiveOnStartup();
      final allGigsNeedingReview = await GigRetrospectiveService.getGigsNeedingRetrospective();

      if (mounted && gigNeedingReview != null) {
        setState(() {
          _gigNeedingReview = gigNeedingReview;
          _totalGigsNeedingReview = allGigsNeedingReview.length;
          _showRetrospectiveBanner = true;
        });
      }
    } catch (e) {
      print('Error checking for retrospectives: $e');
    }
  }

  void _dismissRetrospectiveBanner() async {
    setState(() {
      _showRetrospectiveBanner = false;
    });

    // Check if there are more gigs to review
    final gigsNeedingReview = await GigRetrospectiveService.getGigsNeedingRetrospective();
    if (gigsNeedingReview.isNotEmpty && mounted) {
      setState(() {
        _gigNeedingReview = gigsNeedingReview.first;
        _totalGigsNeedingReview = gigsNeedingReview.length;
        _showRetrospectiveBanner = true;
      });
    }
  }

  void _onRetrospectiveComplete() {
    // Refresh the UI to reflect the completed retrospective
    globalRefreshNotifier.notify();
    _dismissRetrospectiveBanner();
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
        case DemoStep.none:
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
        await showDialog(
          context: context,
          builder: (context) {
            return BookingDialog(
              googleApiKey: googleApiKey,
              existingGigs: existingGigs,
            );
          },
        );
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

  Future<void> _launchThirdRockURL() async {
    final Uri url = Uri.parse('https://www.thirdrockmusiccenter.com/');
    if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar( const SnackBar(content: Text('Could not launch website')), );
    }
  }

  @override
  Widget build(BuildContext context) {
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
          body: Stack(
            children: [
              Column(
                children: <Widget>[
                  // Retrospective notification banner
                  if (_showRetrospectiveBanner && _gigNeedingReview != null)
                    RetrospectiveNotificationBanner(
                      gig: _gigNeedingReview!,
                      totalPendingCount: _totalGigsNeedingReview,
                      onDismiss: _dismissRetrospectiveBanner,
                      onComplete: _onRetrospectiveComplete,
                    ),
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