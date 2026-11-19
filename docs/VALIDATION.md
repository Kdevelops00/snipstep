# Preview validation

## Automated checks

The November 20, 2026 run on Apple silicon with Xcode 27.2 and macOS 27.2.1 passed 46 of 50 discovered core tests, including the opt-in synthetic 1,000-task store benchmark. Four live provider or Ollama tests were skipped. The suite covers persistence, capture recovery, deletion, OCR, attachment validation, API consent and request handling, widget data and task links, and GGUF import validation.

[GitHub Actions runs](https://github.com/Kdevelops00/snipstep/actions/workflows/ci.yml) show the status of each revision. CI runs the default core suite, builds and analyzes the unsigned Release app, and scans repository history and the built app for known credential patterns.

## Scope

| Area | Evidence |
| --- | --- |
| Cloud and local summaries | Network tests use synthetic content and stubbed responses. The current custom endpoint and Ollama flows still need live verification. |
| Desktop UI | Settings and Analytics passed in the isolated XCTest build. The manual-task test timed out during simulated typing on one run. On retry, the test copy exited before the Add task action. Core tests passed for manual task creation and persistence. |
| Capture and widgets | Tests cover screenshot ingestion, thumbnail and widget snapshot logic, widget commands, and task links. The physical gallery, desktop widget interaction and permission transitions still need end-to-end verification on the current build. |
| Preview images | The first panel combines a cropped public page and a native list render. The detail and desktop-widget images are crops of the creator’s screenshots. |
| Platform support | Both app and extension target macOS 15.2. Runtime on macOS 15.2 and Intel hardware still needs verification. |

See the [release checklist](RELEASE_CHECKLIST.md) for what a consumer download would require.
