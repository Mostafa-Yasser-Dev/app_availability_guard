import 'dart:async';

import 'package:firebase_remote_config/firebase_remote_config.dart';

import '../domain/guard_policy.dart';
import '../domain/guard_repository.dart';

/// Remote Config parameter names supplied by the application.
///
/// Use distinct, nonblank names matching your Firebase configuration.
/// The package supplies fallback values, but owns no parameter names.
class GuardConfigKeys {
  const GuardConfigKeys({
    required this.iosLatest,
    required this.iosMinimum,
    required this.iosStore,
    required this.iosNotes,
    required this.androidLatest,
    required this.androidMinimum,
    required this.androidStore,
    required this.androidNotes,
    required this.maintenanceEnabled,
    required this.maintenanceTitle,
    required this.maintenanceMessage,
    required this.maintenanceEndTime,
  });
  final String iosLatest, iosMinimum, iosStore, iosNotes;
  final String androidLatest, androidMinimum, androidStore, androidNotes;
  final String maintenanceEnabled,
      maintenanceTitle,
      maintenanceMessage,
      maintenanceEndTime;

  Map<String, dynamic> get defaults => {
    iosLatest: '1.0.0',
    iosMinimum: '1.0.0',
    iosStore: '',
    iosNotes: '',
    androidLatest: '0.0.0',
    androidMinimum: '0.0.0',
    androidStore: '',
    androidNotes: '',
    maintenanceEnabled: false,
    maintenanceTitle: '',
    maintenanceMessage: '',
    maintenanceEndTime: '',
  };
}

class FirebaseGuardConfiguration {
  const FirebaseGuardConfiguration({
    required this.platform,
    required this.keys,
    this.fetchTimeout = const Duration(seconds: 10),
    this.minimumFetchInterval = const Duration(hours: 1),
    this.additionalDefaults = const {},
    this.configureSdk = true,
    this.listenInRealTime = true,
    this.onError,
  });
  final GuardPlatform platform;
  final GuardConfigKeys keys;
  final Duration fetchTimeout, minimumFetchInterval;

  /// Include all other application defaults when this adapter owns SDK setup.
  final Map<String, dynamic> additionalDefaults;

  /// Set false when the host centrally configures defaults/settings itself.
  final bool configureSdk;
  final bool listenInRealTime;
  final void Function(Object error, StackTrace stack)? onError;
}

/// Firebase adapter and policy mapping. Firebase.initializeApp remains host-owned.
class FirebaseGuardRepository implements GuardRepository {
  FirebaseGuardRepository(this._remote, {required this.configuration});
  final FirebaseRemoteConfig _remote;
  final FirebaseGuardConfiguration configuration;
  final _changes = StreamController<GuardPolicy>.broadcast();
  StreamSubscription<RemoteConfigUpdate>? _subscription;
  Future<void>? _initialization;
  Future<GuardPolicy>? _loading;
  bool _closed = false;

  @override
  Stream<GuardPolicy> get changes => _changes.stream;

  Future<void> _initialize() =>
      _initialization ??= _setup().catchError((Object error, StackTrace stack) {
        _initialization = null;
        Error.throwWithStackTrace(error, stack);
      });

  Future<void> _setup() async {
    if (configuration.configureSdk) {
      await _remote.setDefaults({
        ...configuration.additionalDefaults,
        ...configuration.keys.defaults,
      });
      await _remote.setConfigSettings(
        RemoteConfigSettings(
          fetchTimeout: configuration.fetchTimeout,
          minimumFetchInterval: configuration.minimumFetchInterval,
        ),
      );
    }
    await _remote.ensureInitialized();
    if (_closed) return;
    _publish(PolicyOrigin.available);
    if (configuration.listenInRealTime) {
      _subscription = _remote.onConfigUpdated.listen(
        (_) => unawaited(_activate()),
        onError: (Object error, StackTrace stack) =>
            configuration.onError?.call(error, stack),
      );
    }
  }

  Future<void> _activate() async {
    try {
      await _remote.activate();
      _publish(PolicyOrigin.refreshed);
    } catch (error, stack) {
      configuration.onError?.call(error, stack);
    }
  }

  void _publish(PolicyOrigin origin) {
    if (!_closed) _changes.add(_read(origin));
  }

  @override
  Future<GuardPolicy> load({bool refresh = true}) {
    if (_closed) return Future.error(StateError('Repository is closed'));
    if (!refresh) return _available();
    return _loading ??= _fetch().whenComplete(() => _loading = null);
  }

  Future<GuardPolicy> _available() async {
    await _initialize();
    return _read(PolicyOrigin.available);
  }

  Future<GuardPolicy> _fetch() async {
    await _initialize();
    var origin = PolicyOrigin.available;
    if (!_closed) {
      try {
        await _remote.fetchAndActivate();
        origin = PolicyOrigin.refreshed;
      } catch (error, stack) {
        configuration.onError?.call(error, stack);
      }
    }
    final value = _read(origin);
    if (!_closed) _changes.add(value);
    return value;
  }

  GuardPolicy _read(PolicyOrigin origin) {
    final keys = configuration.keys;
    final ios = configuration.platform == GuardPlatform.ios;
    String? optional(String key) {
      final value = _remote.getString(key).trim();
      return value.isEmpty ? null : value;
    }

    final fetched = _remote.lastFetchTime;
    return GuardPolicy(
      origin: origin,
      lastSuccessfulFetch: fetched.millisecondsSinceEpoch > 0 ? fetched : null,
      update: UpdatePolicy(
        latestVersion: _remote
            .getString(ios ? keys.iosLatest : keys.androidLatest)
            .trim(),
        minimumVersion: _remote
            .getString(ios ? keys.iosMinimum : keys.androidMinimum)
            .trim(),
        storeUrl: _remote
            .getString(ios ? keys.iosStore : keys.androidStore)
            .trim(),
        releaseNotes: _remote.getString(
          ios ? keys.iosNotes : keys.androidNotes,
        ),
      ),
      maintenance: MaintenancePolicy(
        enabled: _remote.getBool(keys.maintenanceEnabled),
        title: optional(keys.maintenanceTitle),
        message: optional(keys.maintenanceMessage),
        endTime: optional(keys.maintenanceEndTime),
      ),
    );
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _subscription?.cancel();
    await _changes.close();
  }
}
