import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import '../domain/models.dart';

/// Never render exception.toString(): network and parser errors can contain secrets.
String operationError(Object error, String stage) {
  final String reason;
  if (error is AppError) {
    reason = '${error.message} [${error.code}]';
  } else if (error is MissingPluginException) {
    reason = '系统插件未正确加载，请完全退出后启动新版本应用。';
  } else if (error is PlatformException) {
    reason = '系统平台调用失败，请检查本地存储是否可用。';
  } else if (error is FileSystemException) {
    reason = '无法访问本地文件，请检查目录权限和剩余空间。';
  } else if (error is DioException || error is SocketException) {
    reason = '网络连接失败，请检查网络后重试。';
  } else if (error is FormatException) {
    reason = '数据格式无法解析。';
  } else {
    reason = '发生内部错误（${error.runtimeType}）。';
  }
  return '$stage失败：$reason';
}
