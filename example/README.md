# Offline App Guard example

Run `flutter pub get`, then `flutter run -d chrome` from this directory. No Firebase project is required. The sample uses in-memory policies, a fixed installed version and a simulated successful store launcher.

Try optional updates, mandatory updates, maintenance, API outages and critical-work deferral. Blocking demo policies clear after five seconds because the example repository publishes a new policy; the package never interprets maintenance end-time text as an automatic expiry.

For Android/iOS runners, run `flutter create --platforms=android,ios .`, then `flutter run`.
