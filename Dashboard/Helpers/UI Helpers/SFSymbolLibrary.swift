// Dashboard/Helpers/UI Helpers/SFSymbolLibrary.swift
import Foundation

enum SFSymbolLibrary {
    struct Category {
        let name: String
        let symbols: [String]
    }

    static let categories: [Category] = [
        Category(name: "Suggested", symbols: [
            "play.fill", "stop.fill", "pause.fill", "dot.radiowaves.left.and.right",
            "record.circle.fill", "mic.fill", "text.bubble.fill", "waveform",
            "arrow.clockwise", "square.and.arrow.down.fill", "forward.fill",
            "backward.fill", "bolt.fill", "lightbulb.fill", "power",
            "exclamationmark.triangle.fill"
        ]),
        Category(name: "Media & Playback", symbols: [
            "play.circle", "play.circle.fill", "pause.circle", "pause.circle.fill",
            "stop.circle", "stop.circle.fill", "backward.circle", "forward.circle",
            "repeat", "repeat.1", "shuffle", "speaker.fill", "speaker.slash.fill",
            "speaker.wave.2.fill", "headphones", "airplay.audio", "airplay.video",
            "film", "music.note", "music.note.list", "music.mic",
            "photo", "video", "video.slash", "mic", "mic.slash.fill",
            "mic.circle", "mic.circle.fill", "waveform.circle", "waveform.circle.fill"
        ]),
        Category(name: "Arrows", symbols: [
            "arrow.right", "arrow.left", "arrow.up", "arrow.down",
            "arrow.counterclockwise",
            "arrow.up.arrow.down", "arrow.left.arrow.right",
            "arrow.uturn.left", "arrow.uturn.right",
            "arrowshape.right.fill", "arrowshape.left.fill",
            "chevron.right", "chevron.left", "chevron.up", "chevron.down",
            "chevron.up.chevron.down",
            "arrow.right.circle", "arrow.right.circle.fill",
            "arrow.up.right", "arrow.down.left",
            "arrow.forward", "arrow.backward",
            "return", "arrow.turn.up.left", "arrow.turn.up.right",
            "arrow.up.right.square", "arrow.down.left.square"
        ]),
        Category(name: "Communication", symbols: [
            "bubble.left", "bubble.left.fill", "bubble.right", "bubble.right.fill",
            "bubble.left.and.bubble.right", "message", "message.fill",
            "envelope", "envelope.fill", "envelope.open", "envelope.open.fill",
            "phone", "phone.fill", "phone.down", "phone.down.fill",
            "bell", "bell.fill", "bell.slash", "bell.badge",
            "megaphone", "megaphone.fill",
            "antenna.radiowaves.left.and.right", "wifi", "wifi.slash",
            "paperplane", "paperplane.fill",
            "link", "shareplay", "shared.with.you"
        ]),
        Category(name: "Devices & Tech", symbols: [
            "tv", "tv.fill", "display", "display.2",
            "keyboard", "keyboard.fill", "mouse", "mouse.fill",
            "laptopcomputer", "iphone", "ipad", "appletv",
            "gamecontroller", "gamecontroller.fill", "applewatch",
            "cpu", "memorychip", "sd.card",
            "externaldrive", "externaldrive.fill",
            "cloud", "cloud.fill", "icloud", "icloud.fill",
            "server.rack", "network"
        ]),
        Category(name: "Objects & Tools", symbols: [
            "doc", "doc.fill", "doc.text", "doc.text.fill",
            "folder", "folder.fill", "folder.badge.plus",
            "star", "star.fill", "bookmark", "bookmark.fill",
            "tag", "tag.fill", "calendar", "calendar.badge.plus",
            "clock", "clock.fill", "timer", "stopwatch",
            "gauge", "gauge.high",
            "mappin", "mappin.circle", "map", "map.fill",
            "globe", "safari",
            "lock", "lock.fill", "lock.open", "key", "key.fill",
            "wrench.and.screwdriver", "hammer", "scissors",
            "trash", "trash.fill", "archivebox", "archivebox.fill",
            "tray", "tray.fill", "square.and.arrow.up"
        ]),
        Category(name: "People", symbols: [
            "person", "person.fill", "person.circle", "person.circle.fill",
            "person.2", "person.2.fill",
            "person.crop.circle", "person.crop.circle.fill",
            "figure.walk", "figure.stand",
            "hand.raised", "hand.raised.fill",
            "hand.thumbsup", "hand.thumbsup.fill",
            "hand.thumbsdown", "hand.thumbsdown.fill",
            "hands.clap", "hands.clap.fill",
            "eye", "eye.fill", "eye.slash", "ear"
        ]),
        Category(name: "Nature & Weather", symbols: [
            "sun.max", "sun.max.fill", "sun.min", "sun.min.fill",
            "moon", "moon.fill", "moon.stars", "moon.stars.fill",
            "cloud.rain", "cloud.rain.fill", "cloud.bolt", "cloud.bolt.fill",
            "wind", "tornado", "flame", "flame.fill",
            "bolt", "bolt.circle", "bolt.circle.fill",
            "drop", "drop.fill", "snowflake",
            "thermometer.medium", "leaf", "leaf.fill"
        ]),
        Category(name: "Finance & Data", symbols: [
            "dollarsign.circle", "dollarsign.circle.fill",
            "creditcard", "creditcard.fill",
            "chart.bar", "chart.bar.fill",
            "chart.line.uptrend.xyaxis",
            "chart.pie", "chart.pie.fill",
            "percent", "number", "textformat.123",
            "list.number", "checkmark.seal", "checkmark.seal.fill",
            "exclamationmark.shield",
            "shield", "shield.fill", "lock.shield",
            "scroll", "scroll.fill"
        ]),
        Category(name: "Interface", symbols: [
            "gear", "gear.circle", "gear.circle.fill",
            "checkmark", "checkmark.circle", "checkmark.circle.fill",
            "xmark", "xmark.circle", "xmark.circle.fill",
            "plus", "plus.circle", "plus.circle.fill",
            "minus", "minus.circle", "minus.circle.fill",
            "magnifyingglass", "magnifyingglass.circle",
            "slider.horizontal.3", "line.3.horizontal",
            "ellipsis", "ellipsis.circle",
            "rectangle.grid.2x2", "square.grid.2x2", "square.grid.3x3",
            "list.bullet", "list.dash",
            "info.circle", "info.circle.fill",
            "questionmark.circle", "questionmark.circle.fill",
            "exclamationmark.circle", "exclamationmark.circle.fill",
            "heart", "heart.fill", "flag", "flag.fill",
            "pin", "pin.fill"
        ])
    ]
}
