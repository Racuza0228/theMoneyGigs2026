// lib/main.dart
import 'package:in_app_review/in_app_review.dart';
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
import 'features/app_demo/widgets/tutorial_overlay.dart';
import 'features/gigs/views/gig_calculator_page.dart';
import 'features/map_venues/views/map.dart';
import 'features/gigs/views/gigs.dart';
import 'features/profile/views/profile.dart';
import 'core/widgets/page_background_wrapper.dart';
import 'package:url_launcher/url_launcher.dart';
import 'global_refresh_notifier.dart';
import 'features/app_demo/widgets/animated_text.dart';

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

class _GlobalDemoStep {
  final GlobalKey? key;
  final String text;
  final Alignment alignment;
  final Widget? customChild;
  final String nextButtonText;
  final bool hideSkipButton;

  _GlobalDemoStep({
    this.key,
    this.text = '',
    required this.alignment,
    this.customChild,
    this.nextButtonText = 'NEXT',
    this.hideSkipButton = false,
  });
}

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
        ChangeNotifierProvider(create: (_) => GlobalRefreshNotifier()),
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

  final List<Widget?> _widgetInstances = List.generate(4, (_) => null);

  late List<String?> _pageBackgroundPaths;
  late List<Color?> _pageBackgroundColors;
  late List<double> _pageBackgroundOpacities;

  final GlobalKey _venuesTabKey = GlobalKey();
  final GlobalKey _myGigsTabKey = GlobalKey();
  late final List<_GlobalDemoStep> _globalDemoScript;

  static const List<String> _pageTitles = [ 'Gig Pay', 'Venues', 'My Gigs', 'Profile', ];
  static const List<String?> _defaultBackgroundImages = [ 'assets/background1.png', null, 'assets/background2.png', 'assets/background3.png', ];
  static const double _defaultOpacity = 0.7;

  @override
  void initState() {
    super.initState();
    _initializeAppServices();

    Provider.of<GlobalRefreshNotifier>(context, listen: false).addListener(_onSettingsChanged);
    Provider.of<DemoProvider>(context, listen: false).addListener(_onDemoStateChanged);

    _globalDemoScript = [
      _GlobalDemoStep( key: _venuesTabKey, text: 'You can now see your booked gig on the Venues Map! Come back here after the demo and click on places to add them or book gigs right from the map!', alignment: Alignment.bottomCenter),
      _GlobalDemoStep( key: _myGigsTabKey, text: 'On the My Gigs List, you can see your gig in the list of Upcoming gigs.', alignment: Alignment.bottomCenter),
      _GlobalDemoStep( key: null, alignment: Alignment.center, nextButtonText: 'FINISH', hideSkipButton: true, customChild: const AnimatedText( text: "Hey, It's Cliff. Thank you! It's not just an app, it's a movement. I can't do this without your support. I want to do this with you. I need your feedback! I look forward to hearing from you! NOW GO BOOK THEM MONEY GIGS!", style: TextStyle( color: Colors.white, fontSize: 20, fontWeight: FontWeight.w600, height: 1.5, shadows: [Shadow(blurRadius: 8, color: Colors.black)], ), ), ),
    ];
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

    // This needs SharedPreferences, so it runs after _initializeSettings.
    await _checkAndRunFirstTimeDemo();

    // Once local services are ready, show the UI.
    if (mounted) {
      setState(() {
        _isInitializingLocalServices = false;
      });
    }
  }

  @override
  void dispose() {
    Provider.of<GlobalRefreshNotifier>(context, listen: false).removeListener(_onSettingsChanged);
    Provider.of<DemoProvider>(context, listen: false).removeListener(_onDemoStateChanged);
    super.dispose();
  }

  void _onDemoStateChanged() {
    final demoProvider = Provider.of<DemoProvider>(context, listen: false);
    if (!mounted) return;
    if (demoProvider.isDemoModeActive) {
      int targetIndex = -1;
      if (demoProvider.currentStep == 1) { targetIndex = 0; }
      else if (demoProvider.currentStep == 12) { targetIndex = 1; }
      else if (demoProvider.currentStep == 13) { targetIndex = 2; }
      else if (demoProvider.currentStep == 14) { targetIndex = 2; }

      if (targetIndex != -1 && _selectedIndex != targetIndex) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) setState(() { _selectedIndex = targetIndex; });
        });
      } else {
        setState(() {});
      }
    } else {
      setState(() {});
    }
  }

  void _onSettingsChanged() => _initializeSettings();

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

  Future<void> _checkAndRunFirstTimeDemo() async {
    final prefs = await SharedPreferences.getInstance();
    final bool hasSeenIntro = prefs.getBool(DemoProvider.hasSeenIntroKey) ?? false;
    if (!hasSeenIntro && mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _startDemo(isFirstTime: true);
      });
    }
  }

  void _onItemTapped(int index) => setState(() { _selectedIndex = index; });

  Future<void> _launchThirdRockURL() async {
    final Uri url = Uri.parse('https://www.thirdrockmusiccenter.com/');
    if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar( const SnackBar(content: Text('Could not launch website')), );
    }
  }

  Future<void> _startDemo({bool isFirstTime = false}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(DemoProvider.hasSeenIntroKey, true);
    if (mounted) {
      Provider.of<DemoProvider>(context, listen: false).startDemo();
      if (_selectedIndex != 0) setState(() => _selectedIndex = 0);
    }
  }

  Widget _buildGlobalDemoOverlay(DemoProvider demoProvider) {
    int currentStepIndex = -1;
    if (demoProvider.currentStep == 12) currentStepIndex = 0;
    else if (demoProvider.currentStep == 13) currentStepIndex = 1;
    else if (demoProvider.currentStep == 14) currentStepIndex = 2;

    if (currentStepIndex < 0 || currentStepIndex >= _globalDemoScript.length) {
      return const SizedBox.shrink();
    }
    final step = _globalDemoScript[currentStepIndex];
    final bool shouldDimOverlay = demoProvider.currentStep == 14;
    return TutorialOverlay(
      key: ValueKey('global_demo_step_${demoProvider.currentStep}'),
      highlightKey: step.key,
      instructionalText: step.text,
      customInstructionalChild: step.customChild,
      textAlignment: step.alignment,
      hideNextButton: false,
      nextButtonText: step.nextButtonText,
      showDimmedOverlay: shouldDimOverlay,
      hideSkipButton: step.hideSkipButton,
      onNext: () async {
        if (demoProvider.currentStep == 14) {
          final InAppReview inAppReview = InAppReview.instance;
          if (await inAppReview.isAvailable()) inAppReview.requestReview();
          await Future.delayed(const Duration(seconds: 1));
          demoProvider.endDemo();
        } else {
          demoProvider.nextStep();
        }
      },
    );
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
        return Scaffold(
          extendBodyBehindAppBar: true,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            leading: Padding( padding: const EdgeInsets.all(8.0), child: Image.asset('assets/app_icon.png'), ),
            title: Text(_pageTitles[_selectedIndex]),
          ),
          body: Stack(
            children: [
              Column(
                children: <Widget>[
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
                  GestureDetector(
                    onTap: _launchThirdRockURL,
                    child: Container( height: 70, padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0), decoration: BoxDecoration( color: Colors.grey[850], border: Border(top: BorderSide(color: Colors.grey.shade700, width: 1.0)), ), child: Row( children: <Widget>[ Image.asset('assets/third_rock_logo.png', height: 50.0, width: 50.0, fit: BoxFit.contain), const SizedBox(width: 12.0), Expanded( child: Column( mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[ Text('Third Rock Music Center', style: TextStyle( fontWeight: FontWeight.bold, fontSize: 15, color: Colors.orangeAccent.shade100)), Text('Your one-stop shop for musical gear!', style: TextStyle(fontSize: 12, color: Colors.grey[300])), ], ), ), Icon(Icons.open_in_new, color: Colors.orangeAccent.shade100, size: 20.0), ], ),
                    ),
                  ),
                ],
              ),
              if (demoProvider.isDemoModeActive) _buildGlobalDemoOverlay(demoProvider),
            ],
          ),
          bottomNavigationBar: BottomNavigationBar(
            items: <BottomNavigationBarItem>[
              const BottomNavigationBarItem(icon: Icon(Icons.attach_money_rounded), label: 'Pay'),
              BottomNavigationBarItem( icon: Container(key: _venuesTabKey, child: const Icon(Icons.map)), label: 'Venues'),
              BottomNavigationBarItem( icon: Container(key: _myGigsTabKey, child: const Icon(Icons.list)), label: 'My Gigs'),
              const BottomNavigationBarItem(icon: Icon(Icons.person), label: 'Profile'),
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