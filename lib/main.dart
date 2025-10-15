// lib/main.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart'; // Make sure this is imported
import 'features/app_demo/providers/demo_provider.dart'; // *** NEW: Import DemoProvider
import 'features/app_demo/widgets/tutorial_overlay.dart'; // *** FIX: Import the overlay widget
import 'package:shared_preferences/shared_preferences.dart';
import 'features/gigs/views/gig_calculator_page.dart';
import 'features/map_venues/views/map.dart';
import 'features/gigs/views/gigs.dart';
import 'features/profile/views/profile.dart';
import 'core/widgets/page_background_wrapper.dart';
import 'package:url_launcher/url_launcher.dart';

// This simple notifier will allow the profile page to trigger a refresh in main.dart
class RefreshNotifier extends ChangeNotifier {
  void notify() {
    notifyListeners();
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => DemoProvider()),
        ChangeNotifierProvider(create: (_) => RefreshNotifier()),
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
      home: const MainPage(), // This is correct
      debugShowCheckedModeBanner: false,
    );
  }
}

// *** FIX: This class definition is crucial ***
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
    Provider.of<RefreshNotifier>(context, listen: false).addListener(_onSettingsChanged);
  }

  @override
  void dispose() {
    Provider.of<RefreshNotifier>(context, listen: false).removeListener(_onSettingsChanged);
    super.dispose();
  }

  void _onSettingsChanged() {
    print("MainPage: Notified of settings change. Reloading...");
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
        provider = null;
      } else {
        final path = _pageBackgroundPaths[index];
        if (path != null) {
          provider = path.startsWith('/') ? FileImage(File(path)) : AssetImage(path);
        } else {
          final defaultPath = _defaultBackgroundImages[index];
          if (defaultPath != null) {
            provider = AssetImage(defaultPath);
          }
        }
        bgColor = null;
      }

      return PageBackgroundWrapper(
        imageProvider: provider,
        backgroundColor: bgColor,
        backgroundOpacity: _pageBackgroundOpacities[index],
        child: _widgetOptions[index],
      );
    });

    final GlobalKey calcTabKey = GlobalKey();
    final GlobalKey venuesTabKey = GlobalKey();
    final GlobalKey gigsTabKey = GlobalKey();
    final GlobalKey profileTabKey = GlobalKey();
    final GlobalKey thirdRockBannerKey = GlobalKey();

    return Consumer<DemoProvider>(
      builder: (context, demoProvider, child) {
        return Stack(
          children: [
            child!,
            if (demoProvider.isDemoModeActive)
              _buildDemoOverlay(
                context: context,
                provider: demoProvider,
                keys: {
                  'calc': calcTabKey,
                  'venues': venuesTabKey,
                  'gigs': gigsTabKey,
                  'profile': profileTabKey,
                  'banner': thirdRockBannerKey,
                },
              ),
          ],
        );
      },
      child: Scaffold(
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
        body: Column(
          children: <Widget>[
            Expanded(
              child: IndexedStack(
                index: _selectedIndex,
                children: wrappedPages,
              ),
            ),
            GestureDetector(
              key: thirdRockBannerKey,
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
                    Image.asset('assets/third_rock_logo.png', height: 50.0, width: 50.0, fit: BoxFit.contain),
                    const SizedBox(width: 12.0),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text('Third Rock Music Center', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.orangeAccent.shade100)),
                          Text('Your one-stop shop for musical gear!', style: TextStyle(fontSize: 12, color: Colors.grey[300])),
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
        bottomNavigationBar: BottomNavigationBar(
          items: <BottomNavigationBarItem>[
            BottomNavigationBarItem(icon: KeyedSubtree(key: calcTabKey, child: const Icon(Icons.calculate)), label: 'Calc'),
            BottomNavigationBarItem(icon: KeyedSubtree(key: venuesTabKey, child: const Icon(Icons.map)), label: 'Venues'),
            BottomNavigationBarItem(icon: KeyedSubtree(key: gigsTabKey, child: const Icon(Icons.list)), label: 'My Gigs'),
            BottomNavigationBarItem(icon: KeyedSubtree(key: profileTabKey, child: const Icon(Icons.person)), label: 'Profile'),
          ],
          currentIndex: _selectedIndex,
          selectedItemColor: Theme.of(context).colorScheme.primary,
          unselectedItemColor: Colors.grey,
          onTap: _onItemTapped,
          type: BottomNavigationBarType.fixed,
          backgroundColor: Colors.grey[850],
        ),
      ),
    );
  }

  Widget _buildDemoOverlay({
    required BuildContext context,
    required DemoProvider provider,
    required Map<String, GlobalKey> keys,
  }) {
    switch (provider.currentStep) {
      case 1:
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _onItemTapped(2);
        });
        return TutorialOverlay(
          highlightKey: keys['gigs']!,
          instructionalText: "Welcome to The Money Gigs! Let's start with the 'My Gigs' tab, where all your events are organized.",
          textAlignment: Alignment.topCenter,
          onNext: () => provider.nextStep(),
        );
      case 2:
        WidgetsBinding.instance.addPostFrameCallback((_) {
          provider.nextStep();
        });
        return const SizedBox.shrink();
      case 3:
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _onItemTapped(3);
        });
        return TutorialOverlay(
          highlightKey: keys['profile']!,
          instructionalText: "The 'Profile' tab lets you customize the app's look and feel, and reset this demo.",
          textAlignment: Alignment.topCenter,
          onNext: () => provider.nextStep(),
        );
      case 4:
        return TutorialOverlay(
          highlightKey: keys['banner']!,
          instructionalText: "Finally, check out our sponsor, Third Rock Music Center, for all your gear needs!",
          textAlignment: Alignment.center,
          onNext: () {
            provider.endDemo();
            _onItemTapped(0);
          },
        );
      default:
        WidgetsBinding.instance.addPostFrameCallback((_) {
          provider.endDemo();
        });
        return const SizedBox.shrink();
    }
  }
}
