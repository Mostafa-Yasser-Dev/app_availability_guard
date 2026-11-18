import 'dart:async';
import 'package:flutter/foundation.dart';
import '../data/platform_adapters.dart';
import '../domain/guard_policy.dart';
import '../domain/guard_repository.dart';
import '../domain/version_comparator.dart';

enum StoreOpenResult { opened, invalidUrl, failed, busy }

class AppGuardController extends ChangeNotifier {
  AppGuardController({
    required GuardRepository repository,
    InstalledVersionReader versionReader =
        const PackageInstalledVersionReader(),
    StoreLauncher storeLauncher = const ExternalStoreLauncher(),
    this.isStoreUriAllowed = isPlatformStoreUri,
    this.checkApiAvailable,
    ValueListenable<bool>? apiUnavailable,
    ValueListenable<bool>? criticalOperationActive,
    this.onError,
  }) : _repository = repository,
       _versions = versionReader,
       _store = storeLauncher,
       _apiSignal = apiUnavailable,
       _criticalSignal = criticalOperationActive {
    _apiDown = apiUnavailable?.value ?? false;
    _critical = criticalOperationActive?.value ?? false;
    apiUnavailable?.addListener(_onApiChanged);
    criticalOperationActive?.addListener(_onCriticalChanged);
    _subscription = repository.changes.listen(
      _receive,
      onError: (Object error, StackTrace stack) => _recordError(error, stack),
    );
  }

  final GuardRepository _repository;
  final InstalledVersionReader _versions;
  final StoreLauncher _store;
  final ValueListenable<bool>? _apiSignal, _criticalSignal;
  final bool Function(Uri uri) isStoreUriAllowed;
  final Future<bool> Function()? checkApiAvailable;
  final void Function(Object error, StackTrace stack)? onError;
  late final StreamSubscription<GuardPolicy> _subscription;
  final _shownOptionalVersions = <String>{};
  String? _visibleOptionalVersion;
  String? _installedVersion;
  GuardPolicy? _latest;
  UpdatePolicy? _update;
  MaintenancePolicy _maintenance = const MaintenancePolicy();
  UpdateDecision _decision = UpdateDecision.none;
  GuardView _heldView = GuardView.none;
  bool _apiDown = false, _critical = false, _disposed = false;
  bool _refreshing = false, _launching = false;
  int _revision = 0;
  Future<void>? _refresh;
  Future<void>? _closeFuture;
  Object? _operationError;
  Object? _policyError;
  StoreOpenResult? _storeResult;

  String? get installedVersion => _installedVersion;
  UpdatePolicy? get updatePolicy => _update;
  MaintenancePolicy get maintenancePolicy => _maintenance;
  GuardPolicy? get latestPolicy => _latest;
  UpdateDecision get updateDecision => _decision;
  bool get isRefreshing => _refreshing;
  bool get isLaunchingStore => _launching;
  Object? get lastError => _operationError ?? _policyError;
  StoreOpenResult? get storeResult => _storeResult;
  bool get apiUnavailable => _apiDown;

  GuardView get view {
    if (_maintenance.enabled ||
        _apiDown ||
        _heldView == GuardView.maintenance) {
      return GuardView.maintenance;
    }
    if (_critical) return GuardView.none;
    if (_decision == UpdateDecision.mandatory ||
        _heldView == GuardView.mandatoryUpdate) {
      return GuardView.mandatoryUpdate;
    }
    final latest = _update?.latestVersion;
    if (_decision == UpdateDecision.optional &&
        latest != null &&
        (_visibleOptionalVersion == latest ||
            !_shownOptionalVersions.contains(latest))) {
      return GuardView.optionalUpdate;
    }
    return GuardView.none;
  }

  void _onApiChanged() {
    _apiDown = _apiSignal!.value;
    _notify();
  }

