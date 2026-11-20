import SwiftUI
import SnipstepCore

struct SettingsView: View {
    let model: AppModel
    @State private var key = ""
    @State private var showSetup = false
    @State private var replacingKey = false
    @State private var error: String?
    @State private var page = "Basics"
    @State private var draftConnection = CloudConnection.google
    @State private var showLocalSetup = false
    @Namespace private var selection
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Settings").font(.system(size: 26, weight: .semibold))
                    Text("Capture and model preferences.").foregroundStyle(.secondary).font(.callout)
                }
                Spacer()
                BrandMark().frame(width: 40, height: 40)
            }
            HStack(spacing: 8) {
                ForEach(["Basics", "AI summaries"], id: \.self) { title in
                    Button { withAnimation(reduceMotion ? nil : .spring(duration: 0.35)) { page = title; key = ""; showSetup = false } } label: {
                        Text(title).font(.callout.weight(.medium)).padding(.horizontal, 16).padding(.vertical, 10)
                            .background { if page == title { RoundedRectangle(cornerRadius: 2).fill(.primary.opacity(0.7)).frame(height: 2).frame(maxHeight: .infinity, alignment: .bottom).matchedGeometryEffect(id: "settingsTab", in: selection) } }
                    }.buttonStyle(SoftPress()).accessibilityAddTraits(page == title ? [.isSelected] : [])
                }
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if page == "Basics" {
                        card("Capture", icon: "command") {
                            HStack {
                                Text("Capture full screen").font(.callout)
                                Spacer()
                                ShortcutRecorder(label: model.shortcutLabel) { model.changeShortcut(keyCode: $0, modifiers: $1, label: $2) }
                                    .frame(width: 225, height: 32)
                            }
                            Text("Click Change and press two modifiers plus a letter or number. Escape cancels.").font(.caption).foregroundStyle(.secondary)
                            if !model.captureShortcutAvailable { Label("Shortcut unavailable. Choose another combination.", systemImage: "exclamationmark.circle").font(.callout).foregroundStyle(.orange) }
                            Button("Open screen recording permissions", systemImage: "lock.shield") {
                                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") { NSWorkspace.shared.open(url) }
                            }.buttonStyle(.bordered)
                            Text("Allow Snipstep in macOS once. Keep the app running; its window can be closed.").font(.caption).foregroundStyle(.secondary)
                        }
                        card("Notifications", icon: "waveform") {
                            Text("A confirmation sound plays only after your screenshot is saved.").font(.callout).foregroundStyle(.secondary)
                            Toggle("Show a saved notification", isOn: Binding(get: { model.notificationsEnabled }, set: { model.setNotifications($0) })).toggleStyle(.switch)
                            Text("No screenshot or task text appears in notifications.").font(.caption).foregroundStyle(.secondary)
                        }
                        card("Desktop widgets", icon: "rectangle.on.rectangle") {
                            Text("Right-click your desktop → Edit Widgets → Snipstep. To-Do shows unfinished ideas. Progress shows how far you’ve come.").font(.callout).foregroundStyle(.secondary)
                        }
                    } else if page == "AI summaries" {
                        card("Processing", icon: "sparkles") {
                            ForEach(ProcessingMode.allCases, id: \.self) { option in
                                Button {
                                    showLocalSetup = option == .localAI
                                    if option == .gemini && !(model.keyConfigured && model.hasCloudConsent) { replacingKey = false; showSetup = true }
                                    else if option == .localAI && model.localModelName.isEmpty { model.refreshLocalModels() }
                                    else { model.setMode(option) }
                                } label: {
                                    HStack {
                                        Image(systemName: model.mode == option ? "checkmark.circle.fill" : "circle")
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(option.label).font(.callout.weight(.medium))
                                            Text(option == .ocrOnly ? "Read text, no AI." : option == .localAI ? "Summarize text on this Mac, using Ollama." : "Summarize using your configured LLM API.")
                                                .font(.caption).foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                    }.padding(12).background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                                }.buttonStyle(.plain).accessibilityIdentifier(option == .gemini ? "aiSummaries" : option.rawValue)
                            }
                        }
                        if showLocalSetup {
                        card("Local models", icon: "desktopcomputer") {
                            Button("Load model file…", systemImage: "folder") { model.loadLocalModelFile() }
                                .buttonStyle(.borderedProminent).disabled(model.importingLocalModel)
                            if model.importingLocalModel { ProgressView("Importing into Ollama…").controlSize(.small) }
                            Text("Download a GGUF model, then choose its file from any folder. Qwen3 0.6B / 1.7B Q4 text models are good starting sizes; compatibility depends on your Ollama version.")
                                .font(.caption).foregroundStyle(.secondary)
                            Link("Qwen3 1.7B GGUF · model files & license", destination: URL(string: "https://huggingface.co/Qwen/Qwen3-1.7B-GGUF")!)
                            if let source = model.localModelSource { Text("Source: " + source).font(.caption).foregroundStyle(.secondary).textSelection(.enabled) }
                            Text("Runtime storage is managed by Ollama (default ~/.ollama/models). Import creates a runtime copy; the file you choose stays unchanged.")
                                .font(.caption).foregroundStyle(.secondary)
                            HStack {
                                Text(model.localModelName.isEmpty ? "No model selected" : model.localModelName).font(.callout)
                                Spacer()
                                Button("Refresh") { model.refreshLocalModels() }.disabled(model.loadingLocalModels)
                            }
                            if model.loadingLocalModels { ProgressView().controlSize(.small) }
                            ForEach(model.localModels) { local in
                                Button { model.useLocalModel(local.name) } label: {
                                    HStack {
                                        Text(local.name)
                                        Spacer()
                                        Text(String(format: "%.1f GB", Double(local.size) / 1_000_000_000)).foregroundStyle(.secondary)
                                        Image(systemName: model.mode == .localAI && model.localModelName == local.name ? "checkmark.circle.fill" : "arrow.down.circle")
                                    }.padding(.vertical, 8)
                                }.buttonStyle(.plain)
                            }
                            if let status = model.localStatus { Text(status).font(.caption).foregroundStyle(.secondary) }
                            Text("For an 8 GB Mac, start with your smallest installed model. This mode uses cached OCR text, not image understanding. Model licenses and resource requirements are set by each model’s author.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        } else {
                        card("LLM API connection", icon: "network") {
                            HStack {
                                ForEach(CloudConnection.Format.allCases, id: \.self) { format in
                                    Button(format.label) {
                                        draftConnection = format == .gemini ? .google : .init(format: .chatCompletions, endpoint: "", model: "")
                                    }.buttonStyle(.bordered)
                                }
                            }
                            TextField("HTTPS request endpoint", text: $draftConnection.endpoint).textFieldStyle(.roundedBorder).accessibilityIdentifier("cloudEndpoint")
                            TextField("Model ID", text: $draftConnection.model).textFieldStyle(.roundedBorder).accessibilityIdentifier("cloudModel")
                            Toggle("Include screenshot image", isOn: $draftConnection.sendsImage)
                            Text(draftConnection.sendsImage ? "Choose a model that accepts images. Your screenshot and extracted text will be sent." : "Send extracted text only. Image pixels will not be sent.").font(.caption).foregroundStyle(.secondary)
                            if draftConnection.format == .chatCompletions {
                                Text("Use an OpenAI-compatible Chat Completions request endpoint from your provider, including its full path, and a supported model ID. Other API formats are not supported.").font(.caption).foregroundStyle(.secondary)
                            }
                            Button("Save connection") {
                                do { try model.saveCloudConnection(draftConnection); key = ""; showSetup = false }
                                catch { self.error = (error as? SnapError)?.localizedDescription ?? SnapError.invalidConnection.localizedDescription }
                            }.disabled(draftConnection == model.cloudConnection)
                            Text("Changing this connection turns cloud processing off. Keys stay bound to their destination; enable summaries again when you’re ready.").font(.caption).foregroundStyle(.secondary)
                        }
                        card("API key", icon: "key") {
                            HStack {
                                Label(model.keyConfigured ? "Key stored securely" : "Add your API key", systemImage: model.keyConfigured ? "checkmark.shield" : "key")
                                Spacer()
                                Button(model.keyConfigured ? "Change key" : "Add key") { replacingKey = model.keyConfigured; showSetup = true }.buttonStyle(.bordered).disabled(draftConnection != model.cloudConnection)
                            }
                            if model.keyConfigured {
                                Button("Remove key", role: .destructive) {
                                    do { try model.removeKey() } catch { self.error = SnapError.keyUnavailable.localizedDescription }
                                }.font(.caption)
                            }
                            if showSetup { Divider(); setup }
                        }
                        card("Before you turn AI on", icon: "hand.raised") {
                            Text("Destination: \(model.cloudConnection.host) · Model: \(model.cloudConnection.model). \(model.cloudConnection.sendsImage ? "Screenshot and extracted text are sent." : "Only extracted text is sent.") Provider charges, retention and training policies apply. Avoid sensitive content. You can switch cloud processing off anytime.")
                                .font(.callout).foregroundStyle(.secondary)
                            if model.cloudConnection.format == .gemini { Link("Provider terms & data use", destination: URL(string: "https://ai.google.dev/gemini-api/terms")!) }
                        }
                    }
                    }
                    Link("By @Kdevelops00", destination: URL(string: "https://github.com/Kdevelops00")!)
                        .font(.caption).foregroundStyle(.secondary).padding(.top, 12)
                }.padding(.bottom, 20)
            }.scrollIndicators(.hidden)
        }.padding(.horizontal, 24).padding(.top, 8)
        .onAppear {
            draftConnection = model.cloudConnection
            showLocalSetup = model.mode == .localAI
            page = ["Basics", "AI summaries"].contains(model.settingsPage) ? model.settingsPage : "Basics"
            if page == "AI summaries" && !model.isTesting { model.refreshLocalModels() }
        }
        .onChange(of: page) { _, value in model.settingsPage = value; if value == "AI summaries" && !model.isTesting { model.refreshLocalModels() } }
        .onChange(of: draftConnection) { _, _ in key = ""; showSetup = false }
        .onDisappear { key = "" }
        .alert("Couldn’t update AI settings", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK") { error = nil }
        } message: { Text(error ?? "") }
    }
    private func card<Content: View>(_ title: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title.uppercased()).font(.system(size: 10, weight: .semibold)).tracking(1.4).foregroundStyle(.secondary)
            content()
            Divider().padding(.top, 8)
        }.padding(18).frame(maxWidth: .infinity, alignment: .leading)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private var setup: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(replacingKey ? "Change API key" : "Turn on AI summaries").font(.title2.bold())
            if !model.keyConfigured || replacingKey {
                Text("Paste the key for \(model.cloudConnection.host). It will be stored securely in your Mac’s Keychain.")
                    .foregroundStyle(.secondary)
                SecureField("API key", text: $key)
                    .textFieldStyle(.roundedBorder).accessibilityIdentifier("apiKey")
                if model.cloudConnection.format == .gemini { Link("Get an API key", destination: URL(string: "https://aistudio.google.com/apikey")!) }
            }
            if !replacingKey {
                Text("Enable summaries for \(model.cloudConnection.host), model \(model.cloudConnection.model). \(model.cloudConnection.sendsImage ? "New screenshots and extracted text" : "Only extracted text from new screenshots") will be sent automatically. The provider’s charges and data policies apply. Existing tasks are sent only when you request a summary.")
                    .font(.callout).fixedSize(horizontal: false, vertical: true)
                if model.cloudConnection.format == .gemini {
                    Text("Unpaid processing may use content to improve models or involve human review. Avoid sensitive screenshots.").font(.caption)
                    Link("Provider terms & data use", destination: URL(string: "https://ai.google.dev/gemini-api/terms")!).font(.callout)
                }
                Text("Enable below to agree to these transfers. You can switch AI off anytime.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                Button("Cancel", role: .cancel) { key = ""; showSetup = false }.keyboardShortcut(.cancelAction)
                Spacer()
                Button(replacingKey ? "Save key" : "Enable AI summaries") {
                    do {
                        if !model.keyConfigured || replacingKey { try model.saveKey(key) }
                        key = ""
                        if !replacingKey { model.setMode(.gemini) }
                        showSetup = false
                    } catch {
                        key = ""; showSetup = false
                        self.error = SnapError.keyUnavailable.localizedDescription
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled((!model.keyConfigured || replacingKey) && key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .keyboardShortcut(.defaultAction)
            }
        }.padding(.vertical, 12).frame(maxWidth: .infinity)
    }
}
