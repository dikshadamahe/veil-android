class AppConfig {
  AppConfig._();

  static String get proxyBaseUrl => _normalizeProxyBaseUrl(
    const String.fromEnvironment(
      'ORACLE_URL',
      defaultValue: 'http://127.0.0.1:3001',
    ),
  );

  static String get tmdbReadToken =>
      const String.fromEnvironment('TMDB_TOKEN', defaultValue: '');

  static bool get hasTmdbReadToken => tmdbReadToken.trim().isNotEmpty;

  /// Wyzie Subs API key — https://sub.wyzie.io/redeem (never commit; use `--dart-define`).
  static String get wyzieApiKey =>
      const String.fromEnvironment('WYZIE_API_KEY', defaultValue: '');

  static bool get hasWyzieApiKey => wyzieApiKey.trim().isNotEmpty;

  /// OpenSubtitles.com REST API key (never commit).
  static String get opensubtitlesApiKey =>
      const String.fromEnvironment('OPENSUBTITLES_API_KEY', defaultValue: '');

  /// Optional: OpenSubtitles **account** for `/login` (needed to turn `file_id` into a download link).
  static String get opensubtitlesUsername =>
      const String.fromEnvironment('OPENSUBTITLES_USERNAME', defaultValue: '');

  static String get opensubtitlesPassword =>
      const String.fromEnvironment('OPENSUBTITLES_PASSWORD', defaultValue: '');

  static bool get hasOpensubtitlesApiKey =>
      opensubtitlesApiKey.trim().isNotEmpty;

  static bool get hasOpensubtitlesLogin =>
      hasOpensubtitlesApiKey &&
      opensubtitlesUsername.trim().isNotEmpty &&
      opensubtitlesPassword.trim().isNotEmpty;

  /// Required by OpenSubtitles.com on every request.
  static String get subtitleHttpUserAgent => const String.fromEnvironment(
        'SUBTITLE_HTTP_USER_AGENT',
        defaultValue: 'Veil 1.0.0',
      );

  static bool get isDefaultLocalOracleUrl {
    return proxyBaseUrl == 'http://127.0.0.1:3001' ||
        proxyBaseUrl == 'http://localhost:3001';
  }

  static double get watchedRatio {
    const String rawValue = String.fromEnvironment(
      'WATCHED_RATIO',
      defaultValue: '0.90',
    );
    return double.tryParse(rawValue) ?? 0.90;
  }

  static String _trimTrailingSlash(String value) {
    return value.replaceFirst(RegExp(r'/+$'), '');
  }

  static String _normalizeProxyBaseUrl(String value) {
    final String trimmed = _trimTrailingSlash(value.trim());
    if (trimmed.isEmpty) {
      return '';
    }

    final Uri? uri = Uri.tryParse(trimmed);
    if (uri == null || uri.host.isEmpty) {
      return trimmed;
    }

    if (uri.hasPort) {
      return trimmed;
    }

    final Uri normalized = uri.replace(port: 3001);
    return normalized.toString();
  }
}
