# app_availability_guard

A private, local Flutter package combining App Update and Maintenance. Firebase remains initialized by the host. No dependency on Sahhal, GoRouter, GetIt, application translations, or application API clients exists inside this package.

## Install

```yaml
dependencies:
  app_availability_guard:
    path: packages/app_availability_guard
```

Initialize Firebase in application bootstrap, then define your parameter names in an application configuration file and create one controller for the application lifetime:

```dart
const appGuardKeys = GuardConfigKeys(
  iosLatest: 'my_app_ios_latest_version',
  iosMinimum: 'my_app_ios_minimum_version',
  iosStore: 'my_app_ios_store_url',
  iosNotes: 'my_app_ios_release_notes',
  androidLatest: 'my_app_android_latest_version',
  androidMinimum: 'my_app_android_minimum_version',
  androidStore: 'my_app_android_store_url',
  androidNotes: 'my_app_android_release_notes',
  maintenanceEnabled: 'my_app_maintenance_enabled',
  maintenanceTitle: 'my_app_maintenance_title',
  maintenanceMessage: 'my_app_maintenance_message',
  maintenanceEndTime: 'my_app_maintenance_end_time',
);

final controller = AppGuardController(
  repository: FirebaseGuardRepository(
    FirebaseRemoteConfig.instance,
    configuration: FirebaseGuardConfiguration(
      platform: currentGuardPlatform(),
      keys: appGuardKeys,
      additionalDefaults: {'unrelated_feature_enabled': false},
    ),
  ),
  apiUnavailable: apiUnavailableNotifier, // optional ValueListenable<bool>
  criticalOperationActive: criticalWorkNotifier, // optional
  checkApiAvailable: checkApiAvailability, // optional Future<bool> callback
);
final guardObserver = GuardNavigatorObserver(controller);
```

Register `guardObserver` on the application's Navigator or GoRouter and wrap the builder child:

```dart
MaterialApp(
  navigatorObservers: [guardObserver],
  builder: (context, child) => AppGuardGate(
    controller: controller,
    child: child!,
  ),
  home: const HomeScreen(),
)
```

For GoRouter, pass `observers: [guardObserver]` to GoRouter and use the same gate in `MaterialApp.router.builder`. The observer protects the host route's back gesture/predictive-back behavior, while the gate owns its presentation Navigator. For apps with additional nested navigators, register an observer attached to the same controller on each navigator whose routes must be protected.

