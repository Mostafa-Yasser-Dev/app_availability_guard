import 'dart:async';
import 'package:app_availability_guard/app_availability_guard.dart';

const storeUrl = 'https://play.google.com/store/apps/details?id=ai.sahhal.app';
GuardPolicy policy({
  String latest = '2.0.0',
  String minimum = '1.0.0',
  bool maintenance = false,
  String? title,
  String? message,
  String? endTime,
  String url = storeUrl,
}) => GuardPolicy(
  update: UpdatePolicy(
    latestVersion: latest,
    minimumVersion: minimum,
    storeUrl: url,
  ),
  maintenance: MaintenancePolicy(
    enabled: maintenance,
    title: title,
    message: message,
    endTime: endTime,
  ),
);

class FakeRepository implements GuardRepository {
  GuardPolicy value = policy();
  final events = StreamController<GuardPolicy>.broadcast(sync: true);
  Object? error;
  Completer<GuardPolicy>? pending;
  int calls = 0;
  bool? requestedRefresh;
  bool closed = false;
  @override
  Stream<GuardPolicy> get changes => events.stream;
  @override
  Future<GuardPolicy> load({bool refresh = true}) async {
    calls++;
    requestedRefresh = refresh;
    if (pending != null) return pending!.future;
    if (error != null) throw error!;
    return value;
  }

  void publish(GuardPolicy policy) {
    value = policy;
    events.add(policy);
  }

  @override
  Future<void> close() async {
    if (closed) return;
    closed = true;
    await events.close();
  }
}

class FakeVersion implements InstalledVersionReader {
  String value = '1.0.0';
  int calls = 0;
  Object? error;
  @override
  Future<String> read() async {
    calls++;
    if (error != null) throw error!;
    return value;
  }
}

class FakeStore implements StoreLauncher {
  bool succeeds = true;
  Object? error;
  Completer<bool>? pending;
  int calls = 0;
  @override
  Future<bool> launch(Uri uri) async {
    calls++;
    if (error != null) throw error!;
    return pending?.future ?? succeeds;
  }
}
