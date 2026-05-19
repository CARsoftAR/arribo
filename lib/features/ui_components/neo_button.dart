import 'package:flutter/material.dart' hide BoxDecoration, BoxShadow;
import 'package:flutter_inset_shadow/flutter_inset_shadow.dart';

class NeoButton extends StatefulWidget {
  final Widget child;
  final VoidCallback onTap;
  final double borderRadius;
  final EdgeInsets padding;

  const NeoButton({
    super.key,
    required this.child,
    required this.onTap,
    this.borderRadius = 15.0,
    this.padding = const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
  });

  @override
  State<NeoButton> createState() => _NeoButtonState();
}

class _NeoButtonState extends State<NeoButton> {
  bool isPressed = false;

  @override
  Widget build(BuildContext context) {
    final backgroundColor = Theme.of(context).scaffoldBackgroundColor;
    
    return GestureDetector(
      onTapDown: (_) => setState(() => isPressed = true),
      onTapUp: (_) => setState(() => isPressed = false),
      onTapCancel: () => setState(() => isPressed = false),
      onTap: widget.onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: widget.padding,
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(widget.borderRadius),
          boxShadow: [
            BoxShadow(
              blurRadius: isPressed ? 5 : 10,
              offset: isPressed ? const Offset(-2, -2) : const Offset(-5, -5),
              color: Colors.white.withValues(alpha: 0.05), // Subtle top light
              inset: isPressed,
            ),
            BoxShadow(
              blurRadius: isPressed ? 5 : 10,
              offset: isPressed ? const Offset(2, 2) : const Offset(5, 5),
              color: Colors.black.withValues(alpha: 0.5), // Deep bottom shadow
              inset: isPressed,
            ),
          ],
        ),
        child: widget.child,
      ),
    );
  }
}
