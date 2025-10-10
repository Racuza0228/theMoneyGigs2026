// lib/page_background_wrapper.dart
import 'dart:io';import 'package:flutter/material.dart';

class PageBackgroundWrapper extends StatelessWidget {
  final Widget child;
  final ImageProvider? imageProvider;
  final Color? backgroundColor;
  final double backgroundOpacity;

  const PageBackgroundWrapper({
    super.key,
    required this.child,
    this.imageProvider,
    this.backgroundColor,
    this.backgroundOpacity = 1.0,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        // --- Background Layer ---
        Container(
          decoration: BoxDecoration(
            color: backgroundColor,
            image: imageProvider != null
                ? DecorationImage(
              image: imageProvider!,
              fit: BoxFit.cover,
              opacity: backgroundOpacity,
            )
                : null,
          ),
        ),
        // --- Content Layer ---
        // *** FIX: Wrap the child with SafeArea ***
        // This automatically adds padding to avoid the status bar and AppBar,
        // solving the overlap issue.
        SafeArea(
          child: child,
        ),
      ],
    );
  }
}
