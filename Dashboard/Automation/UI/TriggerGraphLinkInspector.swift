import Foundation
import CryptoKit

enum TriggerGraphLinkInspector {
    static func isDirectlyLinkedToConsoleNode(graph: DashboardGraph?, nodeId: UUID) -> Bool {
        guard let g = graph else { return false }
        let gm = Mirror(reflecting: g)

        var neighborIds = Set<UUID>()
        let linkContainerAny: Any? =
            gm.children.first(where: { $0.label == "links" })?.value
            ?? gm.children.first(where: { $0.label == "graphLinks" })?.value
            ?? gm.children.first(where: { $0.label == "edges" })?.value

        if let linksAnyRaw = linkContainerAny {
            let unwrappedLinksAny: Any = unwrapOptional(linksAnyRaw)
            let lm = Mirror(reflecting: unwrappedLinksAny)

            func visitLink(_ link: Any) {
                let m = Mirror(reflecting: link)
                if let en = m.children.first(where: { $0.label == "isEnabled" })?.value as? Bool, en == false {
                    return
                }

                func childValue(_ labels: [String]) -> Any? {
                    for l in labels {
                        if let v = m.children.first(where: { $0.label == l })?.value { return v }
                    }
                    return nil
                }

                let fromId = uuidValue(childValue(["fromNodeId","fromTileId","sourceNodeId","sourceTileId","srcNodeId"]))
                let toId = uuidValue(childValue(["toNodeId","toTileId","destNodeId","destinationNodeId","dstNodeId"]))
                let fromPortStr = stringValue(childValue(["fromPortId","fromPortID","sourcePortId","sourcePortID","srcPortId","sourcePort"]))
                let toPortStr = stringValue(childValue(["toPortId","toPortID","destPortId","destPortID","dstPortId","destPort","targetPortId","targetPort"]))

                let resolvedFromId: UUID? = {
                    if let fromId { return fromId }
                    if let s = fromPortStr { return nodeIdFromPortString(s, graph: graph) }
                    return nil
                }()
                let resolvedToId: UUID? = {
                    if let toId { return toId }
                    if let s = toPortStr { return nodeIdFromPortString(s, graph: graph) }
                    return nil
                }()

                if let a = resolvedFromId, a == nodeId, let b = resolvedToId { neighborIds.insert(b) }
                if let b = resolvedToId, b == nodeId, let a = resolvedFromId { neighborIds.insert(a) }
            }

            if lm.displayStyle == .collection || lm.displayStyle == .set {
                for c in lm.children { visitLink(c.value) }
            } else if lm.displayStyle == .dictionary {
                for c in lm.children {
                    let em = Mirror(reflecting: c.value)
                    if let val = em.children.first(where: { $0.label == "value" })?.value { visitLink(val) }
                }
            }
        }

        guard !neighborIds.isEmpty else { return false }

        let derivedConsoleIds = derivedConsoleNodeIds()
        if !derivedConsoleIds.isEmpty, !neighborIds.isDisjoint(with: derivedConsoleIds) {
            return true
        }

        let neighborInstanceById = neighborInstancesById(graphMirror: gm, neighborIds: neighborIds)

        for nid in neighborIds {
            let inst = neighborInstanceById[nid]
            if let extId = externalDeviceIdForNeighborNode(graphMirror: gm, nodeId: nid, nodeInstance: inst),
               isConsoleExternalDevice(extId) {
                return true
            }

            let keyStr = groupKeyForNodeId(nid, graphMirror: gm, neighborInstanceById: neighborInstanceById)
            if !keyStr.isEmpty, looksLikeConsoleNodeKey(keyStr) {
                return true
            }
        }

        return false
    }

