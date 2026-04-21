//
//  SettingsView.swift
//  CodeSergeantUI
//
//  Settings panel with AI configuration, screen monitoring, and privacy options
//

import SwiftUI

enum SettingsTab: Hashable {
    case ai
    case xp
    case monitoring
    case personality
    case about
}

struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @State private var selectedTab: SettingsTab = .ai
    
    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            SettingsSidebar(selectedTab: $selectedTab)

            Group {
                switch selectedTab {
                case .ai:
                    AISettingsTab()
                        .environmentObject(appState)
                        .transition(.opacity)
                case .xp:
                    XPSettingsTab()
                        .transition(.opacity)
                case .monitoring:
                    ScreenMonitoringTab()
                        .environmentObject(appState)
                        .transition(.opacity)
                case .personality:
                    PersonalityTab()
                        .transition(.opacity)
                case .about:
                    AboutTab()
                        .transition(.opacity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .animation(.easeInOut(duration: 0.18), value: selectedTab)
        }
        .padding(AppTheme.chromePadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct SettingsSidebar: View {
    @Binding var selectedTab: SettingsTab

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SettingsSidebarButton(title: "AI", icon: "cpu", isSelected: selectedTab == .ai) {
                selectedTab = .ai
            }
            SettingsSidebarButton(title: "XP", icon: "star.fill", isSelected: selectedTab == .xp) {
                selectedTab = .xp
            }
            SettingsSidebarButton(title: "Monitor", icon: "eye", isSelected: selectedTab == .monitoring) {
                selectedTab = .monitoring
            }
            SettingsSidebarButton(title: "Personality", icon: "person.fill", isSelected: selectedTab == .personality) {
                selectedTab = .personality
            }
            SettingsSidebarButton(title: "About", icon: "info.circle", isSelected: selectedTab == .about) {
                selectedTab = .about
            }

            Spacer()
        }
        .frame(width: 152)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        // Prevent any implicit animation from causing button position shifts on tab change
        .animation(.none, value: selectedTab)
    }
}

private struct SettingsSidebarButton: View {
    let title: String
    let icon: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(isSelected ? AppTheme.signalTint : Color.secondary)
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .tracking(0.3)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .foregroundStyle(isSelected ? Color.white : Color.primary)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: 36, maxHeight: 36, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 10)
                    .fill(isSelected ? AppTheme.canvasAccent.opacity(0.9) : Color.white.opacity(0.04))
                    .overlay {
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(
                                isSelected ? AppTheme.signalTint.opacity(0.50) : AppTheme.glassStroke,
                                lineWidth: 1
                            )
                    }
            }
            .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, minHeight: 36, maxHeight: 36)
    }
}

private struct SettingsCard<Content: View>: View {
    let title: String
    let subtitle: String?
    let stretchesVertically: Bool
    let compact: Bool
    let content: Content

    init(title: String, subtitle: String? = nil, stretchesVertically: Bool = false, compact: Bool = false, @ViewBuilder content: () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.stretchesVertically = stretchesVertically
        self.compact = compact
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 9 : 12) {
            VStack(alignment: .leading, spacing: compact ? 3 : 4) {
                Text(title.uppercased())
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .tracking(1.4)
                    .foregroundStyle(AppTheme.signalTint.opacity(0.75))

                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: compact ? 11 : 12))
                        .foregroundStyle(.secondary)
                }
            }

            content
        }
        .padding(compact ? 10 : 14)
        .frame(maxWidth: .infinity, maxHeight: stretchesVertically ? .infinity : nil, alignment: .topLeading)
        .glassCard(cornerRadius: compact ? 12 : 16)
    }
}

private struct SettingsKeyEditor: View {
    let title: String
    let placeholder: String
    let helper: String
    @Binding var text: String
    @Binding var isSecure: Bool
    let buttonTitle: String
    let isSaving: Bool
    let message: String?
    let action: () -> Void

