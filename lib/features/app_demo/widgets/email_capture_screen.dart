// lib/features/app_demo/widgets/email_capture_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../providers/demo_provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class EmailCaptureScreen extends StatefulWidget {
  const EmailCaptureScreen({super.key});

  @override
  State<EmailCaptureScreen> createState() => _EmailCaptureScreenState();
}

class _EmailCaptureScreenState extends State<EmailCaptureScreen> {
  final _emailController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _isSubmitting = false;
  String? _userCity;

  @override
  void initState() {
    super.initState();
    _loadUserCity();
  }

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _loadUserCity() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _userCity = prefs.getString('profile_city') ?? 'your area';
    });
  }

  Future<void> _submitEmail() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSubmitting = true);

    try {
      final prefs = await SharedPreferences.getInstance();
      final email = _emailController.text.trim();

      // Gather onboarding data
      final onboardingData = {
        'email': email,
        'city': prefs.getString('profile_city'),
        'state': prefs.getString('profile_state'),
        'instruments': prefs.getStringList('profile_instrument_tags'),
        'genres': prefs.getStringList('profile_genre_tags'),
        'persona': prefs.getString('user_persona'),
        'minRate': prefs.getInt('profile_min_hourly_rate'),
        'submittedAt': FieldValue.serverTimestamp(),
        'source': 'onboarding_demo',
      };

      // Store in Firestore
      await FirebaseFirestore.instance
          .collection('emailLeads')
          .doc(email) // Use email as doc ID to prevent duplicates
          .set(onboardingData, SetOptions(merge: true));

      // Save locally that they submitted
      await prefs.setBool('email_captured', true);
      await prefs.setString('captured_email', email);

      print('✅ Email lead captured: $email');

      // Advance demo
      if (mounted) {
        final demoProvider = Provider.of<DemoProvider>(context, listen: false);
        demoProvider.nextStep();
        Navigator.of(context).pop();
      }
    } catch (e) {
      print('❌ Error capturing email: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error saving email. Please try again.')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  Future<void> _skipEmailCapture() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('email_skipped', true);

    if (mounted) {
      final demoProvider = Provider.of<DemoProvider>(context, listen: false);
      demoProvider.nextStep();
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        // 🎯 1. Wrap the column in a SingleChildScrollView
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            // 🎯 2. Add constraints to ensure it fits the screen height
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: MediaQuery.of(context).size.height -
                    (MediaQuery.of(context).padding.top +
                        MediaQuery.of(context).padding.bottom) -
                    48, // 48 for padding
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.notifications_active_outlined,
                    size: 80,
                    color: Colors.amber,
                  ),
                  const SizedBox(height: 32),
                  const Text(
                    'Stay Connected',
                    style: TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Get notified when we add venues in $_userCity and exclusive musician tips from working pros.',
                    style: const TextStyle(
                      fontSize: 18,
                      color: Colors.white70,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 40),
                  Form(
                    key: _formKey,
                    child: TextFormField(
                      controller: _emailController,
                      keyboardType: TextInputType.emailAddress,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 18,
                        color: Colors.white,
                      ),
                      decoration: InputDecoration(
                        hintText: 'your.email@example.com',
                        hintStyle: const TextStyle(color: Colors.white38),
                        filled: true,
                        fillColor: Colors.white.withOpacity(0.1),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: Colors.white54),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: Colors.white54),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: Colors.amber, width: 2),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 16,
                        ),
                      ),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Please enter your email';
                        }
                        final emailRegex = RegExp(
                            r"^[a-zA-Z0-9.a-zA-Z0-9.!#$%&'*+-/=?^_`{|}~]+@[a-zA-Z0-9]+\.[a-zA-Z]+");
                        if (!emailRegex.hasMatch(value)) {
                          return 'Please enter a valid email address';
                        }
                        return null;
                      },
                    ),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _isSubmitting ? null : _submitEmail,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.amber,
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: _isSubmitting
                          ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.black,
                        ),
                      )
                          : const Text(
                        'Keep me posted',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextButton(
                    onPressed: _isSubmitting ? null : _skipEmailCapture,
                    child: const Text(
                      'Maybe later',
                      style: TextStyle(
                        fontSize: 16,
                        color: Colors.white54,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}