import 'guard_policy.dart';

abstract interface class GuardRepository {
  Stream<GuardPolicy> get changes;

  /// Refresh requests may use the SDK cache. They do not promise a network fetch.
  Future<GuardPolicy> load({bool refresh = true});
  Future<void> close();
}

abstract interface class InstalledVersionReader {
  Future<String> read();
}

abstract interface class StoreLauncher {
  Future<bool> launch(Uri uri);
}