    var body: some View {
        SettingsCard(title: title, subtitle: helper) {
            HStack(spacing: 8) {
                Group {
                    if isSecure {
                        SecureField(placeholder, text: $text)
                    } else {
                        TextField(placeholder, text: $text)
                    }
                }
                .textFieldStyle(.roundedBorder)

                Button {
                    isSecure.toggle()
                } label: {
                    Image(systemName: isSecure ? "eye" : "eye.slash")
                }
                .buttonStyle(.borderless)
            }

            HStack(spacing: 8) {
                Button(buttonTitle, action: action)
                    .disabled(text.isEmpty || isSaving)

                if let message, !message.isEmpty {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(message.contains("Error") ? .red : .green)
                        .lineLimit(1)
                }
            }
        }
    }
}

private struct SettingsStatusRow: View {
    let title: String
    let icon: String
    let value: String
    let tint: Color?

    var body: some View {
        HStack {
            Label(title, systemImage: icon)
                .font(.subheadline)
            Spacer()
            if let tint {
                StatusBadge(status: value, color: tint)
            } else {
                Text(value)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private extension Binding where Value == Bool {
    var inverted: Binding<Bool> {
        Binding<Bool>(
            get: { !wrappedValue },
            set: { wrappedValue = !$0 }
        )
    }
}

// MARK: - AI Settings Tab

private enum AISettingsPane: String, CaseIterable, Identifiable {
    case overview = "Overview"
    case keys = "Keys"
    case voice = "Voice"

    var id: String { rawValue }
}

struct AISettingsTab: View {
    @EnvironmentObject var appState: AppState
    @State private var openAIKey: String = ""
    @State private var showKey: Bool = false
    @State private var elevenLabsKey: String = ""
    @State private var showElevenLabsKey: Bool = false
    @State private var isSaving: Bool = false
    @State private var saveMessage: String?
    @State private var isSavingElevenLabs: Bool = false
    @State private var saveElevenLabsMessage: String?
    @State private var ttsVoiceId: String = ""
    @State private var elevenLabsVoiceRows: [(id: String, name: String)] = []
    @State private var isLoadingVoices: Bool = false
    @State private var isSavingVoice: Bool = false
    @State private var saveVoiceMessage: String?
    @State private var selectedPane: AISettingsPane = .overview
    
    private let bridgeURL = "http://127.0.0.1:5050"
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Picker("AI Section", selection: $selectedPane) {
                ForEach(AISettingsPane.allCases) { pane in
                    Text(pane.rawValue).tag(pane)
                }
            }
            .pickerStyle(.segmented)

            Group {
                switch selectedPane {
                case .overview:
                    HStack(alignment: .top, spacing: 16) {
                        SettingsCard(title: "Status", subtitle: "Current backend and voice state.") {
                            VStack(spacing: 10) {
                                SettingsStatusRow(
                                    title: "OpenAI",
                                    icon: "cpu",
                                    value: appState.openAIAvailable ? "Active" : "Not configured",
                                    tint: appState.openAIAvailable ? .green : .orange
                                )
                                SettingsStatusRow(
                                    title: "Ollama",
                                    icon: "server.rack",
                                    value: appState.ollamaAvailable ? "Running" : "Offline",
                                    tint: appState.ollamaAvailable ? .green : .gray
                                )
                                SettingsStatusRow(
                                    title: "Primary",
                                    icon: "checkmark.circle.fill",
                                    value: appState.primaryBackend.capitalized,
                                    tint: nil
                                )
                                SettingsStatusRow(
                                    title: "Voice",
                                    icon: "speaker.wave.2",
                                    value: appState.ttsProvider == "elevenlabs" ? "ElevenLabs" : "System",
                                    tint: nil
                                )
                                SettingsStatusRow(
                                    title: "ElevenLabs key",
                                    icon: "key.fill",
                                    value: appState.elevenLabsKeyConfigured ? "Saved" : "Missing",
                                    tint: appState.elevenLabsKeyConfigured ? .green : .orange
                                )
                            }

                            if !appState.elevenLabsSdkAvailable {
                                Text("Install `elevenlabs` in the Python env to enable ElevenLabs speech.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        VStack(spacing: 16) {
                            SettingsCard(title: "Voice", subtitle: "Current speech output target.") {
                                if !elevenLabsVoiceRows.isEmpty {
                                    Picker("Voice", selection: $ttsVoiceId) {
                                        Text("Select a voice…").tag("")
                                        ForEach(elevenLabsVoiceRows, id: \.id) { row in
                                            Text(row.name).tag(row.id)
                                        }
                                    }
                                    .labelsHidden()
                                }

                                TextField("Voice ID", text: $ttsVoiceId)
                                    .textFieldStyle(.roundedBorder)

                                HStack(spacing: 8) {
                                    Button("Refresh") {
                                        loadElevenLabsVoices(refresh: true)
                                    }
                                    .disabled(isLoadingVoices || !appState.elevenLabsKeyConfigured)

                                    Button("Save Voice") {
                                        saveTTSVoiceId()
                                    }
                                    .disabled(ttsVoiceId.isEmpty || isSavingVoice)

                                    if isLoadingVoices {
                                        ProgressView()
                                            .scaleEffect(0.8)
                                    }
                                }

                                if let saveVoiceMessage, !saveVoiceMessage.isEmpty {
                                    Text(saveVoiceMessage)
                                        .font(.caption)
                                        .foregroundStyle(saveVoiceMessage.contains("Error") ? .red : .green)
                                }
                            }

                            SettingsCard(title: "Links") {
                                VStack(alignment: .leading, spacing: 8) {
                                    Link("OpenAI API Keys", destination: URL(string: "https://platform.openai.com/api-keys")!)
                                    Link("Ollama Download", destination: URL(string: "https://ollama.com/download")!)
                                    Link("ElevenLabs API Keys", destination: URL(string: "https://elevenlabs.io/app/settings/api-keys")!)
                                }
                                .font(.subheadline)
                            }
                        }
                    }

                case .keys:
                    HStack(alignment: .top, spacing: 16) {
                        SettingsKeyEditor(
                            title: "OpenAI API Key",
                            placeholder: "sk-...",
                            helper: "Stored securely in `.env` and never logged.",
                            text: $openAIKey,
                            isSecure: $showKey.inverted,
                            buttonTitle: "Save OpenAI Key",
                            isSaving: isSaving,
                            message: saveMessage,
                            action: saveAPIKey
                        )

                        SettingsKeyEditor(
                            title: "ElevenLabs API Key",
                            placeholder: "Paste your ElevenLabs API key",
                            helper: "Stored securely in `.env` and used for session speech.",
                            text: $elevenLabsKey,
                            isSecure: $showElevenLabsKey.inverted,
                            buttonTitle: "Save ElevenLabs Key",
                            isSaving: isSavingElevenLabs,
                            message: saveElevenLabsMessage,
                            action: saveElevenLabsKey
                        )
                    }

                case .voice:
                    HStack(alignment: .top, spacing: 16) {
                        SettingsCard(title: "ElevenLabs Voice", subtitle: "Pick a saved voice or paste a voice ID.") {
                            if !elevenLabsVoiceRows.isEmpty {
                                Picker("Voice", selection: $ttsVoiceId) {
                                    Text("Select a voice…").tag("")
                                    ForEach(elevenLabsVoiceRows, id: \.id) { row in
                                        Text(row.name).tag(row.id)
                                    }
                                }
                            }

                            TextField("Voice ID", text: $ttsVoiceId)
                                .textFieldStyle(.roundedBorder)

                            Text("Save your API key first, then pick a voice or paste a Voice ID.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        SettingsCard(title: "Actions") {
                            VStack(alignment: .leading, spacing: 10) {
                                Button("Refresh Voice List") {
                                    loadElevenLabsVoices(refresh: true)
                                }
                                .disabled(isLoadingVoices || !appState.elevenLabsKeyConfigured)

                                Button("Save Voice") {
                                    saveTTSVoiceId()
                                }
                                .disabled(ttsVoiceId.isEmpty || isSavingVoice)

                                if isLoadingVoices {
                                    ProgressView()
                                        .scaleEffect(0.8)
                                }

                                if let saveVoiceMessage, !saveVoiceMessage.isEmpty {
                                    Text(saveVoiceMessage)
                                        .font(.caption)
                                        .foregroundStyle(saveVoiceMessage.contains("Error") ? .red : .green)
                                }
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            loadTTSVoiceFromConfig()
            loadElevenLabsVoices(refresh: false)
        }
    }
    
    private func loadTTSVoiceFromConfig() {
        guard let url = URL(string: "\(bridgeURL)/api/config") else { return }
        URLSession.shared.dataTask(with: url) { data, _, _ in
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tts = json["tts"] as? [String: Any],
                  let vid = tts["voice_id"] as? String else { return }
            DispatchQueue.main.async {
                ttsVoiceId = vid
            }
        }.resume()
    }
    
    private func loadElevenLabsVoices(refresh: Bool) {
        isLoadingVoices = true
        var components = URLComponents(string: "\(bridgeURL)/api/tts/voices")!
        if refresh {
            components.queryItems = [URLQueryItem(name: "refresh", value: "true")]
        }
        guard let url = components.url else { return }
        URLSession.shared.dataTask(with: url) { data, _, _ in
            defer { DispatchQueue.main.async { isLoadingVoices = false } }
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let raw = json["voices"] as? [[String: Any]] else { return }
            let rows: [(String, String)] = raw.compactMap { v in
                guard let id = v["id"] as? String,
                      let name = v["name"] as? String else { return nil }
                if let provider = v["provider"] as? String, provider != "elevenlabs" { return nil }
                return (id, name)
            }
            DispatchQueue.main.async {
                elevenLabsVoiceRows = rows
            }
        }.resume()
    }
    
    private func saveTTSVoiceId() {
        isSavingVoice = true
        saveVoiceMessage = nil
        guard let url = URL(string: "\(bridgeURL)/api/config") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: [
            "tts": [
                "voice_id": ttsVoiceId,
                "provider": "elevenlabs"
            ]
        ])
        URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                isSavingVoice = false
                if error != nil {
                    saveVoiceMessage = "Error: \(error!.localizedDescription)"
                    return
                }
                guard let http = response as? HTTPURLResponse else {
                    saveVoiceMessage = "Error: Invalid response"
                    return
                }
                if (200...299).contains(http.statusCode) {
                    saveVoiceMessage = "✓ Saved successfully"
                    appState.refreshTTSStatus()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        saveVoiceMessage = nil
                    }
                } else {
                    let msg = (data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] })?["error"] as? String
                    saveVoiceMessage = "Error: \(msg ?? "HTTP \(http.statusCode)")"
                }
            }
        }.resume()
    }
    
    private func saveAPIKey() {
        isSaving = true
        saveMessage = nil
        
        appState.setOpenAIKey(openAIKey) { ok, err in
            isSaving = false
            if ok {
                saveMessage = "✓ Saved successfully"
                openAIKey = ""
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    saveMessage = nil
                }
            } else {
                saveMessage = "Error: \(err ?? "Unknown error")"
            }
        }
    }
    
    private func saveElevenLabsKey() {
        isSavingElevenLabs = true
        saveElevenLabsMessage = nil
        
        appState.setElevenLabsKey(elevenLabsKey) { ok, err in
            isSavingElevenLabs = false
            if ok {
                saveElevenLabsMessage = "✓ Saved successfully"
                elevenLabsKey = ""
                loadElevenLabsVoices(refresh: true)
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    saveElevenLabsMessage = nil
                }
            } else {
                saveElevenLabsMessage = "Error: \(err ?? "Unknown error")"
            }
        }
    }
}

// MARK: - XP Settings Tab

struct XPSettingsTab: View {
    @State private var xpPerMinute: Double = 1.0
    @State private var earlyEndPenalty: Double = 50.0
    @State private var isSaving: Bool = false
    @State private var saveMessage: String?
    @State private var showingResetConfirmation = false
    
    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 16) {
                SettingsCard(title: "XP Rules", subtitle: "Tune how sessions reward and penalize progress.", compact: true) {
                    VStack(alignment: .leading, spacing: 9) {
                        LabeledContent("XP per Minute") {
                            Text("\(Int(xpPerMinute)) XP")
                                .font(.system(.body, design: .rounded))
                                .foregroundStyle(.secondary)
                        }
                        Slider(value: $xpPerMinute, in: 1...10, step: 1)
                        Text("XP earned for each minute of focus time.")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Divider()

                        LabeledContent("Early End Penalty") {
                            Text("\(Int(earlyEndPenalty))%")
                                .font(.system(.body, design: .rounded))
                                .foregroundStyle(.secondary)
                        }
                        Slider(value: $earlyEndPenalty, in: 0...100, step: 10)
                        Text("Percentage of session XP lost when ending early.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                SettingsCard(title: "Actions", compact: true) {
                    HStack(spacing: 12) {
                        Button("Save Settings") {
                            saveXPSettings()
                        }
                        .disabled(isSaving)

                        Button("Reset All XP", role: .destructive) {
                            showingResetConfirmation = true
                        }

                        if let saveMessage, !saveMessage.isEmpty {
                            Text(saveMessage)
                                .font(.caption)
                                .foregroundStyle(saveMessage.contains("Error") ? .red : .green)
                        }
                    }
                }
            }

            SettingsCard(title: "Ranks", subtitle: "Current defaults from config.", compact: true) {
                VStack(alignment: .leading, spacing: 4) {
                    RankRow(name: "Recruit", threshold: 0)
                    RankRow(name: "Private", threshold: 100)
                    RankRow(name: "Corporal", threshold: 300)
                    RankRow(name: "Sergeant", threshold: 600)
                    RankRow(name: "Staff Sergeant", threshold: 1000)
                    RankRow(name: "Captain", threshold: 1500)
                }

                Text("Edit `config.json` to customize names, thresholds, and icons.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .confirmationDialog(
            "Reset all XP?",
            isPresented: $showingResetConfirmation,
            titleVisibility: .visible
        ) {
            Button("Reset", role: .destructive) {
                resetAllXP()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will reset your XP to zero and return you to Recruit.")
        }
        .onAppear {
            loadCurrentSettings()
        }
    }
    
    private func loadCurrentSettings() {
        // Load from backend config
        guard let url = URL(string: "http://127.0.0.1:5050/api/config") else { return }
        
        URLSession.shared.dataTask(with: url) { data, response, error in
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let xpConfig = json["xp"] as? [String: Any] else { return }
            
            DispatchQueue.main.async {
                xpPerMinute = Double(xpConfig["xp_per_minute"] as? Int ?? 1)
                earlyEndPenalty = Double(xpConfig["early_end_penalty_percent"] as? Int ?? 50)
            }
        }.resume()
    }
    
    private func saveXPSettings() {
        isSaving = true
        saveMessage = nil
        
        guard let url = URL(string: "http://127.0.0.1:5050/api/config") else { return }
        
        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = [
            "xp": [
                "xp_per_minute": Int(xpPerMinute),
                "early_end_penalty_percent": Int(earlyEndPenalty)
            ]
        ]
        
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                isSaving = false
                
                if error == nil {
                    saveMessage = "✓ Saved successfully"
                } else {
                    saveMessage = "Error saving settings"
                }
                
                // Clear message after delay
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    saveMessage = nil
                }
            }
        }.resume()
    }
    
    private func resetAllXP() {
        guard let url = URL(string: "http://127.0.0.1:5050/api/xp/reset") else { return }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        
        URLSession.shared.dataTask(with: request).resume()
    }
}

struct RankRow: View {
    let name: String
    let threshold: Int
    
