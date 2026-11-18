import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../domain/guard_policy.dart';
import '../domain/guard_repository.dart';

GuardPlatform currentGuardPlatform() {
  if (!kIsWeb) {
    if (defaultTargetPlatform == TargetPlatform.iOS) return GuardPlatform.ios;
    if (defaultTargetPlatform == TargetPlatform.android)
      return GuardPlatform.android;
  }
  throw UnsupportedError(
    'App guard requires an explicit policy platform outside iOS/Android.',
  );
}

class PackageInstalledVersionReader implements InstalledVersionReader {
  const PackageInstalledVersionReader();
  @override
  Future<String> read() async => (await PackageInfo.fromPlatform()).version;
}

class ExternalStoreLauncher implements StoreLauncher {
  const ExternalStoreLauncher();
  @override
  Future<bool> launch(Uri uri) =>
      launchUrl(uri, mode: LaunchMode.externalApplication);
}

/// Hosts can replace this validator for enterprise distribution URLs.
bool isPlatformStoreUri(Uri uri) {
  if (uri.scheme == 'https') {
    return (uri.host == 'apps.apple.com' && uri.path.contains('/app/')) ||
        (uri.host == 'play.google.com' &&
            uri.path == '/store/apps/details' &&
            (uri.queryParameters['id']?.isNotEmpty ?? false));
  }
  if (uri.scheme == 'market') {
    return uri.host == 'details' &&
        (uri.queryParameters['id']?.isNotEmpty ?? false);
  }
  return uri.scheme == 'itms-apps' &&
      (uri.host == 'apps.apple.com' || uri.host == 'itunes.apple.com') &&
      uri.path.contains('/app/');
}
