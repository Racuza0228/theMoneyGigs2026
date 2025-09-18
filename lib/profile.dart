// lib/profile_page.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // For TextInputFormatter
import 'package:shared_preferences/shared_preferences.dart';
import 'package:the_money_gigs/refreshable_page.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  final _formKey = GlobalKey<FormState>();

  // Controllers for Address fields
  final _address1Controller = TextEditingController();
  final _address2Controller = TextEditingController();
  final _cityController = TextEditingController();
  final _zipCodeController = TextEditingController();

  // Controller for Work Preferences
  final _minHourlyRateController = TextEditingController();

  String? _selectedState;

  // State Variables for Edit/View modes
  bool _isEditingAddress = false;
  bool _isEditingRate = false; // <-- NEW
  bool _profileDataLoaded = false;

  static const String _keyAddress1 = 'profile_address1';
  static const String _keyAddress2 = 'profile_address2';
  static const String _keyCity = 'profile_city';
  static const String _keyState = 'profile_state';
  static const String _keyZipCode = 'profile_zip_code';
  static const String _keyMinHourlyRate = 'profile_min_hourly_rate';

  final List<String> _usStates = [
    'AL', 'AK', 'AZ', 'AR', 'CA', 'CO', 'CT', 'DE', 'FL', 'GA',
    'HI', 'ID', 'IL', 'IN', 'IA', 'KS', 'KY', 'LA', 'ME', 'MD',
    'MA', 'MI', 'MN', 'MS', 'MO', 'MT', 'NE', 'NV', 'NH', 'NJ',
    'NM', 'NY', 'NC', 'ND', 'OH', 'OK', 'OR', 'PA', 'RI', 'SC',
    'SD', 'TN', 'TX', 'UT', 'VT', 'VA', 'WA', 'WV', 'WI', 'WY'
  ];

  @override
  void initState() {
    super.initState();
    _loadProfileData();
  }
  @override
  Future<void> refreshPageData() async {
    print("ProfilePage: Refresh triggered by global refresh button.");
    // Implement your specific refresh logic here
    // e.g., await _loadProfileData();
    setState(() {});
  }

  Future<void> _loadProfileData() async {
    // Don't set _profileDataLoaded = false here if you want the loading indicator
    // to show based on its initial state. The build method should handle the
    // CircularProgressIndicator based on the initial value of _profileDataLoaded.

    try {
      final prefs = await SharedPreferences.getInstance();

      // Check if the widget is still mounted after the await.
      if (!mounted) return;

      // Load address fields
      String address1 = prefs.getString(_keyAddress1) ?? '';
      String address2 = prefs.getString(_keyAddress2) ?? ''; // Load address2 directly
      String city = prefs.getString(_keyCity) ?? '';
      String? state = prefs.getString(_keyState); // This can be null
      String zip = prefs.getString(_keyZipCode) ?? '';

      // Load and process minimum hourly rate
      String minRateString = ''; // Default to empty string
      // Check if the key exists first to avoid unnecessary getInt calls if it was never set
      if (prefs.containsKey(_keyMinHourlyRate)) {
        int? minHourlyRate = prefs.getInt(_keyMinHourlyRate);
        if (minHourlyRate != null && minHourlyRate > 0) { // Only use it if it's a valid positive number
          minRateString = minHourlyRate.toString();
        }
        // If minHourlyRate is 0 or null after being set, it implies it should be treated as empty or reset.
      }
      // The previous complex conditions for minRateString like '0' or 'null'
      // are simplified by this approach. If it was stored as 0 or couldn't be parsed
      // to a positive int, it defaults to ''.

      setState(() {
        _address1Controller.text = address1;
        _address2Controller.text = address2;
        _cityController.text = city;
        _selectedState = state;
        _zipCodeController.text = zip;
        _minHourlyRateController.text = minRateString;

        // Determine initial editing states
        // Start editing address if all core address fields are empty
        bool hasCoreAddressInfo = address1.isNotEmpty ||
            city.isNotEmpty ||
            (state != null && state.isNotEmpty) || // Check if state is not just null but also not empty
            zip.isNotEmpty;
        _isEditingAddress = !hasCoreAddressInfo;

        // Start editing rate if no valid rate is set
        _isEditingRate = minRateString.isEmpty;

        _profileDataLoaded = true; // Data is loaded (or attempted to load)
      });

    } catch (e) {
      // Handle any errors during SharedPreferences access or processing
      print("Error loading profile data: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading profile: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
        setState(() {
          // Even on error, we mark data as "loaded" to stop the loading indicator.
          // The UI will show empty fields or whatever default state is appropriate.
          _profileDataLoaded = true;
          // Optionally, you might want to set _isEditingAddress and _isEditingRate to true
          // to encourage the user to input data if loading failed.
          _isEditingAddress = true;
          _isEditingRate = true;
        });
      }
    }
  }


  @override
  void dispose() {
    _address1Controller.dispose();
    _address2Controller.dispose();
    _cityController.dispose();
    _zipCodeController.dispose();
    _minHourlyRateController.dispose();
    super.dispose();
  }

  Future<void> _saveProfile() async {
    if (_formKey.currentState!.validate()) {
      _formKey.currentState!.save();
      final prefs = await SharedPreferences.getInstance();

      String address1 = _address1Controller.text;
      String address2 = _address2Controller.text;
      String city = _cityController.text;
      String? stateValue = _selectedState;
      String zipCode = _zipCodeController.text;
      int? minHourlyRate = int.tryParse(_minHourlyRateController.text);

      await prefs.setString(_keyAddress1, address1);
      await prefs.setString(_keyAddress2, address2);
      await prefs.setString(_keyCity, city);
      if (stateValue != null) {
        await prefs.setString(_keyState, stateValue);
      } else {
        await prefs.remove(_keyState);
      }
      await prefs.setString(_keyZipCode, zipCode);
      if (minHourlyRate != null) {
        await prefs.setInt(_keyMinHourlyRate, minHourlyRate);
      } else {
        await prefs.remove(_keyMinHourlyRate);
      }

      print('Profile Saved (SharedPreferences)');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Profile saved successfully!')),
        );
        setState(() {
          _isEditingAddress = false;
          _isEditingRate = false; // <-- Switch back to view mode for rate too
        });
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please correct the errors in the form.')),
        );
      }
    }
  }

  InputDecoration _formInputDecoration({
    required String labelText,
    String? hintText,
    IconData? icon,
    String? prefixText,
  }) {
    final formLabelColor = Colors.orangeAccent.shade100;
    final formHintColor = Colors.white70;
    final inputBorderColor = Colors.grey.shade600;
    final focusedInputBorderColor = Theme.of(context).colorScheme.primary;
    final formTextColor = Colors.white;

    return InputDecoration(
      labelText: labelText,
      labelStyle: TextStyle(color: formLabelColor),
      hintText: hintText,
      hintStyle: TextStyle(color: formHintColor),
      prefixText: prefixText,
      prefixStyle: TextStyle(color: formTextColor, fontSize: 16),
      prefixIcon: icon != null ? Icon(icon, color: formLabelColor) : null,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8.0)),
      enabledBorder: OutlineInputBorder(
        borderSide: BorderSide(color: inputBorderColor),
        borderRadius: BorderRadius.circular(8.0),
      ),
      focusedBorder: OutlineInputBorder(
        borderSide: BorderSide(color: focusedInputBorderColor, width: 2.0),
        borderRadius: BorderRadius.circular(8.0),
      ),
      errorBorder: OutlineInputBorder(
        borderSide: BorderSide(color: Colors.redAccent.shade200, width: 1.5),
        borderRadius: BorderRadius.circular(8.0),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderSide: BorderSide(color: Colors.redAccent.shade200, width: 2.0),
        borderRadius: BorderRadius.circular(8.0),
      ),
      contentPadding: icon == null
          ? const EdgeInsets.symmetric(horizontal: 12.0, vertical: 16.0)
          : null,
    );
  }

  Widget _buildSectionTitle(
      String title, {
        bool showEditIcon = false,
        VoidCallback? onEditPressed,
        String tooltip = 'Edit', // Generic tooltip
      }) {
    return Padding(
      padding: const EdgeInsets.only(top: 20.0, bottom: 12.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
                color: Colors.white,
                shadows: [
                  Shadow(
                    offset: const Offset(1.0, 1.0),
                    blurRadius: 2.0,
                    color: Colors.black.withAlpha(128),
                  ),
                ]),
          ),
          if (showEditIcon)
            IconButton(
              icon: Icon(Icons.edit_outlined, color: Colors.orangeAccent.shade100),
              onPressed: onEditPressed,
              tooltip: tooltip,
            ),
        ],
      ),
    );
  }

  Widget _buildAddressDisplay() {
    String displayAddress1 = _address1Controller.text;
    String displayAddress2 = _address2Controller.text;
    String displayCity = _cityController.text;
    String? displayState = _selectedState;
    String displayZip = _zipCodeController.text;

    if (displayAddress1.isEmpty && displayCity.isEmpty && displayState == null && displayZip.isEmpty) {
      return const Center(child: Padding(
        padding: EdgeInsets.symmetric(vertical: 8.0),
        child: Text("No address information available. Tap edit to add.", style: TextStyle(color: Colors.white70)),
      ));
    }

    TextStyle textStyle = const TextStyle(color: Colors.white, fontSize: 16, height: 1.5);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 4.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (displayAddress1.isNotEmpty) Text(displayAddress1, style: textStyle),
          if (displayAddress2.isNotEmpty) Text(displayAddress2, style: textStyle),
          if (displayCity.isNotEmpty || displayState != null || displayZip.isNotEmpty)
            Text(
              "${displayCity.isNotEmpty ? displayCity : ''}"
                  "${displayCity.isNotEmpty && displayState != null ? ', ' : ''}"
                  "${displayState ?? ''} ${displayZip.isNotEmpty ? displayZip : ''}",
              style: textStyle,
            ),
          const SizedBox(height: 10),
        ],
      ),
    );
  }

  Widget _buildRateDisplay() { // <-- NEW WIDGET FOR RATE DISPLAY
    String displayRate = _minHourlyRateController.text;
    if (displayRate.isEmpty) {
      return const Center(child: Padding(
        padding: EdgeInsets.symmetric(vertical: 8.0),
        child: Text("No minimum rate set. Tap edit to add.", style: TextStyle(color: Colors.white70)),
      ));
    }
    TextStyle textStyle = const TextStyle(color: Colors.white, fontSize: 16, height: 1.5);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 4.0),
      child: Text("\$ $displayRate per hour", style: textStyle),
    );
  }


  @override
  Widget build(BuildContext context) {
    if (!_profileDataLoaded) {
      return const Center(child: CircularProgressIndicator());
    }

    final formBackgroundColor = Colors.black.withAlpha(128);
    final formTextColor = Colors.white;

    // Determine if any address data exists for the edit icon logic
    bool hasAddressData = _address1Controller.text.isNotEmpty ||
        _address2Controller.text.isNotEmpty || // Also check address2
        _cityController.text.isNotEmpty ||
        _selectedState != null ||
        _zipCodeController.text.isNotEmpty;

    bool hasRateData = _minHourlyRateController.text.isNotEmpty;


    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 24.0),
      child: Container(
        padding: const EdgeInsets.all(20.0),
        decoration: BoxDecoration(
          color: formBackgroundColor,
          borderRadius: BorderRadius.circular(16.0),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha(100),
              spreadRadius: 2,
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              _buildSectionTitle(
                'Your Address',
                showEditIcon: !_isEditingAddress && hasAddressData,
                onEditPressed: () => setState(() => _isEditingAddress = true),
                tooltip: 'Edit Address',
              ),
              if (_isEditingAddress) ...[
                TextFormField(
                  controller: _address1Controller,
                  style: TextStyle(color: formTextColor, fontSize: 16),
                  decoration: _formInputDecoration(
                    labelText: 'Address 1',
                    hintText: 'Street address, P.O. box, company name, c/o',
                    icon: Icons.home_outlined,
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) return 'Please enter Address 1';
                    return null;
                  },
                ),
                const SizedBox(height: 16.0),
                TextFormField(
                  controller: _address2Controller,
                  style: TextStyle(color: formTextColor, fontSize: 16),
                  decoration: _formInputDecoration(
                    labelText: 'Address 2 (Optional)',
                    hintText: 'Apartment, suite, unit, building, floor, etc.',
                    icon: Icons.apartment_outlined,
                  ),
                ),
                const SizedBox(height: 16.0),
                TextFormField(
                  controller: _cityController,
                  style: TextStyle(color: formTextColor, fontSize: 16),
                  decoration: _formInputDecoration(
                    labelText: 'City',
                    icon: Icons.location_city_outlined,
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) return 'Please enter your city';
                    return null;
                  },
                ),
                const SizedBox(height: 16.0),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Expanded(
                      flex: 2,
                      child: Theme(
                        data: Theme.of(context).copyWith(canvasColor: Colors.grey[800]),
                        child: DropdownButtonFormField<String>(
                          style: TextStyle(color: formTextColor, fontSize: 16),
                          decoration: _formInputDecoration(labelText: 'State'),
                          dropdownColor: Colors.grey[850],
                          value: _selectedState,
                          hint: Text('Select', style: TextStyle(color: Colors.white70)),
                          isExpanded: true,
                          items: _usStates.map<DropdownMenuItem<String>>((String value) {
                            return DropdownMenuItem<String>(
                              value: value,
                              child: Text(value, style: TextStyle(color: formTextColor)),
                            );
                          }).toList(),
                          onChanged: (String? newValue) => setState(() => _selectedState = newValue),
                          validator: (value) {
                            if (value == null || value.isEmpty) return 'Select a state';
                            return null;
                          },
                        ),
                      ),
                    ),
                    const SizedBox(width: 16.0),
                    Expanded(
                      flex: 3,
                      child: TextFormField(
                        controller: _zipCodeController,
                        style: TextStyle(color: formTextColor, fontSize: 16),
                        decoration: _formInputDecoration(labelText: 'Zip Code'),
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(5),
                        ],
                        validator: (value) {
                          if (value == null || value.isEmpty) return 'Enter zip code';
                          if (value.length != 5) return 'Zip must be 5 digits';
                          return null;
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16.0),
              ] else ...[
                _buildAddressDisplay(),
              ],

              _buildSectionTitle(
                'Work Preferences',
                showEditIcon: !_isEditingRate && hasRateData, // <-- Show edit for rate
                onEditPressed: () => setState(() => _isEditingRate = true), // <-- Set editing rate
                tooltip: 'Edit Minimum Rate',
              ),
              if (_isEditingRate) ...[ // <-- Conditional display for rate
                TextFormField(
                  controller: _minHourlyRateController,
                  style: TextStyle(color: formTextColor, fontSize: 16),
                  decoration: _formInputDecoration(
                    labelText: 'Minimum Hourly Rate',
                    hintText: 'e.g., 25',
                    prefixText: '\$ ',
                    icon: Icons.price_change_outlined,
                  ),
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  validator: (value) {
                    if (value == null || value.isEmpty) return null;
                    final rate = int.tryParse(value);
                    if (rate == null) return 'Please enter a valid number';
                    if (rate <= 0) return 'Rate must be > 0';
                    return null;
                  },
                ),
                const SizedBox(height: 10), // Space after rate input
              ] else ...[
                _buildRateDisplay(), // <-- Display rate as text
              ],

              const SizedBox(height: 32.0),
              ElevatedButton(
                onPressed: _saveProfile,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  foregroundColor: Theme.of(context).colorScheme.onPrimary,
                  padding: const EdgeInsets.symmetric(vertical: 16.0),
                  textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.0)),
                  minimumSize: const Size(double.infinity, 50),
                ),
                // Adjust button text if either address or rate is being edited.
                child: Text(_isEditingAddress || _isEditingRate ? 'Save Changes' : 'Save Profile'),
              ),
              const SizedBox(height: 20.0),
            ],
          ),
        ),
      ),
    );
  }
}

