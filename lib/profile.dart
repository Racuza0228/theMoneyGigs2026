// lib/profile.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'main.dart'; // Import for refreshNotifier

// Keep the rest of your ProfilePage code as it is.
// The key changes are adding the settings icon and the dialog.
class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  // ... (keep all your existing controllers and variables)
  final _formKey = GlobalKey<FormState>();
  final _address1Controller = TextEditingController();
  final _address2Controller = TextEditingController();
  final _cityController = TextEditingController();
  final _zipCodeController = TextEditingController();
  final _minHourlyRateController = TextEditingController();
  String? _selectedState;
  bool _isEditingAddress = false;
  bool _isEditingRate = false;
  bool _profileDataLoaded = false;
  bool _isExporting = false;
  static const String _keyAddress1 = 'profile_address1';
  static const String _keyAddress2 = 'profile_address2';
  static const String _keyCity = 'profile_city';
  static const String _keyState = 'profile_state';
  static const String _keyZipCode = 'profile_zip_code';
  static const String _keyMinHourlyRate = 'profile_min_hourly_rate';
  static const String _keyGigsList = 'gigs_list';
  static const String _keySavedLocations = 'saved_locations';
  final List<String> _usStates = [ 'AL', 'AK', 'AZ', 'AR', 'CA', 'CO', 'CT', 'DE', 'FL', 'GA', 'HI', 'ID', 'IL', 'IN', 'IA', 'KS', 'KY', 'LA', 'ME', 'MD', 'MA', 'MI', 'MN', 'MS', 'MO', 'MT', 'NE', 'NV', 'NH', 'NJ', 'NM', 'NY', 'NC', 'ND', 'OH', 'OK', 'OR', 'PA', 'RI', 'SC', 'SD', 'TN', 'TX', 'UT', 'VT', 'VA', 'WA', 'WV', 'WI', 'WY' ];

  @override
  void initState() {
    super.initState();
    _loadProfileData();
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

  Future<void> _loadProfileData() async { /* ... your existing code ... */
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!mounted) return;

      String address1 = prefs.getString(_keyAddress1) ?? '';
      String address2 = prefs.getString(_keyAddress2) ?? '';
      String city = prefs.getString(_keyCity) ?? '';
      String? state = prefs.getString(_keyState);
      String zip = prefs.getString(_keyZipCode) ?? '';
      String minRateString = '';
      if (prefs.containsKey(_keyMinHourlyRate)) {
        int? minHourlyRate = prefs.getInt(_keyMinHourlyRate);
        if (minHourlyRate != null && minHourlyRate > 0) {
          minRateString = minHourlyRate.toString();
        }
      }

      setState(() {
        _address1Controller.text = address1;
        _address2Controller.text = address2;
        _cityController.text = city;
        _selectedState = state;
        _zipCodeController.text = zip;
        _minHourlyRateController.text = minRateString;

        bool hasCoreAddressInfo = address1.isNotEmpty ||
            city.isNotEmpty ||
            (state != null && state.isNotEmpty) ||
            zip.isNotEmpty;
        _isEditingAddress = !hasCoreAddressInfo;
        _isEditingRate = minRateString.isEmpty;
        _profileDataLoaded = true;
      });

    } catch (e) {
      print("Error loading profile data: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading profile: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
        setState(() {
          _profileDataLoaded = true;
          _isEditingAddress = true;
          _isEditingRate = true;
        });
      }
    }
  }
  Future<void> _saveProfile() async { /* ... your existing code ... */
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
      if (minHourlyRate != null && minHourlyRate > 0) { // Store only positive rates
        await prefs.setInt(_keyMinHourlyRate, minHourlyRate);
      } else { // Remove if zero, negative, or not parseable
        await prefs.remove(_keyMinHourlyRate);
      }

      print('Profile Saved (SharedPreferences)');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Profile saved successfully!')),
        );
        setState(() {
          _isEditingAddress = false;
          _isEditingRate = false;
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
  Future<void> _exportAppData() async { /* ... your existing code ... */
    if (!mounted) return;
    setState(() {
      _isExporting = true;
    });

    try {
      final prefs = await SharedPreferences.getInstance();

      // 1. Gather Profile Data
      Map<String, dynamic> profileData = {
        _keyAddress1: prefs.getString(_keyAddress1) ?? '',
        _keyAddress2: prefs.getString(_keyAddress2) ?? '',
        _keyCity: prefs.getString(_keyCity) ?? '',
        _keyState: prefs.getString(_keyState), // Can be null
        _keyZipCode: prefs.getString(_keyZipCode) ?? '',
        _keyMinHourlyRate: prefs.getInt(_keyMinHourlyRate), // Can be null
      };

      // 2. Gather Gigs Data
      final String? gigsJsonString = prefs.getString(_keyGigsList);
      final List<dynamic> gigsList = gigsJsonString != null && gigsJsonString.isNotEmpty
          ? jsonDecode(gigsJsonString)
          : [];

      // 3. Gather Venues Data
      final List<String>? venuesJsonStringList = prefs.getStringList(_keySavedLocations);
      final List<dynamic> venuesList = venuesJsonStringList != null
          ? venuesJsonStringList.map((v) => jsonDecode(v)).toList()
          : [];

      // 4. Combine all data
      Map<String, dynamic> allData = {
        'profile': profileData,
        'gigs': gigsList,
        'venues': venuesList,
        'exported_at': DateTime.now().toIso8601String(),
        'app_version': 'your_app_version_here', // Consider adding app version
      };

      // 5. Convert to pretty JSON string for email body
      String prettyJsonData = const JsonEncoder.withIndent('  ').convert(allData);

      // 6. Create mailto link
      final String emailTo = 'clifford.adams.ii@gmail.com'; // <<< REPLACE WITH YOUR EMAIL
      final String emailSubject = 'MoneyGigs App - User Data Export';
      final Uri emailLaunchUri = Uri(
        scheme: 'mailto',
        path: emailTo,
        queryParameters: {
          'subject': emailSubject,
          'body': 'Hi Developer,\n\nPlease find my app data attached below for testing purposes:\n\n$prettyJsonData',
        },
      );

      if (await canLaunchUrl(emailLaunchUri)) {
        await launchUrl(emailLaunchUri);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Please send the prepared email.')),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not open email client. Please copy data manually if needed.'),backgroundColor: Colors.orange),
          );
        }
        // As a fallback, you could print to console or offer to copy to clipboard
        print("--- APP DATA EXPORT ---");
        print(prettyJsonData);
        print("--- END APP DATA EXPORT ---");
        Clipboard.setData(ClipboardData(text: prettyJsonData)).then((_){
          if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Data copied to clipboard as email client failed.')));
        });
      }
    } catch (e) {
      print('Error exporting app data: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error exporting data: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isExporting = false;
        });
      }
    }
  }
  InputDecoration _formInputDecoration({ required String labelText, String? hintText, IconData? icon, String? prefixText, }) { /* ... your existing code ... */
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
  Widget _buildAddressDisplay() { /* ... your existing code ... */
    String displayAddress1 = _address1Controller.text;
    String displayAddress2 = _address2Controller.text;
    String displayCity = _cityController.text;
    String? displayState = _selectedState;
    String displayZip = _zipCodeController.text;

    if (displayAddress1.isEmpty && displayAddress2.isEmpty && displayCity.isEmpty && displayState == null && displayZip.isEmpty) {
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
                  "${(displayCity.isNotEmpty && displayState != null) ? ', ' : ''}" // Add comma only if both city and state exist
                  "${displayState ?? ''} ${displayZip.isNotEmpty ? displayZip : ''}".trim(), // Trim to remove leading/trailing spaces if some parts are empty
              style: textStyle,
            ),
          const SizedBox(height: 10),
        ],
      ),
    );
  }
  Widget _buildRateDisplay() { /* ... your existing code ... */
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

  // UPDATED: Section title builder with a new flag for the settings icon
  Widget _buildSectionTitle(
      String title, {
        bool showEditIcon = false,
        VoidCallback? onEditPressed,
        String tooltip = 'Edit',
        bool showSettingsIcon = false, // <-- NEW
      }) {
    return Padding(
      padding: const EdgeInsets.only(top: 20.0, bottom: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold, color: Colors.white),
          ),
          // Row for icons to ensure they are together
          Row(
            children: [
              if (showEditIcon)
                IconButton(
                  icon: Icon(Icons.edit_outlined, color: Colors.orangeAccent.shade100),
                  onPressed: onEditPressed,
                  tooltip: tooltip,
                ),
              // NEW: Show settings icon if the flag is true
              if (showSettingsIcon)
                IconButton(
                  icon: Icon(Icons.settings_outlined, color: Colors.orangeAccent.shade100),
                  onPressed: () => _showBackgroundSettingsDialog(context),
                  tooltip: 'App Settings',
                ),
            ],
          ),
        ],
      ),
    );
  }

  // NEW: Method to show the settings dialog
  void _showBackgroundSettingsDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return const BackgroundSettingsDialog();
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    // ... (Your build method's logic)
    // The key change is in the call to _buildSectionTitle
    if (!_profileDataLoaded) {
      return const Center(child: CircularProgressIndicator());
    }

    final formBackgroundColor = Colors.black.withAlpha(128);
    final formTextColor = Colors.white;

    bool hasAddressData = _address1Controller.text.isNotEmpty ||
        _address2Controller.text.isNotEmpty ||
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
              // UPDATED: This title now includes the settings icon
              _buildSectionTitle(
                'Your Profile',
                showSettingsIcon: true,
              ),
              Divider(color: Colors.grey.shade700, height: 1),

              // ... (rest of your build method is the same)
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
                    // Make Address 1 optional if user doesn't want to save any address
                    // if (value == null || value.isEmpty) return 'Please enter Address 1';
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
                  // validator: (value) {
                  //   if (value == null || value.isEmpty) return 'Please enter your city';
                  //   return null;
                  // },
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
                          // validator: (value) {
                          //   if (value == null || value.isEmpty) return 'Select a state';
                          //   return null;
                          // },
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
                        // validator: (value) {
                        //   if (value == null || value.isEmpty) return 'Enter zip code';
                        //   if (value.length != 5) return 'Zip must be 5 digits';
                        //   return null;
                        // },
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
                showEditIcon: !_isEditingRate && hasRateData,
                onEditPressed: () => setState(() => _isEditingRate = true),
                tooltip: 'Edit Minimum Rate',
              ),
              if (_isEditingRate) ...[
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
                    if (value != null && value.isNotEmpty) { // Only validate if not empty
                      final rate = int.tryParse(value);
                      if (rate == null) return 'Please enter a valid number';
                      if (rate <= 0) return 'Rate must be > 0';
                    }
                    return null; // Null if empty or valid
                  },
                ),
                const SizedBox(height: 10),
              ] else ...[
                _buildRateDisplay(),
              ],

              const SizedBox(height: 32.0),
              ElevatedButton(
                onPressed: (_isEditingAddress || _isEditingRate) && !_isExporting ? _saveProfile : null, // Disable if not editing or currently exporting
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  foregroundColor: Theme.of(context).colorScheme.onPrimary,
                  padding: const EdgeInsets.symmetric(vertical: 16.0),
                  textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.0)),
                  minimumSize: const Size(double.infinity, 50),
                ).copyWith(
                  backgroundColor: MaterialStateProperty.resolveWith<Color?>(
                        (Set<MaterialState> states) {
                      if (states.contains(MaterialState.disabled)) {
                        return Colors.grey.shade700; // Color when disabled
                      }
                      return Theme.of(context).colorScheme.primary; // Default color
                    },
                  ),
                ),
                child: Text((_isEditingAddress || _isEditingRate) ? 'Save Changes' : 'Profile Saved'),
              ),
              const SizedBox(height: 20.0),

              // <<< EXPORT BUTTON ADDED HERE >>>
              Divider(color: Colors.grey.shade700, height: 40),
              Text(
                "Developer Options",
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.orangeAccent.shade200, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10.0),
              ElevatedButton.icon(
                icon: _isExporting
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.email_outlined),
                label: const Text('Export App Data for Developer'),
                onPressed: _isExporting ? null : _exportAppData, // Disable while exporting
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.teal.shade700,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12.0),
                  textStyle: const TextStyle(fontSize: 15),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10.0)),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 8.0),
                child: Text(
                  "This helps the developer understand how the app is being used during testing.",
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade400),
                ),
              ),
              const SizedBox(height: 20.0),
            ],
          ),
        ),
      ),
    );
  }
}

