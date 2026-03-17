import 'package:flutter/material.dart';

class GlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final Color? glowColor;
  final double borderRadius;

  const GlassCard({
    super.key,
    required this.child,
    this.padding,
    this.margin,
    this.glowColor,
    this.borderRadius = 16,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: margin,
      decoration: BoxDecoration(
        color: const Color(0xFF13132B),
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border.all(color: const Color(0xFF2A2A55), width: 1),
        boxShadow: [
          if (glowColor != null)
            BoxShadow(
              color: glowColor!.withValues(alpha: 0.15),
              blurRadius: 24,
              spreadRadius: 2,
            ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 16,
          ),
        ],
      ),
      child: Padding(
        padding: padding ?? const EdgeInsets.all(20),
        child: child,
      ),
    );
  }
}

class GradientButton extends StatefulWidget {
  final VoidCallback? onTap;
  final Widget child;
  final List<Color> colors;
  final double height;

  const GradientButton({
    super.key,
    required this.onTap,
    required this.child,
    this.colors = const [Color(0xFF7C3AED), Color(0xFFDB2777)],
    this.height = 46,
  });

  @override
  State<GradientButton> createState() => _GradientButtonState();
}

class _GradientButtonState extends State<GradientButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        height: widget.height,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: enabled
                ? widget.colors
                : [const Color(0xFF333355), const Color(0xFF333355)],
          ),
          borderRadius: BorderRadius.circular(12),
          boxShadow: enabled && _hovered
              ? [
                  BoxShadow(
                    color: widget.colors.first.withValues(alpha: 0.45),
                    blurRadius: 20,
                    spreadRadius: 1,
                  )
                ]
              : [],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: widget.onTap,
            borderRadius: BorderRadius.circular(12),
            child: Center(child: widget.child),
          ),
        ),
      ),
    );
  }
}

class GradientProgressBar extends StatelessWidget {
  final double value;
  final double height;
  final List<Color> colors;

  const GradientProgressBar({
    super.key,
    required this.value,
    this.height = 8,
    this.colors = const [Color(0xFF7C3AED), Color(0xFFEC4899)],
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(height / 2),
      child: Stack(
        children: [
          Container(
            height: height,
            decoration: BoxDecoration(
              color: const Color(0xFF1E1E40),
              borderRadius: BorderRadius.circular(height / 2),
            ),
          ),
          LayoutBuilder(
            builder: (ctx, constraints) {
              final width = constraints.maxWidth * value.clamp(0.0, 1.0);
              return AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                height: height,
                width: width,
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: colors),
                  borderRadius: BorderRadius.circular(height / 2),
                  boxShadow: [
                    BoxShadow(
                      color: colors.last.withValues(alpha: 0.5),
                      blurRadius: 8,
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
