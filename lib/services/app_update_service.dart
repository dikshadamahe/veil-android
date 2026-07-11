import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pstream_android/config/app_config.dart';
import 'package:pstream_android/models/app_update_info.dart';
import 'package:pstream_android/storage/local_storage.dart';

/// Checks GitHub Releases for a newer Veil APK and installs it in-place.
class AppUpdateService {
  AppUpdateService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  static const Duration defaultCheckInterval = Duration(hours: 24);

  Future<PackageInfo> installedPackageInfo() => PackageInfo.fromPlatform();

  Future<int> installedVersionCode() async {
    final PackageInfo info = await installedPackageInfo();
    return int.tryParse(info.buildNumber) ?? 0;
  }

  /// Returns the latest published update when it is newer than the installed
  /// build; otherwise `null`.
  Future<AppUpdateInfo?> checkForUpdate({bool force = false}) async {
    if (!force && !_shouldCheckNow()) {
      return null;
    }

    final AppUpdateInfo? latest = await fetchLatestRelease();
    await LocalStorage.setLastUpdateCheckAt(DateTime.now());

    if (latest == null) {
      return null;
    }

    final int installed = await installedVersionCode();
    if (!latest.isNewerThan(installed)) {
      return null;
    }

    final int? dismissed = LocalStorage.getDismissedUpdateVersionCode();
    if (!force &&
        !latest.mandatory &&
        dismissed != null &&
        dismissed >= latest.versionCode) {
      return null;
    }

    return latest;
  }

  Future<AppUpdateInfo?> fetchLatestRelease() async {
    final String? manifestUrl = AppConfig.updateManifestUrl;
    if (manifestUrl != null && manifestUrl.isNotEmpty) {
      return _fetchManifest(Uri.parse(manifestUrl));
    }
    return _fetchGithubLatestRelease();
  }

  Future<AppUpdateInfo?> _fetchManifest(Uri uri) async {
    final http.Response response = await _client.get(
      uri,
      headers: const <String, String>{
        'Accept': 'application/json',
        'User-Agent': 'Veil-Android-Updater',
      },
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError(
        'Update manifest HTTP ${response.statusCode}: ${response.body}',
      );
    }
    final Object? decoded = jsonDecode(response.body);
    if (decoded is! Map) {
      throw const FormatException('Update manifest is not a JSON object');
    }
    final AppUpdateInfo info = AppUpdateInfo.fromJson(
      Map<String, dynamic>.from(decoded),
    );
    if (info.apkUrl.isEmpty || info.versionCode <= 0) {
      return null;
    }
    return info;
  }

  Future<AppUpdateInfo?> _fetchGithubLatestRelease() async {
    final Uri uri = Uri.parse(
      'https://api.github.com/repos/${AppConfig.updateGithubOwner}/'
      '${AppConfig.updateGithubRepo}/releases/latest',
    );
    final http.Response response = await _client.get(
      uri,
      headers: const <String, String>{
        'Accept': 'application/vnd.github+json',
        'User-Agent': 'Veil-Android-Updater',
        'X-GitHub-Api-Version': '2022-11-28',
      },
    );
    if (response.statusCode == 404) {
      return null;
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError(
        'GitHub releases HTTP ${response.statusCode}: ${response.body}',
      );
    }

    final Object? decoded = jsonDecode(response.body);
    if (decoded is! Map) {
      throw const FormatException('GitHub release payload is not a JSON object');
    }
    final Map<String, dynamic> release = Map<String, dynamic>.from(decoded);
    if (release['draft'] == true || release['prerelease'] == true) {
      return null;
    }

    final List<dynamic> assets =
        (release['assets'] as List<dynamic>?) ?? const <dynamic>[];
    Map<String, dynamic>? versionJsonAsset;
    Map<String, dynamic>? apkAsset;
    for (final dynamic raw in assets) {
      if (raw is! Map) {
        continue;
      }
      final Map<String, dynamic> asset = Map<String, dynamic>.from(raw);
      final String name = (asset['name'] ?? '').toString().toLowerCase();
      if (name == 'version.json') {
        versionJsonAsset = asset;
      } else if (name.endsWith('.apk')) {
        // Prefer tag-named assets (veil-vX.Y.Z.apk) over any other .apk.
        apkAsset ??= asset;
        if (name.startsWith('veil-v') || name.startsWith('veil-')) {
          apkAsset = asset;
        }
      }
    }

    if (versionJsonAsset != null) {
      final String? url = versionJsonAsset['browser_download_url']?.toString();
      if (url != null && url.isNotEmpty) {
        final AppUpdateInfo? fromManifest = await _fetchManifest(Uri.parse(url));
        if (fromManifest != null) {
          return fromManifest.copyWith(
            notes: fromManifest.notes ?? release['body']?.toString(),
            tag: fromManifest.tag.isNotEmpty
                ? fromManifest.tag
                : (release['tag_name']?.toString() ?? ''),
          );
        }
      }
    }

    if (apkAsset == null) {
      return null;
    }

    final String tag = (release['tag_name'] ?? '').toString();
    final String versionName = tag.startsWith('v') ? tag.substring(1) : tag;
    final int versionCode = _versionCodeFromTagOrName(versionName);

    return AppUpdateInfo(
      versionName: versionName.isEmpty ? 'unknown' : versionName,
      versionCode: versionCode,
      apkUrl: apkAsset['browser_download_url']?.toString() ?? '',
      tag: tag,
      notes: release['body']?.toString(),
    );
  }

