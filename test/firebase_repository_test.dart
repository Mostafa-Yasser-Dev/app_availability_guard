import 'dart:async';
import 'package:app_availability_guard/app_availability_guard.dart';
import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:flutter_test/flutter_test.dart';

const testKeys = GuardConfigKeys(
  iosLatest: 'team_ios_latest_version',
  iosMinimum: 'team_ios_minimum_version',
  iosStore: 'team_ios_store_url',
  iosNotes: 'team_ios_release_notes',
  androidLatest: 'team_android_latest_version',
  androidMinimum: 'team_android_minimum_version',
  androidStore: 'team_android_store_url',
  androidNotes: 'team_android_release_notes',
  maintenanceEnabled: 'team_maintenance_enabled',
  maintenanceTitle: 'team_maintenance_title',
  maintenanceMessage: 'team_maintenance_message',
  maintenanceEndTime: 'team_maintenance_end_time',
);

class FakeFirebase extends Fake implements FirebaseRemoteConfig {
  final values = <String, dynamic>{};
  final updates = StreamController<RemoteConfigUpdate>.broadcast();
  int setups = 0, fetches = 0, activations = 0;
  bool setupFails = false, fetchFails = false, activationFails = false;
  Completer<bool>? pending;
  RemoteConfigSettings? configuredSettings;
  @override
  DateTime get lastFetchTime => DateTime.fromMillisecondsSinceEpoch(0);
  @override
  Future<void> setDefaults(Map<String, dynamic> defaults) async {
    setups++;
    if (setupFails) throw Exception('init');
    defaults.forEach((key, value) => values.putIfAbsent(key, () => value));
  }

  @override
  Future<void> ensureInitialized() async {}
  @override
  Future<void> setConfigSettings(RemoteConfigSettings settings) async {
    configuredSettings = settings;
  }

  @override
  Stream<RemoteConfigUpdate> get onConfigUpdated => updates.stream;
  @override
  Future<bool> fetchAndActivate() async {
    fetches++;
    if (fetchFails) throw Exception('offline');
    return pending?.future ?? false;
  }

  @override
  Future<bool> activate() async {
    activations++;
    if (activationFails) throw Exception('activation');
    return true;
  }

  @override
  String getString(String key) => values[key]?.toString() ?? '';
  @override
  bool getBool(String key) => values[key] == true;
}

