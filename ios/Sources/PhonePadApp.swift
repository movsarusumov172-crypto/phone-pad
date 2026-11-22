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
        GeometryReader { geo in
            if geo.size.height > geo.size.width {
                // Портрет: телефон лежит неправильно — показываем подсказку
                // вместо сломанной раскладки.
                RotateHintView()
            } else {
                ZStack {
                    PadView(controller: app.pad)
                        .ignoresSafeArea()

                    VStack(alignment: .leading, spacing: 8) {
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
                                // HUD — информационный слой: он лежит поверх пада,
                                // но не должен перехватывать касания.
                                .allowsHitTesting(false)
                        }

                        Spacer()
                    }
                    .padding(.top, 6)
                }
                .sheet(isPresented: $app.showSettings) {
                    SettingsView(app: app)
                }
            }
        }
        .onAppear {
            // экран не должен гаснуть во время игры
            UIApplication.shared.isIdleTimerDisabled = true
            UIApplication.shared.isStatusBarHidden = true
        }
    }
}

/// Подсказка «поверните телефон».
struct RotateHintView: View {
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "iphone.landscape")
                .font(.system(size: 54, weight: .light))
                .foregroundStyle(.white.opacity(0.8))
            Text("Поверните телефон")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.white)
            Text("PhonePad работает в горизонтальном положении — как настоящий геймпад.")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white.opacity(0.65))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
    }
}
