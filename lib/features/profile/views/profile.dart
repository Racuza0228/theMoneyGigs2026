// lib/features/profile/views/profile.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:flutter/foundation.dart';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:the_money_gigs/core/services/export_service.dart';
import 'package:the_money_gigs/global_refresh_notifier.dart';

import '../../app_demo/providers/demo_provider.dart';
import 'widgets/address_display.dart';
import 'widgets/address_form_fields.dart';
import 'package:the_money_gigs/features/profile/views/widgets/connect_widget.dart';
import 'widgets/notification_settings_dialog.dart';
import 'widgets/rate_display.dart';
import 'widgets/rate_form_field.dart';
import 'package:the_money_gigs/core/services/auth_service.dart';
import 'package:the_money_gigs/core/services/network_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';



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

  //<<< NEW: Method to show the notification settings dialog
  void _showNotificationSettings() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return const NotificationSettingsDialog();
      },
    );
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

  Future<void> _sendFeedbackEmail() async {
    if (!mounted) return;

    // Show dialog asking if user wants to include diagnostic data
    final bool? includeData = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Send Feedback'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Would you like to include diagnostic data with your feedback?',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            const Text(
              'Diagnostic data helps us troubleshoot issues faster.',
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blue.shade200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.check_circle, size: 16, color: Colors.green.shade700),
                      const SizedBox(width: 8),
                      const Text('Included:', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  const Text('• Gig dates, times, venues', style: TextStyle(color: Colors.black)),
                  const Text('• Venue names and addresses', style: TextStyle(color: Colors.black)),
                  const Text('• App settings', style: TextStyle(color: Colors.black)),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(Icons.lock, size: 16, color: Colors.red.shade700),
                      const SizedBox(width: 8),
                      const Text('NOT Included:', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  const Text('• Pay amounts', style: TextStyle(color: Colors.black)),
                  const Text('• Contact names, phone numbers, emails', style: TextStyle(color: Colors.black)),
                  const Text('• Private venue details', style: TextStyle(color: Colors.black)),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, null), // Cancel
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, false), // No data
            child: const Text('Send Without Data'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true), // Include data
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue.shade700,
            ),
            child: const Text('Include Data'),
          ),
        ],
      ),
    );

    // User cancelled
    if (includeData == null) return;

    // Proceed with export
    setState(() => _isExporting = true);

    final exportService = ExportService();
    await exportService.sendFeedback(context, includeData: includeData);

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
        return ChangeNotifierProvider.value(
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
              // <<< NEW: Notifications button
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: _showNotificationSettings,
                  icon: const Icon(Icons.notifications_outlined),
                  label: const Text('Notifications'),
                  style: TextButton.styleFrom(
                      foregroundColor: Colors.orangeAccent.shade100),
                ),
              ),

              // <<< NEW: Connect to Network widget
              const ConnectWidget(),

              // Background Settings section
              _buildSectionTitle(
                'Background Settings',
                showSettingsIcon: true,
              ),
              Divider(color: Colors.grey.shade700, height: 1),

              // Your Address section
              _buildSectionTitle(
                'Your Address',
                showEditIcon: !_isEditingAddress && hasAddressData,
                onEditPressed: () => setState(() => _isEditingAddress = true),
                tooltip: 'Edit Address',
              ),
              if (_isEditingAddress)
                AddressFormFields(
                  address1Controller: _address1Controller,
                  address2Controller: _address2Controller,
                  cityController: _cityController,
                  zipCodeController: _zipCodeController,
                  selectedState: _selectedState,
                  usStates: _usStates,
                  onStateChanged: (newValue) => setState(() => _selectedState = newValue),
                  formInputDecoration: ({required String labelText, String? hintText, IconData? icon, String? prefixText}) =>
                      _formInputDecoration(labelText: labelText, hintText: hintText, icon: icon),
                )
              else
                AddressDisplay(
                  address1: _address1Controller.text,
                  address2: _address2Controller.text,
                  city: _cityController.text,
                  state: _selectedState,
                  zip: _zipCodeController.text,
                ),

              // Work Preferences section
              _buildSectionTitle(
                'Work Preferences',
                showEditIcon: !_isEditingRate && hasRateData,
                onEditPressed: () => setState(() => _isEditingRate = true),
                tooltip: 'Edit Minimum Rate',
              ),
              if (_isEditingRate)
                RateFormField(
                  minHourlyRateController: _minHourlyRateController,
                  formInputDecoration: _formInputDecoration,
                )
              else
                RateDisplay(rate: _minHourlyRateController.text),
              const SizedBox(height: 32.0),

              // Save Changes button
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
                  backgroundColor: WidgetStateProperty.resolveWith<Color?>(
                        (Set<WidgetState> states) {
                      if (states.contains(WidgetState.disabled)) return Colors.grey.shade700;
                      return Theme.of(context).colorScheme.primary;
                    },
                  ),
                ),
                child: Text((_isEditingAddress || _isEditingRate) ? 'Save Changes' : 'Profile Saved'),
              ),
              const SizedBox(height: 20.0),

              // Support section
              Divider(color: Colors.grey.shade700, height: 40),
              Text(
                "Support",
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.orangeAccent.shade200, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10.0),

              // TEST BUTTONS (only visible in debug mode)
              if (kDebugMode) ...[
                ElevatedButton.icon(
                  icon: const Icon(Icons.login),
                  label: const Text('Test Google Sign-In'),
                  onPressed: () async {
                    final authService = AuthService();

                    // Show loading
                    if (!mounted) return;
                    showDialog(
                      context: context,
                      barrierDismissible: false,
                      builder: (context) => const Center(child: CircularProgressIndicator()),
                    );

                    final result = await authService.signInWithGoogle();

                    // Close loading
                    if (!mounted) return;
                    Navigator.pop(context);

                    // Show result
                    if (result != null) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('✅ Signed in as: ${result.user?.email}\nUser ID: ${result.user?.uid}'),
                          backgroundColor: Colors.green,
                          duration: const Duration(seconds: 5),
                        ),
                      );
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('❌ Sign-in failed or cancelled'),
                          backgroundColor: Colors.red,
                        ),
                      );
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green.shade700,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12.0),
                    textStyle: const TextStyle(fontSize: 15),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10.0)),
                  ),
                ),
                const SizedBox(height: 10.0),
                // TESTING: Reset Network State
                ElevatedButton.icon(
                  icon: const Icon(Icons.refresh),
                  label: const Text('🧪 Reset Network State'),
                  onPressed: () async {
                    final authService = AuthService();
                    final prefs = await SharedPreferences.getInstance();

                    // Confirm reset
                    final confirm = await showDialog<bool>(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: const Text('Reset Network State'),
                        content: const Text(
                            'This will:\n'
                                '• Delete your networkMember record in Firestore\n'
                                '• Clear local network settings\n'
                                '• Keep you signed in to Google\n\n'
                                'Use this to test the invite code flow again.'
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context, false),
                            child: const Text('Cancel'),
                          ),
                          ElevatedButton(
                            onPressed: () => Navigator.pop(context, true),
                            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                            child: const Text('Reset'),
                          ),
                        ],
                      ),
                    );

                    if (confirm != true) return;

                    // Delete from Firestore
                    final userId = authService.currentUserId;
                    await FirebaseFirestore.instance
                        .collection('networkMembers')
                        .doc(userId)
                        .delete();

                    // Clear local state
                    await prefs.setBool('is_connected_to_network', false);
                    await prefs.remove('network_invite_code');

                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('✅ Network state reset! You can test invite codes again.'),
                        backgroundColor: Colors.green,
                      ),
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange.shade700,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12.0),
                    textStyle: const TextStyle(fontSize: 15),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10.0)),
                  ),
                ),
              ], // End of debug-only buttons

              ElevatedButton.icon(
                icon: const Icon(Icons.logout),
                label: const Text('Sign Out'),
                onPressed: () async {
                  // Confirm sign out
                  final confirm = await showDialog<bool>(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: const Text('Sign Out'),
                      content: const Text('Are you sure you want to sign out?'),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context, false),
                          child: const Text('Cancel'),
                        ),
                        ElevatedButton(
                          onPressed: () => Navigator.pop(context, true),
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                          child: const Text('Sign Out'),
                        ),
                      ],
                    ),
                  );

                  if (confirm != true) return;

                  // Sign out from Google/Firebase
                  final authService = AuthService();
                  await authService.signOut();

                  // Clear network connection state
                  final prefs = await SharedPreferences.getInstance();
                  await prefs.setBool('is_connected_to_network', false);
                  await prefs.remove('network_invite_code');

                  // Show confirmation
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('✅ Signed out successfully'),
                      backgroundColor: Colors.green,
                    ),
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red.shade700,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12.0),
                  textStyle: const TextStyle(fontSize: 15),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10.0)),
                ),
              ),
              const SizedBox(height: 12.0),
              ElevatedButton.icon(
                icon: _isExporting
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.feedback_outlined),
                label: const Text('Send Feedback Email'),
                onPressed: _isExporting ? null : _sendFeedbackEmail,
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
                  '',
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
                  // Change "Default Image" to "The Stage"
                  title: const Text('The Stage'),
                  onTap: () => _setBackground(context, pageIndex, imagePath: 'USE_STAGE_DEFAULT'),
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

    if (imagePath != null) {
      // This now handles both custom images (e.g., '/path/to/image.jpg')
      // and our special keyword for "The Stage".
      await prefs.setString(imageKey, imagePath);
    } else if (color != null) {
      await prefs.setInt(colorKey, color.value);
    }

    if (context.mounted) {
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