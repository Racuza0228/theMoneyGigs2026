// lib/features/profile/views/profile.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:the_money_gigs/core/services/export_service.dart';
import 'package:the_money_gigs/global_refresh_notifier.dart'; // <<< 1. IMPORT THE CORRECT NOTIFIER

import '../../app_demo/providers/demo_provider.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
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
  final List<String> _usStates = [ 'AL', 'AK', 'AZ', 'AR', 'CA', 'CO', 'CT', 'DE', 'FL', 'GA', 'HI', 'ID', 'IL', 'IN', 'IA', 'KS', 'KY', 'LA', 'ME', 'MD', 'MA', 'MI', 'MN', 'MS', 'MO', 'MT', 'NE', 'NV', 'NH', 'NJ', 'NM', 'NY', 'NC', 'ND', 'OH', 'OK', 'OR', 'PA', 'RI', 'SC', 'SD', 'TN', 'TX', 'UT', 'VT', 'VA', 'WA', 'WV', 'WI', 'WY' ];

  // --- All methods from initState() to _buildSectionTitle() are unchanged ---
  // --- They are included here for completeness of the file. ---
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

  Future<void> _loadProfileData() async {
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

  Future<void> _saveProfile() async {
    if (_formKey.currentState!.validate()) {
      _formKey.currentState!.save();
      final prefs = await SharedPreferences.getInstance();

      await prefs.setString(_keyAddress1, _address1Controller.text);
      await prefs.setString(_keyAddress2, _address2Controller.text);
      await prefs.setString(_keyCity, _cityController.text);
      if (_selectedState != null) {
        await prefs.setString(_keyState, _selectedState!);
      } else {
        await prefs.remove(_keyState);
      }
      await prefs.setString(_keyZipCode, _zipCodeController.text);
      int? minHourlyRate = int.tryParse(_minHourlyRateController.text);
      if (minHourlyRate != null && minHourlyRate > 0) {
        await prefs.setInt(_keyMinHourlyRate, minHourlyRate);
      } else {
        await prefs.remove(_keyMinHourlyRate);
      }

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

  Future<void> _exportAppData() async {
    if (!mounted) return;
    setState(() => _isExporting = true);

    final exportService = ExportService();
    await exportService.export(context);

    if (mounted) {
      setState(() => _isExporting = false);
    }
  }

  InputDecoration _formInputDecoration({ required String labelText, String? hintText, IconData? icon, String? prefixText, }) {
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

  Widget _buildAddressDisplay() {
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
                  "${(displayCity.isNotEmpty && displayState != null) ? ', ' : ''}"
                  "${displayState ?? ''} ${displayZip.isNotEmpty ? displayZip : ''}".trim(),
              style: textStyle,
            ),
          const SizedBox(height: 10),
        ],
      ),
    );
  }

  Widget _buildRateDisplay() {
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

  Widget _buildSectionTitle(String title, {bool showEditIcon = false, VoidCallback? onEditPressed, String tooltip = 'Edit', bool showSettingsIcon = false}) {
    return Padding(
      padding: const EdgeInsets.only(top: 20.0, bottom: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold, color: Colors.white),
          ),
          Row(
            children: [
              if (showEditIcon)
                IconButton(
                  icon: Icon(Icons.edit_outlined, color: Colors.orangeAccent.shade100),
                  onPressed: onEditPressed,
                  tooltip: tooltip,
                ),
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

  void _showBackgroundSettingsDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        // <<< 2. PASS THE CORRECT NOTIFIER TYPE TO THE DIALOG
        return Provider.value(
          value: context.read<GlobalRefreshNotifier>(),
          child: const BackgroundSettingsDialog(),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
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
              _buildSectionTitle(
                'Background Settings',
                showSettingsIcon: true,
              ),
              Divider(color: Colors.grey.shade700, height: 1),
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
                  validator: (value) => null,
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
                    if (value != null && value.isNotEmpty) {
                      final rate = int.tryParse(value);
                      if (rate == null) return 'Please enter a valid number';
                      if (rate <= 0) return 'Rate must be > 0';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 10),
              ] else ...[
                _buildRateDisplay(),
              ],
              const SizedBox(height: 32.0),
              ElevatedButton(
                onPressed: (_isEditingAddress || _isEditingRate) && !_isExporting ? _saveProfile : null,
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
                      if (states.contains(MaterialState.disabled)) return Colors.grey.shade700;
                      return Theme.of(context).colorScheme.primary;
                    },
                  ),
                ),
                child: Text((_isEditingAddress || _isEditingRate) ? 'Save Changes' : 'Profile Saved'),
              ),
              const SizedBox(height: 20.0),
              Divider(color: Colors.grey.shade700, height: 40),
              Text(
                "Support",
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.orangeAccent.shade200, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10.0),
              ElevatedButton.icon(
                icon: _isExporting
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.email_outlined),
                label: const Text('Export App Data'),
                onPressed: _isExporting ? null : _exportAppData,
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
              const SizedBox(height: 16),
              ElevatedButton.icon(
                icon: const Icon(Icons.replay_outlined),
                label: const Text('Replay App Demo'),
                onPressed: () {
                  context.read<DemoProvider>().startDemo();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Starting demo now...'),
                      backgroundColor: Colors.blueAccent,
                    ),
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blueGrey.shade600,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12.0),
                  textStyle: const TextStyle(fontSize: 15),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10.0)),
                ),
              ),
              const SizedBox(height: 8),
              // <<< 3. NEW "RESET DEMO" BUTTON FOR TESTING
              TextButton(
                onPressed: () {
                  context.read<DemoProvider>().resetDemoFlagForTesting();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Demo flag reset. The demo will run on the next app restart.'),
                      backgroundColor: Colors.green,
                    ),
                  );
                },
                child: const Text(
                  'Reset Demo on Next Launch (for testing)',
                  style: TextStyle(color: Colors.white70, fontSize: 12),
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

class BackgroundSettingsDialog extends StatelessWidget {
  const BackgroundSettingsDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final List<String> pageNames = ['Calculator', 'Gigs', 'Profile'];
    final List<int> pageIndices = [0, 2, 3];

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

  Future<void> _setBackground(BuildContext context, int pageIndex, {String? imagePath, Color? color, bool isDefault = false}) async {
    final prefs = await SharedPreferences.getInstance();
    final imageKey = 'background_image_$pageIndex';
    final colorKey = 'background_color_$pageIndex';

    await prefs.remove(imageKey);
    await prefs.remove(colorKey);

    if (isDefault) {
      // Settings cleared
    } else if (imagePath != null) {
      await prefs.setString(imageKey, imagePath);
    } else if (color != null) {
      await prefs.setInt(colorKey, color.value);
    }

    if (context.mounted) {
      // <<< 4. USE THE CORRECT NOTIFIER TYPE
      context.read<GlobalRefreshNotifier>().notify();
      Navigator.of(context).pop(); // Pop the parent dialog
    }
  }

  Future<void> _pickImage(BuildContext context, int pageIndex) async {
    final ImagePicker picker = ImagePicker();
    final XFile? image = await picker.pickImage(source: ImageSource.gallery);
    if (image != null && context.mounted) {
      _setBackground(context, pageIndex, imagePath: image.path);
    }
  }

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
              Navigator.of(dialogContext).pop();
              _setBackground(context, pageIndex, color: pickerColor);
            },
          ),
        ],
      ),
    );
  }
}
