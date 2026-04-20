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
  print("🚀 Initializing Network Services...");
  try {
    String apiKey = _getRevenueCatApiKey();
    await Purchases.configure(PurchasesConfiguration(apiKey));
    print('✅ RevenueCat initialized (${kDebugMode ? 'TEST' : 'PRODUCTION'})');
  } catch (e) {
    print('❌ Error initializing RevenueCat: $e');
  }
  _areNetworkServicesInitialized = true;
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  print('✅ Firebase Initialized');

  DemoTrackingService().syncPendingData();

  final prefs = await SharedPreferences.getInstance();
  final bool hasEverConnected = prefs.getBool('is_connected_to_network') ?? false;

  if (hasEverConnected) {
    print("👤 Network user — initializing RevenueCat at startup.");
    await initializeNetworkServices();
  } else {
    print("👤 Standalone user — skipping RevenueCat initialization.");
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
  // ✅ Start on Venues (Map) tab — index 0
  int _selectedIndex = 0;
  bool _isInitializingLocalServices = true;
  bool _showOnboardingFlow = false;

  final List<Widget?> _widgetInstances = List.generate(4, (_) => null);

  late List<String?> _pageBackgroundPaths;
  late List<Color?> _pageBackgroundColors;
  late List<double> _pageBackgroundOpacities;

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
    print('🎬 Main: _checkFirstLaunch() called');
    final prefs = await SharedPreferences.getInstance();
    const bool forceDemoForTesting = false;

    final hasSeenIntro =
    forceDemoForTesting ? false : (prefs.getBool(DemoProvider.hasSeenIntroKey) ?? false);

    print('🎬 Main: hasSeenIntro=$hasSeenIntro, mounted=$mounted');

    if (!hasSeenIntro && mounted) {
      print('🎬 Main: First launch — starting onboarding...');
      await Provider.of<DemoProvider>(context, listen: false)
          .startDemo(force: forceDemoForTesting);
    }
  }

  Future<void> _initializeAppServices() async {
    final results = await Future.wait([
      _initializeSettings(),
      _checkForAppUpdate(),
      GigRetrospectiveService.checkForRetrospectiveOnStartup(),
    ]);

    final pendingGigResult = results[2] as Gig?;

    tz.initializeTimeZones();
    final notificationService = NotificationService();
    // init() must run at startup — sets up timezone + plugin so that
    // already-scheduled gig reminders fire correctly.
    await notificationService.init();
    await notificationService.debugPendingNotifications();
    // requestPermissions() is intentionally NOT called here.
    // The user opts in from the Profile page so they understand why
    // we are asking before the OS dialog appears.

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
    print(
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
      print('Error launching email: $e');
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
      print('Error opening Add Gig dialog: $e');
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

    // ✅ UPDATED: Tabs are now 0=Map, 1=Pay, 2=Gigs, 3=Profile
    Widget buildPage(int index) {
      if (_widgetInstances[index] == null) {
        switch (index) {
          case 0: _widgetInstances[index] = const MapPage(); break;       // ← Venues FIRST
          case 1: _widgetInstances[index] = const GigCalculator(); break; // ← Pay second
          case 2: _widgetInstances[index] = const GigsPage(); break;
          case 3: _widgetInstances[index] = const ProfilePage(); break;
        }
      }
      return _widgetInstances[index]!;
    }

    return Consumer<DemoProvider>(
      builder: (context, demoProvider, child) {
        // ✅ NEW: Show simplified onboarding instead of the old coaching flow
        if (_showOnboardingFlow &&
            demoProvider.currentStep == DemoStep.onboardingWelcome) {
          return OnboardingFlow(
            onComplete: () {
              print('🎬 Main: Onboarding complete — entering app');
              demoProvider.nextStep(); // Marks as complete, sets hasSeenIntroKey
            },
          );
        }

        // Normal app shell
        return Scaffold(
          extendBodyBehindAppBar: true,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            leading: Padding(
              padding: const EdgeInsets.all(8.0),
              child: Image.asset('assets/app_icon.png'),
            ),
            title: Text(_pageTitles[_selectedIndex]),
            actions: [
              // Add New Gig Button
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
              // ✅ NEW: Feedback/Question Button
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
        child: MediaQuery.removePadding(
        context: context,
        removeTop: _showRetrospectiveBanner && _gigNeedingReview != null,
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
             ),
            ],
          ),
          bottomNavigationBar: BottomNavigationBar(
            // ✅ TAB ORDER UPDATED: Map → Pay → Gigs → Profile
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