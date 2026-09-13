import 'package:flutter/material.dart';

import '../theme.dart';

IconData fileIcon(String kind) =>
    {
      'image': Icons.image_outlined,
      'text': Icons.article_outlined,
      'pdf': Icons.picture_as_pdf_outlined,
      'word': Icons.description_outlined,
      'slides': Icons.slideshow_outlined,
      'sheet': Icons.table_chart_outlined,
      'video': Icons.movie_outlined,
      'audio': Icons.audiotrack_outlined,
      'archive': Icons.archive_outlined,
    }[kind] ??
    Icons.insert_drive_file_outlined;
Color fileColor(String kind) =>
    {
      'image': const Color(0xff55447a),
      'text': ink,
      'pdf': seal,
      'word': blue,
      'slides': gold,
      'sheet': const Color(0xff2e7d32),
      'video': const Color(0xff2a5a5e),
      'audio': const Color(0xff8c3a2e),
      'archive': const Color(0xff8a5222),
    }[kind] ??
    ink;
