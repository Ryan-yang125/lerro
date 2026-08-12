import AppKit
import Foundation
import LerroCore

public struct MacApplicationCatalog: ApplicationCataloging {
    public init() {}

    public func applications() async -> [ApplicationDescriptor] {
        let installed = await Task.detached(priority: .utility) {
            discoveredInstalledApplicationDescriptors()
        }.value
        let running = await MainActor.run { runningApplicationDescriptors() }
        let discovered = mergedApplicationDescriptors(installed: installed, running: running)
        return await MainActor.run {
            discovered.map { descriptor in
                var descriptor = descriptor
                if let path = descriptor.bundleURL {
                    descriptor.iconData = pngData(
                        for: NSWorkspace.shared.icon(forFile: path),
                        pointSize: 64
                    )
                }
                return descriptor
            }
        }
    }
}

func mergedApplicationDescriptors(
    installed: [ApplicationDescriptor],
    running: [ApplicationDescriptor]
) -> [ApplicationDescriptor] {
    var byBundle = Dictionary(uniqueKeysWithValues: installed.map { ($0.bundleIdentifier, $0) })
    for application in running {
        if var existing = byBundle[application.bundleIdentifier] {
            existing.name = application.name
            existing.bundleURL = application.bundleURL ?? existing.bundleURL
            existing.isRunning = true
            byBundle[application.bundleIdentifier] = existing
        } else {
            byBundle[application.bundleIdentifier] = application
        }
    }
    return byBundle.values.sorted { lhs, rhs in
        if lhs.isRunning != rhs.isRunning { return lhs.isRunning }
        let comparison = lhs.name.localizedStandardCompare(rhs.name)
        if comparison != .orderedSame { return comparison == .orderedAscending }
        return lhs.bundleIdentifier < rhs.bundleIdentifier
    }
}

private func discoveredInstalledApplicationDescriptors() -> [ApplicationDescriptor] {
    let fileManager = FileManager.default
    let roots = [
        URL(filePath: "/Applications", directoryHint: .isDirectory),
        URL(filePath: "/System/Applications", directoryHint: .isDirectory),
        fileManager.homeDirectoryForCurrentUser.appending(path: "Applications", directoryHint: .isDirectory),
    ]
    let keys: Set<URLResourceKey> = [.isApplicationKey, .isDirectoryKey]
    var installed: [ApplicationDescriptor] = []
    for root in roots where fileManager.fileExists(atPath: root.path) {
        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { continue }
        for case let url as URL in enumerator {
            guard url.pathExtension.caseInsensitiveCompare("app") == .orderedSame,
                  let bundle = Bundle(url: url),
                  let bundleIdentifier = bundle.bundleIdentifier,
                  !bundleIdentifier.isEmpty else { continue }
            let name = (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
                ?? (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String)
                ?? url.deletingPathExtension().lastPathComponent
            installed.append(
                ApplicationDescriptor(
                    bundleIdentifier: bundleIdentifier,
                    name: name,
                    bundleURL: url.path
                )
            )
        }
    }
    return installed
}

@MainActor
private func runningApplicationDescriptors() -> [ApplicationDescriptor] {
    NSWorkspace.shared.runningApplications.compactMap { application -> ApplicationDescriptor? in
        guard let bundleIdentifier = application.bundleIdentifier,
              let name = application.localizedName else { return nil }
        return ApplicationDescriptor(
            bundleIdentifier: bundleIdentifier,
            name: name,
            bundleURL: application.bundleURL?.path,
            isRunning: true
        )
    }
}

@MainActor
private func pngData(for image: NSImage, pointSize: CGFloat) -> Data? {
    let target = NSSize(width: pointSize, height: pointSize)
    let rendered = NSImage(size: target)
    rendered.lockFocus()
    defer { rendered.unlockFocus() }
    image.draw(
        in: NSRect(origin: .zero, size: target),
        from: .zero,
        operation: .copy,
        fraction: 1
    )
    guard let tiff = rendered.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff) else { return nil }
    return bitmap.representation(using: .png, properties: [:])
}