// NEW: The settings dialog widget
class BackgroundSettingsDialog extends StatelessWidget {
  const BackgroundSettingsDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final List<String> pageNames = ['Calculator', 'Gigs', 'Profile'];
    final List<int> pageIndices = [0, 2, 3]; // Corresponding indices in main.dart

    return AlertDialog(
      title: const Text('Background Settings'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: List.generate(pageNames.length, (i) {
            final pageIndex = pageIndices[i];
            return ExpansionTile(
              title: Text(pageNames[i]),
              children: [
                ListTile(
                  leading: const Icon(Icons.photo_library_outlined),
                  title: const Text('Default Image'),
                  onTap: () => _setBackground(context, pageIndex, isDefault: true),
                ),
                ListTile(
                  leading: const Icon(Icons.color_lens_outlined),
                  title: const Text('Solid Color'),
                  onTap: () => _pickColor(context, pageIndex),
                ),
                ListTile(
                  leading: const Icon(Icons.image_outlined),
                  title: const Text('Custom Image'),
                  onTap: () => _pickImage(context, pageIndex),
                ),
              ],
            );
          }),
        ),
      ),
      actions: [
        TextButton(
          child: const Text('Close'),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }

  // Saves the chosen background setting and notifies the app
  Future<void> _setBackground(BuildContext context, int pageIndex, {String? imagePath, Color? color, bool isDefault = false}) async {
    final prefs = await SharedPreferences.getInstance();
    final imageKey = 'background_image_$pageIndex';
    final colorKey = 'background_color_$pageIndex';

    // Clear old settings before applying new ones
    await prefs.remove(imageKey);
    await prefs.remove(colorKey);

    if (isDefault) {
      // By removing both keys, main.dart will fall back to its defaults
    } else if (imagePath != null) {
      await prefs.setString(imageKey, imagePath);
    } else if (color != null) {
      await prefs.setInt(colorKey, color.value);
    }

    // Notify main.dart to rebuild with the new settings
    refreshNotifier.notify();

    if (context.mounted) Navigator.of(context).pop(); // Close the dialog
  }

  // Opens the image gallery
  Future<void> _pickImage(BuildContext context, int pageIndex) async {
    final ImagePicker picker = ImagePicker();
    final XFile? image = await picker.pickImage(source: ImageSource.gallery);
    if (image != null) {
      if (context.mounted) {
        _setBackground(context, pageIndex, imagePath: image.path);
      }
    }
  }

  // Opens the color picker dialog
  void _pickColor(BuildContext context, int pageIndex) {
    Color pickerColor = Colors.black;
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Pick a color'),
        content: SingleChildScrollView(
          child: ColorPicker(
            pickerColor: pickerColor,
            onColorChanged: (color) => pickerColor = color,
          ),
        ),
        actions: <Widget>[
          TextButton(
            child: const Text('Select'),
            onPressed: () {
              Navigator.of(dialogContext).pop(); // Close color picker
              _setBackground(context, pageIndex, color: pickerColor);
            },
          ),
        ],
      ),
    );
  }
}
