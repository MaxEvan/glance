import AppKit
import ApplicationServices

/// A window thumbnail as reported by the Dock while Mission Control is open.
struct Thumbnail {
    let element: AXUIElement
    let title: String?
    /// Global Accessibility coordinates.
    let frame: CGRect
}

/// Polls the Dock's Accessibility tree to notice Mission Control opening/closing
/// and to read where each window thumbnail is drawn.
///
/// Apple does not document this tree; while Mission Control is open the Dock is
/// expected to expose an extra child group (identifier "mc") holding the thumbnails.
final class MissionControlWatcher {
    var onBegin: (AXUIElement) -> Void = { _ in }
    var onUpdate: ([Thumbnail]) -> Void = { _ in }
    var onEnd: () -> Void = {}

    private var timer: Timer?
    private var isActive = false
    private var lastDockSignature = ""
    private var lastThumbnailCount = -1

    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in self?.tick() }
    }

    private func dockElement() -> AXUIElement? {
        guard let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first else {
            return nil
        }
        let element = AXUIElementCreateApplication(dock.processIdentifier)
        AXUIElementSetMessagingTimeout(element, 0.25)
        return element
    }

    private func tick() {
        guard let dock = dockElement() else { return }
        let children = dock.children
        logDockChildrenIfChanged(children)

        guard let mc = children.first(where: { $0.identifier == "mc" }) else {
            if isActive {
                isActive = false
                lastThumbnailCount = -1
                Log.write("Mission Control closed")
                onEnd()
            }
            return
        }

        if !isActive {
            isActive = true
            Log.write("Mission Control opened")
            onBegin(mc)
        }

        let thumbnails = Self.collectThumbnails(in: mc)
        if thumbnails.count != lastThumbnailCount {
            lastThumbnailCount = thumbnails.count
            Log.write("\(thumbnails.count) window thumbnail(s):")
            for t in thumbnails {
                Log.write("  \"\(t.title ?? "")\" at \(Int(t.frame.minX)),\(Int(t.frame.minY)) \(Int(t.frame.width))x\(Int(t.frame.height))")
            }
        }
        onUpdate(thumbnails)
    }

    /// Logs the Dock's top-level children whenever they change, so we can see what
    /// Mission Control looks like even if the "mc" identifier guess is wrong.
    private func logDockChildrenIfChanged(_ children: [AXUIElement]) {
        let signature = children.map { "\($0.role ?? "?")#\($0.identifier ?? "-")" }.joined(separator: ", ")
        guard signature != lastDockSignature else { return }
        lastDockSignature = signature
        Log.write("Dock children: [\(signature)]")
    }

    /// Window thumbnails are buttons inside the "mc" group, excluding the Spaces bar at the top.
    static func collectThumbnails(in mc: AXUIElement) -> [Thumbnail] {
        var result: [Thumbnail] = []
        func visit(_ element: AXUIElement, inSpacesBar: Bool) {
            let id = element.identifier ?? ""
            let spaces = inSpacesBar || id.hasPrefix("mc.spaces")
            if !spaces, element.role == kAXButtonRole, let frame = element.frame, frame.width > 40, frame.height > 40 {
                result.append(Thumbnail(element: element, title: element.title, frame: frame))
            }
            for child in element.children { visit(child, inSpacesBar: spaces) }
        }
        visit(mc, inSpacesBar: false)
        return result
    }

    /// Writes the full Mission Control subtree to the log, plus every attribute of the
    /// first few thumbnails, so we can learn what the Dock exposes on this macOS version.
    static func dumpTree(_ root: AXUIElement) {
        Log.write("---- Mission Control AX tree ----")
        var detailed = 0
        func visit(_ element: AXUIElement, depth: Int) {
            guard depth < 12 else { return }
            Log.write(String(repeating: "  ", count: depth) + element.summary)
            if element.role == kAXButtonRole, detailed < 2 {
                detailed += 1
                for name in element.attributeNames {
                    let value = element.value(name).map { String(describing: $0) } ?? "nil"
                    Log.write(String(repeating: "  ", count: depth + 2) + "\(name) = \(value.prefix(200))")
                }
            }
            for child in element.children { visit(child, depth: depth + 1) }
        }
        visit(root, depth: 0)
        Log.write("---- end of tree ----")
    }
}
