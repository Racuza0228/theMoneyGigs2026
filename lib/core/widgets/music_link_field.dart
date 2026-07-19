// widgets/music_link_field.dart
//
// Drop-in field for musician_profile_page.dart.
// Place between Genres and Background Settings per the handoff spec.
//
// Usage:
//   MusicLinkField(
//     controller: _musicLinkController,
//     focusNode: _musicLinkFocusNode,  // pass this node so "Add link" tap from
//                                       // EmailVenueButton can focus it directly
//   )

import 'package:flutter/material.dart';

class MusicLinkField extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode? focusNode;

  const MusicLinkField({
    super.key,
    required this.controller,
    this.focusNode,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Music Link',
          style: TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.3,
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'Link to your promo video or EPK',
          style: TextStyle(color: Color(0xFFB3B3B3), fontSize: 12),
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: controller,
          focusNode: focusNode,
          keyboardType: TextInputType.url,
          autocorrect: false,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: 'https://',
            hintStyle: const TextStyle(color: Colors.white38),
            prefixIcon: const Icon(Icons.link, color: Color(0xFFB3B3B3), size: 18),
            filled: true,
            fillColor: Colors.white.withValues(alpha: 0.06),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: Colors.white24),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: Colors.white24),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: Colors.white70),
            ),
            contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          ),
          autovalidateMode: AutovalidateMode.onUserInteraction,
          validator: (value) {
            if (value == null || value.trim().isEmpty) return null; // optional
            final uri = Uri.tryParse(value.trim());
            if (uri == null || !uri.hasScheme) {
              return 'Enter a valid URL (e.g. https://yoursite.com)';
            }
            return null;
          },
        ),
      ],
    );
  }
}