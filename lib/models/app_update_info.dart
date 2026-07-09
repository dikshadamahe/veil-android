/// Metadata for a published Veil APK release (GitHub Releases / version.json).
class AppUpdateInfo {
  const AppUpdateInfo({
    required this.versionName,
    required this.versionCode,
    required this.apkUrl,
    required this.tag,
    this.sha256,
    this.notes,
    this.mandatory = false,
    this.minVersionCode = 1,
  });

  final String versionName;
  final int versionCode;
  final String apkUrl;
  final String tag;
  final String? sha256;
  final String? notes;
  final bool mandatory;
  final int minVersionCode;

  bool isNewerThan(int installedVersionCode) =>
      versionCode > installedVersionCode;

  factory AppUpdateInfo.fromJson(Map<String, dynamic> json) {
    final Object? versionCodeRaw = json['versionCode'] ?? json['version_code'];
    final int versionCode = switch (versionCodeRaw) {
      int value => value,
      String value => int.tryParse(value.trim()) ?? 0,
      num value => value.toInt(),
      _ => 0,
    };

    final Object? minRaw = json['minVersionCode'] ?? json['min_version_code'];
    final int minVersionCode = switch (minRaw) {
      int value => value,
      String value => int.tryParse(value.trim()) ?? 1,
      num value => value.toInt(),
      _ => 1,
    };

    return AppUpdateInfo(
      versionName: (json['versionName'] ?? json['version_name'] ?? '').toString(),
      versionCode: versionCode,
      apkUrl: (json['apkUrl'] ?? json['apk_url'] ?? '').toString(),
      tag: (json['tag'] ?? '').toString(),
      sha256: json['sha256']?.toString(),
      notes: json['notes']?.toString() ?? json['body']?.toString(),
      mandatory: json['mandatory'] == true,
      minVersionCode: minVersionCode,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'versionName': versionName,
      'versionCode': versionCode,
      'apkUrl': apkUrl,
      'tag': tag,
      if (sha256 != null) 'sha256': sha256,
      if (notes != null) 'notes': notes,
      'mandatory': mandatory,
      'minVersionCode': minVersionCode,
    };
  }

  AppUpdateInfo copyWith({
    String? versionName,
    int? versionCode,
    String? apkUrl,
    String? tag,
    String? sha256,
    String? notes,
    bool? mandatory,
    int? minVersionCode,
  }) {
    return AppUpdateInfo(
      versionName: versionName ?? this.versionName,
      versionCode: versionCode ?? this.versionCode,
      apkUrl: apkUrl ?? this.apkUrl,
      tag: tag ?? this.tag,
      sha256: sha256 ?? this.sha256,
      notes: notes ?? this.notes,
      mandatory: mandatory ?? this.mandatory,
      minVersionCode: minVersionCode ?? this.minVersionCode,
    );
  }
}
