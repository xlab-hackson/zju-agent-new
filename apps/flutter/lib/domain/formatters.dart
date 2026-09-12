String? dataUpdatedLabel(String? raw) {
  final time = raw == null ? null : DateTime.tryParse(raw)?.toUtc();
  if (time == null) return null;
  final minutes = DateTime.now().toUtc().difference(time).inMinutes;
  return '数据更新于 ${minutes < 0 ? 0 : minutes} 分钟前';
}

String formatDateTime(String raw) {
  final date = DateTime.tryParse(raw);
  if (date == null) return raw.isEmpty ? '未设置' : raw;
  final local = date.toLocal();
  return '${local.year}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')} ${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
}

String formatHms(int seconds) {
  final safe = seconds < 0 ? 0 : seconds;
  final hours = safe ~/ 3600, minutes = (safe % 3600) ~/ 60, rest = safe % 60;
  return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${rest.toString().padLeft(2, '0')}';
}

String formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

String monthName(int month) => const [
  'JANUARY',
  'FEBRUARY',
  'MARCH',
  'APRIL',
  'MAY',
  'JUNE',
  'JULY',
  'AUGUST',
  'SEPTEMBER',
  'OCTOBER',
  'NOVEMBER',
  'DECEMBER',
][month - 1];
String weekday(int weekday) =>
    const ['星期一', '星期二', '星期三', '星期四', '星期五', '星期六', '星期日'][weekday - 1];
String fileKind(String name) {
  final ext = name.toLowerCase().split('.').last;
  if (['png', 'jpg', 'jpeg', 'gif', 'webp', 'svg'].contains(ext)) {
    return 'image';
  }
  if (['txt', 'md', 'json', 'csv'].contains(ext)) return 'text';
  if (ext == 'pdf') return 'pdf';
  if (['doc', 'docx'].contains(ext)) return 'word';
  if (['ppt', 'pptx'].contains(ext)) return 'slides';
  if (['xls', 'xlsx'].contains(ext)) return 'sheet';
  if (['mp4', 'mov', 'avi'].contains(ext)) return 'video';
  if (['mp3', 'wav'].contains(ext)) return 'audio';
  if (['zip', 'rar', '7z'].contains(ext)) return 'archive';
  return 'file';
}

bool canPreview(String kind) => ['image', 'text', 'pdf'].contains(kind);
bool isOfficeDocument(String name) =>
    ['word', 'slides', 'sheet'].contains(fileKind(name));
