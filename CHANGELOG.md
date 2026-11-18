## Unreleased

- Renamed the package and public import to `app_availability_guard`.

- Breaking: require app-supplied `FirebaseGuardConfiguration.keys` and every `GuardConfigKeys` field; remove built-in Firebase parameter names.
- Move Sahhal's mapping into its app configuration and document custom mappings.

## 0.1.0

- Extracted shared Firebase update and maintenance policies into a standalone Flutter package.
- Added retained blocking decisions, real-time evaluation, lifecycle refresh, independent API/maintenance signals, and critical-work deferral.
- Added reusable default/custom surfaces, per-version optional-prompt tracking, host navigation protection, and recoverable store launching.
- Added injectable adapters, tests, an offline example, and migration documentation.
