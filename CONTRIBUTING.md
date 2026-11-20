# Contributing to Snipstep

Thanks for helping make a small, useful to-do app. The project is maintained by [@Kdevelops00](https://github.com/Kdevelops00) and is an early developer preview.

## Start small

Use an issue for a reproducible bug or a concrete proposal. Check existing issues first. A useful report includes macOS/Xcode versions, expected behavior, actual behavior, and steps using fictional content. Never include personal screenshots, OCR, credentials, or provider response bodies.

For a pull request, explain the problem, resulting behavior, checks performed, and remaining limits. Discuss significant dependencies or architecture changes before implementing them. Keep the app simple: manual tasks first, screenshot context and optional summaries alongside them.

## Local checks

```sh
swift test --parallel --jobs 2
python3 scripts/check-secrets.py --history
xcodebuild -project Snipstep.xcodeproj -scheme Snipstep \
  -configuration Debug -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath build CODE_SIGNING_ALLOWED=NO build analyze
```

Set up your own signing team for widget and permission testing. Live provider tests are opt-in and may incur charges; they must stay disabled in public CI. Document checks that need a desktop, hardware, signing, a local model, or a paid service. See [validation](docs/VALIDATION.md).

## Invariants

Save originals before enrichment. Preserve task identity, edits, and recoverability. Reuse cached OCR. Keep offline fallback usable. Require informed cloud consent, never silently fall back from local inference to cloud, and never log credentials or content. Do not reset a library to hide a schema problem.

Dependencies, assets, models, and datasets keep their upstream ownership and license obligations. Credit AI assistance and upstream work honestly. Contributions are submitted under the repository's MIT license; do not submit code you cannot license. No CLA is currently required.

## Community

Be respectful and specific. Critique code and behavior, not people. Harassment, doxxing, credential sharing, and discriminatory abuse are not welcome. Maintainers may remove harmful content. Report security issues privately via [SECURITY.md](SECURITY.md).