At shutdown detach/dispose the observer, then await `controller.close()` (or call `dispose()` from a widget's disposal method). The controller owns its repository. Do not share one repository between controllers. Host-owned notifiers are not disposed by the package.

## App-owned Firebase keys

`FirebaseGuardConfiguration.keys` and all twelve `GuardConfigKeys` fields are required. The package contains no default Firebase parameter names. Each application owns its mapping; use different mappings for different projects or environments without editing the package. Configure matching parameters in Firebase Remote Config. Passing names here sets local defaults; it does not create or publish Console parameters.

| Mapping fields | Type | Local fallback |
| --- | --- | --- |
| `iosLatest`, `androidLatest` | String | `0.0.0` |
| `iosMinimum`, `androidMinimum` | String | `0.0.0` |
| `iosStore`, `androidStore` | String | Empty |
| `iosNotes`, `androidNotes` | String | Empty |
| `maintenanceEnabled` | Boolean | `false` |
| `maintenanceTitle`, `maintenanceMessage`, `maintenanceEndTime` | String | Empty |

Use distinct, nonblank names. Blank maintenance values use UI defaults. End time stays a raw string in the package and its default surface. Apps can parse and format ISO 8601 values in their `maintenanceBuilder`; Sahhal uses its own `AppDateFormat` to display the device-local date/time in the current app language, preserving non-date estimates as text. Enter timestamps such as `2026-11-20T23:59:59Z` without surrounding quotes. Formatting never adds a countdown or automatically expires the policy. Publish `false` for the parameter mapped to `maintenanceEnabled` to end planned maintenance.

The adapter owns **all SDK defaults and fetch settings** by default. Include the host's other defaults in `additionalDefaults`; guard defaults under the supplied names take precedence on conflicts. If the application already has a central Remote Config owner, use `configureSdk: false` and configure defaults/settings there; `appGuardKeys.defaults` supplies the safe fallback map under your names. Do not run competing initialization services against the same SDK instance.

## Decisions

1. Firebase maintenance **or** API unavailability shows maintenance immediately.
2. Otherwise a mandatory update is presented, unless critical work is active.
3. Otherwise an optional update is presented when eligible and not suppressed.
4. Otherwise the application is accessible.

Maintenance does not cancel uploads. The gate retains the application's mounted subtree. Critical-operation signals defer update UI, not maintenance. When maintenance ends, the next applicable update UI is revealed.

Numeric dotted versions are compared component-by-component, with missing trailing components treated as zero. `1.10 > 1.9` and `1.0 == 1.0.0`. Prerelease/build suffixes are not supported. `PackageInfo.version` is used; build-only releases cannot be distinguished. Invalid versions or reversed bounds report an error and retain the previous valid update decision. On first startup with no valid decision, invalid update policy alone does not block access. Maintenance is evaluated independently.

## Refresh semantics

- `refresh()`: requests SDK fetch/activation, reads installed metadata, and invokes the optional API checker. Concurrent calls coalesce.
- `reevaluate()`: reads available policy/metadata without requesting a backend fetch or API check.
- `allowOptionalPromptAgain()`: clears optional prompt suppression; does not fetch.
- Gate defaults: startup and resume refresh enabled; independently configurable.
- Real-time Firebase publications activate and reevaluate both policies.

There is no application cooldown. Defaults remain a ten-second fetch timeout and one-hour minimum fetch interval. A refresh is **not a guarantee of network freshness**. A cached mandatory policy can remain active offline or after a server-side rollback until newer values arrive. `PolicyOrigin.refreshed` means a successful fetch/activate call, not proof of a fresh network response. `lastSuccessfulFetch` exposes SDK timing. PackageInfo may cache metadata within the process; a newly installed binary is normally evaluated on a new-process launch.

Refresh progress is independent from policy. Existing blocking UI stays visible until refresh work completes. Failed refreshes preserve previous restrictions. Errors are exposed through `lastError`/`onError`; Firebase fallback diagnostics use `FirebaseGuardConfiguration.onError`.

## Store handling

The default validator accepts App Store and Google Play listing URL forms. Other distribution channels can supply `isStoreUriAllowed`. The host is responsible for publishing the correct application's URL and ensuring the required release is available to the targeted users. Version enforcement does not validate store rollout availability.

`openStore()` coalesces launch taps and returns `StoreOpenResult`. Failed/invalid launches leave recovery controls visible. A successful launch dismisses only optional UI; it does not prove installation and does not release mandatory enforcement.

## Custom UI and translations

Use `GuardStrings` for localized default copy or provide `maintenanceBuilder`, `mandatoryBuilder`, and `optionalBuilder`. Each builder receives the controller and a context inside the package Navigator. Use `refresh`, `openStore`, and `dismissOptional`; do not manually pop the host Navigator. Default screens use the ambient ThemeData and scroll for limited viewports.

Sahhal demonstrates custom builders using its existing screens and localization files. Remote strings are displayed as provided; language targeting belongs to the host/Firebase configuration.

## Layout

- `domain`: policy entities, repository contracts, numeric version comparison and evaluation.
- `data`: Firebase adapter/configuration and platform metadata/store adapters.
- `application`: controller, independent policy/progress state, concurrency and presentation eligibility.
- `presentation`: gate, host Navigator observer, default UI and copy customization.

## Example and validation

The offline example demonstrates optional, mandatory, maintenance, API outage and critical-work scenarios. It simulates policy changes and store success; it does not contact Firebase or install anything.

```sh
cd example
flutter create --platforms=android,ios,web .
flutter run
```

From the package directory:

```sh
flutter pub get
flutter analyze
flutter test
```

The package is marked `publish_to: none`. No public publishing, Firebase policy publishing, or store deployment is performed by this migration.
