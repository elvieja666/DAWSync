import CoreMIDI
import Foundation

enum TransportCommand: String, Codable {
    case play
    case stop

    var label: String { self == .play ? "▶ Play" : "■ Stop" }
}

/// Cómo la app le da órdenes al DAW de esta Mac.
enum OutputMode: String, CaseIterable, Identifiable {
    /// Manda un CC que se asigna una vez a play/stop (Live: MIDI Map, Logic: Controller Assignments).
    case cc
    /// Manda comandos MMC (Logic con "Escuchar entrada MMC" activado).
    case mmc

    var id: String { rawValue }
    var label: String { self == .cc ? "CC (asignable)" : "MMC" }
}

/// Crea dos puertos MIDI virtuales:
///  - "DAW Sync → DAW": la app le manda órdenes al DAW.
///  - "DAW → DAW Sync": el DAW le avisa a la app cuando le das play/stop.
final class MIDIBridge {
    static let ccChannel: UInt8 = 15   // canal 16
    static let ccPlay: UInt8 = 118
    static let ccStop: UInt8 = 117

    private var client = MIDIClientRef()
    private var source = MIDIEndpointRef()
    private var destination = MIDIEndpointRef()

    /// Se llama (en un hilo de CoreMIDI) cuando el DAW manda play o stop.
    var onTransport: ((TransportCommand) -> Void)?
    private(set) var ready = false

    init() {
        guard MIDIClientCreateWithBlock("DAW Sync" as CFString, &client, { _ in }) == noErr else { return }
        guard MIDISourceCreate(client, "DAW Sync → DAW" as CFString, &source) == noErr else { return }
        let status = MIDIDestinationCreateWithBlock(client, "DAW → DAW Sync" as CFString, &destination) { [weak self] list, _ in
            self?.handle(list)
        }
        ready = status == noErr
    }

    // MARK: Entrada (DAW → app)

    private func handle(_ list: UnsafePointer<MIDIPacketList>) {
        var found: [TransportCommand] = []
        for packet in list.unsafeSequence() {
            let length = Int(packet.pointee.length)
            guard length > 0, let offset = MemoryLayout<MIDIPacket>.offset(of: \MIDIPacket.data) else { continue }
            let start = UnsafeRawPointer(packet).advanced(by: offset)
            let bytes = Array(UnsafeRawBufferPointer(start: start, count: length))
            found.append(contentsOf: Self.parse(bytes))
        }
        for cmd in found { onTransport?(cmd) }
    }

    /// Detecta Start/Continue/Stop de MIDI Clock (Live) y Play/Stop de MMC (Logic).
    static func parse(_ bytes: [UInt8]) -> [TransportCommand] {
        var result: [TransportCommand] = []
        var i = 0
        while i < bytes.count {
            let b = bytes[i]
            switch b {
            case 0xFA, 0xFB: result.append(.play)       // Start / Continue
            case 0xFC: result.append(.stop)              // Stop
            case 0xF0:
                // SysEx MMC: F0 7F <id> 06 <cmd> F7
                if i + 4 < bytes.count, bytes[i + 1] == 0x7F, bytes[i + 3] == 0x06 {
                    switch bytes[i + 4] {
                    case 0x02, 0x03: result.append(.play)  // Play / Deferred Play
                    case 0x01: result.append(.stop)        // Stop
                    default: break
                    }
                }
                // Saltar hasta el final del SysEx
                while i < bytes.count && bytes[i] != 0xF7 { i += 1 }
            default: break
            }
            i += 1
        }
        return result
    }

    // MARK: Salida (app → DAW)

    func sendToDAW(_ cmd: TransportCommand, mode: OutputMode) {
        switch mode {
        case .cc:
            let cc = cmd == .play ? Self.ccPlay : Self.ccStop
            let status = 0xB0 | Self.ccChannel
            send([status, cc, 127])
            send([status, cc, 0])
        case .mmc:
            send([0xF0, 0x7F, 0x7F, 0x06, cmd == .play ? 0x02 : 0x01, 0xF7])
        }
    }

    private func send(_ bytes: [UInt8]) {
        guard ready else { return }
        var list = MIDIPacketList()
        withUnsafeMutablePointer(to: &list) { listPtr in
            let packet = MIDIPacketListInit(listPtr)
            _ = MIDIPacketListAdd(listPtr, MemoryLayout<MIDIPacketList>.size, packet, 0, bytes.count, bytes)
            _ = MIDIReceived(source, listPtr)
        }
    }
}
