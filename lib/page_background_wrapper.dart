// lib/page_background_wrapper.dart
import 'package:flutter/material.dart';

class PageBackgroundWrapper extends StatelessWidget {
  final String? backgroundImagePath;
  final Widget child;
  final double backgroundOpacity; // <<< MAKE SURE THIS LINE EXISTS

  const PageBackgroundWrapper({
    super.key,
    required this.child,
    this.backgroundImagePath,
    this.backgroundOpacity = 1.0, // <<< AND THIS PARAMETER IS DEFINED HERE
  });

  @override
  Widget build(BuildContext context) {
    Widget content = child;

    if (backgroundImagePath != null && backgroundImagePath!.isNotEmpty) {
      content = Container(
        // Ensure the Container itself tries to fill available space.
        // This is often implicitly handled if the child does, but can be explicit.
        width: double.infinity, // Take full width
        height: double.infinity, // Take full height
        decoration: BoxDecoration(
          image: DecorationImage(
            image: AssetImage(backgroundImagePath!),
            fit: BoxFit.cover,
            opacity: backgroundOpacity,
          ),
        ),
        child: child, // The original child is still the content
      );
    }
    // If the content of the page (child) is not intrinsically expanding,
    // and you want the background to always fill the area given by Expanded,
    // you might wrap `content` in a SizedBox.expand or ensure `child` itself is expansive.
    // However, the width/height: double.infinity on the Container is usually sufficient
    // when the PageBackgroundWrapper is placed inside an Expanded widget.
    return content;
  }
}

