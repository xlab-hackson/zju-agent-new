import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../theme.dart';

class PageHead extends StatelessWidget {
  const PageHead({
    super.key,
    required this.title,
    this.titleSuffix,
    this.subtitle,
    this.updatedAt,
    this.trailing,
  });
  final String title;
  final Widget? titleSuffix;
  final String? subtitle, updatedAt;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) {
    final heading = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontSize: 27,
                fontWeight: FontWeight.bold,
                letterSpacing: 2,
              ),
            ),
            if (titleSuffix != null) ...[
              const SizedBox(width: 12),
              Flexible(child: titleSuffix!),
            ],
          ],
        ),
        if (subtitle != null)
          Padding(
            padding: const EdgeInsets.only(top: 5),
            child: Text(
              subtitle!,
              style: const TextStyle(fontSize: 12, color: ink),
            ),
          ),
        if (updatedAt != null)
          Padding(
            padding: const EdgeInsets.only(top: 5),
            child: Text(
              updatedAt!,
              style: TextStyle(fontSize: 11, color: ink.withValues(alpha: .58)),
            ),
          ),
      ],
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = trailing != null && constraints.maxWidth < 520;
          if (!compact) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(child: heading),
                ?trailing,
              ],
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              heading,
              const SizedBox(height: 8),
              Align(alignment: Alignment.centerRight, child: trailing!),
            ],
          );
        },
      ),
    );
  }
}

class ChapterHead extends StatelessWidget {
  const ChapterHead({
    super.key,
    this.juan,
    required this.title,
    this.subtitle,
    this.icon,
    this.trailing,
  });
  final String title;
  final String? juan, subtitle, icon;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 14, top: 8),
    child: LayoutBuilder(
      builder: (context, constraints) {
        final compact = trailing != null && constraints.maxWidth < 560;
        final row = Row(
          children: [
            if (juan != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: blue,
                  borderRadius: BorderRadius.circular(3),
                ),
                child: Text(
                  juan!,
                  style: const TextStyle(
                    color: paperCard,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            if (juan != null) const SizedBox(width: 10),
            if (icon != null)
              SvgPicture.asset(
                'assets/icons/$icon.svg',
                width: 18,
                height: 18,
                colorFilter: const ColorFilter.mode(gold, BlendMode.srcIn),
              ),
            if (icon != null) const SizedBox(width: 7),
            Text(
              title,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                letterSpacing: 2,
              ),
            ),
            if (subtitle != null)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(left: 12),
                  child: Text(
                    subtitle!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11, color: ink),
                  ),
                ),
              ),
            if (subtitle == null && !compact) const Spacer(),
            if (trailing != null && !compact) trailing!,
          ],
        );
        if (!compact) return row;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (juan != null)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: blue,
                      borderRadius: BorderRadius.circular(3),
                    ),
                    child: Text(
                      juan!,
                      style: const TextStyle(
                        color: paperCard,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                if (juan != null) const SizedBox(width: 10),
                if (icon != null)
                  SvgPicture.asset(
                    'assets/icons/$icon.svg',
                    width: 18,
                    height: 18,
                    colorFilter: const ColorFilter.mode(gold, BlendMode.srcIn),
                  ),
                if (icon != null) const SizedBox(width: 7),
                Flexible(
                  child: Text(
                    title,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 2,
                    ),
                  ),
                ),
              ],
            ),
            if (subtitle != null)
              Padding(
                padding: const EdgeInsets.only(top: 5),
                child: Text(
                  subtitle!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11, color: ink),
                ),
              ),
            if (trailing != null)
              Align(
                alignment: Alignment.centerRight,
                child: Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: trailing!,
                ),
              ),
          ],
        );
      },
    ),
  );
}
