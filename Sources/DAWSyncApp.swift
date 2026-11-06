import AppKit
import SwiftUI

@main
struct DAWSyncApp: App {
    @StateObject private var engine = SyncEngine()

    var body: some Scene {
        MenuBarExtra {
            MenuView(engine: engine)
        } label: {
            Image(systemName: engine.peers.isEmpty ? "metronome" : "metronome.fill")
        }
        .menuBarExtraStyle(.window)
    }
}

struct MenuView: View {
    @ObservedObject var engine: SyncEngine

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("DAW Sync").font(.headline)
                Spacer()
                Text(engine.displayName).font(.caption).foregroundStyle(.secondary)
            }

            // Conexión
            HStack(spacing: 6) {
                Circle()
                    .fill(engine.peers.isEmpty ? Color.orange : Color.green)
                    .frame(width: 8, height: 8)
                Text(engine.peers.isEmpty
                     ? "Buscando la otra Mac…"
                     : "Conectado con: \(engine.peers.joined(separator: ", "))")
                    .font(.callout)
            }
            if let status = engine.networkStatus {
                Text(status).font(.caption).foregroundStyle(.red)
            }
            if !engine.midiReady {
                Text("No se pudieron crear los puertos MIDI.").font(.caption).foregroundStyle(.red)
            }

            Divider()

            // Rol
            VStack(alignment: .leading, spacing: 4) {
                Text("Rol de esta Mac").font(.subheadline)
                Picker("", selection: $engine.role) {
                    ForEach(Role.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                Text(roleHelp).font(.caption).foregroundStyle(.secondary)
            }

            // Cómo recibe el DAW
            VStack(alignment: .leading, spacing: 4) {
                Text("Cómo darle órdenes a tu DAW").font(.subheadline)
                Picker("", selection: $engine.outputMode) {
                    ForEach(OutputMode.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                Text(outputHelp).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Button("Probar ▶") { engine.test(.play) }
                    Button("Probar ■") { engine.test(.stop) }
                }
            }

            Divider()

            Text(engine.lastEvent).font(.caption)

            HStack {
                Spacer()
                Button("Salir") { NSApplication.shared.terminate(nil) }
            }
        }
        .padding(14)
        .frame(width: 320)
    }

    private var roleHelp: String {
        switch engine.role {
        case .emisor: return "Tu DAW da las órdenes a la otra Mac."
        case .receptor: return "Tu DAW obedece a la otra Mac."
        case .ambos: return "Cualquiera de las dos Macs puede dar play o stop."
        }
    }

    private var outputHelp: String {
        switch engine.outputMode {
        case .cc:
            return "Manda CC 118 (play) y CC 117 (stop), canal 16, por el puerto «DAW Sync → DAW». Asignalos una vez con los botones de prueba."
        case .mmc:
            return "Manda MMC por «DAW Sync → DAW». En Logic, activá escuchar entrada MMC."
        }
    }
}
