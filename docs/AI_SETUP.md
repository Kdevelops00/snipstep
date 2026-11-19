# LLM API setup

The product describes the feature generically as optional LLM API support. These are the exact implemented formats, not a promise that every company or model is supported.

## Cloud connection

Open Settings → AI summaries → LLM API connection.

- **Built-in connection:** uses Google's Generate Content API at a fixed HTTPS host. The model ID can be edited. The existing development default is `gemini-3.1-flash-lite`.
- **Custom LLM API:** accepts a full HTTPS **OpenAI-compatible Chat Completions request endpoint**, model ID, and bearer API key. For example, a provider may document a path ending in `/v1/chat/completions`; copy the actual endpoint from its documentation. Responses, Messages, Assistants, and other proprietary API formats are not implemented.

A model must support image content when **Include screenshot image** is on. Turn it off to send extracted text only. Selecting an arbitrary model ID does not establish compatibility or availability. Strict JSON task output is required; malformed, truncated, or oversized responses preserve the local task instead of showing a fabricated summary.

Save the connection, add the destination's key, and explicitly enable summaries. New captures are then processed automatically; existing tasks require Summarize/Retry. The destination host, model, and selected payload are shown before enablement. Changing any connection setting disables cloud processing and invalidates its previous consent. Keys are stored in Keychain under a destination-bound identifier; a key is never automatically reused with another endpoint. Old queued captures stay local after a connection change; only explicit retry sends them to the new destination.

Cloud configuration rejects non-HTTPS URLs, URL credentials, query parameters and fragments. Authentication is in a header, redirects are disabled, sessions have no persistent HTTP cache/cookies, and request/response sizes and deadlines are bounded. Custom API calls are not automatically retried through another provider. Model/service availability, charges, and data retention/training policies belong to the chosen provider.

Google limits built-in API use to eligible adult developers and professional or business purposes within supported regions. Google also requires paid service when making an API client available to users in the EEA, Switzerland, or the UK. Unpaid processing can use submissions to improve products and may involve human review. Keep sensitive, personal, and confidential content out of unpaid requests. Check the [provider terms](https://ai.google.dev/gemini-api/terms) and [available regions](https://ai.google.dev/gemini-api/docs/available-regions). For a custom connection, check the chosen provider’s terms and data handling.

## Local summaries

Local mode currently connects to a separately installed [Ollama](https://github.com/ollama/ollama) service at fixed `http://127.0.0.1:11434`. It summarizes cached OCR text, not image pixels. It does not use your cloud key or silently fall back to cloud. Models marked remote/cloud are rejected.

Choose an installed model or load a compatible single GGUF file up to 4 GB. The source file is unchanged; Ollama manages its runtime copy, normally under `~/.ollama/models`. Settings link to the Qwen team's [Qwen3 1.7B GGUF](https://huggingface.co/Qwen/Qwen3-1.7B-GGUF) as a possible starting point; compatibility and resource needs depend on model architecture, quantization, runtime version and hardware. No model/runtime is bundled or trained by this project.

## Verification scope

Request construction, authentication placement, payload choice, response decoding, size/status handling, consent/key binding and connection-switch cancellation have synthetic tests. These are not live certification of every provider. Earlier development used a synthetic request against the built-in service; new custom provider/model combinations have not been live-tested with real credentials. See [local test and build results](VALIDATION.md).
