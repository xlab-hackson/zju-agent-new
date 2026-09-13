import 'package:flutter/material.dart';

import '../../application/services.dart';
import 'assignments_page.dart';
import 'classroom_page.dart';
import 'courses_page.dart';
import 'dashboard_page.dart';
import 'downloads_page.dart';
import 'exams_page.dart';
import 'school_info_page.dart';

/// Route adapter. Page state lives in each feature's own library.
class FeaturePage extends StatelessWidget {
  const FeaturePage({
    super.key,
    required this.services,
    required this.page,
    this.initialAssignmentTab,
  });
  final AppServices services;
  final String page;
  final String? initialAssignmentTab;

  @override
  Widget build(BuildContext context) => switch (page) {
    '/courses' => CoursesPage(services: services),
    '/assignments' => AssignmentsPage(
      services: services,
      initialAssignmentTab: initialAssignmentTab,
    ),
    '/exams' => ExamsPage(services: services),
    '/school-info' => SchoolInfoPage(services: services),
    '/downloads' => DownloadsPage(services: services),
    '/classroom' => ClassroomPage(services: services),
    _ => DashboardPage(services: services),
  };
}
