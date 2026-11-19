# Architecture

Snipstep is a native SwiftUI/AppKit macOS app, with a Swift package for core logic and a WidgetKit extension. Internal SnapLater identifiers remain stable for existing development installations.

## Capture to task

A configurable Carbon global hotkey starts a one-shot ScreenCaptureKit capture of the display under the pointer. The original attachment is validated and saved atomically with a recovery journal before OCR/enrichment. SwiftData stores task metadata. A sound confirms local save; generic notifications are optional. Apple Vision OCR is cached and reused for retries. The default text-only mode makes no inference request.

The pipeline saves usable local state before optional enrichment. Failures preserve the task and original. Generation checks prevent late responses after mode changes/deletion from overwriting newer state; user edits have field-level protection. Startup recovery does not silently resend interrupted AI requests.

## Inference choices

CloudAPIClient supports the built-in Generate Content format and configurable OpenAI-compatible Chat Completions endpoints. CloudConnection validates HTTPS URLs/model IDs, derives a destination-bound Keychain service and a payload/model-bound consent fingerprint. Changing a connection cancels active cloud work, keeps old queued tasks in OCR-only mode, and requires explicit enablement. A new host never inherits an existing key or cloud consent. Requests include either image+OCR or OCR only, depending on the saved setting. Ephemeral sessions disable cookies, caching, proxies and redirects; bodies/responses and deadlines are bounded. No provider fallback is automatic. A strict complete JSON task suggestion is required. The legacy Gemini mode raw value remains for storage compatibility; its visible label is LLM API.

Local AI sends up to 12,000 characters of cached text to a fixed loopback Ollama service. It lists/validates installed local models and rejects remote/cloud models. No local error triggers a cloud request. A user-selected, validated single GGUF file can be streamed to Ollama's content-addressed blob/import API. Its source remains unchanged; Ollama manages a runtime copy. No runtime or weights are bundled.

## Widgets

A team-prefixed shared app group contains bounded snapshots of up to twelve titles, summaries, completion timestamps and small JPEG previews, plus a command outbox protected by a file lock and atomic writes. The main app retains the canonical library and full originals. The extension has no network entitlement. Completion/deletion intents publish desired state; timestamp-aware acknowledgement preserves newer clicks. The main app commits commands on notification or next launch.

Only pending rows and a brief recent-completion acknowledgement appear in the checklist. A separate Progress widget displays totals. Add task links to `snaplater://new-task`; the app waits for startup, returns to To-Do, and focuses its existing manual composer. Screenshot links use a task UUID, never a file path or credential. TaskLink validates the supported routes.

Widget timelines and outer materials are ultimately controlled by macOS. An app can request reloads but cannot guarantee immediate refresh, erase every system rendering cache, or force a system-wide icon style for just itself.

## UI and local data

The normal app has To-Do, Completed, Analytics and Archive, embedded settings, and editable task details. Manual tasks need no screenshot or screen permission. Analytics is computed locally. There is no backend, sync, automatic screenshot monitoring, or telemetry SDK. App Sandbox/private directories are used; the library is not separately encrypted.

## Development and demo

Core tests use isolated synthetic libraries and network stubs. Live tests require explicit opt-in. The offscreen renderer uses the same SwiftUI views with `AppModel(testing: true)`, an in-memory store populated with a supplied image and scripted sample tasks.
