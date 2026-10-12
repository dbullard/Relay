import Foundation

final class TranscriptionHelperServiceDelegate: NSObject, NSXPCListenerDelegate {
    nonisolated func listener(_ listener: NSXPCListener, shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
        newConnection.remoteObjectInterface = NSXPCInterface(with: TranscriptionHelperCallbackProtocol.self)
        newConnection.exportedInterface = NSXPCInterface(with: TranscriptionHelperProtocol.self)
        newConnection.exportedObject = TranscriptionHelperService(connection: newConnection)
        newConnection.resume()
        return true
    }
}
