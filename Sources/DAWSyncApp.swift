import AppKit
import Combine
import SwiftUI

/// Ícono en la barra de menú con un panel desplegable. Compatible con macOS 11 o más nuevo.
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private var engine: SyncEngine!
    private var hosting: NSHostingController<MenuView>!
    private var cancellable: AnyCancellable?

    func applicationDidFinishLaunching(_ notification: Notification) {
        engine = SyncEngine()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.target = self
        statusItem.button?.action = #selector(togglePopover(_:))

        hosting = NSHostingController(rootView: MenuView(engine: engine))
        popover.contentViewController = hosting
        popover.behavior = .transient

        cancellable = engine.$peers.sink { [weak self] peers in
            self?.updateIcon(connected: !peers.isEmpty)
        }
        updateIcon(connected: false)
    }

    private func updateIcon(connected: Bool) {
        guard let button = statusItem.button else { return }
        let name = connected ? "metronome.fill" : "metronome"
        if let image = NSImage(systemSymbolName: name, accessibilityDescription: "DAW Sync") {
            image.isTemplate = true
            button.image = image
            button.title = ""
        } else {
            button.image = nil
            button.title = connected ? "♪" : "♩"
        }
    }

    @objc private func togglePopover(_ sender: Any?) {
        if popover.isShown {
            popover.performClose(sender)
            return
        }
        guard let button = statusItem.button else { return }
        hosting.view.layoutSubtreeIfNeeded()
        popover.contentSize = hosting.view.fittingSize
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        NSApp.activate(ignoringOtherApps: true)
    }
}

@main
enum DAWSyncMain {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}

struct MenuView: View {
    @ObservedObject var engine: SyncEngine

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("DAW Sync").font(.headline)
                Spacer()
                Text(engine.displayName).font(.caption).foregroundColor(.secondary)
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
                Text(status).font(.caption).foregroundColor(.red)
            }
            if !engine.midiReady {
                Text("No se pudieron crear los puertos MIDI.").font(.caption).foregroundColor(.red)
            }

            Divider()

            // Rol
            VStack(alignment: .leading, spacing: 4) {
                Text("Rol de esta Mac").font(.subheadline)
                Picker("", selection: $engine.role) {
                    ForEach(Role.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(SegmentedPickerStyle())
                .labelsHidden()
                Text(roleHelp).font(.caption).foregroundColor(.secondary)
            }

            // Cómo recibe el DAW
            VStack(alignment: .leading, spacing: 4) {
                Text("Cómo darle órdenes a tu DAW").font(.subheadline)
                Picker("", selection: $engine.outputMode) {
                    ForEach(OutputMode.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(SegmentedPickerStyle())
                .labelsHidden()
                Text(outputHelp).font(.caption).foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Button("Probar ▶") { engine.test(.play) }
                    Button("Probar ■") { engine.test(.stop) }
                }
            }

            Divider()

            Text(engine.lastEvent).font(.caption)
                .fixedSize(horizontal: false, vertical: true)

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
