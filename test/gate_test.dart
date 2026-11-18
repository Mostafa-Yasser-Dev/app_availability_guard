import 'dart:async';
import 'package:app_availability_guard/app_availability_guard.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support.dart';

void main() {
  Widget application(
    AppGuardController controller,
    GuardNavigatorObserver observer,
    GlobalKey<NavigatorState> navigator, {
    bool start = false,
    TextScaler? scaler,
  }) => MaterialApp(
    navigatorKey: navigator,
    navigatorObservers: [observer],
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(textScaler: scaler),
      child: AppGuardGate(
        controller: controller,
        checkOnStart: start,
        child: child!,
      ),
    ),
    home: const CounterPage(),
  );

  testWidgets(
    'optional dialog presents above the router and failed store launch stays recoverable',
    (tester) async {
      final repository = FakeRepository();
      final store = FakeStore()..succeeds = false;
      final controller = AppGuardController(
        repository: repository,
        versionReader: FakeVersion(),
        storeLauncher: store,
      );
      final observer = GuardNavigatorObserver(controller);
      await tester.pumpWidget(
        application(controller, observer, GlobalKey<NavigatorState>()),
      );
      await controller.refresh();
      await tester.pumpAndSettle();
      expect(find.text('New update available'), findsOneWidget);
      await tester.tap(find.text('Update now'));
      await tester.pumpAndSettle();
      expect(
        find.text(
          'Unable to open the store. Please try again or update manually.',
        ),
        findsOneWidget,
      );
      expect(find.text('Later'), findsOneWidget);
      await tester.tap(find.text('Later'));
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsNothing);
      await controller.refresh();
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      observer.dispose();
      controller.dispose();
      await tester.pump();
    },
  );

  testWidgets(
    'priority switches preserve page state and block host Navigator back',
    (tester) async {
      final repository = FakeRepository()..value = policy(latest: '1.0.0');
      final controller = AppGuardController(
        repository: repository,
        versionReader: FakeVersion(),
      );
      final observer = GuardNavigatorObserver(controller);
      final navigator = GlobalKey<NavigatorState>();
      await tester.pumpWidget(application(controller, observer, navigator));
      await tester.pumpAndSettle();
      unawaited(
        navigator.currentState!.push<void>(
          MaterialPageRoute(builder: (_) => const CounterPage()),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Increment'));
      await tester.pump();
      await controller.refresh();
      repository.publish(
        policy(
          minimum: '1.1.0',
          maintenance: true,
          title: 'Working',
          message: 'Please wait',
          endTime: '18:00 UTC',
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Working'), findsOneWidget);
      expect(find.text('18:00 UTC'), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(navigator.currentState!.canPop(), isTrue);
      expect(find.text('Working'), findsOneWidget);
      repository.publish(policy(minimum: '1.1.0'));
      await tester.pumpAndSettle();
      expect(find.text('Update required'), findsOneWidget);
      repository.publish(policy(latest: '1.0.0'));
      await tester.pumpAndSettle();
      expect(find.text('Count 1'), findsOneWidget);
      expect(navigator.currentState!.canPop(), isTrue);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      observer.dispose();
      controller.dispose();
      await tester.pump();
    },
  );

  testWidgets(
    'Check Again never replaces a mandatory screen with app content',
    (tester) async {
      final repository = FakeRepository()..value = policy(minimum: '1.1.0');
      final controller = AppGuardController(
        repository: repository,
        versionReader: FakeVersion(),
      );
      final observer = GuardNavigatorObserver(controller);
      await tester.pumpWidget(
        application(
          controller,
          observer,
          GlobalKey<NavigatorState>(),
          start: true,
        ),
      );
      await tester.pumpAndSettle();
      repository.pending = Completer<GuardPolicy>();
      await tester.tap(find.text('Check again'));
      await tester.pump();
      expect(find.text('Update required'), findsOneWidget);
      expect(find.text('Increment'), findsNothing);
      repository.pending!.completeError(Exception('offline'));
      await tester.pumpAndSettle();
      expect(find.text('Update required'), findsOneWidget);
      expect(
        find.text('Unable to check right now. Please try again.'),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox());
      observer.dispose();
      controller.dispose();
      await tester.pump();
    },
  );

  testWidgets('startup and resume check and lifecycle listener is removed', (
    tester,
  ) async {
    final repository = FakeRepository()..value = policy(latest: '1.0.0');
    final controller = AppGuardController(
      repository: repository,
      versionReader: FakeVersion(),
    );
    final observer = GuardNavigatorObserver(controller);
    await tester.pumpWidget(
      application(
        controller,
        observer,
        GlobalKey<NavigatorState>(),
        start: true,
      ),
    );
    await tester.pumpAndSettle();
    expect(repository.calls, 1);
    repository.value = policy(maintenance: true);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(repository.calls, 2);
    expect(find.text('Scheduled maintenance'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(repository.calls, 2);
    observer.dispose();
    controller.dispose();
    await tester.pump();
  });

  testWidgets(
    'missing strings use defaults and live strings replace a single surface',
    (tester) async {
      final repository = FakeRepository()
        ..value = policy(maintenance: true, title: ' ', message: '');
      final controller = AppGuardController(
        repository: repository,
        versionReader: FakeVersion(),
      );
      final observer = GuardNavigatorObserver(controller);
      await tester.pumpWidget(
        application(
          controller,
          observer,
          GlobalKey<NavigatorState>(),
          start: true,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Scheduled maintenance'), findsOneWidget);
      repository.publish(
        policy(
          maintenance: true,
          title: 'Almost finished',
          message: 'A little longer',
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Almost finished'), findsOneWidget);
      expect(find.text('Scheduled maintenance'), findsNothing);
      expect(find.text('A little longer'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      observer.dispose();
      controller.dispose();
      await tester.pump();
    },
  );

  testWidgets('small viewport with large text remains scrollable', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repository = FakeRepository()
      ..value = policy(
        maintenance: true,
        message: List.filled(15, 'Maintenance continues.').join(' '),
      );
    final controller = AppGuardController(
      repository: repository,
      versionReader: FakeVersion(),
    );
    final observer = GuardNavigatorObserver(controller);
    await tester.pumpWidget(
      application(
        controller,
        observer,
        GlobalKey<NavigatorState>(),
        start: true,
        scaler: const TextScaler.linear(2.5),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.text('Check again'));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    observer.dispose();
    controller.dispose();
    await tester.pump();
  });
}

class CounterPage extends StatefulWidget {
  const CounterPage({super.key});
  @override
  State<CounterPage> createState() => _CounterPageState();
}

class _CounterPageState extends State<CounterPage> {
  int count = 0;
  @override
  Widget build(BuildContext context) => Scaffold(
    body: Column(
      children: [
        Text('Count $count'),
        TextButton(
          onPressed: () => setState(() => count++),
          child: const Text('Increment'),
        ),
      ],
    ),
  );
}
