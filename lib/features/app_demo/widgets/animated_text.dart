import 'dart:async';
import 'package:flutter/material.dart';

class AnimatedText extends StatefulWidget {
  final String text;
  final TextStyle? style;
  final Duration speed;

  const AnimatedText({
    super.key,
    required this.text,
    this.style,
    this.speed = const Duration(milliseconds: 55), // Typing speed
  });

  @override
  State<AnimatedText> createState() => _AnimatedTextState();
}

class _AnimatedTextState extends State<AnimatedText> {
  String _displayText = '';
  Timer? _timer;
  int _charIndex = 0;

  @override
  void initState() {
    super.initState();
    _startAnimation();
  }

  void _startAnimation() {
    _timer = Timer.periodic(widget.speed, (timer) {
      if (_charIndex < widget.text.length) {
        if (mounted) {
          setState(() {
            _displayText += widget.text[_charIndex];
            _charIndex++;
          });
        }
      } else {
        _timer?.cancel();
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Use RichText to add a blinking cursor effect
    return RichText(
      textAlign: TextAlign.center,
      text: TextSpan(
        style: widget.style,
        children: [
          TextSpan(text: _displayText),
          // Show a "cursor" only while typing
          if (_charIndex < widget.text.length)
            const TextSpan(
              text: '▍', // This is a block character for the cursor
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
        ],
      ),
    );
  }
}
