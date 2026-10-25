//
//  HomeView.swift
//  DemonicRevAwakening OBD2
//
//  Startbildschirm: der Dämon als Mittelpunkt, dahinter der dezente
//  Drehzahlbogen, darunter Status und Bedienung. Im Querformat erhält der
//  Dämon den Großteil der Fläche.
//

import SpriteKit
import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var isConnectSheetPresented = false
    @State private var isSettingsPresented = false
    @State private var isGuidePresented = false
    @State private var isFocusMode = false

    var body: some View {
        ZStack {
            BackgroundGradient()
            HomeView(isFocusMode: $isFocusMode,
                     showConnect: { isConnectSheetPresented = true },
                     showSettings: { isSettingsPresented = true },
                     showGuide: { isGuidePresented = true })
        }
        .sheet(isPresented: $isConnectSheetPresented) {
            ConnectionSheet()
        }
        .sheet(isPresented: $isSettingsPresented) {
            SettingsView()
        }
        .sheet(isPresented: $isGuidePresented) {
            GuideView()
        }
        .statusBarHidden(isFocusMode)
        .persistentSystemOverlays(isFocusMode ? .hidden : .automatic)
        .onAppear {
            if model.debugStartsInFocusMode { isFocusMode = true }
            model.setReduceMotion(reduceMotion)
            model.updateIdleTimer(isActive: scenePhase == .active)
        }
        .onChange(of: reduceMotion) { _, newValue in
            model.setReduceMotion(newValue)
        }
        .onChange(of: model.settings.settings) { _, _ in
            model.applySettings()
            model.updateIdleTimer(isActive: scenePhase == .active)
        }
        .onChange(of: model.connection.isSessionActive) { _, _ in
            model.updateIdleTimer(isActive: scenePhase == .active)
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                model.sceneBecameActive()
                model.updateIdleTimer(isActive: true)
            case .background:
                model.sceneEnteredBackground()
            default:
                model.updateIdleTimer(isActive: false)
            }
        }
    }
}

/// Fast schwarzer Hintergrund mit dezentem violettem Schimmer.
struct BackgroundGradient: View {
    var body: some View {
        ZStack {
            Theme.background
            RadialGradient(colors: [Theme.violet.opacity(0.22), .clear],
                           center: .init(x: 0.5, y: 0.35), startRadius: 10, endRadius: 520)
            RadialGradient(colors: [Theme.green.opacity(0.08), .clear],
                           center: .init(x: 0.5, y: 1.0), startRadius: 10, endRadius: 420)
        }
        .ignoresSafeArea()
    }
}

struct HomeView: View {
    @Environment(AppModel.self) private var model
    @Binding var isFocusMode: Bool
    var showConnect: () -> Void
    var showSettings: () -> Void
    var showGuide: () -> Void

    var body: some View {
        GeometryReader { geometry in
            let isLandscape = geometry.size.width > geometry.size.height
            Group {
                if isFocusMode {
                    focusLayout(isLandscape: isLandscape)
                } else if isLandscape {
                    landscapeLayout(size: geometry.size)
                } else {
                    portraitLayout
                }
            }
            .animation(.easeInOut(duration: 0.35), value: isFocusMode)
        }
    }

    // MARK: - Hochformat

    private var portraitLayout: some View {
        let isDemo = model.connection.mode == .demo
        return VStack(spacing: isDemo ? 8 : 14) {
            header
            DemonStage()
                .frame(maxHeight: .infinity)
                .layoutPriority(1)
            RPMReadout(compact: isDemo)
            MetricsRow()
            ConnectionAlertBanner()
            controls
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
    }

    // MARK: - Querformat

    private func landscapeLayout(size: CGSize) -> some View {
        HStack(spacing: 18) {
            DemonStage()
                .frame(width: size.width * 0.6)
            ScrollView {
                VStack(spacing: 14) {
                    header
                    RPMReadout()
                    MetricsRow()
                    ConnectionAlertBanner()
                    controls
                }
                .padding(.vertical, 12)
            }
            .scrollIndicators(.hidden)
        }
        .padding(.horizontal, 16)
    }

    // MARK: - Reduzierter Vollbildmodus

    private func focusLayout(isLandscape: Bool) -> some View {
        ZStack(alignment: .topTrailing) {
            Group {
                if isLandscape {
                    HStack(spacing: 12) {
                        DemonStage()
                        RPMReadout(compact: true)
                            .frame(maxWidth: 260)
                    }
                } else {
                    VStack(spacing: 8) {
                        DemonStage()
                        RPMReadout(compact: true)
                            .padding(.bottom, 24)
                    }
                }
            }
            .padding(.horizontal, 12)

            VStack(alignment: .trailing, spacing: 8) {
                Button {
                    isFocusMode = false
                } label: {
                    Image(systemName: "arrow.down.right.and.arrow.up.left")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Theme.textSecondary)
                        .frame(width: 48, height: 48)
                        .glassPanel(cornerRadius: 24)
                }
                .accessibilityLabel("Vollbildmodus beenden")
                if model.connection.mode == .demo {
                    DemoBadge()
                }
            }
            .padding(16)
        }
    }

    // MARK: - Bausteine

