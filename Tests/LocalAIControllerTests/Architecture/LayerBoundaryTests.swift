// Tests/LocalAIControllerTests/Architecture/LayerBoundaryTests.swift
import Foundation
import XCTest

final class LayerBoundaryTests: XCTestCase {
    private let restrictedDomainImports = [
        "SwiftUI", "UIKit", "Combine", "CoreData", "SwiftData",
        "AppKit", "ServiceManagement", "UserNotifications", "Network"
    ]

    func test_domainFiles_containNoRestrictedImports() throws {
        let files = try swiftFiles(in: "Sources/LocalAIController/Domain")
        XCTAssertFalse(files.isEmpty, "Expected Domain source files to be present")

        for file in files {
            let contents = try String(contentsOf: file, encoding: .utf8)
            for framework in restrictedDomainImports {
                let pattern = #"(?m)^\s*import\s+"# + framework + #"\b"#
                XCTAssertNil(contents.range(of: pattern, options: .regularExpression),
                    "Domain file \(file.path) imports restricted framework \(framework)")
            }
        }
    }

    func test_domainFiles_doNotReferencePresentationOrDataTypes() throws {
        let files = try swiftFiles(in: "Sources/LocalAIController/Domain")
        for file in files {
            let contents = try String(contentsOf: file, encoding: .utf8)
            for forbidden in ["SwiftUI", "UIKit", "ObservableObject", "URLSession"] {
                XCTAssertFalse(contents.contains(forbidden),
                    "Domain file \(file.path) references presentation/infrastructure symbol \(forbidden)")
            }
        }
    }

    func test_layerDirectories_existAndContainSwiftSources() throws {
        for layer in ["Domain", "Data", "Presentation", "Application"] {
            let files = try swiftFiles(in: "Sources/LocalAIController/\(layer)")
            XCTAssertFalse(files.isEmpty, "Layer \(layer) has no Swift sources")
        }
    }

    func test_domainProtocols_haveDataImplementationsWhenPresent() throws {
        let domainFiles = try swiftFiles(in: "Sources/LocalAIController/Domain")
        let dataFiles = try swiftFiles(in: "Sources/LocalAIController/Data")
        let domainText = try domainFiles.map { try String(contentsOf: $0, encoding: .utf8) }
            .joined(separator: "\n")
        let dataText = try dataFiles.map { try String(contentsOf: $0, encoding: .utf8) }
            .joined(separator: "\n")
        let pattern = #"(?m)^\s*protocol\s+(\w+(?:Repository|Provider))\b"#
        let expression = try NSRegularExpression(pattern: pattern)
        let range = NSRange(domainText.startIndex..., in: domainText)
        for match in expression.matches(in: domainText, range: range) {
            guard let nameRange = Range(match.range(at: 1), in: domainText) else { continue }
            let name = String(domainText[nameRange])
            XCTAssertTrue(dataText.contains(name),
                "Domain protocol \(name) has no corresponding Data implementation")
        }
    }

    func test_presentationFiles_doNotDeclareRepositoryImplementations() throws {
        let files = try swiftFiles(in: "Sources/LocalAIController/Presentation")
        for file in files {
            let contents = try String(contentsOf: file, encoding: .utf8)
            XCTAssertFalse(contents.contains("URLSession"),
                "Presentation file \(file.path) reaches directly into networking")
            XCTAssertFalse(contents.contains("Process()"),
                "Presentation file \(file.path) creates processes directly")
        }
    }

    private func swiftFiles(in relativePath: String) throws -> [URL] {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(relativePath)
        guard let enumerator = FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: [.isRegularFileKey]
        ) else { return [] }
        return enumerator.compactMap { item in
            guard let url = item as? URL, url.pathExtension == "swift" else { return nil }
            return url
        }.sorted { $0.path < $1.path }
    }
}
