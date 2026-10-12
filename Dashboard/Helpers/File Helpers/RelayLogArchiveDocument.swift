//
//  RelayLogArchiveDocument.swift
//  Relay
//
//  Created by David Bullard on 2/11/26.
//

import SwiftUI
import UniformTypeIdentifiers

struct RelayLogArchiveDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.plainText] }

    var data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        self.data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
