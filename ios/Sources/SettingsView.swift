import SwiftUI

struct SettingsView: View {
    @ObservedObject var app: AppState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Подключение") {
                    TextField("IP-адрес ПК", text: $app.serverHost)
                        .keyboardType(.numbersAndPunctuation)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)

                    HStack {
                        Text("Порт ввода")
                        Spacer()
                        TextField("8888", value: $app.serverPort, format: .number)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                    }

                    HStack {
                        Text("Порт обратной связи")
                        Spacer()
                        TextField("8889", value: $app.feedbackPort, format: .number)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                    }

                    HStack {
                        Text("Состояние")
                        Spacer()
                        Text(app.status.rawValue)
                            .foregroundStyle(.secondary)
                    }

                    if !app.serverMessage.isEmpty {
                        Text(app.serverMessage)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    Button(app.status == .connected ? "Отключиться" : "Подключиться") {
                        if app.status == .connected {
                            app.disconnect()
                        } else {
                            app.connect()
                        }
                    }

                    Text("Порт обратной связи должен совпадать с `--feedback-port` на ПК (по умолчанию 8889).")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("Раскладка") {
                    Picker("Раскладка", selection: $app.layout) {
                        ForEach(PadLayoutKind.allCases) { kind in
                            Text(kind.rawValue).tag(kind)
                        }
                    }
                    .pickerStyle(.segmented)

                    Text("«Гонки» — крупные педали и руль (тач или гироскоп). «Полная» — раскладка в духе DualSense.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("Обратная связь") {
                    Toggle("Гироскоп (руль по наклону)", isOn: Binding(
                        get: { app.gyroEnabled },
                        set: { newValue in
                            if newValue != app.gyroEnabled { app.toggleGyro() }
                        }))

                    Toggle("Вибрация и тактильность", isOn: $app.hapticsEnabled)
                    Toggle("Звуки контроллера", isOn: $app.soundEnabled)
                    Toggle("Показывать HUD", isOn: $app.showHUD)

                    VStack(alignment: .leading) {
                        Text("Интенсивность: \(Int(app.intensity * 100))%")
                        Slider(value: Binding(
                            get: { app.intensity },
                            set: { app.setIntensity($0) }),
                               in: 0...1)
                    }
                }

                Section {
                    Text("Вибрация приходит из телеметрии FH6: текстура дороги, пробуксовка, ABS, удары и смена передач. Это тот же принцип, по которому работают HorizonHaptics для настоящего DualSense.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("PhonePad")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") { dismiss() }
                }
            }
        }
    }
}
