// lib/main.dart
import 'package:in_app_review/in_app_review.dart';
import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// <<< 1. ADD THIS IMPORT
// <<< 1. ADD THIS IMPORT

import 'package:provider/provider.dart';
import 'features/app_demo/providers/demo_provider.dart';
import 'features/app_demo/widgets/tutorial_overlay.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'features/gigs/views/gig_calculator_page.dart';
import 'features/map_venues/views/map.dart';
import 'features/gigs/views/gigs.dart';
import 'features/profile/views/profile.dart';
import 'core/widgets/page_background_wrapper.dart';
import 'package:url_launcher/url_launcher.dart';
import 'global_refresh_notifier.dart';
import 'features/app_demo/widgets/animated_text.dart'; // <<< IMPORT THE NEW WIDGET


// A flexible class for the global demo steps
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

  // final GoogleMapsFlutterPlatform mapsImplementation = GoogleMapsFlutterPlatform.instance;
  // if (mapsImplementation is GoogleMapsFlutterAndroid) {
  //   mapsImplementation.useAndroidViewSurface = false;
  // }

  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
  ]);

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
  bool _isLoading = true;

  late List<String?> _pageBackgroundPaths;
  late List<Color?> _pageBackgroundColors;
  late List<double> _pageBackgroundOpacities;

  final GlobalKey _venuesTabKey = GlobalKey();
  final GlobalKey _myGigsTabKey = GlobalKey();
  late final List<_GlobalDemoStep> _globalDemoScript;

  static final List<Widget> _widgetOptions = <Widget>[
    const GigCalculator(),
    const MapPage(),
    const GigsPage(),
    const ProfilePage(),
  ];

  static const List<String> _pageTitles = <String>[
    'Gig Calculator',
    'Venues',
    'My Gigs',
    'Profile',
  ];

  static const List<String?> _defaultBackgroundImages = [
    'assets/background1.png',
    null,
    'assets/background2.png',
    'assets/background3.png',
  ];
  static const double _defaultOpacity = 0.7;

  @override
  void initState() {
    super.initState();
    _initializeSettings();
    Provider.of<GlobalRefreshNotifier>(context, listen: false).addListener(_onSettingsChanged);
    Provider.of<DemoProvider>(context, listen: false).addListener(_onDemoStateChanged);
    _checkAndRunFirstTimeDemo();

    // Define the script for the global overlays shown on this page
    _globalDemoScript = [
      // Step 12
      _GlobalDemoStep(
          key: _venuesTabKey,
          text: 'You can now see your booked gig on the Venues Map! Come back here after the demo and click on places to add them or book gigs right from the map!',
          alignment: Alignment.bottomCenter),
      // Step 13
      _GlobalDemoStep(
          key: _myGigsTabKey,
          text: 'On the My Gigs List, you can see your gig in the list of Upcoming gigs.',
          alignment: Alignment.bottomCenter),
      // Step 14 (The new final step)
      _GlobalDemoStep(
        key: null, // No UI element to highlight
        alignment: Alignment.center,
        nextButtonText: 'FINISH', // The button will say "FINISH"
        hideSkipButton: true,
        customChild: const AnimatedText(
          text: "Hey, It's Cliff. Thank you! It's not just an app, it's a movement. I can't do this without your support. I want to do this with you. I need your feedback! I look forward to hearing from you! NOW GO BOOK THEM MONEY GIGS!",
          style: TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.w600,
            height: 1.5, // Line spacing
            shadows: [Shadow(blurRadius: 8, color: Colors.black)],
          ),
        ),
      ),
    ];
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
      if (demoProvider.currentStep == 1) {
        targetIndex = 0; // Go to Calculator
      } else if (demoProvider.currentStep == 12) {
        targetIndex = 1; // Go to Venues
      } else if (demoProvider.currentStep == 13) {
        targetIndex = 2; // Go to My Gigs
      } else if (demoProvider.currentStep == 14) {
        targetIndex = 2; // Stay on "My Gigs" for the final message
      }

      if (targetIndex != -1 && _selectedIndex != targetIndex) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            setState(() { _selectedIndex = targetIndex; });
          }
        });
      } else {
        // If we are already on the right page, just rebuild to show the new overlay
        setState(() {});
      }
    } else {
      // If the demo just ended, rebuild to hide the overlay
      setState(() {});
    }
  }

  void _onSettingsChanged() {
    _initializeSettings();
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
      _isLoading = false;
    });
  }

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  Future<void> _launchThirdRockURL() async {
    final Uri url = Uri.parse('https://www.thirdrockmusiccenter.com/');
    if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not launch website')),
        );
      }
    }
  }

  Future<void> _startDemo({bool isFirstTime = false}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(DemoProvider.hasSeenIntroKey, true);

    if (mounted) {
      Provider.of<DemoProvider>(context, listen: false).startDemo();
      if (_selectedIndex != 0) {
        setState(() => _selectedIndex = 0);
      }
    }
  }

  Widget _buildGlobalDemoOverlay(DemoProvider demoProvider) {
    int currentStepIndex = -1;
    if (demoProvider.currentStep == 12) {
      currentStepIndex = 0;
    } else if (demoProvider.currentStep == 13) {
      currentStepIndex = 1;
    } else if (demoProvider.currentStep == 14) { // Handle step 14
      currentStepIndex = 2;
    }

    if (currentStepIndex < 0 || currentStepIndex >= _globalDemoScript.length) {
      return const SizedBox.shrink();
    }

    final step = _globalDemoScript[currentStepIndex];

    // Dim the overlay for the final step, but not for the tab highlights
    final bool shouldDimOverlay = demoProvider.currentStep == 14;

    return TutorialOverlay(
      key: ValueKey('global_demo_step_${demoProvider.currentStep}'),
      highlightKey: step.key,
      instructionalText: step.text,
      customInstructionalChild: step.customChild, // Pass the custom widget
      textAlignment: step.alignment,
      hideNextButton: false, // The button is always shown in this global overlay
      nextButtonText: step.nextButtonText, // Pass the custom button text
      showDimmedOverlay: shouldDimOverlay,
      hideSkipButton: step.hideSkipButton,
      onNext: () async {
        if (demoProvider.currentStep == 14) {
          final InAppReview inAppReview = InAppReview.instance;
          if (await inAppReview.isAvailable()) {
            inAppReview.requestReview();
          }
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
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final List<Widget> wrappedPages = List.generate(4, (index) {
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
        child: _widgetOptions[index],
      );
    });

    return Consumer<DemoProvider>(
      builder: (context, demoProvider, child) {
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
          ),
          body: Stack(
            children: [
              Column(
                children: <Widget>[
                  Expanded(
                    child: IndexedStack(
                      index: _selectedIndex,
                      children: wrappedPages,
                    ),
                  ),
                  GestureDetector(
                    onTap: _launchThirdRockURL,
                    child: Container(
                      height: 70,
                      padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
                      decoration: BoxDecoration(
                        color: Colors.grey[850],
                        border: Border(top: BorderSide(color: Colors.grey.shade700, width: 1.0)),
                      ),
                      child: Row(
                        children: <Widget>[
                          Image.asset('assets/third_rock_logo.png',
                              height: 50.0, width: 50.0, fit: BoxFit.contain),
                          const SizedBox(width: 12.0),
                          Expanded(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Text('Third Rock Music Center',
                                    style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 15,
                                        color: Colors.orangeAccent.shade100)),
                                Text('Your one-stop shop for musical gear!',
                                    style: TextStyle(fontSize: 12, color: Colors.grey[300])),
                              ],
                            ),
                          ),
                          Icon(Icons.open_in_new, color: Colors.orangeAccent.shade100, size: 20.0),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              if (demoProvider.isDemoModeActive) _buildGlobalDemoOverlay(demoProvider),
            ],
          ),
          bottomNavigationBar: BottomNavigationBar(
            items: <BottomNavigationBarItem>[
              const BottomNavigationBarItem(icon: Icon(Icons.calculate), label: 'Calc'),
              BottomNavigationBarItem(
                  icon: Container(key: _venuesTabKey, child: const Icon(Icons.map)), label: 'Venues'),
              BottomNavigationBarItem(
                  icon: Container(key: _myGigsTabKey, child: const Icon(Icons.list)), label: 'My Gigs'),
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
