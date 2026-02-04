// lib/features/app_demo/widgets/coaching_demo_flow.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:the_money_gigs/features/profile/views/widgets/address_form_fields.dart'; // 🎯 IMPORT
import '../providers/demo_provider.dart';
import 'animated_text.dart';

/// A full-screen coaching overlay that guides users through initial setup
/// Steps: Instruments → Genres → Persona → Address → Min Rate
class CoachingDemoFlow extends StatefulWidget {
  final VoidCallback onComplete;

  const CoachingDemoFlow({
    super.key,
    required this.onComplete,
  });

  @override
  State<CoachingDemoFlow> createState() => _CoachingDemoFlowState();
}

class _CoachingDemoFlowState extends State<CoachingDemoFlow> {
  int _currentStep = 0;

  // Step 1: Instruments
  final Set<String> _selectedInstruments = {};
  final TextEditingController _customInstrumentController = TextEditingController();

  // Step 2: Genres
  final Set<String> _selectedGenres = {};
  final TextEditingController _customGenreController = TextEditingController();

  // Step 3: Persona
  String? _selectedPersona;


  // Step 5: Min Rate
  final TextEditingController _minRateController = TextEditingController();

  final _address1Controller = TextEditingController();
  final _address2Controller = TextEditingController();
  final _cityController = TextEditingController();
  final _zipCodeController = TextEditingController();
  String? _selectedState;
  final List<String> _usStates = [ 'AL', 'AK', 'AZ', 'AR', 'CA', 'CO', 'CT', 'DE', 'FL', 'GA', 'HI', 'ID', 'IL', 'IN', 'IA', 'KS', 'KY', 'LA', 'ME', 'MD', 'MA', 'MI', 'MN', 'MS', 'MO', 'MT', 'NE', 'NV', 'NH', 'NJ', 'NM', 'NY', 'NC', 'ND', 'OH', 'OK', 'OR', 'PA', 'RI', 'SC', 'SD', 'TN', 'TX', 'UT', 'VT', 'VA', 'WA', 'WV', 'WI', 'WY' ];


  // Suggestions
  final List<String> _instrumentSuggestions = [
    'Vocals', 'Acoustic Guitar', 'Electric Guitar', 'Bass Guitar', 'Drums',
    'Percussion', 'Keyboard', 'Piano', 'Saxophone', 'Trumpet', 'Violin', 'Cello'
  ];

  final List<String> _genreSuggestions = [
    'Rock', 'Pop', 'Country', 'Jazz', 'Blues', 'R&B/Soul', 'Hip Hop',
    'Electronic', 'Folk', 'Classical', 'Reggae', 'Metal'
  ];

  final Map<String, Map<String, dynamic>> _personaOptions = {
    'beginner': {
      'title': 'Just Getting Started',
      'description': 'Looking to find my first gigs',
      'suggestedRate': 15,
      'icon': Icons.music_note,
    },
    'intermediate': {
      'title': 'Regular Performer',
      'description': 'I play 4-8 gigs a month',
      'suggestedRate': 25,
      'icon': Icons.star,
    },
    'professional': {
      'title': 'Professional Musician',
      'description': 'Music is my primary income',
      'suggestedRate': 40,
      'icon': Icons.stars,
    },
  };

  @override
  void dispose() {
    _customInstrumentController.dispose();
    _customGenreController.dispose();
    _address1Controller.dispose();
    _address2Controller.dispose();
    _cityController.dispose();
    _zipCodeController.dispose();
    _minRateController.dispose();
    super.dispose();
  }