    private var header: some View {
        VStack(spacing: 10) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Demonic")
                        .font(.system(size: 15, weight: .heavy, design: .rounded))
                        .foregroundStyle(Theme.blurple)
                    Text("RevAwakening")
                        .font(.system(size: 24, weight: .black, design: .rounded))
                        .foregroundStyle(
                            LinearGradient(colors: [Theme.neonGreen, Theme.green],
                                           startPoint: .leading, endPoint: .trailing))
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Demonic RevAwakening")
                .accessibilityAddTraits(.isHeader)
                Spacer()
                iconButton("book.pages", label: "Anleitung", action: showGuide)
                iconButton("gearshape.fill", label: "Einstellungen", action: showSettings)
            }
            HStack {
                // Im Demo-Modus ersetzt die deutliche Demo-Kennzeichnung die Statusanzeige.
                if model.connection.mode == .demo {
                    DemoBadge()
                } else {
                    ConnectionStatusPill()
                }
                Spacer(minLength: 0)
            }
            if model.connection.mode == .live {
                HStack {
                    AdapterInfoLine()
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(.top, 8)
    }

    private func iconButton(_ systemImage: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.title3)
                .foregroundStyle(Theme.textSecondary)
                .frame(width: 46, height: 46)
                .glassPanel(cornerRadius: 23)
        }
        .accessibilityLabel(label)
    }

    @ViewBuilder
    private var controls: some View {
        let connection = model.connection
        VStack(spacing: 10) {
            if connection.mode == .demo {
                DemoControlPanel()
            }
            HStack(spacing: 10) {
                switch connection.mode {
                case .live:
                    Button(role: .destructive) {
                        connection.disconnect()
                    } label: {
                        Label("Trennen", systemImage: "xmark.circle")
                    }
                    .buttonStyle(DemonButtonStyle(kind: .secondary))
                case .none, .demo:
                    Button {
                        showConnect()
                    } label: {
                        Label("Verbinden", systemImage: "antenna.radiowaves.left.and.right")
                    }
                    .buttonStyle(DemonButtonStyle(kind: .primary))
                }
                if connection.mode == .none {
                    Button {
                        connection.startDemo()
                    } label: {
                        Label("Demo", systemImage: "play.fill")
                    }
                    .buttonStyle(DemonButtonStyle(kind: .secondary))
                } else if connection.mode == .demo {
                    Button {
                        connection.stopDemo()
                    } label: {
                        Label("Beenden", systemImage: "stop.circle")
                    }
                    .buttonStyle(DemonButtonStyle(kind: .secondary))
                    .accessibilityLabel("Demo beenden")
                }
                Button {
                    isFocusMode = true
                } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.headline)
                }
                .buttonStyle(DemonButtonStyle(kind: .secondary))
                .frame(width: 64)
                .accessibilityLabel("Reduzierter Vollbildmodus")
            }
        }
    }
}

/// Dämon mit dem Drehzahlbogen im Hintergrund – wie im App-Icon.
struct DemonStage: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height
            let gaugeWidth = min(width * 0.92, height * 1.15)
            ZStack {
                StageGauge()
                    .frame(width: gaugeWidth, height: gaugeWidth / 2)
                    .position(x: width / 2, y: height * 0.36)
                DemonSpriteView(scene: model.demonScene)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Animierter Dämon")
        .accessibilityValue(model.presentation.mood.title)
    }
}

/// Liest nur die Präsentationswerte, damit nur dieser Bogen mit ~30 Hz neu zeichnet.
private struct StageGauge: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let frame = model.presentation.frame
        TachometerView(rpm: frame.smoothedRPM,
                       thresholds: model.settings.settings.thresholds,
                       energy: frame.energy,
                       isDimmed: !frame.mood.isDrivenByRPM)
            .opacity(0.85)
    }
}

/// SpriteKit-Darstellung der Figur mit transparentem Hintergrund.
struct DemonSpriteView: View {
    let scene: DemonScene

    var body: some View {
        SpriteView(scene: scene, preferredFramesPerSecond: 60, options: [.allowsTransparency])
            .background(Color.clear)
    }
}

/// Steuerung des Demo-Modus.
struct DemoControlPanel: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let connection = model.connection
        let demo = connection.demo
        VStack(alignment: .leading, spacing: 8) {
            Picker("Demo-Modus", selection: Binding(get: { demo.mode },
                                                    set: { connection.setDemoMode($0) })) {
                ForEach(DemoEngine.Mode.allCases, id: \.self) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            switch demo.mode {
            case .manual:
                VStack(alignment: .leading, spacing: 0) {
                    Text("Simulierte Drehzahl: \(RPMReadout.rpmText(demo.manualTargetRPM, freshness: .fresh)) RPM")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.textSecondary)
                        .monospacedDigit()
                    Slider(value: Binding(get: { demo.manualTargetRPM },
                                          set: { connection.setDemoManualRPM($0) }),
                           in: DemoEngine.rpmRange, step: 50) {
                        Text("Simulierte Drehzahl")
                    } minimumValueLabel: {
                        Text("0").font(.caption)
                    } maximumValueLabel: {
                        Text("8000").font(.caption)
                    }
                    .tint(Theme.green)
                    .accessibilityValue("\(Int(demo.manualTargetRPM)) RPM")
                }
            case .automatic:
                HStack(spacing: 10) {
                    Text(demo.isPaused ? "Pausiert" : demo.phaseDescription)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button {
                        demo.isPaused ? connection.resumeDemo() : connection.pauseDemo()
                    } label: {
                        Image(systemName: demo.isPaused ? "play.fill" : "pause.fill")
                    }
                    .buttonStyle(DemonButtonStyle(kind: .secondary))
                    .frame(width: 60)
                    .accessibilityLabel(demo.isPaused ? "Demo fortsetzen" : "Demo pausieren")
                    Button {
                        connection.restartDemo()
                    } label: {
                        Image(systemName: "arrow.counterclockwise")
                    }
                    .buttonStyle(DemonButtonStyle(kind: .secondary))
                    .frame(width: 60)
                    .accessibilityLabel("Demo neu starten")
                }
            }
        }
        .padding(12)
        .glassPanel(cornerRadius: 20)
    }
}
