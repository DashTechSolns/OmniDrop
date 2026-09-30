import 'package:flutter/material.dart';

class OmniDropLogo extends StatelessWidget {
  final double size;
  final Color? color;
  final int? illuminatedNode;

  const OmniDropLogo({super.key, required this.size, this.color, this.illuminatedNode});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.square(size),
      painter: _OmniDropLogoPainter(color ?? Theme.of(context).colorScheme.primary, illuminatedNode),
    );
  }
}

class _OmniDropLogoPainter extends CustomPainter {
  final Color color;
  final int? illuminatedNode;

  const _OmniDropLogoPainter(this.color, this.illuminatedNode);

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final scale = size.shortestSide;
    final ringRadius = scale * 0.43;
    final nodeRadius = scale * 0.105;
    final nodes = [
      Offset(center.dx, center.dy - scale * 0.19),
      Offset(center.dx - scale * 0.17, center.dy + scale * 0.12),
      Offset(center.dx + scale * 0.17, center.dy + scale * 0.12),
    ];

    final ringPaint = Paint()
      ..color = color.withValues(alpha: 0.85)
      ..style = PaintingStyle.stroke
      ..strokeWidth = scale * 0.035;
    canvas.drawCircle(center, ringRadius, ringPaint);

    final linkPaint = Paint()
      ..color = color.withValues(alpha: 0.72)
      ..strokeWidth = scale * 0.035
      ..strokeCap = StrokeCap.round;
    for (var index = 0; index < nodes.length; index++) {
      canvas.drawLine(nodes[index], nodes[(index + 1) % nodes.length], linkPaint);
    }

    for (var index = 0; index < nodes.length; index++) {
      final nodeColor = color.withValues(alpha: illuminatedNode == null || illuminatedNode == index ? 1 : 0.48);
      final rect = Rect.fromCircle(center: nodes[index], radius: nodeRadius);
      final nodePaint = Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.35, -0.4),
          colors: [
            Color.lerp(nodeColor, Colors.white, 0.48)!,
            nodeColor,
            Color.lerp(nodeColor, Colors.black, 0.22)!,
          ],
        ).createShader(rect);
      canvas.drawCircle(nodes[index], nodeRadius, nodePaint);
      canvas.drawCircle(
        nodes[index] + Offset(-nodeRadius * 0.27, -nodeRadius * 0.31),
        nodeRadius * 0.19,
        Paint()..color = Colors.white.withValues(alpha: 0.72),
      );
    }
  }

  @override
  bool shouldRepaint(_OmniDropLogoPainter oldDelegate) => color != oldDelegate.color || illuminatedNode != oldDelegate.illuminatedNode;
}