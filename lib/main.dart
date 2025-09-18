// lib/main.dart

import 'package:flutter/material.dart';
import 'gig_calculator.dart';
import 'map.dart';
import 'gigs.dart';
import 'profile.dart';
import 'page_background_wrapper.dart'; // Import the new wrapper
import 'package:url_launcher/url_launcher.dart';
import 'refreshable_page.dart';
import 'package:shared_preferences/shared_preferences.dart';


Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized(); // ENSURE THIS IS CALLED FIRST

  // Optional: If you had any critical SharedPreferences to load *before* runApp,
  // you could do it here. For example:
  // final prefs = await SharedPreferences.getInstance();
  // bool hasSeenOnboarding = prefs.getBool('has_seen_onboarding') ?? false;
  // Now `hasSeenOnboarding` could be passed to MyApp or a global state management solution.
  // However, for most cases, loading within widgets is preferred.

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'The Money Gigs',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
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

  static const List<String> _pageTitles = <String>[
    'Gig Calculator',
    'Venue Map',
    'My Gigs',
    'Profile',
  ];

  // List of background image paths for each page. Null means no background.
  static const List<String?> _pageBackgrounds = <String?>[
    'assets/background1.png', // For GigCalculator
    null,                     // For MapPage
    'assets/background2.png', // For GigsPage
    'assets/background3.png', // For ProfilePage
  ];

  // Optional: Define opacities if you want different ones per background
  static const List<double> _backgroundOpacities = <double>[
    0.7, // Example: GigCalculator background slightly transparent
    1.0, // MapPage (not used as background is null)
    0.8, // Example: GigsPage background
    1.0, // Example: ProfilePage background fully opaque
  ];

  // The actual widgets for each page
  // These should be const if their content doesn't change and they don't have internal state
  // that needs to be preserved by IndexedStack in a specific way by NOT being const.
  // For simplicity and common use with IndexedStack, making them const is often fine.
  static final List<Widget> _widgetOptions = <Widget>[
    const GigCalculator(),
    const MapPage(),
    const GigsPage(),
    const ProfilePage(),
  ];

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  Future<void> _launchThirdRockURL() async {
    final Uri url = Uri.parse('https://www.thirdrockmusiccenter.com/');
    if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
      // Show a SnackBar if the URL can't be launched
      // Ensure context has a ScaffoldMessenger ancestor
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not launch website')),
        );
      }
    }
  }
  @override
  Widget build(BuildContext context) {
    // Get the current page's content, background path, and opacity
    Widget currentPageContent = _widgetOptions.elementAt(_selectedIndex);
    String? currentBackgroundPath = _pageBackgrounds.elementAt(_selectedIndex);
    double currentBackgroundOpacity = _backgroundOpacities.elementAt(_selectedIndex);

    return Scaffold(
      appBar: AppBar(
        leading: Padding(
          padding: const EdgeInsets.all(8.0),
          child: Image.asset(
            'assets/app_icon.png',
            errorBuilder: (BuildContext context, Object exception, StackTrace? stackTrace) {
              //print('Error loading app icon: $exception');
              return const Icon(Icons.error_outline, color: Colors.red);
            },
          ),
        ),
        title: Text(_pageTitles[_selectedIndex]),
      ),
      body: Column(
        children: <Widget>[
          Expanded(
            // Use IndexedStack to preserve page state
            child: IndexedStack(
              index: _selectedIndex,
              children: _widgetOptions.asMap().entries.map((entry) {
                int idx = entry.key;
                Widget pageWidget = entry.value;
                return PageBackgroundWrapper(
                  backgroundImagePath: _pageBackgrounds[idx],
                  backgroundOpacity: _backgroundOpacities[idx], // Apply opacity
                  child: pageWidget,
                );
              }).toList(),
            ),
          ),
          GestureDetector(
            onTap: _launchThirdRockURL, // Make the banner tappable
            child: Container(
              height: 70, // Increased height slightly for better visuals
              padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
              decoration: BoxDecoration(
                // Inspired by the dark theme in your image
                color: Colors.grey[850], // Dark grey background
                // You could also use a gradient like in your image:
                // gradient: LinearGradient(
                //   colors: [Colors.grey.shade800, Colors.black54],
                //   begin: Alignment.centerLeft,
                //   end: Alignment.centerRight,
                // ),
                border: Border( // Subtle top border
                  top: BorderSide(color: Colors.grey.shade700, width: 1.0),
                ),
                // boxShadow: [ // Optional: add a subtle shadow
                //   BoxShadow(
                //     color: Colors.black.withOpacity(0.2),
                //     spreadRadius: 1,
                //     blurRadius: 3,
                //     offset: Offset(0, -1), // changes position of shadow
                //   ),
                // ],
              ),
              child: Row(
                children: <Widget>[
                  // Logo
                  Image.asset(
                    'assets/third_rock_logo.png',
                    height: 50.0, // Adjust as needed
                    width: 50.0,  // Adjust as needed
                    fit: BoxFit.contain,
                    errorBuilder: (context, error, stackTrace) {
                      return const SizedBox(width: 50, height: 50, child: Icon(Icons.store, color: Colors.white70, size: 30)); // Fallback
                    },
                  ),
                  const SizedBox(width: 12.0),
                  // Text Content
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          'Third Rock Music Center',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                            color: Colors.orangeAccent.shade100, // Accent color
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2.0),
                        Text(
                          'Your one-stop shop for musical gear!',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[300], // Lighter text for subtitle
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8.0),
                  // "Visit Us" Icon (Optional)
                  Icon(
                    Icons.open_in_new,
                    color: Colors.orangeAccent.shade100,
                    size: 20.0,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        items: const <BottomNavigationBarItem>[
          BottomNavigationBarItem(
            icon: Icon(Icons.calculate),
            label: 'Calc',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.map),
            label: 'Map',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.list),
            label: 'My Gigs',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person),
            label: 'Profile',
          ),
        ],
        currentIndex: _selectedIndex,
        selectedItemColor: Theme.of(context).colorScheme.primary,
        unselectedItemColor: Colors.grey,
        onTap: _onItemTapped,
        type: BottomNavigationBarType.fixed,
      ),
    );
  }
}
