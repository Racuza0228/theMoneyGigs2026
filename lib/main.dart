// lib/main.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'gig_calculator.dart';
import 'map.dart';
import 'gigs.dart';
import 'profile.dart';
import 'page_background_wrapper.dart';
import 'package:url_launcher/url_launcher.dart';

// This simple notifier will allow the profile page to trigger a refresh in main.dart
class RefreshNotifier extends ChangeNotifier {
  void notify() {
    notifyListeners();
  }
}

final refreshNotifier = RefreshNotifier();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyApp());
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

  // State variables for dynamic backgrounds
  late List<String?> _pageBackgroundPaths;
  late List<Color?> _pageBackgroundColors;
  late List<double> _pageBackgroundOpacities;

  static const List<Widget> _widgetOptions = <Widget>[
    GigCalculator(),
    MapPage(),
    GigsPage(),
    ProfilePage(),
  ];

  static const List<String> _pageTitles = <String>[
    'Gig Calculator',
    'Venue Map',
    'My Gigs',
    'Profile',
  ];

  // Default values
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
    refreshNotifier.addListener(_onSettingsChanged);
  }

  @override
  void dispose() {
    refreshNotifier.removeListener(_onSettingsChanged);
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

      // *** FIX: Logic to decide between color, custom image, or default image ***
      ImageProvider? provider;
      Color? bgColor;

      if (color != null) {
        // If a color is set, use it and ensure no image is shown.
        bgColor = color;
        provider = null;
      } else {
        // If no color, check for a custom image path.
        final path = _pageBackgroundPaths[index];
        if (path != null) {
          provider = path.startsWith('/') ? FileImage(File(path)) : AssetImage(path);
        } else {
          // If no custom path, fall back to the default asset image.
          final defaultPath = _defaultBackgroundImages[index];
          if (defaultPath != null) {
            provider = AssetImage(defaultPath);
          }
        }
        // If there's an image, the background color should be null.
        bgColor = null;
      }

      return PageBackgroundWrapper(
        imageProvider: provider,
        backgroundColor: bgColor,
        backgroundOpacity: _pageBackgroundOpacities[index],
        child: _widgetOptions[index],
      );
    });

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
      body: Column(
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
        items: const <BottomNavigationBarItem>[
          BottomNavigationBarItem(icon: Icon(Icons.calculate), label: 'Calc'),
          BottomNavigationBarItem(icon: Icon(Icons.map), label: 'Map'),
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
  }
}
