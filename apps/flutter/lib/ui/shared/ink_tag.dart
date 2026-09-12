import 'package:flutter/material.dart';

import '../theme.dart';

class InkTag extends StatelessWidget {
  const InkTag({
    super.key,
    required this.label,
    required this.color,
    this.dot = false,
    this.filled = false,
  });
  final String label;
  final Color color;
  final bool dot, filled;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: filled ? color : color.withValues(alpha: .1),
      border: Border.all(color: color.withValues(alpha: .4)),
      borderRadius: BorderRadius.circular(3),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (dot)
          Container(
            width: 6,
            height: 6,
            margin: const EdgeInsets.only(right: 5),
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
        Text(
          label,
          style: TextStyle(
            color: filled ? paperCard : color,
            fontSize: 10,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    ),
  );
}
