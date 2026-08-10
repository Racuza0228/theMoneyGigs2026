// lib/core/widgets/email_auth_dialog.dart
//
// Shared email/password sign-in dialog. Added 8/2/26 as the fix for
// Trello #300 / #313: Google Sign-In was the ONLY auth path in the app,
// which silently locked out any musician without a Gmail account at the
// exact moment they tried to activate (Community Edition toggle, or the
// invite-code step of onboarding).
//
// Usage: await showDialog<UserCredential?>(
//   context: context,
//   builder: (_) => const EmailAuthDialog(),
// );
// Returns the UserCredential on success, or null if the user cancelled.
// Firebase errors are shown inline in the dialog — it does NOT rethrow,
// so the caller only needs to branch on null vs non-null.

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:the_money_gigs/core/services/auth_service.dart';

class EmailAuthDialog extends StatefulWidget {
  const EmailAuthDialog({super.key});

  @override
  State<EmailAuthDialog> createState() => _EmailAuthDialogState();
}

class _EmailAuthDialogState extends State<EmailAuthDialog> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _isCreatingAccount = false; // false = Sign In, true = Create Account
  bool _isSubmitting = false;
  String? _errorText;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  String _friendlyError(FirebaseAuthException e) {
    switch (e.code) {
      case 'user-not-found':
        return 'No account found for that email. Try "Create one" below.';
      case 'wrong-password':
      case 'invalid-credential':
        return 'Incorrect email or password.';
      case 'email-already-in-use':
        return 'An account already exists for that email. Try signing in instead.';
      case 'weak-password':
        return 'Password should be at least 6 characters.';
      case 'invalid-email':
        return 'That email address doesn\'t look right.';
      default:
        return e.message ?? 'Something went wrong. Please try again.';
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isSubmitting = true;
      _errorText = null;
    });

    final authService = AuthService();
    final email = _emailController.text.trim();
    final password = _passwordController.text;

    try {
      final result = _isCreatingAccount
          ? await authService.createAccountWithEmail(email, password)
          : await authService.signInWithEmail(email, password);

      if (!mounted) return;

      if (result == null) {
        setState(() {
          _isSubmitting = false;
          _errorText = 'Something went wrong. Please try again.';
        });
        return;
      }

      Navigator.of(context).pop(result);
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
        _errorText = _friendlyError(e);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
        _errorText = 'Something went wrong. Please try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_isCreatingAccount ? 'Create Account' : 'Sign In with Email'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _emailController,
              enabled: !_isSubmitting,
              keyboardType: TextInputType.emailAddress,
              autocorrect: false,
              decoration: const InputDecoration(labelText: 'Email'),
              validator: (value) {
                if (value == null || !value.contains('@')) {
                  return 'Enter a valid email';
                }
                return null;
              },
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _passwordController,
              enabled: !_isSubmitting,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Password'),
              validator: (value) {
                if (value == null || value.length < 6) {
                  return 'At least 6 characters';
                }
                return null;
              },
            ),
            if (_errorText != null) ...[
              const SizedBox(height: 12),
              Text(
                _errorText!,
                style: TextStyle(color: Theme.of(context).colorScheme.error, fontSize: 13),
              ),
            ],
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: _isSubmitting
                    ? null
                    : () => setState(() {
                          _isCreatingAccount = !_isCreatingAccount;
                          _errorText = null;
                        }),
                child: Text(
                  _isCreatingAccount
                      ? 'Already have an account? Sign in'
                      : 'New here? Create one',
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSubmitting ? null : () => Navigator.of(context).pop(null),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _isSubmitting ? null : _submit,
          child: _isSubmitting
              ? const SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(_isCreatingAccount ? 'Create Account' : 'Sign In'),
        ),
      ],
    );
  }
}
