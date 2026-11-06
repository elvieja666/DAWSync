import Foundation
import Network

struct WireMessage: Codable {
    enum Kind: String, Codable { case hello, command }
    let kind: Kind
    let id: String
    let from: String
    var command: TransportCommand?
}

/// Una conexión TCP con otra Mac. Los mensajes son JSON separados por salto de línea.
final class PeerConnection {
    let connection: NWConnection
    let dialedName: String?
    var peerName: String?
    private var buffer = Data()
    private var closed = false

    var onMessage: ((PeerConnection, WireMessage) -> Void)?
    var onClose: ((PeerConnection) -> Void)?

    init(connection: NWConnection, dialedName: String?) {
        self.connection = connection
        self.dialedName = dialedName
    }

    func start(hello: WireMessage) {
        connection.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                self.send(hello)
            case .failed, .waiting:
                self.close()
            case .cancelled:
                self.finish()
            default:
                break
            }
        }
        connection.start(queue: .main)
        receive()
    }

    func send(_ message: WireMessage) {
        guard !closed, var data = try? JSONEncoder().encode(message) else { return }
        data.append(0x0A)
        connection.send(content: data, completion: .contentProcessed { _ in })
    }

    func close() {
        connection.cancel()
        finish()
    }

    private func finish() {
        guard !closed else { return }
        closed = true
        onClose?(self)
    }

    private func receive() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let data, !data.isEmpty {
                self.buffer.append(data)
                while let newline = self.buffer.firstIndex(of: 0x0A) {
                    let line = Data(self.buffer[self.buffer.startIndex..<newline])
                    self.buffer.removeSubrange(self.buffer.startIndex...newline)
                    if let message = try? JSONDecoder().decode(WireMessage.self, from: line) {
                        self.onMessage?(self, message)
                    }
                }
            }
            if isComplete || error != nil {
                self.close()
            } else {
                self.receive()
            }
        }
    }
}

/// Encuentra otras Macs con DAW Sync (Bonjour) y se conecta a ellas.
/// Con includePeerToPeer usa WiFi directo tipo AirDrop si no hay red compartida.
final class PeerNetwork {
    static let serviceType = "_dawsync._tcp"

    let displayName: String
    let serviceName: String

    var onCommand: ((TransportCommand, String) -> Void)?
    var onPeersChanged: (([String]) -> Void)?
    var onStatus: ((String) -> Void)?

    private var listener: NWListener?
    private var browser: NWBrowser?
    private var connections: [ObjectIdentifier: PeerConnection] = [:]
    private var dialed = Set<String>()
    private var seenIDs: [String] = []
    private var retryTimer: Timer?

    init() {
        let host = Host.current().localizedName ?? "Mac"
        displayName = host
        serviceName = "\(host.prefix(40))#\(UUID().uuidString.prefix(6))"
    }

    private static func parameters() -> NWParameters {
        let params = NWParameters.tcp
        params.includePeerToPeer = true
        if let tcp = params.defaultProtocolStack.transportProtocol as? NWProtocolTCP.Options {
            tcp.noDelay = true
            tcp.enableKeepalive = true
            tcp.keepaliveIdle = 5
        }
        return params
    }

    func start() {
        startListener()
        startBrowser()
        retryTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            self?.dialKnownPeers()
        }
    }

    func broadcast(_ command: TransportCommand) {
        let message = WireMessage(kind: .command, id: UUID().uuidString, from: displayName, command: command)
        remember(message.id)
        for peer in connections.values where peer.peerName != nil {
            peer.send(message)
        }
    }

    // MARK: Escuchar

    private func startListener() {
        do {
            let listener = try NWListener(using: Self.parameters())
            listener.service = NWListener.Service(name: serviceName, type: Self.serviceType)
            listener.newConnectionHandler = { [weak self] connection in
                self?.add(connection, dialedName: nil)
            }
            listener.stateUpdateHandler = { [weak self] state in
                if case .failed(let error) = state {
                    self?.onStatus?("Error de red: \(error.localizedDescription)")
                    self?.listener?.cancel()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) { self?.startListener() }
                }
            }
            listener.start(queue: .main)
            self.listener = listener
        } catch {
            onStatus?("No se pudo abrir la red: \(error.localizedDescription)")
        }
    }

    // MARK: Buscar

    private func startBrowser() {
        let params = NWParameters()
        params.includePeerToPeer = true
        let browser = NWBrowser(for: .bonjour(type: Self.serviceType, domain: nil), using: params)
        browser.browseResultsChangedHandler = { [weak self] _, _ in
            self?.dialKnownPeers()
        }
        browser.stateUpdateHandler = { [weak self] state in
            if case .failed = state {
                self?.browser?.cancel()
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) { self?.startBrowser() }
            }
        }
        browser.start(queue: .main)
        self.browser = browser
    }

    private func dialKnownPeers() {
        guard let results = browser?.browseResults else { return }
        for result in results {
            guard case let .service(name, _, _, _) = result.endpoint,
                  name != serviceName,
                  !dialed.contains(name) else { continue }
            dialed.insert(name)
            add(NWConnection(to: result.endpoint, using: Self.parameters()), dialedName: name)
        }
    }

    // MARK: Conexiones

    private func add(_ connection: NWConnection, dialedName: String?) {
        let peer = PeerConnection(connection: connection, dialedName: dialedName)
        connections[ObjectIdentifier(peer)] = peer
        peer.onMessage = { [weak self] peer, message in
            self?.handle(message, from: peer)
        }
        peer.onClose = { [weak self] peer in
            guard let self else { return }
            self.connections.removeValue(forKey: ObjectIdentifier(peer))
            if let name = peer.dialedName { self.dialed.remove(name) }
            self.publishPeers()
        }
        peer.start(hello: WireMessage(kind: .hello, id: UUID().uuidString, from: displayName))
    }

    private func handle(_ message: WireMessage, from peer: PeerConnection) {
        switch message.kind {
        case .hello:
            peer.peerName = message.from
            publishPeers()
        case .command:
            // Puede haber dos conexiones con la misma Mac: se ignoran los repetidos.
            guard !seenIDs.contains(message.id), let command = message.command else { return }
            remember(message.id)
            onCommand?(command, message.from)
        }
    }

    private func remember(_ id: String) {
        seenIDs.append(id)
        if seenIDs.count > 200 { seenIDs.removeFirst(100) }
    }

    private func publishPeers() {
        let names = Set(connections.values.compactMap { $0.peerName })
        onPeersChanged?(names.sorted())
    }
}