    var body: some View {
        HStack {
            Text(name)
                .font(.system(size: 14, design: .monospaced))

            Spacer()

            Text("\(threshold) XP")
                .font(.system(size: 14, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(.white.opacity(0.05))
        )
    }
}

// MARK: - Screen Monitoring Tab

struct ScreenMonitoringTab: View {
    @EnvironmentObject var appState: AppState
    @State private var blockedApps: String = ""
    @State private var isScreenMonitoringEnabled = false
    
    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            SettingsCard(title: "Screen Analysis", subtitle: "Analyze progress without storing captures to disk.") {
                Toggle("Enable Screen Monitoring", isOn: $isScreenMonitoringEnabled)

                SettingsStatusRow(
                    title: "Vision Backend",
                    icon: "eye.fill",
                    value: appState.visionBackendStatus.replacingOccurrences(of: "_", with: " ").capitalized,
                    tint: statusColor
                )

                Toggle("Use Local Vision (LLaVA)", isOn: $appState.useLocalVision)
                    .disabled(!appState.ollamaAvailable)

                if appState.useLocalVision && !appState.ollamaAvailable {
                    Label("Ollama is not running. The app will fall back to OpenAI.", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            SettingsCard(title: "Privacy Blocklist", subtitle: "These apps are never captured.") {
                TextField("One app per line", text: $blockedApps, axis: .vertical)
                    .lineLimit(8...8)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onChange(of: isScreenMonitoringEnabled) {
            appState.toggleScreenMonitoring(isScreenMonitoringEnabled)
        }
        .onAppear {
            isScreenMonitoringEnabled = appState.screenMonitoringEnabled
            // Load default blocked apps
            blockedApps = """
            1Password
            LastPass
            Keychain Access
            PayPal
            Chase
            Bank of America
            """
        }
    }
    
    private var statusColor: Color {
        switch appState.visionBackendStatus {
        case "ollama":
            return .green
        case "openai", "openai_fallback":
            return .blue
        case "ollama_fallback":
            return .orange
        case "disabled":
            return .red
        default:
            return .gray
        }
    }
}

// MARK: - Personality Tab

private struct PersonalityOption: Identifiable {
    let id: String
    let displayName: String
    let description: String
}

struct PersonalityTab: View {
    @State private var selectedProfile: String = "sergeant"
    @State private var customDescription: String = ""
    @State private var customWakeWord: String = ""
    @State private var inputDeviceName: String = ""
    @State private var inputDevices: [(name: String, isDefault: Bool)] = []
    @State private var defaultInputName: String?
    @State private var resolvedInputName: String?
    @State private var options: [PersonalityOption] = []
    @State private var isLoading = false
    @State private var isLoadingInputs = false
    @State private var isSaving = false
    @State private var isSavingInput = false
    @State private var saveMessage: String?
    @State private var saveInputMessage: String?
    
    private let bridgeURL = "http://127.0.0.1:5050"
    
    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 16) {
                SettingsCard(title: "Guide", subtitle: "Choose how Code Sergeant talks and judges focus.") {
                    if options.isEmpty && !isLoading {
                        Text("Connect to the bridge to load personalities.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Picker("Personality", selection: $selectedProfile) {
                        ForEach(options) { opt in
                            Text(opt.displayName).tag(opt.id)
                        }
                    }
                    .disabled(options.isEmpty)

                    if let current = options.first(where: { $0.id == selectedProfile }) {
                        Text(current.description)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(4)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    if selectedProfile == "custom" {
                        TextField("Describe the tone you want", text: $customDescription, axis: .vertical)
                            .lineLimit(3...3)
                            .textFieldStyle(.roundedBorder)

                        TextField("Wake word name", text: $customWakeWord)
                            .textFieldStyle(.roundedBorder)
                    }
                }

                SettingsCard(title: "Actions", subtitle: "This saves to `config.json` and updates future sessions.") {
                    HStack(spacing: 12) {
                        Button("Save Personality") {
                            savePersonality()
                        }
                        .disabled(isSaving || options.isEmpty)

                        if isLoading {
                            ProgressView()
                                .scaleEffect(0.8)
                        }

                        if let saveMessage, !saveMessage.isEmpty {
                            Text(saveMessage)
                                .font(.caption)
                                .foregroundStyle(saveMessage.contains("Error") ? .red : .green)
                        }
                    }
                }
            }

            SettingsCard(title: "Microphone", subtitle: "Wake word, voice commands, and note-taking use this input.") {
                Picker("Microphone", selection: $inputDeviceName) {
                    Text("System Default").tag("")
                    ForEach(inputDevices, id: \.name) { device in
                        Text(deviceLabel(for: device)).tag(device.name)
                    }
                }
                .disabled(isLoadingInputs)

                if let resolvedInputName, !resolvedInputName.isEmpty {
                    Text(inputDeviceName.isEmpty ? "Current default: \(resolvedInputName)" : "Selected mic: \(resolvedInputName)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                if let defaultInputName, !defaultInputName.isEmpty, !inputDeviceName.isEmpty {
                    Text("System default microphone: \(defaultInputName)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                HStack(spacing: 8) {
                    Button("Refresh", action: loadInputDevices)
                        .disabled(isLoadingInputs)

                    Button("Save Mic", action: saveInputDevice)
                        .disabled(isSavingInput || isLoadingInputs)

                    if isLoadingInputs {
                        ProgressView()
                            .scaleEffect(0.8)
                    }
                }

                if let saveInputMessage, !saveInputMessage.isEmpty {
                    Text(saveInputMessage)
                        .font(.caption)
                        .foregroundStyle(saveInputMessage.contains("Error") ? .red : .green)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            loadPersonality()
            loadInputDevices()
        }
    }
    
    private func loadPersonality() {
        isLoading = true
        saveMessage = nil
        guard let url = URL(string: "\(bridgeURL)/api/personality") else {
            isLoading = false
            return
        }
        URLSession.shared.dataTask(with: url) { data, _, _ in
            defer { DispatchQueue.main.async { isLoading = false } }
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
            let name = json["name"] as? String ?? "sergeant"
            let desc = json["description"] as? String ?? ""
            let wake = json["wake_word_name"] as? String ?? "sergeant"
            let raw = json["available_profiles"] as? [[String: Any]] ?? []
            let parsed: [PersonalityOption] = raw.compactMap { p in
                guard let id = p["name"] as? String else { return nil }
                return PersonalityOption(
                    id: id,
                    displayName: p["display_name"] as? String ?? id,
                    description: p["description"] as? String ?? ""
                )
            }
            DispatchQueue.main.async {
                selectedProfile = name
                customDescription = desc
                customWakeWord = wake
                options = parsed
            }
        }.resume()
    }
    
    private func savePersonality() {
        isSaving = true
        saveMessage = nil
        guard let url = URL(string: "\(bridgeURL)/api/personality") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var body: [String: Any] = [
            "profile": selectedProfile,
            "silent": true
        ]
        if selectedProfile == "custom" {
            body["custom_description"] = customDescription
            body["custom_wake_word"] = customWakeWord
        }
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                isSaving = false
                if error != nil {
                    saveMessage = "Error: \(error!.localizedDescription)"
                    return
                }
                guard let http = response as? HTTPURLResponse else {
                    saveMessage = "Error: Invalid response"
                    return
                }
                if (200...299).contains(http.statusCode) {
                    saveMessage = "✓ Saved successfully"
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        saveMessage = nil
                    }
                } else {
                    let msg = (data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] })?["error"] as? String
                    saveMessage = "Error: \(msg ?? "HTTP \(http.statusCode)")"
                }
            }
        }.resume()
    }

    private func loadInputDevices() {
        isLoadingInputs = true
        saveInputMessage = nil

        guard let url = URL(string: "\(bridgeURL)/api/audio/input-devices") else {
            isLoadingInputs = false
            return
        }

        URLSession.shared.dataTask(with: url) { data, _, error in
            defer {
                DispatchQueue.main.async {
                    isLoadingInputs = false
                }
            }

            guard error == nil,
                  let data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return
            }

            let rawDevices = json["devices"] as? [[String: Any]] ?? []
            let devices: [(name: String, isDefault: Bool)] = rawDevices.compactMap { device in
                guard let name = device["name"] as? String else { return nil }
                return (name, device["is_default"] as? Bool ?? false)
            }

            DispatchQueue.main.async {
                inputDevices = devices
                inputDeviceName = json["selected_device_name"] as? String ?? ""
                defaultInputName = json["default_device_name"] as? String
                resolvedInputName = json["resolved_device_name"] as? String
            }
        }.resume()
    }

    private func saveInputDevice() {
        isSavingInput = true
        saveInputMessage = nil

        guard let url = URL(string: "\(bridgeURL)/api/config") else {
            isSavingInput = false
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "voice_activation": [
                "input_device_name": inputDeviceName.isEmpty ? NSNull() : inputDeviceName as Any
            ]
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                isSavingInput = false

                if error != nil {
                    saveInputMessage = "Error: \(error!.localizedDescription)"
                    return
                }

                guard let http = response as? HTTPURLResponse else {
                    saveInputMessage = "Error: Invalid response"
                    return
                }

                if (200...299).contains(http.statusCode) {
                    saveInputMessage = "✓ Saved successfully"
                    loadInputDevices()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        saveInputMessage = nil
                    }
                } else {
                    let msg = (data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] })?["error"] as? String
                    saveInputMessage = "Error: \(msg ?? "HTTP \(http.statusCode)")"
                }
            }
        }.resume()
    }

    private func deviceLabel(for device: (name: String, isDefault: Bool)) -> String {
        device.isDefault ? "\(device.name) (Default)" : device.name
    }
}