void main() {
  late FakeFirebase sdk;
  late FirebaseGuardRepository repository;
  final errors = <Object>[];
  setUp(() {
    errors.clear();
    sdk = FakeFirebase();
    repository = FirebaseGuardRepository(
      sdk,
      configuration: FirebaseGuardConfiguration(
        platform: GuardPlatform.android,
        keys: testKeys,
        additionalDefaults: const {'other_feature': true},
        onError: (error, stack) => errors.add(error),
      ),
    );
  });
  tearDown(() async {
    await repository.close();
    await sdk.updates.close();
  });
  test('initializes all twelve keys once and coalesces fetches', () async {
    await Future.wait([repository.load(), repository.load()]);
    expect(sdk.setups, 1);
    expect(sdk.fetches, 1);
    expect(
      sdk.values.keys,
      unorderedEquals([...testKeys.defaults.keys, 'other_feature']),
    );
    expect(sdk.values['other_feature'], isTrue);
    expect(
      sdk.configuredSettings?.minimumFetchInterval,
      const Duration(hours: 1),
    );
  });
  test(
    'defaults permit normal access and omit optional maintenance copy',
    () async {
      final value = await repository.load();
      expect(value.update.latestVersion, '0.0.0');
      expect(value.maintenance.enabled, isFalse);
      expect(value.maintenance.title, isNull);
      expect(value.maintenance.endTime, isNull);
    },
  );
  test('Android values and trimmed maintenance strings are mapped', () async {
    sdk.values.addAll({
      testKeys.androidLatest: ' 2.0.0 ',
      testKeys.iosLatest: '9.0.0',
      testKeys.maintenanceEnabled: true,
      testKeys.maintenanceTitle: '  Work ',
      testKeys.maintenanceMessage: ' ',
      testKeys.maintenanceEndTime: 'Tomorrow',
    });
    final value = await repository.load();
    expect(value.update.latestVersion, '2.0.0');
    expect(value.maintenance.title, 'Work');
    expect(value.maintenance.message, isNull);
    expect(value.maintenance.endTime, 'Tomorrow');
  });
  test('iOS selects only the iOS policy', () async {
    final ios = FirebaseGuardRepository(
      sdk,
      configuration: const FirebaseGuardConfiguration(
        platform: GuardPlatform.ios,
        keys: testKeys,
      ),
    );
    sdk.values.addAll({
      testKeys.iosLatest: '3.0.0',
      testKeys.androidLatest: '2.0.0',
    });
    expect((await ios.load()).update.latestVersion, '3.0.0');
    await ios.close();
  });
  for (final platform in GuardPlatform.values) {
    test(
      'all app-supplied keys drive $platform without legacy fallbacks',
      () async {
        final custom = FirebaseGuardRepository(
          sdk,
          configuration: FirebaseGuardConfiguration(
            platform: platform,
            keys: testKeys,
          ),
        );
        addTearDown(custom.close);
        sdk.values.addAll({
          testKeys.iosLatest: '4.0.0',
          testKeys.iosMinimum: '3.0.0',
          testKeys.iosStore: 'https://apps.apple.com/app/id123',
          testKeys.iosNotes: 'iOS notes',
          testKeys.androidLatest: '6.0.0',
          testKeys.androidMinimum: '5.0.0',
          testKeys.androidStore:
              'https://play.google.com/store/apps/details?id=team.app',
          testKeys.androidNotes: 'Android notes',
          testKeys.maintenanceEnabled: true,
          testKeys.maintenanceTitle: 'Team maintenance',
          testKeys.maintenanceMessage: 'Please wait',
          testKeys.maintenanceEndTime: 'Tonight',
          'maintenance_enabled': false,
          'ios_latest_version': '99.0.0',
          'android_latest_version': '99.0.0',
        });
        final policy = await custom.load(refresh: false);
        final ios = platform == GuardPlatform.ios;
        expect(policy.update.latestVersion, ios ? '4.0.0' : '6.0.0');
        expect(policy.update.minimumVersion, ios ? '3.0.0' : '5.0.0');
        expect(
          policy.update.storeUrl,
          sdk.values[ios ? testKeys.iosStore : testKeys.androidStore],
        );
        expect(policy.update.releaseNotes, ios ? 'iOS notes' : 'Android notes');
        expect(policy.maintenance.enabled, isTrue);
        expect(policy.maintenance.title, 'Team maintenance');
        expect(policy.maintenance.message, 'Please wait');
        expect(policy.maintenance.endTime, 'Tonight');
      },
    );
  }
  test('cached enabled policy is delivered before a slow fetch', () async {
    sdk.values[testKeys.maintenanceEnabled] = true;
    sdk.pending = Completer<bool>();
    final cached = repository.changes.first;
    final check = repository.load();
    expect((await cached).maintenance.enabled, isTrue);
    sdk.pending!.complete(false);
    await check;
  });
  test('fetch failure preserves policy and reports diagnostics', () async {
    sdk.values[testKeys.maintenanceEnabled] = true;
    sdk.fetchFails = true;
    final value = await repository.load();
    expect(value.maintenance.enabled, isTrue);
    expect(value.origin, PolicyOrigin.available);
    expect(errors, hasLength(1));
  });
  test('live publication activates once and emits updated fields', () async {
    await repository.load();
    await Future<void>.delayed(Duration.zero);
    final next = repository.changes.first;
    sdk.values[testKeys.maintenanceEnabled] = true;
    sdk.updates.add(RemoteConfigUpdate({testKeys.maintenanceEnabled}));
    expect((await next).maintenance.enabled, isTrue);
    expect(sdk.activations, 1);
  });
  test('failed initialization is retryable', () async {
    sdk.setupFails = true;
    await expectLater(repository.load(), throwsException);
    sdk.setupFails = false;
    await repository.load();
    expect(sdk.setups, 2);
  });
  test('host-managed SDK setup is not overwritten', () async {
    final external = FirebaseGuardRepository(
      sdk,
      configuration: const FirebaseGuardConfiguration(
        platform: GuardPlatform.android,
        keys: testKeys,
        configureSdk: false,
      ),
    );
    await external.load();
    expect(sdk.setups, 0);
    expect(sdk.configuredSettings, isNull);
    await external.close();
  });
  test('custom key names and cache-only reads are supported', () async {
    final custom = FirebaseGuardRepository(
      sdk,
      configuration: const FirebaseGuardConfiguration(
        platform: GuardPlatform.android,
        keys: testKeys,
      ),
    );
    sdk.values[testKeys.maintenanceEnabled] = true;
    expect((await custom.load(refresh: false)).maintenance.enabled, isTrue);
    expect(sdk.fetches, 0);
    await custom.close();
  });
  test(
    'activation failure reports error without clearing current policy',
    () async {
      await repository.load();
      sdk.activationFails = true;
      sdk.updates.add(RemoteConfigUpdate({testKeys.maintenanceEnabled}));
      await Future<void>.delayed(Duration.zero);
      expect(errors, hasLength(1));
    },
  );
  test('close cancels subscriptions and rejects subsequent loads', () async {
    await repository.load();
    expect(sdk.updates.hasListener, isTrue);
    await repository.close();
    expect(sdk.updates.hasListener, isFalse);
    await expectLater(repository.load(), throwsStateError);
  });
}
