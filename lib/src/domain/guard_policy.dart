import 'version_comparator.dart';

enum GuardPlatform { ios, android }

enum UpdateDecision { none, optional, mandatory }

enum GuardView { none, optionalUpdate, mandatoryUpdate, maintenance }

enum PolicyOrigin { available, refreshed }

class UpdatePolicy {
  const UpdatePolicy({
    required this.latestVersion,
    required this.minimumVersion,
    required this.storeUrl,
    this.releaseNotes = '',
  });
  final String latestVersion;
  final String minimumVersion;
  final String storeUrl;
  final String releaseNotes;
}

class MaintenancePolicy {
  const MaintenancePolicy({
    this.enabled = false,
    this.title,
    this.message,
    this.endTime,
  });
  final bool enabled;
  final String? title;
  final String? message;

  /// Informational only; never automatically clears maintenance.
  final String? endTime;
}

class GuardPolicy {
  const GuardPolicy({
    required this.update,
    this.maintenance = const MaintenancePolicy(),
    this.origin = PolicyOrigin.available,
    this.lastSuccessfulFetch,
  });
  final UpdatePolicy update;
  final MaintenancePolicy maintenance;
  final PolicyOrigin origin;
  final DateTime? lastSuccessfulFetch;
}

/// Invalid policies throw; the controller retains its last valid decision.
class EvaluateUpdatePolicy {
  const EvaluateUpdatePolicy();

  UpdateDecision call(String installed, UpdatePolicy policy) {
    for (final version in [
      installed,
      policy.latestVersion,
      policy.minimumVersion,
    ]) {
      if (!AppVersionComparator.isValid(version)) {
        throw FormatException('Invalid numeric version', version);
      }
    }
    if (AppVersionComparator.compare(
          policy.minimumVersion,
          policy.latestVersion,
        ) >
        0) {
      throw const FormatException('Minimum version exceeds latest version');
    }
    if (AppVersionComparator.isOlderThan(installed, policy.minimumVersion)) {
      return UpdateDecision.mandatory;
    }
    return AppVersionComparator.isOlderThan(installed, policy.latestVersion)
        ? UpdateDecision.optional
        : UpdateDecision.none;
  }
}