  /// Downloads [update] to app cache, verifies SHA-256 when present, then
  /// opens the system package installer.
  Future<File> downloadAndInstall(
    AppUpdateInfo update, {
    void Function(double progress)? onProgress,
  }) async {
    if (update.apkUrl.isEmpty) {
      throw StateError('Update APK URL is empty');
    }

    final Directory base = await getTemporaryDirectory();
    final Directory dir = Directory('${base.path}/updates');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    final File apkFile = File('${dir.path}/veil-${update.versionCode}.apk');
    if (await apkFile.exists()) {
      await apkFile.delete();
    }

    final http.Request request = http.Request('GET', Uri.parse(update.apkUrl));
    request.headers['User-Agent'] = 'Veil-Android-Updater';
    final http.StreamedResponse response = await _client.send(request);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError('APK download HTTP ${response.statusCode}');
    }

    final int? total = response.contentLength;
    int received = 0;
    final IOSink sink = apkFile.openWrite();
    await for (final List<int> chunk in response.stream) {
      sink.add(chunk);
      received += chunk.length;
      if (total != null && total > 0) {
        onProgress?.call(received / total);
      }
    }
    await sink.close();
    onProgress?.call(1);

    if (update.sha256 != null && update.sha256!.trim().isNotEmpty) {
      final Digest digest = await sha256.bind(apkFile.openRead()).first;
      final String actual = digest.toString();
      if (actual.toLowerCase() != update.sha256!.trim().toLowerCase()) {
        await apkFile.delete();
        throw StateError(
          'APK checksum mismatch (expected ${update.sha256}, got $actual)',
        );
      }
    }

    final OpenResult result = await OpenFilex.open(
      apkFile.path,
      type: 'application/vnd.android.package-archive',
    );
    if (result.type != ResultType.done) {
      throw StateError(
        result.message.isEmpty
            ? 'Unable to open the package installer'
            : result.message,
      );
    }
    return apkFile;
  }

  Future<void> dismissUpdate(AppUpdateInfo update) {
    return LocalStorage.setDismissedUpdateVersionCode(update.versionCode);
  }

  bool _shouldCheckNow() {
    final DateTime? last = LocalStorage.getLastUpdateCheckAt();
    if (last == null) {
      return true;
    }
    return DateTime.now().difference(last) >= defaultCheckInterval;
  }

  /// Best-effort parse when version.json is missing: `1.0.2` → try pubspec
  /// style is unavailable, so fall back to stripping non-digits from the
  /// patch-ish form. Prefer attaching version.json from CI.
  static int _versionCodeFromTagOrName(String versionName) {
    final RegExpMatch? match = RegExp(
      r'^(\d+)\.(\d+)\.(\d+)$',
    ).firstMatch(versionName.trim());
    if (match != null) {
      final int major = int.parse(match.group(1)!);
      final int minor = int.parse(match.group(2)!);
      final int patch = int.parse(match.group(3)!);
      return major * 10000 + minor * 100 + patch;
    }
    return int.tryParse(versionName.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
  }

  void dispose() {
    _client.close();
  }
}
