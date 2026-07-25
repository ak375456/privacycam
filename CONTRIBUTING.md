# Contributing to PrivacyCam

Thank you for helping improve PrivacyCam.

## Before opening a change

- Use a public issue for ordinary bugs and feature proposals.
- Do not open a public issue for a security or privacy vulnerability; follow
  `SECURITY.md`.
- Do not include real private records, faces without consent, credentials,
  signing material, store secrets, or copyrighted sample media.
- Use synthetic fixtures wherever possible.

## Development

1. Install the stable Flutter SDK version compatible with `pubspec.yaml`.
2. Run `flutter pub get`.
3. Make a focused change.
4. Run `dart format .`, `flutter analyze`, and `flutter test`.
5. Add or update tests for behavior changes.

Native video export behavior should also be checked on physical iOS and Android
devices when a change touches codecs, metadata, tracking, or platform channels.

## Licensing

By submitting a contribution, you agree that it may be distributed under the
Apache License 2.0 used by this repository. You must have the right to submit
the code, media, model, or documentation in your contribution.
