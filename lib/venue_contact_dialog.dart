// lib/venue_contact_dialog.dart
import 'package:flutter/material.dart';
import 'package:the_money_gigs/venue_model.dart';
import 'package:the_money_gigs/venue_contact.dart';

class VenueContactDialog extends StatefulWidget {
  final StoredLocation venue;

  const VenueContactDialog({super.key, required this.venue});

  @override
  State<VenueContactDialog> createState() => _VenueContactDialogState();
}

class _VenueContactDialogState extends State<VenueContactDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _phoneController;
  late final TextEditingController _emailController;

  @override
  void initState() {
    super.initState();
    final contact = widget.venue.contact ?? const VenueContact();
    _nameController = TextEditingController(text: contact.name);
    _phoneController = TextEditingController(text: contact.phone);
    _emailController = TextEditingController(text: contact.email);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  void _onSave() {
    if (_formKey.currentState!.validate()) {
      final updatedContact = VenueContact(
        name: _nameController.text.trim(),
        phone: _phoneController.text.trim(),
        email: _emailController.text.trim(),
      );
      // Pop the dialog and return the updated contact
      Navigator.of(context).pop(updatedContact);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Contact for ${widget.venue.name}'),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: ListBody(
            children: <Widget>[
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'Contact Name',
                  icon: Icon(Icons.person_outline),
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _phoneController,
                decoration: const InputDecoration(
                  labelText: 'Phone Number',
                  icon: Icon(Icons.phone_outlined),
                ),
                keyboardType: TextInputType.phone,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _emailController,
                decoration: const InputDecoration(
                  labelText: 'Email Address',
                  icon: Icon(Icons.email_outlined),
                ),
                keyboardType: TextInputType.emailAddress,
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return null; // Email is optional
                  }
                  // Simple email validation regex
                  final emailRegex = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
                  if (!emailRegex.hasMatch(value)) {
                    return 'Please enter a valid email address';
                  }
                  return null;
                },
              ),
            ],
          ),
        ),
      ),
      actions: <Widget>[
        TextButton(
          child: const Text('CANCEL'),
          onPressed: () => Navigator.of(context).pop(),
        ),
        ElevatedButton(
          onPressed: _onSave,
          child: const Text('SAVE CONTACT'),
        ),
      ],
    );
  }
}
