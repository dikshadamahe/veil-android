// Veil runtime configuration.
//
// `ORACLE_URL` is the base of the self-hosted cinepro-org/core resolver
// (OMSS v1.0) running on the Oracle VM. cinepro returns absolute proxy
// URLs in every `source.url`, so the app does no URL prefixing or
// header injection. `resolveOmssUrl` exists as a defensive guard for
// any future relative path the server might emit.

class AppConfig {
  AppConfig._();

  /// Base URL for the cinepro-org/core resolver (e.g.
  /// `http://VM_IP:3001`). Used to build OMSS v1.0 request URLs and
  /// as the prefix for any relative path passed to [resolveOmssUrl].
  static String get oracleUrl {
    const String raw = String.fromEnvironment(
      'ORACLE_URL',
      defaultValue: 'http://127.0.0.1:3001',
    );
    return _trimTrailingSlash(raw.trim());
  }

  /// Returns [path] unchanged if it is already an absolute URL
  /// (has a scheme and host). Otherwise prefixes it with [oracleUrl].
  ///
  /// Also rewrites absolute resolver endpoints (starting with `/v1/`)
  /// that point to the loopback or same host to use [oracleUrl]'s
  /// scheme, host, and port, to handle port/proxy differences.
  static String resolveOmssUrl(String path) {
    final String trimmed = path.trim();
    if (trimmed.isEmpty) {
      return trimmed;
    }
    final Uri? uri = Uri.tryParse(trimmed);
    if (uri != null && uri.hasScheme && uri.host.isNotEmpty) {
      final Uri baseUri = Uri.parse(oracleUrl);
      final String host = uri.host.toLowerCase();
      final String baseHost = baseUri.host.toLowerCase();
      if (uri.path.startsWith('/v1/') &&
          (host == baseHost ||
           host == '127.0.0.1' ||
           host == 'localhost' ||
           host == '10.0.2.2')) {
        return uri.replace(
          scheme: baseUri.scheme,
          host: baseUri.host,
          port: baseUri.port,
        ).toString();
      }
      return trimmed;
    }
    if (trimmed.startsWith('/')) {
      return '$oracleUrl$trimmed';
    }
    return '$oracleUrl/$trimmed';
  }

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
    return oracleUrl == 'http://127.0.0.1:3001' ||
        oracleUrl == 'http://localhost:3001';
  }

  static double get watchedRatio {
    const String rawValue = String.fromEnvironment(
      'WATCHED_RATIO',
      defaultValue: '0.90',
    );
    return double.tryParse(rawValue) ?? 0.90;
  }

  /// Optional direct URL to a `version.json` manifest. When empty, the app
  /// falls back to the GitHub Releases API for [updateGithubOwner]/[updateGithubRepo].
  static String? get updateManifestUrl {
    const String raw = String.fromEnvironment(
      'UPDATE_MANIFEST_URL',
      defaultValue: '',
    );
    final String trimmed = raw.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  static String get updateGithubOwner => const String.fromEnvironment(
        'UPDATE_GITHUB_OWNER',
        defaultValue: 'dikshadamahe',
      );

  static String get updateGithubRepo => const String.fromEnvironment(
        'UPDATE_GITHUB_REPO',
        defaultValue: 'veil-android',
      );

  static String _trimTrailingSlash(String value) {
    return value.replaceFirst(RegExp(r'/+$'), '');
  }
}
