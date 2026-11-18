import 'dart:async';
import 'package:app_availability_guard/app_availability_guard.dart';
import 'package:flutter/material.dart';

void main() => runApp(const ExampleApp());

/// An offline example; no Firebase project or store account is needed.
class ExampleApp extends StatefulWidget {
  const ExampleApp({super.key});
  @override
  State<ExampleApp> createState() => _ExampleAppState();
}

class _ExampleAppState extends State<ExampleApp> {
  final repository = ExampleRepository();
  final apiDown = ValueNotifier(false);
  final critical = ValueNotifier(false);
  late final controller = AppGuardController(
    repository: repository,
    versionReader: ExampleVersion(),
    storeLauncher: ExampleLauncher(),
    apiUnavailable: apiDown,
    criticalOperationActive: critical,
  );
  late final observer = GuardNavigatorObserver(controller);

  @override
  void dispose() {
    observer.dispose();
    unawaited(controller.close());
    apiDown.dispose();
    critical.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    navigatorObservers: [observer],
    builder: (context, child) =>
        AppGuardGate(controller: controller, child: child!),
    home: Scaffold(
      appBar: AppBar(title: const Text('App guard example')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const Text(
            'Installed version: 1.0.0. Blocking examples clear themselves after five seconds.',
          ),
          FilledButton(
            onPressed: () => repository.publish(latest: '2.0.0'),
            child: const Text('Optional update'),
          ),
          FilledButton(
            onPressed: () => repository.blockTemporarily(mandatory: true),
            child: const Text('Mandatory update'),
          ),
          FilledButton(
            onPressed: () => repository.blockTemporarily(maintenance: true),
            child: const Text('Maintenance'),
          ),
          ValueListenableBuilder<bool>(
            valueListenable: critical,
            builder: (_, active, _) => SwitchListTile(
              title: const Text('Critical operation active'),
              value: active,
              onChanged: (value) => critical.value = value,
            ),
          ),
          FilledButton(
            onPressed: () {
              apiDown.value = true;
              Future<void>.delayed(const Duration(seconds: 5), () {
                if (mounted) apiDown.value = false;
              });
            },
            child: const Text('API outage for five seconds'),
          ),
        ],
      ),
    ),
  );
}

class ExampleRepository implements GuardRepository {
  final _events = StreamController<GuardPolicy>.broadcast();
  Timer? _timer;
  GuardPolicy _policy = const GuardPolicy(
    update: UpdatePolicy(
      latestVersion: '1.0.0',
      minimumVersion: '1.0.0',
      storeUrl: '',
    ),
  );
  @override
  Stream<GuardPolicy> get changes => _events.stream;
  @override
  Future<GuardPolicy> load({bool refresh = true}) async => _policy;
  void publish({
    String latest = '1.0.0',
    String minimum = '1.0.0',
    bool maintenance = false,
  }) {
    _policy = GuardPolicy(
      update: UpdatePolicy(
        latestVersion: latest,
        minimumVersion: minimum,
        storeUrl: 'https://play.google.com/store/apps/details?id=example.app',
      ),
      maintenance: MaintenancePolicy(
        enabled: maintenance,
        title: 'Example maintenance',
        message: 'This simulated flag clears in five seconds.',
        endTime: 'Approximately five seconds',
      ),
    );
    _events.add(_policy);
  }

  void blockTemporarily({bool mandatory = false, bool maintenance = false}) {
    _timer?.cancel();
    publish(
      latest: mandatory ? '2.0.0' : '1.0.0',
      minimum: mandatory ? '2.0.0' : '1.0.0',
      maintenance: maintenance,
    );
    _timer = Timer(const Duration(seconds: 5), publish);
  }

  @override
  Future<void> close() async {
    _timer?.cancel();
    await _events.close();
  }
}

class ExampleVersion implements InstalledVersionReader {
  @override
  Future<String> read() async => '1.0.0';
}

class ExampleLauncher implements StoreLauncher {
  @override
  Future<bool> launch(Uri uri) async => true;
}
