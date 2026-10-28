import AppKit
import ApplicationServices

/// Thin conveniences over the C Accessibility API.
extension AXUIElement {
    func value(_ attribute: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(self, attribute as CFString, &value) == .success else { return nil }
        return value
    }

    func string(_ attribute: String) -> String? { value(attribute) as? String }

    var role: String? { string(kAXRoleAttribute) }
    var subrole: String? { string(kAXSubroleAttribute) }
    var identifier: String? { string(kAXIdentifierAttribute) }
    var title: String? { string(kAXTitleAttribute) }
    var axDescription: String? { string(kAXDescriptionAttribute) }

    var children: [AXUIElement] { (value(kAXChildrenAttribute) as? [AXUIElement]) ?? [] }

    var pid: pid_t {
        var pid: pid_t = 0
        AXUIElementGetPid(self, &pid)
        return pid
    }

    var attributeNames: [String] {
        var names: CFArray?
        guard AXUIElementCopyAttributeNames(self, &names) == .success else { return [] }
        return (names as? [String]) ?? []
    }

    /// Frame in global Accessibility coordinates (origin at the top-left of the primary screen).
    var frame: CGRect? {
        guard let p = value(kAXPositionAttribute), let s = value(kAXSizeAttribute),
              CFGetTypeID(p) == AXValueGetTypeID(), CFGetTypeID(s) == AXValueGetTypeID() else { return nil }
        var point = CGPoint.zero
        var size = CGSize.zero
        AXValueGetValue(p as! AXValue, .cgPoint, &point)
        AXValueGetValue(s as! AXValue, .cgSize, &size)
        return CGRect(origin: point, size: size)
    }

    /// One-line summary used in log dumps.
    var summary: String {
        var parts = [role ?? "?"]
        if let subrole { parts.append("subrole=\(subrole)") }
        if let identifier { parts.append("id=\(identifier)") }
        if let title, !title.isEmpty { parts.append("title=\"\(title)\"") }
        if let axDescription, !axDescription.isEmpty { parts.append("desc=\"\(axDescription)\"") }
        if let frame { parts.append("frame=\(Int(frame.minX)),\(Int(frame.minY)) \(Int(frame.width))x\(Int(frame.height))") }
        return parts.joined(separator: " ")
    }
}

/// Converts a rect from Accessibility coordinates (top-left origin) to Cocoa screen coordinates (bottom-left origin).
func cocoaRect(fromAX rect: CGRect) -> NSRect {
    let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
    return NSRect(x: rect.minX, y: primaryHeight - rect.maxY, width: rect.width, height: rect.height)
}
