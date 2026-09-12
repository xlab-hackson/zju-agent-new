import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../shared/ink_tag.dart';
import '../theme.dart';

class ToolCard extends StatefulWidget {
  const ToolCard({
    super.key,
    required this.title,
    required this.icon,
    required this.url,
    required this.onOpen,
  });
  final String title, icon;
  final String? url;
  final VoidCallback? onOpen;
  @override
  State<ToolCard> createState() => _ToolCardState();
}

class _ToolCardState extends State<ToolCard> {
  bool hovered = false, pressed = false;

  @override
  Widget build(BuildContext context) {
    final active = widget.onOpen != null && (hovered || pressed);
    final iconColor = active ? paperCard : blue;
    final iconAccent = active ? gold : blue;
    final titleColor = active ? gold : ink;
    return AnimatedSlide(
      offset: active ? const Offset(0, -.015) : Offset.zero,
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      child: Opacity(
        opacity: widget.url == null ? .62 : 1,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          margin: const EdgeInsets.only(bottom: 16),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: paperCard,
            border: Border.all(
              color: active
                  ? gold.withValues(alpha: .58)
                  : ink.withValues(alpha: .14),
            ),
            borderRadius: BorderRadius.circular(3),
            boxShadow: active
                ? const [
                    BoxShadow(
                      color: Color(0x1f0e1c38),
                      offset: Offset(2, 5),
                      blurRadius: 9,
                    ),
                  ]
                : const [
                    BoxShadow(color: Color(0x110e1c38), offset: Offset(2, 3)),
                  ],
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: widget.onOpen,
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
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      AnimatedRotation(
                        turns: active ? -3 / 360 : 0,
                        duration: const Duration(milliseconds: 180),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          width: 44,
                          height: 44,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: active ? gold : blue.withValues(alpha: .05),
                            border: Border.all(
                              color: iconAccent.withValues(alpha: .6),
                            ),
                            borderRadius: BorderRadius.circular(3),
                          ),
                          child: SvgPicture.asset(
                            'assets/icons/${widget.icon}.svg',
                            width: 22,
                            height: 22,
                            colorFilter: ColorFilter.mode(
                              iconColor,
                              BlendMode.srcIn,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              widget.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                                color: titleColor,
                              ),
                            ),
                          ),
                          if (widget.url == null) ...[
                            const SizedBox(width: 8),
                            const InkTag(label: '即将推出', color: ink),
                          ],
                        ],
                      ),
                    ],
                  ),
                  if (widget.url != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Row(
                        children: [
                          Expanded(
                            child: Container(
                              height: 1,
                              color: ink.withValues(alpha: .1),
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (widget.url != null)
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            '访问校内服务',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11,
                              color: gold,
                              fontWeight: FontWeight.bold,
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
                            '↗',
                            style: const TextStyle(fontSize: 16, color: gold),
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
