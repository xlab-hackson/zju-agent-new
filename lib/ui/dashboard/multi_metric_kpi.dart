import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../theme.dart';

class MultiMetricItem {
  final String value;
  final String label;
  final Color? valueColor;
  final VoidCallback? onTap;
  final String? tooltip;

  const MultiMetricItem({
    required this.value,
    required this.label,
    this.valueColor,
    this.onTap,
    this.tooltip,
  });
}

class MultiMetricKpi extends StatefulWidget {
  const MultiMetricKpi({
    super.key,
    required this.label,
    required this.icon,
    required this.items,
    this.foot,
    this.footOnTap,
  });

  final String label;
  final String icon;
  final List<MultiMetricItem> items;
  final String? foot;
  final VoidCallback? footOnTap;

  @override
  State<MultiMetricKpi> createState() => _MultiMetricKpiState();
}

class _MultiMetricKpiState extends State<MultiMetricKpi> {
  int? hoveredIndex;
  bool footHovered = false;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: paperCard,
        border: Border.all(color: ink.withValues(alpha: .12)),
        borderRadius: BorderRadius.circular(3),
      ),
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
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: blue,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SvgPicture.asset(
                'assets/icons/${widget.icon}.svg',
                width: 17,
                height: 17,
                colorFilter: ColorFilter.mode(
                  blue.withValues(alpha: .85),
                  BlendMode.srcIn,
                ),
              ),
            ],
          ),
          const Spacer(),
          Row(
            children: [
              for (var i = 0; i < widget.items.length; i++) ...[
                if (i > 0)
                  Container(
                    width: 1,
                    height: 38,
                    margin: const EdgeInsets.symmetric(horizontal: 2),
                    color: ink.withValues(alpha: .08),
                  ),
                Expanded(child: _buildMetricItem(widget.items[i], i)),
              ],
            ],
          ),
          const Spacer(),
          if (widget.foot != null && widget.foot!.isNotEmpty) ...[
            Divider(height: 16, color: ink.withValues(alpha: .1)),
            InkWell(
              onTap: widget.footOnTap,
              onHover: (v) {
                if (mounted) setState(() => footHovered = v);
              },
              borderRadius: BorderRadius.circular(2),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        widget.foot!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          color: gold,
                          decoration: (widget.footOnTap != null && footHovered)
                              ? TextDecoration.underline
                              : TextDecoration.none,
                        ),
                      ),
                    ),
                    if (widget.footOnTap != null)
                      Text(
                        '→',
                        style: TextStyle(
                          fontSize: 16,
                          color: footHovered ? gold : blue,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMetricItem(MultiMetricItem item, int index) {
    final canTap = item.onTap != null;
    final isHovered = hoveredIndex == index;

    final content = AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
      decoration: BoxDecoration(
        color: isHovered && canTap
            ? blue.withValues(alpha: .06)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            height: 28,
            child: Center(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  item.value,
                  maxLines: 1,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: item.valueColor ?? blue,
                    letterSpacing: -0.3,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 3),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              item.label,
              maxLines: 1,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 10.5,
                color: isHovered && canTap ? blue : ink,
                fontWeight: isHovered && canTap
                    ? FontWeight.bold
                    : FontWeight.normal,
              ),
            ),
          ),
        ],
      ),
    );

    if (!canTap) {
      return item.tooltip != null
          ? Tooltip(message: item.tooltip!, child: content)
          : content;
    }

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) {
        if (mounted) setState(() => hoveredIndex = index);
      },
      onExit: (_) {
        if (mounted) setState(() => hoveredIndex = null);
      },
      child: Tooltip(
        message: item.tooltip ?? '',
        waitDuration: const Duration(milliseconds: 500),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: item.onTap,
            borderRadius: BorderRadius.circular(4),
            child: content,
          ),
        ),
      ),
    );
  }
}
