# Privacy

Snipstep is a local-first developer preview, not independently audited software.

## Default local use

Manual tasks and offline text extraction need no account, API key or internet. Originals, cached OCR text, titles, notes and task states live in the app's private macOS container. Files are protected by App Sandbox and private directory permissions, but are not separately encrypted. FileVault is the Mac owner's setting. Privileged local access and system backups remain outside the app's protection boundary.

The app captures only when invoked. It does not continuously record the display, inspect browser history, monitor the clipboard, intercept other screenshots, or index your library into Spotlight. Capture uses macOS Screen Recording permission. Imported files use explicit selection. The app does not require Accessibility or Full Disk Access.

## Optional LLM API processing

Cloud processing is off by default. You configure a supported API endpoint/model, store the destination's key in non-synchronizing Keychain, review what will be sent, and explicitly enable summaries. Future captures are then processed automatically. Existing tasks are sent only when you choose Summarize/Retry. Capture Locally Only bypasses cloud processing.

When image sending is enabled, the provider receives screenshot pixels with nonessential metadata stripped, cached OCR text and task-generation instructions. Otherwise it receives cached OCR text and instructions only. The saved original remains unchanged. Visual content is not automatically redacted. Authentication uses a request header, never a URL query.

The built-in integration sends to Google's HTTPS API. Custom integrations send directly to the configured HTTPS Chat Completions endpoint; there is no product backend or proxy. The app cannot determine whether that provider, endpoint or model is trustworthy. Provider fees, retention, logging, training and human-review policies vary; review them before enabling. Unpaid built-in-provider services may use content to improve models and involve human review. [Provider terms](https://ai.google.dev/gemini-api/terms).

Saving a changed connection turns cloud off and clears its consent. Credentials are destination-bound, and old queued captures remain local after a connection change. No automatic switch to a different provider occurs on failure. A disabled/cancelled request cannot retract content already received by the former provider. Removing a key disables cloud use for that connection; independently stored keys for earlier connections remain in Keychain until removed when that connection is selected.

Requests use ephemeral sessions, no persistent HTTP caches/cookies or redirects, bounded payloads/responses, and deadlines. Provider errors are converted to content-free messages. No response bodies or keys are logged. No automatic cloud retry is performed by the configurable API client.

## Optional local model service

Local mode sends cached OCR text, up to 12,000 characters, to a fixed loopback Ollama service. It sends no image or cloud key, rejects models marked remote/cloud, and never falls back to cloud. The runtime and user-selected model are separate software, not bundled by this project; their licenses, logs, configuration and trust remain the user's responsibility. A process controlling that service can read submitted text.

Load model file reads an explicitly selected GGUF weight file into the local runtime's managed storage. It does not move or modify the source or send weights to a cloud API. The selected source path is stored locally for display. Model weights are excluded from Git.

## Desktop widgets and notifications

The signed app and its WidgetKit extension share an entitlement-protected group containing bounded snapshots: up to twelve titles, short notes/summaries, completion timestamps, small thumbnails and an outbox of task actions. Keys and full cached OCR are not shared. The extension has no network entitlement. Completion/deletion commands are committed by the app while running or on its next launch. Native-widget Add task opens the app's composer.

Snapshots are replaced and reloads requested after changes. macOS controls rendering caches and scheduling; immediate forensic erasure of old widget pixels cannot be guaranteed. Widget content is marked privacy-sensitive. Optional save notifications contain generic status only, not screenshot pixels, titles, notes or OCR. Analytics is computed locally and is not telemetry.

## Deletion, diagnostics and demo

Deleting a task removes local metadata, the original and cached OCR; interrupted deletions are retried. It does not erase SSD history, OS snapshots/backups, or data previously received by a provider. Remove a configured key separately through settings. The app has no automatic telemetry or crash-upload service; OS crash diagnostics can still contain process memory.

The walkthrough uses a cropped public webpage and cropped Snipstep views supplied by the creator. The scripted render uses isolated sample data and offline OCR. [Demo notes](docs/media/README.md). Use fictional content for shareable diagnostics.

There is no iPhone app, sync, automatic screenshot monitoring, or bundled inference runtime/model. Such features will require separate disclosure before shipping. The privacy manifest is conservative about optional cloud transfers; it does not indicate that cloud transfers occur in text-only mode. Distribution and App Store disclosures still require review before a consumer release.
