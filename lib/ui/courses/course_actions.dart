import 'package:flutter/material.dart';

import '../../application/course_details.dart';
import '../../domain/models.dart';
import '../shared/campus_page.dart';
import '../shared/file_actions.dart';
import '../theme.dart';
import 'course_detail_sheet.dart';
import 'course_overview_state.dart';

mixin CourseActions<T extends CampusDataPage>
    on CampusPageState<T>, FileActions<T>, CourseOverviewState<T> {
  CourseDetails get _details => CourseDetails(
    services: s,
    semester: semester,
    data: data,
    overviewData: overviewData,
  );
  @override
  Future<void> courseDetail(Json course) async {
    final enriched = await _details.enrichCourse(course);
    if (!mounted) return;
    syncPageContext(activeCourse: enriched, courseTab: 'materials');
    try {
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        backgroundColor: paperCard,
        builder: (ctx) => CourseDetailSheet(
          services: s,
          course: enriched,
          onDownload: downloadFile,
          onPreview: previewFile,
          onAssignmentDetail: assignmentDetail,
          onTabChanged: (tab) {
            syncPageContext(activeCourse: enriched, courseTab: tab);
          },
        ),
      );
    } finally {
      syncPageContext();
    }
  }

  Future<void> openTimetableCourse(TimetableEntry entry) async {
    final course = await _details.timetableCourse(entry);
    if (mounted) await courseDetail(course);
  }

  Future<void> openEventCourse(Json event) async {
    final course = await _details.eventCourse(event);
    if (mounted && course != null) await courseDetail(course);
  }
}
