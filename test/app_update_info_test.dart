import 'package:flutter_test/flutter_test.dart';
import 'package:pstream_android/models/app_update_info.dart';

void main() {
  group('AppUpdateInfo', () {
    test('parses version.json payload', () {
      final AppUpdateInfo info = AppUpdateInfo.fromJson(<String, dynamic>{
        'versionName': '1.0.2',
        'versionCode': 3,
        'apkUrl':
            'https://github.com/dikshadamahe/veil-android/releases/download/v1.0.2/veil.apk',
        'tag': 'v1.0.2',
        'sha256': 'abc',
        'mandatory': false,
        'minVersionCode': 1,
        'notes': 'Bug fixes',
      });

      expect(info.versionName, '1.0.2');
      expect(info.versionCode, 3);
      expect(info.isNewerThan(2), isTrue);
      expect(info.isNewerThan(3), isFalse);
      expect(info.sha256, 'abc');
      expect(info.notes, 'Bug fixes');
    });

    test('copyWith preserves unset fields', () {
      const AppUpdateInfo base = AppUpdateInfo(
        versionName: '1.0.2',
        versionCode: 3,
        apkUrl: 'https://example.com/veil.apk',
        tag: 'v1.0.2',
        sha256: 'deadbeef',
      );

      final AppUpdateInfo next = base.copyWith(notes: 'Changelog');
      expect(next.notes, 'Changelog');
      expect(next.sha256, 'deadbeef');
      expect(next.versionCode, 3);
    });
  });
}
