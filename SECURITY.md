# Security and threat model

Snipstep is a development MVP with tested controls, not an audited or completely secure product. See [PRIVACY.md](PRIVACY.md) and [release checklist](docs/RELEASE_CHECKLIST.md).

| Asset / threat | Current control | Remaining limit |
| --- | --- | --- |
| Sensitive screenshots and OCR | Local default, explicit cloud consent, local-only command, sandbox, private directories | No app-level encryption or automatic secret redaction; privileged local access and backups remain possible |
| LLM API key | Non-synchronizing Keychain, secure input, header authentication, validated destination-bound endpoint | Keychain access can fail; a compromised unlocked process can access in-memory secrets |
| Cloud transfer | HTTPS, no redirects/cookies/disk cache, 30-second deadline per attempt, bounded bodies, no automatic provider fallback or retries | Cancellation cannot recall transmitted bytes; provider retention/billing is outside app control |
| Malicious OCR/model text | No tools or execution; bounded title/summary schema; field edit protection | Models can still produce inaccurate or inappropriate suggestions; prompt wording is not a security boundary |
| Addresses/instructions in screenshot text | Rendered as text; no link extraction, browser-opening action, or tool execution | A user may still manually copy untrusted text into another application |
| File/path attacks | UUID internal paths, allowlisted extensions, size/pixel limits, symlink rejection in attachment operations | Sandbox and directory permissions remain the primary boundary; same-user/root races are not a complete forensic-defense model |
| Crash/write failure | Atomic synchronized originals, journal, explicit database saves, recovery, deletion tombstones | Unpersisted capture data cannot survive a crash/disk failure; no automatic repair of a corrupt database |
| Late asynchronous results | Stable ID, tombstone checks, consent generations, protected edited fields | Changes not saved from the detail editor are drafts; leaving that editor can discard them |
| Dependency compromise | No third-party runtime dependencies; pinned CI checkout; local source/artifact scans | Apple SDK/compiler and the configured API service remain trust dependencies; pattern scanning is not exhaustive |
| Optional local AI | Loopback-only user-managed Ollama, remote-model rejection, bounded text requests | Model/runtime trust and licensing remain user responsibilities; sync is not shipped |

## Permissions

The app requests App Sandbox, outbound network access for opt-in LLM APIs and the local loopback model service, and read-only access to user-selected files. The default shortcut captures the display under the pointer using macOS’s explicit screen permission. An optional image-receiving App Intent and selected-image import are also available. A signed, team-prefixed app group is shared with the WidgetKit extension for bounded display snapshots and completion commands. The widget has no network entitlement. Neither target requests Accessibility, microphone, camera, contacts, full disk access, iCloud, or keychain sharing. Test automation permissions belong to the developer test runner, not the product.

Debug builds use local ad-hoc signing. Xcode may disable hardened runtime for ad-hoc builds; verify hardened runtime with the actual Developer ID signing identity before distribution. Release builds exclude the development credential importer and synthetic UI test controls.

## Reporting a vulnerability

Use [GitHub's private vulnerability report form](https://github.com/Kdevelops00/snipstep/security/advisories/new). Include the affected version and steps with fictional content. Keep screenshots, OCR, credentials and sensitive diagnostics out of public issues.

## If a credential is exposed

Revoke or rotate it with the provider immediately. Removing a later file or commit is not sufficient. Inspect all Git history, CI logs, build artifacts, crash bundles, screenshots, and shared messages. Never print the credential while investigating. The local scan script reports only paths and detection categories.
