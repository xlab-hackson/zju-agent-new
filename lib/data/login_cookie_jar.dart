/// Cookie dates are more permissive than HTTP Date headers (RFC 6265 §5.1.1).
/// CAS uses values such as "Thu, 01-Jan-1970 00:00:00 GMT" that HttpDate.parse
/// rejects with HttpException. Preserve past dates so logout cookies are removed.
DateTime? parseLoginCookieExpiry(String value) {
  final tokens = value.split(
    RegExp(r'[\x09\x20-\x2f\x3b-\x40\x5b-\x60\x7b-\x7e]+'),
  );
  int? hour, minute, second, day, month, year;
  const months = [
    'jan',
    'feb',
    'mar',
    'apr',
    'may',
    'jun',
    'jul',
    'aug',
    'sep',
    'oct',
    'nov',
    'dec',
  ];
  for (final token in tokens) {
    final time = RegExp(
      r'^(\d{1,2}):(\d{1,2}):(\d{1,2})(?:\D.*)?$',
    ).firstMatch(token);
    if (hour == null && time != null) {
      hour = int.parse(time[1]!);
      minute = int.parse(time[2]!);
      second = int.parse(time[3]!);
      continue;
    }
    final number = RegExp(r'^(\d{1,4})(?:\D.*)?$').firstMatch(token)?[1];
    if (day == null && number != null && number.length <= 2) {
      day = int.parse(number);
      continue;
    }
    final shortMonth = token.toLowerCase();
    final index = shortMonth.length < 3
        ? -1
        : months.indexOf(shortMonth.substring(0, 3));
    if (month == null && index >= 0) {
      month = index + 1;
      continue;
    }
    if (year == null && number != null && number.length >= 2) {
      year = int.parse(number);
    }
  }
  if (hour == null ||
      minute == null ||
      second == null ||
      day == null ||
      month == null ||
      year == null) {
    return null;
  }
  if (year <= 69) {
    year += 2000;
  } else if (year <= 99) {
    year += 1900;
  }
  if (year < 1601 ||
      day < 1 ||
      day > 31 ||
      hour > 23 ||
      minute > 59 ||
      second > 59) {
    return null;
  }
  final result = DateTime.utc(year, month, day, hour, minute, second);
  return result.month == month && result.day == day ? result : null;
}

/// login-zju's jar selects one matching cookie per name, uses the request
/// path when Path is absent, and replaces the first colliding scope.
/// Deliberately local to campus authentication; not a general browser jar.
class LoginCookieJar {
  final Map<String, List<_Cookie>> _cookies = {};
  void clear() => _cookies.clear();
  void store(Uri origin, List<String> values) {
    for (final raw in values) {
      if (raw.length > 32768) continue;
      final parts = raw.split(';').where((s) => s.isNotEmpty).toList();
      if (parts.isEmpty) continue;
      final eq = parts.first.indexOf('=');
      if (eq <= 0) continue;
      final c = _Cookie(
        parts.first.substring(0, eq).trim(),
        parts.first.substring(eq + 1),
        origin.host,
        origin.path.isEmpty ? '/' : origin.path,
      );
      for (final part in parts.skip(1)) {
        final i = part.indexOf('='),
            key = (i < 0 ? part : part.substring(0, i)).trim().toLowerCase(),
            value = i < 0 ? '' : part.substring(i + 1).trim();
        switch (key) {
          case 'domain':
            c.domain = value.isEmpty ? origin.host : value;
            c.explicitDomain = value.isNotEmpty;
          case 'path':
            c.path = value;
          case 'secure':
            c.secure = true;
          case 'expires':
            c.expires = parseLoginCookieExpiry(value);
        }
      }
      // Reject cross-domain cookie injection while retaining upstream scope rules.
      final domain = c.domain.replaceFirst(RegExp(r'^\.'), '');
      if (origin.host != domain && !origin.host.endsWith('.$domain')) continue;
      final list = _cookies.putIfAbsent(c.name, () => []),
          index = list.indexWhere((old) => old.collides(c.domain, c.path));
      if (c.expired) {
        if (index >= 0) list.removeAt(index);
      } else if (index >= 0) {
        list[index] = c;
      } else {
        list.add(c);
      }
    }
  }

  String header(Uri target) {
    final selected = <String>[];
    for (final list in _cookies.values) {
      for (final c in list) {
        if (!c.expired &&
            (!c.secure || target.scheme == 'https') &&
            c.collides(target.host, target.path.isEmpty ? '/' : target.path)) {
          selected.add('${c.name}=${c.value}');
          break;
        }
      }
    }
    return selected.join('; ');
  }
}

class _Cookie {
  _Cookie(this.name, this.value, this.domain, this.path);
  final String name, value;
  String domain, path;
  bool explicitDomain = false, secure = false;
  DateTime? expires;
  bool get expired => expires != null && !expires!.isAfter(DateTime.now());
  bool collides(String host, String targetPath) {
    if (!targetPath.startsWith(path)) return false;
    final access = host.replaceFirst(RegExp(r'^\.'), ''),
        cookie = domain.replaceFirst(RegExp(r'^\.'), '');
    return cookie == access || (explicitDomain && access.endsWith('.$cookie'));
  }
}