// MARK: - About Tab

struct AboutTab: View {
    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "2.0.0"
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)

            VStack(spacing: 20) {
                // Full brand logo — takes up a commanding amount of space
                Image("CodeSergeantLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 260)
                    .shadow(color: AppTheme.signalTint.opacity(0.18), radius: 28, y: 10)
                    .accessibilityLabel("Code Sergeant logo")

                Text("Version \(appVersion)")
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .tracking(1.2)

                Text("Your AI-powered productivity drill sergeant.\nStay focused. Get things done.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(5)
                    .padding(.horizontal, 24)
            }

            Spacer(minLength: 0)

            // Footer — fixed at bottom, never floats
            VStack(spacing: 10) {
                HStack(spacing: 24) {
                    Link("GitHub", destination: URL(string: "https://github.com/CuevaLabs/CodeSergeant")!)
                    Link("Docs", destination: URL(string: "https://github.com/CuevaLabs/CodeSergeant#readme")!)
                    Link("Report Issue", destination: URL(string: "https://github.com/CuevaLabs/CodeSergeant/issues")!)
                }
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(AppTheme.signalTint.opacity(0.85))

                Text("© 2026 Code Sergeant")
                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .tracking(0.6)
            }
            .padding(.bottom, 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Status Badge

struct StatusBadge: View {
    let status: String
    let color: Color
    
    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            
            Text(status)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(color.opacity(0.1))
        )
    }
}

// MARK: - Preview

#Preview {
    SettingsView()
        .environmentObject(AppState())
}