    static func directLinkedConsoleExternalDeviceIds(graph: DashboardGraph?, nodeId: UUID) -> [UUID] {
        guard let g = graph else { return [] }
        let gm = Mirror(reflecting: g)
        var neighborIds = Set<UUID>()

        let linkContainerAny: Any? =
            gm.children.first(where: { $0.label == "links" })?.value
            ?? gm.children.first(where: { $0.label == "graphLinks" })?.value
            ?? gm.children.first(where: { $0.label == "edges" })?.value

        if let linksAnyRaw = linkContainerAny {
            let unwrappedLinksAny: Any = unwrapOptional(linksAnyRaw)
            let lm = Mirror(reflecting: unwrappedLinksAny)

            func visitLink(_ link: Any) {
                let m = Mirror(reflecting: link)
                if let en = m.children.first(where: { $0.label == "isEnabled" })?.value as? Bool, en == false {
                    return
                }

                func childValue(_ labels: [String]) -> Any? {
                    for l in labels {
                        if let v = m.children.first(where: { $0.label == l })?.value { return v }
                    }
                    return nil
                }

                let fromId = uuidValue(childValue(["fromNodeId","fromTileId","sourceNodeId","sourceTileId","srcNodeId"]))
                let toId = uuidValue(childValue(["toNodeId","toTileId","destNodeId","destinationNodeId","dstNodeId"]))
                let fromPortStr = stringValue(childValue(["fromPortId","fromPortID","sourcePortId","sourcePortID","srcPortId","sourcePort"]))
                let toPortStr = stringValue(childValue(["toPortId","toPortID","destPortId","destPortID","dstPortId","destPort","targetPortId","targetPort"]))

                let resolvedFromId: UUID? = {
                    if let fromId { return fromId }
                    if let s = fromPortStr { return nodeIdFromPortString(s, graph: graph) }
                    return nil
                }()
                let resolvedToId: UUID? = {
                    if let toId { return toId }
                    if let s = toPortStr { return nodeIdFromPortString(s, graph: graph) }
                    return nil
                }()

                if let a = resolvedFromId, a == nodeId, let b = resolvedToId { neighborIds.insert(b) }
                if let b = resolvedToId, b == nodeId, let a = resolvedFromId { neighborIds.insert(a) }
            }

            if lm.displayStyle == .collection || lm.displayStyle == .set {
                for c in lm.children { visitLink(c.value) }
            } else if lm.displayStyle == .dictionary {
                for c in lm.children {
                    let em = Mirror(reflecting: c.value)
                    if let val = em.children.first(where: { $0.label == "value" })?.value { visitLink(val) }
                }
            }
        }

        guard !neighborIds.isEmpty else { return [] }

        var out: [UUID] = []
        var seen = Set<UUID>()

        for dev in ExternalDevicesStore.shared.devices {
            let kindStr = String(describing: dev.kind).lowercased()
            guard kindStr.contains("console") else { continue }
            if neighborIds.contains(derivedGraphNodeId(forExternalDeviceId: dev.id)) {
                if seen.insert(dev.id).inserted { out.append(dev.id) }
            }
        }

        let neighborInstanceById = neighborInstancesById(graphMirror: gm, neighborIds: neighborIds)
        for nid in neighborIds {
            if let extId = externalDeviceIdForNeighborNode(graphMirror: gm, nodeId: nid, nodeInstance: neighborInstanceById[nid]),
               isConsoleExternalDevice(extId),
               seen.insert(extId).inserted {
                out.append(extId)
            }
        }

        return out
    }

    private static func neighborInstancesById(graphMirror gm: Mirror, neighborIds: Set<UUID>) -> [UUID: Any] {
        var neighborInstanceById: [UUID: Any] = [:]
        guard let instAnyRaw = gm.children.first(where: { $0.label == "moduleGroupNodeInstances" })?.value else {
            return neighborInstanceById
        }
        let instAny: Any = unwrapOptional(instAnyRaw)
        let im = Mirror(reflecting: instAny)
        if im.displayStyle == .collection || im.displayStyle == .set {
            for c in im.children {
                let inst = c.value
                let m = Mirror(reflecting: inst)
                let id: UUID? =
                    (m.children.first(where: { $0.label == "id" })?.value as? UUID)
                    ?? (m.children.first(where: { $0.label == "nodeId" })?.value as? UUID)
                    ?? uuidValue(m.children.first(where: { $0.label == "id" || $0.label == "nodeId" })?.value)
                if let id, neighborIds.contains(id) {
                    neighborInstanceById[id] = inst
                }
            }
        }
        return neighborInstanceById
    }

    private static func groupKeyForNodeId(_ nid: UUID, graphMirror gm: Mirror, neighborInstanceById: [UUID: Any]) -> String {
        if let inst = neighborInstanceById[nid] {
            let m = Mirror(reflecting: inst)
            if let s = (m.children.first(where: { $0.label == "groupKey" })?.value as? String) { return s }
            if let s = (m.children.first(where: { $0.label == "key" })?.value as? String) { return s }
            if let s = (m.children.first(where: { $0.label == "kind" })?.value as? String) { return s }
        }

        let containerKeys = ["nodes","graphNodes","moduleGroupNodes","nodeInstances","allNodes"]
        for key in containerKeys {
            guard let child = gm.children.first(where: { $0.label == key }) else { continue }
            let container = unwrapOptional(child.value)
            let cm = Mirror(reflecting: container)

            func matchNode(_ node: Any) -> String? {
                let m = Mirror(reflecting: node)
                let id: UUID? =
                    (m.children.first(where: { $0.label == "id" })?.value as? UUID)
                    ?? (m.children.first(where: { $0.label == "nodeId" })?.value as? UUID)
                guard id == nid else { return nil }
                if let s = (m.children.first(where: { $0.label == "groupKey" })?.value as? String) { return s }
                if let s = (m.children.first(where: { $0.label == "key" })?.value as? String) { return s }
                if let s = (m.children.first(where: { $0.label == "kind" })?.value as? String) { return s }
                return nil
            }

            if cm.displayStyle == .collection || cm.displayStyle == .set {
                for c in cm.children {
                    if let s = matchNode(c.value) { return s }
                }
            } else if cm.displayStyle == .dictionary {
                for c in cm.children {
                    let em = Mirror(reflecting: c.value)
                    if let val = em.children.first(where: { $0.label == "value" })?.value,
                       let s = matchNode(val) {
                        return s
                    }
                }
            }
        }

        return ""
    }

