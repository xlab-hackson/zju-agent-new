import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'theme.dart';

final _avatarCache = <String, Uint8List>{};

Uint8List? decodeAvatar(String value) {
  if (value.isEmpty) return null;
  final cached = _avatarCache[value];
  if (cached != null) return cached;
  final comma = value.indexOf(',');
  if (!value.startsWith('data:') || comma < 0) return null;
  try {
    final bytes = Uint8List.fromList(base64Decode(value.substring(comma + 1)));
    if (_avatarCache.length > 20) {
      _avatarCache.remove(_avatarCache.keys.first);
    }
    _avatarCache[value] = bytes;
    return bytes;
  } catch (_) {
    return null;
  }
}

class UserAvatar extends StatelessWidget {
  const UserAvatar({super.key, this.dataUrl, this.radius = 32, this.onTap});
  final String? dataUrl;
  final double radius;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final bytes = decodeAvatar(dataUrl ?? '');
    final diameter = radius * 2;
    final avatar = RepaintBoundary(
      child: Container(
        width: diameter,
        height: diameter,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: paperCard,
          border: Border.all(color: gold.withValues(alpha: .7), width: 1.5),
        ),
        child: bytes == null
            ? Icon(Icons.person_outline, size: radius, color: blue)
            : Image.memory(bytes, fit: BoxFit.cover),
      ),
    );
    return onTap == null
        ? avatar
        : Semantics(
            button: true,
            label: '更换头像',
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: onTap,
              child: avatar,
            ),
          );
  }
}
