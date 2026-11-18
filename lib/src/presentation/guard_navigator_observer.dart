import 'package:flutter/widgets.dart';
import '../application/app_guard_controller.dart';
import '../domain/guard_policy.dart';

/// Register on the host Navigator/GoRouter to also block route gestures and
/// predictive back while a guard surface is active. Can attach before or after
/// the controller is constructed; ownership remains with the host.
class GuardNavigatorObserver extends NavigatorObserver {
  GuardNavigatorObserver([AppGuardController? controller]) {
    attach(controller);
  }
  AppGuardController? _controller;
  final _entries = <ModalRoute<dynamic>, _GuardPopEntry>{};

  void attach(AppGuardController? controller) {
    _controller?.removeListener(_changed);
    _controller = controller;
    _controller?.addListener(_changed);
    _changed();
  }

  bool get _canPop =>
      _controller == null || _controller!.view == GuardView.none;
  void _changed() {
    for (final entry in _entries.values) {
      entry.canPopNotifier.value = _canPop;
    }
  }

  void _register(Route<dynamic> route) {
    if (route is! ModalRoute<dynamic> || _entries.containsKey(route)) return;
    final entry = _GuardPopEntry(_canPop, () {
      if (_controller?.view == GuardView.optionalUpdate)
        _controller?.dismissOptional();
    });
    _entries[route] = entry;
    route.registerPopEntry(entry);
  }

  void _remove(Route<dynamic>? route) {
    final entry = _entries.remove(route);
    if (entry != null && route is ModalRoute<dynamic>) {
      route.unregisterPopEntry(entry);
      entry.canPopNotifier.dispose();
    }
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _register(route);
  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _remove(route);
  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _remove(route);
  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    _remove(oldRoute);
    if (newRoute != null) _register(newRoute);
  }

  void dispose() {
    attach(null);
    for (final route in _entries.keys.toList()) {
      _remove(route);
    }
  }
}

class _GuardPopEntry extends PopEntry<Object?> {
  _GuardPopEntry(bool canPop, this.onBlocked)
    : canPopNotifier = ValueNotifier(canPop);
  final VoidCallback onBlocked;
  @override
  final ValueNotifier<bool> canPopNotifier;
  @override
  void onPopInvokedWithResult(bool didPop, Object? result) {
    if (!didPop) onBlocked();
  }
}
