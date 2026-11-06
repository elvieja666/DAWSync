import Foundation
import SwiftUI

enum Role: String, CaseIterable, Identifiable {
    case emisor, receptor, ambos

    var id: String { rawValue }
    var label: String {
        switch self {
        case .emisor: return "Emisor"
        case .receptor: return "Receptor"
        case .ambos: return "Ambos"
        }
    }
    var canSend: Bool { self != .receptor }
    var canReceive: Bool { self != .emisor }
}

final class SyncEngine: ObservableObject {
    @Published var role: Role {
        didSet { UserDefaults.standard.set(role.rawValue, forKey: "role") }
    }
    @Published var outputMode: OutputMode {
        didSet { UserDefaults.standard.set(outputMode.rawValue, forKey: "outputMode") }
    }
    @Published private(set) var peers: [String] = []
    @Published private(set) var lastEvent = "Sin actividad todavía"
    @Published private(set) var networkStatus: String?

    let midiReady: Bool
    var displayName: String { network.displayName }

    private let midi = MIDIBridge()
    private let network = PeerNetwork()

    /// Anti-eco: después de darle una orden al DAW, se ignora lo que el DAW devuelva por un instante.
    private var ignoreFromDAWUntil: [TransportCommand: Date] = [:]
    /// Evita mandar dos veces la misma orden si el DAW manda MMC y Clock juntos.
    private var lastSent: [TransportCommand: Date] = [:]

    private static let echoWindow: TimeInterval = 0.75
    private static let duplicateWindow: TimeInterval = 0.3

    init() {
        let defaults = UserDefaults.standard
        role = Role(rawValue: defaults.string(forKey: "role") ?? "") ?? .ambos
        outputMode = OutputMode(rawValue: defaults.string(forKey: "outputMode") ?? "") ?? .cc
        midiReady = midi.ready

        midi.onTransport = { [weak self] command in
            DispatchQueue.main.async { self?.fromDAW(command) }
        }
        network.onCommand = { [weak self] command, sender in
            self?.fromNetwork(command, sender: sender)
        }
        network.onPeersChanged = { [weak self] names in
            self?.peers = names
        }
        network.onStatus = { [weak self] status in
            self?.networkStatus = status
        }
        network.start()
    }

    private func fromDAW(_ command: TransportCommand) {
        let now = Date()
        if let until = ignoreFromDAWUntil[command], now < until { return }
        guard role.canSend else { return }
        if let last = lastSent[command], now.timeIntervalSince(last) < Self.duplicateWindow { return }
        lastSent[command] = now

        network.broadcast(command)
        lastEvent = peers.isEmpty
            ? "\(command.label) en tu DAW (no hay otra Mac conectada)"
            : "Enviado \(command.label)"
    }

    private func fromNetwork(_ command: TransportCommand, sender: String) {
        guard role.canReceive else {
            lastEvent = "Ignorado \(command.label) de \(sender) (modo Emisor)"
            return
        }
        giveToDAW(command)
        lastEvent = "Recibido \(command.label) de \(sender)"
    }

    /// Botones de prueba: sirven para asignar el CC en el DAW (MIDI Map / Learn).
    func test(_ command: TransportCommand) {
        giveToDAW(command)
        lastEvent = "Prueba \(command.label) enviada a tu DAW"
    }

    private func giveToDAW(_ command: TransportCommand) {
        ignoreFromDAWUntil[command] = Date().addingTimeInterval(Self.echoWindow)
        midi.sendToDAW(command, mode: outputMode)
    }
}
