import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../theme.dart';

class SideSection extends StatelessWidget {
  const SideSection({
    super.key,
    required this.title,
    required this.children,
    this.icon,
    this.trailing,
  });
  final String title;
  final String? icon;
  final Widget? trailing;
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          if (icon != null)
            SvgPicture.asset(
              'assets/icons/$icon.svg',
              width: 16,
              height: 16,
              colorFilter: const ColorFilter.mode(gold, BlendMode.srcIn),
            ),
          if (icon != null) const SizedBox(width: 8),
          Text(
            title,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              letterSpacing: 2,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Container(height: 1, color: ink.withValues(alpha: .15)),
          ),
          if (trailing != null) ...[const SizedBox(width: 6), trailing!],
        ],
      ),
      const SizedBox(height: 16),
      ...children,
    ],
  );
}

class SideCount extends StatelessWidget {
  const SideCount({
    super.key,
    required this.label,
    required this.value,
    required this.color,
    required this.icon,
  });
  final String label;
  final int value;
  final Color color;
  final IconData icon;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(
      children: [
        Icon(icon, color: color, size: 15),
        const SizedBox(width: 7),
        Text(
          label,
          style: TextStyle(
            color: color,
            fontWeight: FontWeight.bold,
            fontSize: 12,
          ),
        ),
        const Spacer(),
        Text('$value 项', style: const TextStyle(fontSize: 12)),
      ],
    ),
  );
}
