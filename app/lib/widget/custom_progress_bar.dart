import 'package:flutter/material.dart';

class CustomProgressBar extends StatelessWidget {
  final double? progress;
  final double borderRadius;
  final Color? color;

  const CustomProgressBar({required this.progress, this.borderRadius = 10, this.color});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(begin: null, end: progress ?? 0),
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
        builder: (context, animatedProgress, _) => LinearProgressIndicator(
          value: progress == null ? null : animatedProgress,
          color: color ?? Theme.of(context).colorScheme.primary,
          minHeight: 10,
        ),
      ),
    );
  }
}
