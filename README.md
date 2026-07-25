# PrivacyCam

PrivacyCam is a privacy-first Flutter app for reviewing and redacting photos,
short videos, and PDF documents before sharing. Face, person, text, barcode,
QR-code, and possible number-plate detection run on-device. Originals are never
overwritten.

## Privacy design

- No account, developer-operated content upload, advertising, or cloud
  persistence.
- OCR strings and barcode values are not persisted or logged.
- Photo exports are re-encoded and checked for remaining EXIF metadata.
- Video exports remove and verify source metadata through native platform code.
- PDF exports are rebuilt from flattened page images and checked for a
  selectable text layer.
- Temporary working files are removed when the user discards or starts over,
  subject to the limitations documented in the privacy policy.
- Automatic detection is probabilistic. Every result requires user review.

Google ML Kit may send limited SDK diagnostics as described in
[`docs/privacy.html`](docs/privacy.html). In-app purchases are processed by the
platform app store.

## Supported platforms

The maintained application targets iOS 16.0+ and Android API 23+. Flutter
desktop and web scaffolding is present but is not currently a supported release
target.

## Run

```sh
flutter pub get
flutter run
```

For iOS device builds, open `ios/Runner.xcworkspace`. The checked-in project
uses the developer's production bundle and App Group identifiers. Contributors
must replace these consistently in the Runner target, Share Extension target,
and both entitlement files with identifiers available to their own Apple
Developer team.

Android release signing is intentionally not included. Local signing uses
`android/key.properties` and a keystore file; both are ignored and must never be
committed.

## Verify

```sh
flutter analyze
flutter test
flutter build apk --debug
flutter build ios --simulator --no-codesign
```

Google ML Kit's iOS binary dependencies may emit an arm64 simulator
compatibility warning on some Apple Silicon toolchains. Physical iOS devices
remain the authoritative ML integration target.

## Open source and third-party software

PrivacyCam source code is licensed under the Apache License 2.0. See
[`LICENSE`](LICENSE) and [`NOTICE`](NOTICE).

Bundled machine-learning models retain their upstream licenses. Their sources,
hashes, and required notices are documented in
[`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md). The PrivacyCam name and logo
are not granted for use by the software license; see
[`TRADEMARKS.md`](TRADEMARKS.md).

The onboarding examples are synthetic demonstration media created for this
project. They contain fictional people and data and must not be treated as real
records.

## Contributing and security

See [`CONTRIBUTING.md`](CONTRIBUTING.md) before submitting a change. Please
report security or privacy vulnerabilities privately using
[`SECURITY.md`](SECURITY.md), not through a public issue.