  Future<void> _saveAndContinue() async {
    final prefs = await SharedPreferences.getInstance();

    switch (_currentStep) {
      case 0: // Instruments
        if (_selectedInstruments.isEmpty) {
          _showValidationError('Please select at least one instrument or skill');
          return;
        }
        await prefs.setStringList('profile_instrument_tags', _selectedInstruments.toList());
        break;

      case 1: // Genres
        if (_selectedGenres.isEmpty) {
          _showValidationError('Please select at least one genre');
          return;
        }
        await prefs.setStringList('profile_genre_tags', _selectedGenres.toList());
        break;

      case 2: // Persona
        if (_selectedPersona == null) {
          _showValidationError('Please select your experience level');
          return;
        }
        await prefs.setString('user_persona', _selectedPersona!);
        // Pre-fill the rate based on persona
        final suggestedRate = _personaOptions[_selectedPersona]!['suggestedRate'] as int;
        _minRateController.text = suggestedRate.toString();
        break;

    // 🎯 NEW: Logic for the Address step
      case 3: // Address
      // This is optional, so we just save whatever data was entered
        await prefs.setString('profile_address1', _address1Controller.text);
        await prefs.setString('profile_address2', _address2Controller.text);
        await prefs.setString('profile_city', _cityController.text);
        if (_selectedState != null) {
          await prefs.setString('profile_state', _selectedState!);
        }
        await prefs.setString('profile_zip_code', _zipCodeController.text);
        break;

      case 4: // Min Rate (was 3)
        final rate = int.tryParse(_minRateController.text);
        if (rate == null || rate <= 0) {
          _showValidationError('Please enter a valid minimum hourly rate');
          return;
        }
        await prefs.setInt('profile_min_hourly_rate', rate);
        // Mark that intro has been seen
        await prefs.setBool(DemoProvider.hasSeenIntroKey, true);
        // Exit the coaching flow and trigger the map step
        widget.onComplete();
        return;
    }

    setState(() {
      _currentStep++;
    });
  }

