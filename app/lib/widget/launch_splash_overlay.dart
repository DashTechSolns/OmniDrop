import 'package:flutter/material.dart';
import 'package:localsend_app/gen/assets.gen.dart';
import 'package:localsend_app/widget/omnidrop_logo.dart';

class LaunchSplashOverlay extends StatefulWidget {
  final Widget child;

  const LaunchSplashOverlay({super.key, required this.child});

  @override
  State<LaunchSplashOverlay> createState() => _LaunchSplashOverlayState();
}

class _LaunchSplashOverlayState extends State<LaunchSplashOverlay> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 1250))
    ..forward();
  bool _visible = true;

  @override
  void initState() {
    super.initState();
    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed && mounted) {
        setState(() => _visible = false);
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        if (_visible)
          IgnorePointer(
            child: AnimatedOpacity(
              opacity: _visible ? 1 : 0,
              duration: const Duration(milliseconds: 180),
              child: ColoredBox(
                color: Theme.of(context).colorScheme.surface,
                child: AnimatedBuilder(
                  animation: _controller,
                  builder: (context, _) {
                    final node = (_controller.value * 3).floor().clamp(0, 2);
                    return Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SizedBox(
                          width: 150,
                          height: 150,
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              Opacity(opacity: 0.16, child: Assets.img.logo512.image(width: 142, height: 142)),
                              OmniDropLogo(size: 126, illuminatedNode: node),
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),
                        Opacity(
                          opacity: ((_controller.value - 0.55) / 0.3).clamp(0, 1),
                          child: Text('OmniDrop', style: Theme.of(context).textTheme.headlineMedium),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
      ],
    );
  }
}