    private static func externalDeviceIdForNeighborNode(graphMirror gm: Mirror, nodeId: UUID, nodeInstance: Any?) -> UUID? {
        let dictKeys = [
            "consoleDeviceIdByNodeId",
            "consoleExternalDeviceIdByNodeId",
            "consoleExternalDeviceIDByNodeId",
            "audioConsoleExternalDeviceIdByNodeId",
            "audioConsoleExternalDeviceIDByNodeId",
            "externalDeviceIdByNodeId",
            "externalDeviceIDByNodeId",
            "consoleNodeExternalDeviceIdByNodeId",
            "consoleNodeExternalDeviceIDByNodeId"
        ]

        for key in dictKeys {
            guard let child = gm.children.first(where: { $0.label == key }) else { continue }
            if let dict = child.value as? [UUID: UUID], let v = dict[nodeId] { return v }
            if let dict = child.value as? [String: UUID], let v = dict[nodeId.uuidString] { return v }
            if let dict = child.value as? [UUID: Any], let any = dict[nodeId] { return uuidValue(any) }
            if let dict = child.value as? [String: Any], let any = dict[nodeId.uuidString] { return uuidValue(any) }
        }

        if let inst = nodeInstance {
            return extractExternalDeviceId(fromNodeInstance: inst)
        }

        return nil
    }

    private static func extractExternalDeviceId(fromNodeInstance inst: Any) -> UUID? {
        let m = Mirror(reflecting: inst)
        let keys = [
            "externalDeviceId", "externalDeviceID",
            "deviceId", "deviceID",
            "consoleExternalDeviceId", "consoleExternalDeviceID",
            "audioConsoleExternalDeviceId", "audioConsoleExternalDeviceID"
        ]
        for k in keys {
            guard let v = m.children.first(where: { $0.label == k })?.value else { continue }
            if let u = uuidValue(v) { return u }
        }
        return nil
    }

    private static func isConsoleExternalDevice(_ id: UUID) -> Bool {
        guard let dev = ExternalDevicesStore.shared.devices.first(where: { $0.id == id }) else { return false }
        let kindStr = String(describing: dev.kind).lowercased()
        return kindStr.contains("console")
    }

    private static func derivedConsoleNodeIds() -> Set<UUID> {
        let consoles = ExternalDevicesStore.shared.devices.filter { String(describing: $0.kind).lowercased().contains("console") }
        return Set(consoles.map { derivedGraphNodeId(forExternalDeviceId: $0.id) })
    }

    private static func derivedGraphNodeId(forExternalDeviceId id: UUID) -> UUID {
        let data = Data(id.uuidString.utf8)
        let digest = SHA256.hash(data: data)
        let byteArray = Array(digest.prefix(16))
        var uuidBytes: (UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8) =
            (0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0)
        withUnsafeMutableBytes(of: &uuidBytes) { buf in
            buf.copyBytes(from: byteArray)
        }
        return UUID(uuid: uuidBytes)
    }

    private static func looksLikeConsoleNodeKey(_ keyStr: String) -> Bool {
        let k = keyStr.lowercased()
        if k.contains("send") || k.contains("action") || k.contains("trigger") { return false }
        if k == "console" { return true }
        if k.contains("audioconsole") { return true }
        if k.contains("digico") { return true }
        if k.contains("x32") || k.contains("m32") { return true }
        if k.contains("ah") || k.contains("allen") { return true }
        return k.contains("console")
    }

    private static func nodeIdFromPortString(_ port: String, graph: DashboardGraph?) -> UUID? {
        if let mapped = graph?.nodeIdByPortId[port] { return mapped }
        if port.hasPrefix("node:") {
            let raw = String(port.dropFirst("node:".count))
            return UUID(uuidString: raw)
        }
        return UUID(uuidString: port)
    }

    private static func unwrapOptional(_ any: Any) -> Any {
        let om = Mirror(reflecting: any)
        if om.displayStyle == .optional, let child = om.children.first { return child.value }
        return any
    }

    private static func uuidValue(_ v: Any?) -> UUID? {
        guard let v else { return nil }
        if let u = v as? UUID { return u }
        if let s = v as? String, let u = UUID(uuidString: s) { return u }
        let uv = unwrapOptional(v)
        if let u = uv as? UUID { return u }
        if let s = uv as? String, let u = UUID(uuidString: s) { return u }
        return nil
    }

    private static func stringValue(_ v: Any?) -> String? {
        guard let v else { return nil }
        if let s = v as? String { return s }
        if let u = v as? UUID { return u.uuidString }
        let uv = unwrapOptional(v)
        if let s = uv as? String { return s }
        if let u = uv as? UUID { return u.uuidString }
        return nil
    }
}
