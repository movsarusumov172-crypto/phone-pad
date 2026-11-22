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

/// Ключ для получения размера экрана без влияния на вёрстку.
private struct ScreenSizeKey: PreferenceKey {
    static var defaultValue: CGSize = .zero

    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        let next = nextValue()
        if next != .zero {
            value = next
        }
    }
}

struct ContentView: View {
    @EnvironmentObject private var app: AppState
    @State private var screenSize: CGSize = .zero

    var body: some View {
        Group {
            if screenSize.height > screenSize.width {
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
                                  hud: app.hud,
                                  showHUD: app.showHUD,
                                  onSettings: { app.showSettings = true },
                                  onGyro: { app.toggleGyro() },
                                  onCalibrate: { app.calibrateGyro() },
                                  onConnect: {
                                      if app.status == .connected { app.disconnect() } else { app.connect() }
                                  })
                            .padding(.horizontal, 12)

                        Spacer()
                    }
                    .padding(.top, 6)
                }
                .sheet(isPresented: $app.showSettings) {
                    SettingsView(app: app)
                }
            }
        }
        // Размер экрана измеряем фоновым GeometryReader: он ничего не влияет
        // на вёрстку, в отличие от обёртки всего интерфейса в GeometryReader
        // (тогда панель пада уезжала бы внутрь безопасной зоны от выреза).
        .background {
            GeometryReader { geo in
                Color.clear.preference(key: ScreenSizeKey.self, value: geo.size)
            }
        }
        .onPreferenceChange(ScreenSizeKey.self) { screenSize = $0 }
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
