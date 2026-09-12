import 'package:flutter/material.dart';

import '../../domain/models.dart';
import '../shared/campus_page.dart';
import '../shared/page_empty.dart';
import '../theme.dart';

class ClassroomPage extends CampusDataPage {
  const ClassroomPage({super.key, required super.services});
  @override
  State<ClassroomPage> createState() => _ClassroomPageState();
}

class _ClassroomPageState extends CampusPageState<ClassroomPage> {
  @override
  String get pageKey => '/classroom';
  @override
  String get title => '智云课堂';

  @override
  bool get usesNetworkCache => false;
  @override
  Future<Json> load({bool refresh = false}) async => {};
  @override
  PageContext buildPageContext({Json? activeCourse, String? courseTab}) =>
      PageContext.classroom();
  @override
  List<Widget> content(Json data, {required bool wide}) => [
    Paper(
      child: const PageEmpty(
        icon: 'video-lesson-play',
        title: '智云课堂尚未开放',
        description: '课堂回放、课件下载与语音检索将在服务接入后开放。',
      ),
    ),
  ];
}