  void _showValidationError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.orange.shade700,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _skip() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Skip Onboarding?'),
        content: const Text('You can always update your profile later from the Profile tab.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Skip'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(DemoProvider.hasSeenIntroKey, true);
      if (mounted) {
        Provider.of<DemoProvider>(context, listen: false).endDemo();
      }
    }
  }

  // 🎯 NEW: Helper method for input decoration to pass to the form fields
  InputDecoration _formInputDecoration({required String labelText, String? hintText, IconData? icon}) {
    return InputDecoration(
      labelText: labelText,
      labelStyle: TextStyle(color: Colors.orangeAccent.shade100),
      hintText: hintText,
      hintStyle: const TextStyle(color: Colors.white70),
      prefixIcon: icon != null ? Icon(icon, color: Colors.orangeAccent.shade100) : null,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8.0)),
      enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.grey.shade600), borderRadius: BorderRadius.circular(8.0)),
      focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: Theme.of(context).colorScheme.primary, width: 2.0), borderRadius: BorderRadius.circular(8.0)),
      errorBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.redAccent.shade200, width: 1.5), borderRadius: BorderRadius.circular(8.0)),
      focusedErrorBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.redAccent.shade200, width: 2.0), borderRadius: BorderRadius.circular(8.0)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black87,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            children: [
              // Header with progress (This is fine)
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Getting Started',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  TextButton(
                    onPressed: _skip,
                    child: const Text('Skip', style: TextStyle(color: Colors.white70)),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              // 🎯 Update progress indicator for 5 total steps
              LinearProgressIndicator(
                value: (_currentStep + 1) / 5,
                backgroundColor: Colors.white24,
                valueColor: AlwaysStoppedAnimation<Color>(Theme.of(context).colorScheme.primary),
              ),
              const SizedBox(height: 32),

              Expanded(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  transitionBuilder: (Widget child, Animation<double> animation) {
                    final slideAnimation = Tween<Offset>(
                      begin: const Offset(0.5, 0),
                      end: Offset.zero,
                    ).animate(animation);
                    return FadeTransition(
                      opacity: animation,
                      child: SlideTransition(
                        position: slideAnimation,
                        child: child,
                      ),
                    );
                  },
                  child: SingleChildScrollView(
                    key: ValueKey<int>(_currentStep),
                    child: _buildStepContent(),
                  ),
                ),
              ),

              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  if (_currentStep > 0)
                    TextButton.icon(
                      onPressed: () {
                        setState(() {
                          _currentStep--;
                        });
                      },
                      icon: const Icon(Icons.arrow_back, color: Colors.white70),
                      label: const Text('Back', style: TextStyle(color: Colors.white70)),
                    )
                  else
                    const SizedBox.shrink(),
                  ElevatedButton(
                    onPressed: _saveAndContinue,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                      backgroundColor: Theme.of(context).colorScheme.primary,
                    ),
                    // 🎯 Update final step check to 4
                    child: Text(
                      _currentStep == 4 ? 'Get Started!' : 'Continue',
                      style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStepContent() {
    switch (_currentStep) {
      case 0: return _buildInstrumentsStep();
      case 1: return _buildGenresStep();
      case 2: return _buildPersonaStep();
    // 🎯 UPDATED: Call the new address step builder
      case 3: return _buildAddressStep();
      case 4: return _buildMinRateStep();
      default: return const SizedBox.shrink();
    }
  }

  // _buildInstrumentsStep(), _buildGenresStep(), and _buildPersonaStep() remain unchanged...

  // Paste the existing _buildInstrumentsStep method here
  Widget _buildInstrumentsStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const AnimatedText(
          text: 'What instrument(s) do you play?',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 24),

        // Selected tags
        if (_selectedInstruments.isNotEmpty) ...[
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _selectedInstruments.map((instrument) {
              return Chip(
                label: Text(instrument, style: const TextStyle(color: Colors.white)),
                backgroundColor: Theme.of(context).colorScheme.primary,
                deleteIcon: const Icon(Icons.close, size: 18, color: Colors.white),
                onDeleted: () {
                  setState(() {
                    _selectedInstruments.remove(instrument);
                  });
                },
              );
            }).toList(),
          ),
          const SizedBox(height: 16),
        ],

        // Suggestions
        Text(
          'Popular choices:',
          style: TextStyle(
            fontSize: 16,
            color: Colors.orangeAccent.shade100,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _instrumentSuggestions
              .where((s) => !_selectedInstruments.contains(s))
              .map((instrument) {
            return ActionChip(
              label: Text(instrument),
              onPressed: () {
                setState(() {
                  _selectedInstruments.add(instrument);
                });
              },
            );
          }).toList(),
        ),

        const SizedBox(height: 24),

        // Custom input
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _customInstrumentController,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: 'Add your own...',
                  hintStyle: const TextStyle(color: Colors.white54),
                  border: const OutlineInputBorder(),
                  enabledBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: Colors.grey.shade600),
                  ),
                ),
                onSubmitted: (value) {
                  if (value.trim().isNotEmpty) {
                    setState(() {
                      _selectedInstruments.add(value.trim());
                      _customInstrumentController.clear();
                    });
                  }
                },
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(Icons.add_circle, color: Colors.white, size: 32),
              onPressed: () {
                final value = _customInstrumentController.text.trim();
                if (value.isNotEmpty) {
                  setState(() {
                    _selectedInstruments.add(value);
                    _customInstrumentController.clear();
                  });
                }
              },
            ),
          ],
        ),
      ],
    );
  }

  // Paste the existing _buildGenresStep method here
  Widget _buildGenresStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const AnimatedText(
          text: 'What genre(s) do you play?',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 24),

        // Selected tags
        if (_selectedGenres.isNotEmpty) ...[
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _selectedGenres.map((genre) {
              return Chip(
                label: Text(genre, style: const TextStyle(color: Colors.white)),
                backgroundColor: Theme.of(context).colorScheme.primary,
                deleteIcon: const Icon(Icons.close, size: 18, color: Colors.white),
                onDeleted: () {
                  setState(() {
                    _selectedGenres.remove(genre);
                  });
                },
              );
            }).toList(),
          ),
          const SizedBox(height: 16),
        ],

        // Suggestions
        Text(
          'Popular choices:',
          style: TextStyle(
            fontSize: 16,
            color: Colors.orangeAccent.shade100,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _genreSuggestions
              .where((s) => !_selectedGenres.contains(s))
              .map((genre) {
            return ActionChip(
              label: Text(genre),
              onPressed: () {
                setState(() {
                  _selectedGenres.add(genre);
                });
              },
            );
          }).toList(),
        ),

        const SizedBox(height: 24),

        // Custom input
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _customGenreController,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: 'Add your own...',
                  hintStyle: const TextStyle(color: Colors.white54),
                  border: const OutlineInputBorder(),
                  enabledBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: Colors.grey.shade600),
                  ),
                ),
                onSubmitted: (value) {
                  if (value.trim().isNotEmpty) {
                    setState(() {
                      _selectedGenres.add(value.trim());
                      _customGenreController.clear();
                    });
                  }
                },
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(Icons.add_circle, color: Colors.white, size: 32),
              onPressed: () {
                final value = _customGenreController.text.trim();
                if (value.isNotEmpty) {
                  setState(() {
                    _selectedGenres.add(value);
                    _customGenreController.clear();
                  });
                }
              },
            ),
          ],
        ),
      ],
    );
  }

  // Paste the existing _buildPersonaStep method here
  Widget _buildPersonaStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const AnimatedText(
          text: 'Tell us about your experience',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'This helps us customize your experience',
          style: TextStyle(
            fontSize: 16,
            color: Colors.white70,
          ),
        ),
        const SizedBox(height: 32),

        ..._personaOptions.entries.map((entry) {
          final key = entry.key;
          final data = entry.value;
          final isSelected = _selectedPersona == key;

          return Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: InkWell(
              onTap: () {
                setState(() {
                  _selectedPersona = key;
                });
              },
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: isSelected
                      ? Theme.of(context).colorScheme.primary.withOpacity(0.3)
                      : Colors.white10,
                  border: Border.all(
                    color: isSelected
                        ? Theme.of(context).colorScheme.primary
                        : Colors.white24,
                    width: isSelected ? 2 : 1,
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(
                      data['icon'] as IconData,
                      size: 40,
                      color: isSelected
                          ? Theme.of(context).colorScheme.primary
                          : Colors.white70,
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            data['title'] as String,
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: isSelected ? Colors.white : Colors.white70,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            data['description'] as String,
                            style: const TextStyle(
                              fontSize: 14,
                              color: Colors.white60,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (isSelected)
                      Icon(
                        Icons.check_circle,
                        color: Theme.of(context).colorScheme.primary,
                        size: 32,
                      ),
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ],
    );
  }

  // 🎯 NEW: The new method to build the address step UI.
  Widget _buildAddressStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const AnimatedText(text: "What's your home base?", style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white)),
        const SizedBox(height: 8),
        const Text("We use this to calculate travel distance to gigs. You can skip this and add it later in your Profile.", style: TextStyle(fontSize: 16, color: Colors.white70)),
        const SizedBox(height: 32),
        AddressFormFields(
          address1Controller: _address1Controller,
          address2Controller: _address2Controller,
          cityController: _cityController,
          zipCodeController: _zipCodeController,
          selectedState: _selectedState,
          usStates: _usStates,
          onStateChanged: (newValue) => setState(() => _selectedState = newValue),
          formInputDecoration: ({required String labelText, String? hintText, IconData? icon}) => _formInputDecoration(labelText: labelText, hintText: hintText, icon: icon),
        ),
      ],
    );
  }

  // Paste the existing _buildMinRateStep method here
  Widget _buildMinRateStep() {
    final suggestedRate = _selectedPersona != null
        ? _personaOptions[_selectedPersona]!['suggestedRate'] as int
        : 20;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const AnimatedText(
          text: 'What\'s your minimum hourly rate?',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Based on your experience, we suggest \$${suggestedRate}/hour',
          style: TextStyle(
            fontSize: 16,
            color: Colors.orangeAccent.shade100,
          ),
        ),
        const SizedBox(height: 32),
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white10,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white24),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Minimum Hourly Rate',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  const Text(
                    '\$',
                    style: TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _minRateController,
                      keyboardType: TextInputType.number,
                      style: const TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                      decoration: const InputDecoration(
                        hintText: '0',
                        hintStyle: TextStyle(color: Colors.white38),
                        border: OutlineInputBorder(),
                        enabledBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: Colors.white38),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    '/hr',
                    style: TextStyle(
                      fontSize: 20,
                      color: Colors.white70,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.blue.shade900.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.blue.shade700),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, color: Colors.blue.shade300),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        'This is the minimum you want to make per hour after expenses. You can always adjust this later.',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
