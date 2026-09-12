import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../theme.dart';

class PageEmpty extends StatelessWidget {
  const PageEmpty({
    super.key,
    this.icon = 'scroll',
    required this.title,
    this.description,
  });
  final String icon, title;
  final String? description;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 34, horizontal: 20),
    child: Center(
      child: Column(
        children: [
          SvgPicture.asset(
            'assets/icons/$icon.svg',
            width: 40,
            height: 40,
            colorFilter: ColorFilter.mode(
              ink.withValues(alpha: .25),
              BlendMode.srcIn,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: ink,
            ),
          ),
          if (description != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                description!,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 12, color: ink),
              ),
            ),
        ],
      ),
    ),
  );
}