  void _onCriticalChanged() {
    _critical = _criticalSignal!.value;
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  void _recordError(Object error, StackTrace stack) {
    if (_disposed) return;
    _operationError = error;
    onError?.call(error, stack);
    _notify();
  }

  void _receive(GuardPolicy policy) {
    if (_disposed) return;
    _revision++;
    _latest = policy;
    _maintenance = policy.maintenance;
    _evaluate();
    _notify();
  }

  void _evaluate() {
    final policy = _latest;
    final installed = _installedVersion;
    if (policy == null || installed == null) return;
    try {
      final decision = const EvaluateUpdatePolicy()(installed, policy.update);
      _update = policy.update;
      _decision = decision;
      _policyError = null;
      if (_visibleOptionalVersion != _update?.latestVersion ||
          decision != UpdateDecision.optional) {
        _visibleOptionalVersion = null;
      }
    } catch (error, stack) {
      // Maintenance still updates independently; invalid update policy cannot
      // discard an existing valid mandatory decision.
      _policyError = error;
      onError?.call(error, stack);
    }
  }

  /// Reads metadata and available policy without requesting a backend fetch.
  Future<void> reevaluate() => _runRefresh(false);

  /// Requests policy refresh; SDK caching still applies. Also checks the host
  /// API when an availability callback is provided.
  Future<void> refresh() => _runRefresh(true);

  Future<void> _runRefresh(bool fetch) {
    if (_disposed) return Future.value();
    return _refresh ??= _performRefresh(
      fetch,
    ).whenComplete(() => _refresh = null);
  }

  Future<void> _performRefresh(bool fetch) async {
    final previous = view;
    _heldView =
        previous == GuardView.maintenance ||
            previous == GuardView.mandatoryUpdate
        ? previous
        : GuardView.none;
    _operationError = null;
    _refreshing = true;
    _notify();
    try {
      await Future.wait([
        _readVersion(),
        _loadPolicy(fetch),
        if (fetch && checkApiAvailable != null) _checkApi(),
      ]);
    } finally {
      _refreshing = false;
      _heldView = GuardView.none;
      _notify();
    }
  }

  Future<void> _readVersion() async {
    try {
      final version = await _versions.read();
      if (_disposed) return;
      if (!AppVersionComparator.isValid(version))
        throw FormatException('Invalid installed version', version);
      _installedVersion = version;
      _evaluate();
    } catch (error, stack) {
      _recordError(error, stack);
    }
  }

  Future<void> _loadPolicy(bool refresh) async {
    final revision = _revision;
    try {
      final policy = await _repository.load(refresh: refresh);
      if (!_disposed && revision == _revision) _receive(policy);
    } catch (error, stack) {
      _recordError(error, stack);
    }
  }

  Future<void> _checkApi() async {
    try {
      final available = await checkApiAvailable!();
      if (!_disposed) _apiDown = !available;
    } catch (error, stack) {
      if (!_disposed) _apiDown = true;
      _recordError(error, stack);
    }
    _notify();
  }

  /// Called by the gate after the optional surface is mounted, not on detection.
  void markOptionalPresented(String version) {
    if (_disposed ||
        view != GuardView.optionalUpdate ||
        _update?.latestVersion != version)
      return;
    _visibleOptionalVersion = version;
    _shownOptionalVersions.add(version);
  }

  void dismissOptional() {
    if (_disposed) return;
    final version = _update?.latestVersion;
    if (version != null) _shownOptionalVersions.add(version);
    _visibleOptionalVersion = null;
    _notify();
  }

  void allowOptionalPromptAgain() {
    _shownOptionalVersions.clear();
    _notify();
  }

  Future<StoreOpenResult> openStore() async {
    if (_disposed || _launching) return StoreOpenResult.busy;
    final policy = _update;
    final uri = Uri.tryParse(policy?.storeUrl.trim() ?? '');
    if (uri == null || !isStoreUriAllowed(uri)) {
      _storeResult = StoreOpenResult.invalidUrl;
      _notify();
      return StoreOpenResult.invalidUrl;
    }
    _launching = true;
    _storeResult = null;
    _notify();
    try {
      final opened = await _store.launch(uri);
      if (_disposed)
        return opened ? StoreOpenResult.opened : StoreOpenResult.failed;
      _storeResult = opened ? StoreOpenResult.opened : StoreOpenResult.failed;
      if (opened &&
          _decision == UpdateDecision.optional &&
          identical(policy, _update))
        dismissOptional();
      return _storeResult!;
    } catch (error, stack) {
      _recordError(error, stack);
      _storeResult = StoreOpenResult.failed;
      return StoreOpenResult.failed;
    } finally {
      _launching = false;
      _notify();
    }
  }

  /// Owns and closes the injected repository; do not share it across controllers.
  Future<void> close() {
    if (_closeFuture != null) return _closeFuture!;
    dispose();
    return _closeFuture!;
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _apiSignal?.removeListener(_onApiChanged);
    _criticalSignal?.removeListener(_onCriticalChanged);
    super.dispose();
    _closeFuture = Future.wait<void>([
      _subscription.cancel(),
      _repository.close(),
    ]).then((_) {});
    unawaited(_closeFuture);
  }
}
