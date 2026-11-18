import 'dart:async';
import 'package:app_availability_guard/app_availability_guard.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support.dart';

void main() {
  late FakeRepository repository;
  late FakeVersion version;
  late FakeStore store;
  late ValueNotifier<bool> api, critical;
  late AppGuardController controller;
  setUp(() {
    repository = FakeRepository();
    version = FakeVersion();
    store = FakeStore();
    api = ValueNotifier(false);
    critical = ValueNotifier(false);
    controller = AppGuardController(
      repository: repository,
      versionReader: version,
      storeLauncher: store,
      apiUnavailable: api,
      criticalOperationActive: critical,
    );
  });
  tearDown(() async {
    await controller.close();
    api.dispose();
    critical.dispose();
  });

  test('equal/newer versions allow access', () async {
    repository.value = policy(latest: '1.0.0');
    await controller.refresh();
    expect(controller.view, GuardView.none);
    version.value = '3.0.0';
    await controller.refresh();
    expect(controller.view, GuardView.none);
  });
  test('minimum equality permits optional update', () async {
    await controller.refresh();
    expect(controller.view, GuardView.optionalUpdate);
  });
  test('below minimum requires update', () async {
    repository.value = policy(minimum: '1.1.0');
    await controller.refresh();
    expect(controller.view, GuardView.mandatoryUpdate);
  });
  test(
    'maintenance takes priority and reveals mandatory after disabling',
    () async {
      repository.value = policy(
        minimum: '1.1.0',
        maintenance: true,
        title: 'Work',
      );
      await controller.refresh();
      expect(controller.view, GuardView.maintenance);
      repository.publish(policy(minimum: '1.1.0'));
      expect(controller.view, GuardView.mandatoryUpdate);
    },
  );
  test('API and Firebase restrictions are independent', () async {
    await controller.refresh();
    api.value = true;
    repository.publish(policy(maintenance: true));
    api.value = false;
    expect(controller.view, GuardView.maintenance);
    api.value = true;
    repository.publish(policy());
    expect(controller.view, GuardView.maintenance);
    api.value = false;
    expect(controller.view, GuardView.optionalUpdate);
  });
  test('mandatory gate survives loading and failed refresh', () async {
    repository.value = policy(minimum: '1.1.0');
    await controller.refresh();
    repository.pending = Completer<GuardPolicy>();
    final check = controller.refresh();
    expect(controller.isRefreshing, isTrue);
    expect(controller.view, GuardView.mandatoryUpdate);
    repository.pending!.completeError(Exception('offline'));
    await check;
    expect(controller.view, GuardView.mandatoryUpdate);
    expect(controller.lastError, isNotNull);
  });
  test('overlapping checks coalesce', () async {
    repository.pending = Completer<GuardPolicy>();
    final first = controller.refresh();
    final second = controller.refresh();
    expect(identical(first, second), isTrue);
    repository.pending!.complete(policy());
    await first;
    expect(repository.calls, 1);
    expect(version.calls, 1);
  });
  test('reevaluate requests cached policy only', () async {
    await controller.reevaluate();
    expect(repository.requestedRefresh, isFalse);
  });
  test('invalid latest preserves previous mandatory decision', () async {
    repository.value = policy(minimum: '1.1.0');
    await controller.refresh();
    repository.publish(policy(latest: 'bad'));
    expect(controller.view, GuardView.mandatoryUpdate);
    expect(controller.lastError, isA<FormatException>());
  });
  for (final entry in {
    'invalid minimum': policy(minimum: 'bad'),
    'reversed bounds': policy(latest: '1.0.0', minimum: '2.0.0'),
  }.entries) {
    test(
      '${entry.key} is reported without inventing a blocking policy',
      () async {
        repository.value = entry.value;
        await controller.refresh();
        expect(controller.view, GuardView.none);
        expect(controller.lastError, isA<FormatException>());
      },
    );
  }
  test('maintenance works independently of invalid update metadata', () async {
    version.value = 'bad';
    repository.value = policy(maintenance: true);
    await controller.refresh();
    expect(controller.view, GuardView.maintenance);
  });
  test(
    'critical work defers mandatory and releases without a new fetch',
    () async {
      critical.value = true;
      repository.value = policy(minimum: '1.1.0');
      await controller.refresh();
      expect(controller.view, GuardView.none);
      critical.value = false;
      expect(controller.view, GuardView.mandatoryUpdate);
      expect(repository.calls, 1);
    },
  );
  test('critical work does not postpone maintenance', () async {
    critical.value = true;
    repository.value = policy(maintenance: true);
    await controller.refresh();
    expect(controller.view, GuardView.maintenance);
  });
  test('suppressed optional prompt is not consumed', () async {
    critical.value = true;
    await controller.refresh();
    controller.markOptionalPresented('2.0.0');
    critical.value = false;
    expect(controller.view, GuardView.optionalUpdate);
  });
  test(
    'optional session suppression is per version and explicitly resettable',
    () async {
      await controller.refresh();
      controller.markOptionalPresented('2.0.0');
      controller.dismissOptional();
      await controller.refresh();
      expect(controller.view, GuardView.none);
      repository.publish(policy(latest: '3.0.0'));
      expect(controller.view, GuardView.optionalUpdate);
      controller.dismissOptional();
      controller.allowOptionalPromptAgain();
      expect(controller.view, GuardView.optionalUpdate);
    },
  );
  test('failed launch retains optional recovery controls', () async {
    await controller.refresh();
    store.succeeds = false;
    expect(await controller.openStore(), StoreOpenResult.failed);
    expect(controller.view, GuardView.optionalUpdate);
    store.error = Exception('no handler');
    expect(await controller.openStore(), StoreOpenResult.failed);
    expect(controller.isLaunchingStore, isFalse);
  });
  test('invalid store URL is rejected before calling launcher', () async {
    repository.value = policy(url: 'https://wrong.example/app');
    await controller.refresh();
    expect(await controller.openStore(), StoreOpenResult.invalidUrl);
    expect(store.calls, 0);
  });
  test(
    'store launch deduplicates and success dismisses only optional',
    () async {
      await controller.refresh();
      store.pending = Completer<bool>();
      final first = controller.openStore();
      expect(await controller.openStore(), StoreOpenResult.busy);
      store.pending!.complete(true);
      await first;
      expect(controller.view, GuardView.none);
      store.pending = null;
      repository.publish(policy(minimum: '1.1.0'));
      await controller.openStore();
      expect(controller.view, GuardView.mandatoryUpdate);
    },
  );
  test(
    'new metadata can release mandatory without a forced backend fetch',
    () async {
      repository.value = policy(minimum: '1.1.0');
      await controller.refresh();
      version.value = '2.0.0';
      await controller.reevaluate();
      expect(controller.view, GuardView.none);
    },
  );
  test('live policy takes precedence over an older in-flight result', () async {
    repository.pending = Completer<GuardPolicy>();
    final check = controller.refresh();
    repository.publish(policy(minimum: '1.1.0'));
    repository.pending!.complete(policy(latest: '1.0.0'));
    await check;
    expect(controller.view, GuardView.mandatoryUpdate);
  });
  test('late results do not notify after disposal', () async {
    repository.pending = Completer<GuardPolicy>();
    final check = controller.refresh();
    var notifications = 0;
    controller.addListener(() => notifications++);
    await controller.close();
    repository.pending!.complete(policy(maintenance: true));
    await check;
    expect(notifications, 0);
    expect(repository.closed, isTrue);
  });
  test('API retry result cannot override Firebase maintenance', () async {
    final repo = FakeRepository()..value = policy(maintenance: true);
    final guard = AppGuardController(
      repository: repo,
      versionReader: FakeVersion(),
      checkApiAvailable: () async => true,
    );
    await guard.refresh();
    expect(guard.view, GuardView.maintenance);
    await guard.close();
  });
  test('gate stays blocked until both retry operations finish', () async {
    final available = Completer<bool>();
    final repo = FakeRepository()..value = policy(maintenance: true);
    final guard = AppGuardController(
      repository: repo,
      versionReader: FakeVersion(),
      checkApiAvailable: () => available.future,
    );
    final check = guard.refresh();
    repo.publish(policy(maintenance: true));
    await Future<void>.delayed(Duration.zero);
    expect(guard.view, GuardView.maintenance);
    available.complete(true);
    await check;
    final slow = Completer<GuardPolicy>();
    repo.pending = slow;
    final retry = guard.refresh();
    repo.publish(policy(latest: '1.0.0'));
    expect(guard.view, GuardView.maintenance);
    slow.complete(policy(latest: '1.0.0'));
    await retry;
    expect(guard.view, GuardView.none);
    await guard.close();
  });
}
