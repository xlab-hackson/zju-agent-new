import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../theme.dart';

class Kpi extends StatefulWidget {
  const Kpi({
    super.key,
    required this.label,
    required this.value,
    required this.unit,
    required this.foot,
    required this.icon,
    this.onTap,
    this.small = false,
  });
  final String label, value, unit, foot, icon;
  final VoidCallback? onTap;
  final bool small;

  @override
  State<Kpi> createState() => _KpiState();
}

class _KpiState extends State<Kpi> {
  bool hovered = false, pressed = false;

  @override
  Widget build(BuildContext context) {
    final active = hovered || pressed;
    final color = active ? gold : blue;
    return AnimatedSlide(
      offset: active ? const Offset(0, -.015) : Offset.zero,
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: paperCard,
          border: Border.all(
            color: active
                ? gold.withValues(alpha: .58)
                : ink.withValues(alpha: .12),
          ),
          borderRadius: BorderRadius.circular(3),
          boxShadow: active
              ? const [
                  BoxShadow(
                    color: Color(0x1f0e1c38),
                    offset: Offset(1, 4),
                    blurRadius: 8,
                  ),
                ]
              : const [],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: widget.onTap,
            hoverColor: Colors.transparent,
            focusColor: Colors.transparent,
            highlightColor: Colors.transparent,
            splashColor: Colors.transparent,
            onHover: (value) {
              if (mounted) setState(() => hovered = value);
            },
            onHighlightChanged: (value) {
              if (mounted) setState(() => pressed = value);
            },
            borderRadius: BorderRadius.circular(3),
            child: Padding(
              padding: const EdgeInsets.all(1),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          widget.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 12, color: color),
                        ),
                      ),
                      const SizedBox(width: 8),
                      AnimatedRotation(
                        turns: active ? -.017 : 0,
                        duration: const Duration(milliseconds: 180),
                        child: SvgPicture.asset(
                          'assets/icons/${widget.icon}.svg',
                          width: 17,
                          height: 17,
                          colorFilter: ColorFilter.mode(
                            color.withValues(alpha: .85),
                            BlendMode.srcIn,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    height: 44,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Flexible(
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Text(
                              widget.value,
                              maxLines: 1,
                              style: TextStyle(
                                fontSize: widget.small ? 28 : 36,
                                fontWeight: FontWeight.bold,
                                color: color,
                              ),
                            ),
                          ),
                        ),
                        if (widget.unit.isNotEmpty)
                          Flexible(
                            child: Padding(
                              padding: const EdgeInsets.only(
                                left: 4,
                                bottom: 5,
                              ),
                              child: Text(
                                widget.unit,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: ink,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (widget.foot.isNotEmpty) ...[
                    const Divider(height: 18),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            widget.foot,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11,
                              color: gold,
                              decoration: active
                                  ? TextDecoration.underline
                                  : TextDecoration.none,
                            ),
                          ),
                        ),
                        AnimatedSlide(
                          offset: active ? const Offset(.15, 0) : Offset.zero,
                          duration: const Duration(milliseconds: 180),
                          child: Text(
                            '→',
                            style: TextStyle(fontSize: 16, color: color),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
