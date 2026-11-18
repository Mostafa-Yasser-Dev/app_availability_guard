import 'dart:async';

import 'package:flutter/material.dart';

import '../application/app_guard_controller.dart';
import '../domain/guard_policy.dart';
import 'guard_strings.dart';

typedef GuardWidgetBuilder =
    Widget Function(BuildContext context, AppGuardController controller);

/// Wrap MaterialApp.builder / MaterialApp.router.builder's child. The host owns
/// the controller and must close it when the application scope is disposed.
class AppGuardGate extends StatefulWidget {
  const AppGuardGate({
    required this.controller,
    required this.child,
    this.strings = const GuardStrings(),
    this.maintenanceBuilder,
    this.mandatoryBuilder,
    this.optionalBuilder,
    this.checkOnStart = true,
    this.checkOnResume = true,
    super.key,
  });
  final AppGuardController controller;
  final Widget child;
  final GuardStrings strings;
  final GuardWidgetBuilder? maintenanceBuilder,
      mandatoryBuilder,
      optionalBuilder;
  final bool checkOnStart, checkOnResume;
  @override
  State<AppGuardGate> createState() => _AppGuardGateState();
}

class _AppGuardGateState extends State<AppGuardGate>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _start();
  }

  void _start() {
    if (widget.checkOnStart) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(widget.controller.refresh());
      });
    }
  }

  @override
  void didUpdateWidget(covariant AppGuardGate oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) _start();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && widget.checkOnResume)
      unawaited(widget.controller.refresh());
  }

  @override
  Future<bool> didPopRoute() async {
    final view = widget.controller.view;
    if (view == GuardView.optionalUpdate) widget.controller.dismissOptional();
    return view != GuardView.none;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) {
      final view = widget.controller.view;
      final blocked =
          view == GuardView.maintenance || view == GuardView.mandatoryUpdate;
      return Stack(
        fit: StackFit.expand,
        children: [
          ExcludeFocus(
            excluding: view != GuardView.none,
            child: Offstage(
              offstage: blocked,
              child: TickerMode(enabled: !blocked, child: widget.child),
            ),
          ),
          if (view != GuardView.none)
            HeroControllerScope.none(
              child: Navigator(
                key: ObjectKey(widget.controller),
                onGenerateRoute: (_) => PageRouteBuilder<void>(
                  opaque: false,
                  transitionDuration: Duration.zero,
                  pageBuilder: (context, animation, secondaryAnimation) =>
                      ListenableBuilder(
                        listenable: widget.controller,
                        builder: (context, _) => _surface(context),
                      ),
                ),
              ),
            ),
        ],
      );
    },
  );

  Widget _surface(BuildContext context) {
    final controller = widget.controller;
    final view = controller.view;
    if (view == GuardView.none) return const SizedBox.shrink();
    final optional = view == GuardView.optionalUpdate;
    final builder = switch (view) {
      GuardView.maintenance => widget.maintenanceBuilder,
      GuardView.mandatoryUpdate => widget.mandatoryBuilder,
      GuardView.optionalUpdate => widget.optionalBuilder,
      GuardView.none => null,
    };
    final child =
        builder?.call(context, controller) ??
        _DefaultSurface(controller: controller, strings: widget.strings);
    if (optional) {
      final version = controller.updatePolicy!.latestVersion;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) controller.markOptionalPresented(version);
      });
    }
    return PopScope(
      canPop: false,
      child: optional
          ? ColoredBox(
              color: Colors.black54,
              child: SafeArea(child: Center(child: child)),
            )
          : child,
    );
  }
}

class _DefaultSurface extends StatelessWidget {
  const _DefaultSurface({required this.controller, required this.strings});
  final AppGuardController controller;
  final GuardStrings strings;

  @override
  Widget build(BuildContext context) {
    final maintenance = controller.view == GuardView.maintenance;
    final optional = controller.view == GuardView.optionalUpdate;
    final policy = controller.maintenancePolicy;
    String? nonblank(String? value) =>
        value == null || value.trim().isEmpty ? null : value.trim();
    final title = maintenance
        ? (policy.enabled ? nonblank(policy.title) : null) ??
              strings.maintenanceTitle
        : optional
        ? strings.optionalTitle
        : strings.mandatoryTitle;
    final body = SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            maintenance ? Icons.build_outlined : Icons.system_update,
            size: 48,
          ),
          const SizedBox(height: 16),
          Text(
            title,
            style: Theme.of(context).textTheme.headlineSmall,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          Text(
            maintenance
                ? (policy.enabled ? nonblank(policy.message) : null) ??
                      strings.maintenanceMessage
                : strings.updateMessage,
            textAlign: TextAlign.center,
          ),
          if (maintenance && policy.enabled && nonblank(policy.endTime) != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(policy.endTime!),
            ),
          if (!maintenance) ...[
            const SizedBox(height: 12),
            Text(
              '${controller.installedVersion} → ${controller.updatePolicy?.latestVersion}',
            ),
            if (controller.updatePolicy?.releaseNotes.isNotEmpty ?? false)
              Text(controller.updatePolicy!.releaseNotes),
          ],
          if (controller.lastError != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(strings.refreshError),
            ),
          if (controller.storeResult == StoreOpenResult.failed ||
              controller.storeResult == StoreOpenResult.invalidUrl)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(strings.storeError),
            ),
          const SizedBox(height: 20),
          if (!maintenance)
            FilledButton(
              onPressed: controller.isLaunchingStore
                  ? null
                  : () => unawaited(controller.openStore()),
              child: Text(strings.updateNow),
            ),
          if (optional)
            TextButton(
              onPressed: controller.dismissOptional,
              child: Text(strings.later),
            )
          else
            OutlinedButton(
              onPressed: controller.isRefreshing
                  ? null
                  : () => unawaited(controller.refresh()),
              child: controller.isRefreshing
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(strings.retry),
            ),
        ],
      ),
    );
    return optional
        ? Dialog(child: body)
        : Scaffold(
            body: SafeArea(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: body,
                ),
              ),
            ),
          );
  }
}
