import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Web manifest', () {
    late Map<String, Object?> manifest;

    setUpAll(() {
      manifest =
          jsonDecode(File('web/manifest.json').readAsStringSync())
              as Map<String, Object?>;
    });

    test('uses Pixrompt branding instead of Flutter defaults', () {
      expect(manifest['description'], isNot('A new Flutter project.'));
      expect(
        (manifest['description'] as String).toLowerCase(),
        contains('pixrompt'),
      );
      expect((manifest['name'] as String).toLowerCase(), contains('pixrompt'));
      expect(
        (manifest['short_name'] as String).toLowerCase(),
        contains('pixrompt'),
      );
    });

    test('uses dark productivity colors', () {
      expect(manifest['background_color'], '#0B1020');
      expect(manifest['theme_color'], '#1E293B');
    });

    test('declares existing non-stock icon assets', () {
      final icons = manifest['icons'] as List<Object?>;
      expect(icons, isNotEmpty);

      final favicon = File('web/favicon.png');
      expect(favicon.existsSync(), isTrue);
      expect(_stockFlutterIconHashes, isNot(contains(_sha256Hex(favicon))));

      for (final icon in icons) {
        final entry = Map<String, Object?>.from(icon as Map);
        final src = entry['src'] as String;
        expect(src, startsWith('icons/'));
        expect(entry['type'], 'image/png');

        final file = File('web/$src');
        expect(file.existsSync(), isTrue);
        expect(_stockFlutterIconHashes, isNot(contains(_sha256Hex(file))));
      }
    });
  });

  group('Web shell', () {
    late String indexHtml;

    setUpAll(() {
      indexHtml = File('web/index.html').readAsStringSync();
    });

    test('uses Pixrompt metadata for browser and installed app surfaces', () {
      expect(indexHtml, contains('<title>Pixrompt</title>'));
      expect(indexHtml, contains('Pixrompt prompt workspace'));
      expect(
        indexHtml,
        contains(
          '<meta name="apple-mobile-web-app-title" content="Pixrompt">',
        ),
      );
      expect(indexHtml, isNot(contains('A new Flutter project.')));
      expect(indexHtml, isNot(contains('<title>pixrompt</title>')));
    });
  });

  group('iOS platform shell', () {
    test('declares photo-library usage for image picking', () {
      final infoPlist = File('ios/Runner/Info.plist').readAsStringSync();

      expect(
        infoPlist,
        contains('<key>NSPhotoLibraryUsageDescription</key>'),
      );
      expect(infoPlist, contains('Pixrompt'));
      expect(infoPlist, contains('图片'));
    });

    test('keeps a CocoaPods integration file for plugins', () {
      final podfile = File('ios/Podfile');

      expect(podfile.existsSync(), isTrue);
      expect(
        podfile.readAsStringSync(),
        contains('flutter_install_all_ios_pods'),
      );
    });

    test('uses the quaternijkon bundle identifier', () {
      final project =
          File('ios/Runner.xcodeproj/project.pbxproj').readAsStringSync();

      expect(
        project,
        contains('PRODUCT_BUNDLE_IDENTIFIER = online.quaternijkon.pixrompt;'),
      );
    });
  });

  group('macOS entitlements', () {
    for (final path in <String>[
      'macos/Runner/DebugProfile.entitlements',
      'macos/Runner/Release.entitlements',
    ]) {
      test('$path keeps sandbox and allows outbound network access', () {
        final entitlements = File(path).readAsStringSync();

        expect(
          entitlements,
          matches(_enabledEntitlement('com.apple.security.app-sandbox')),
        );
        expect(
          entitlements,
          matches(_enabledEntitlement('com.apple.security.network.client')),
        );
        expect(
          entitlements,
          matches(
            _enabledEntitlement(
              'com.apple.security.files.user-selected.read-write',
            ),
          ),
        );
      });
    }
  });

  group('macOS platform shell', () {
    test('uses Pixrompt as the product name', () {
      final appInfo =
          File('macos/Runner/Configs/AppInfo.xcconfig').readAsStringSync();

      expect(appInfo, contains('PRODUCT_NAME = Pixrompt'));
      expect(
        appInfo,
        contains('PRODUCT_BUNDLE_IDENTIFIER = online.quaternijkon.pixrompt'),
      );
    });

    test('keeps a CocoaPods integration file for plugins', () {
      final podfile = File('macos/Podfile');

      expect(podfile.existsSync(), isTrue);
      expect(
        podfile.readAsStringSync(),
        contains('flutter_install_all_macos_pods'),
      );
    });
  });
}

RegExp _enabledEntitlement(String key) {
  return RegExp('<key>${RegExp.escape(key)}</key>\\s*<true/>');
}

String _sha256Hex(File file) {
  return sha256.convert(file.readAsBytesSync()).toString();
}

const _stockFlutterIconHashes = {
  '7ab2525f4b86b65d3e4c70358a17e5a1aaf6f437f99cbcc046dad73d59bb9015',
  '3dce99077602f70421c1c6b2a240bc9b83d64d86681d45f2154143310c980be3',
  'baccb205ae45f0b421be1657259b4943ac40c95094ab877f3bcbe12cd544dcbe',
  'd2c842e22a9f4ec9d996b23373a905c88d9a203b220c5c151885ad621f974b5c',
  '6aee06cdcab6b2aef74b1734c4778f4421d2da100b0ff9e52b21b55240202929',
};
