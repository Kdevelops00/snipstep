# Credits and ownership

**Creator and maintainer: [Kdevelops00](https://github.com/Kdevelops00).** Product direction, the Snipstep interface, application workflow, and integration are maintained in this repository. Snipstep was developed with AI coding and documentation assistance through OpenAI's Codex. Code review and tests remain necessary; AI assistance is not a quality certification.

| Component | Credit | Role and ownership boundary |
| --- | --- | --- |
| Swift, SwiftUI, AppKit, SwiftData, Vision, ScreenCaptureKit, WidgetKit, Security, ImageIO, Charts, SF Symbols | Apple | Native language/frameworks, persistence, OCR, capture, widgets, and system interface symbols; not authored by Snipstep |
| Gemini 3.1 Flash-Lite | Google | Optional hosted image-aware summary model; Snipstep integrates the API and does not train or own the model |
| Ollama | [Ollama contributors](https://github.com/ollama/ollama) | Separately installed local inference runtime, MIT licensed; not bundled or implemented by Snipstep |
| Qwen3 model files linked from settings | [Qwen team](https://huggingface.co/Qwen/Qwen3-1.7B-GGUF) | Optional user-selected weights; linked 1.7B GGUF repository identifies Apache-2.0; not bundled, trained, or owned by Snipstep |
| Other user-selected GGUF models | Their respective publishers | Their own licenses and compatibility requirements apply; selection does not imply endorsement |
| actions/checkout | GitHub and contributors | CI checkout action, MIT licensed; pinned in the workflow |
| Geometric S icon | Snipstep project / Kdevelops00 | Original code-generated capture-bracket artwork; source in scripts/generate-icon.swift |

[Ponytail](https://github.com/DietrichGebert/ponytail) informed the development approach. [Hyperframes](https://github.com/heygen-com/hyperframes) and [Remotion](https://github.com/remotion-dev/remotion) were consulted as motion-design references. Their implementations are not bundled, and this is not an affiliated or endorsed project.

The walkthrough shows [Ponytail](https://github.com/DietrichGebert/ponytail) as an example of a project to revisit. [Screenshot credits](docs/media/README.md).
