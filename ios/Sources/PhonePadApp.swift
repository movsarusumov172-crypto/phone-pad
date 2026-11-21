import SwiftUI
import UIKit

@main
struct PhonePadApp: App {
    @StateObject private var app = AppState()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(app)
                .preferredColorScheme(.dark)
                .statusBarHidden(true)
                .persistentSystemOverlays(.hidden)
                .onChange(of: scenePhase) { phase in
                    // В фоне телефон не шлёт ввод: если оставить нажатые кнопки,
                    // в игре залипнет газ. Сбрасываем состояние пада.
                    if phase != .active {
                        app.resetPad()
                    }
                }
        }
    }
}

struct ContentView: View {
    @EnvironmentObject private var app: AppState

    var body: some View {
        ZStack {
            PadView(controller: app.pad)
                .ignoresSafeArea()

            VStack(spacing: 10) {
                StatusBar(status: app.status,
                          gyroEnabled: app.gyroEnabled,
                          message: app.serverMessage,
                          lightBar: app.lightBar,
                          onSettings: { app.showSettings = true },
                          onGyro: { app.toggleGyro() },
                          onCalibrate: { app.calibrateGyro() },
                          onConnect: {
                              if app.status == .connected { app.disconnect() } else { app.connect() }
                          })
                .padding(.horizontal, 12)

                if app.showHUD {
                    HudView(hud: app.hud)
                }

                Spacer()
            }
            .padding(.top, 6)
        }
        .sheet(isPresented: $app.showSettings) {
            SettingsView(app: app)
        }
        .onAppear {
            // экран не должен гаснуть во время игры
            UIApplication.shared.isIdleTimerDisabled = true
            UIApplication.shared.isStatusBarHidden = true
        }
    }
}
