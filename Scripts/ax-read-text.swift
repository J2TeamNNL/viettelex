#!/usr/bin/env swift
// ax-read-text.swift — print the focused text of an app through Accessibility, to
// see what a driven typing session (Scripts/ime-drive.swift) actually left on screen
// when a screenshot is not available. Default bundle id is MarkEdit; pass another as
// the first argument. Needs Accessibility for the process running it.
//
//   swiftc -o /tmp/ax-read-text Scripts/ax-read-text.swift && /tmp/ax-read-text app.cyan.markedit
import Cocoa
import ApplicationServices

func attr(_ e: AXUIElement, _ n: String) -> AnyObject? {
    var v: AnyObject?
    AXUIElementCopyAttributeValue(e, n as CFString, &v)
    return v
}

let bundleID = CommandLine.arguments.dropFirst().first ?? "app.cyan.markedit"
guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first else {
    print("not running: \(bundleID)"); exit(1)
}
let ax = AXUIElementCreateApplication(app.processIdentifier)
if let f = attr(ax, kAXFocusedUIElementAttribute) {
    let fe = f as! AXUIElement
    print("focused role=\(attr(fe, kAXRoleAttribute) ?? "nil" as AnyObject)")
    if let v = attr(fe, kAXValueAttribute) { print("focused value=[\(v)]") }
    if let sel = attr(fe, kAXSelectedTextRangeAttribute) { print("selrange=\(sel)") }
}
func walk(_ e: AXUIElement, _ d: Int) {
    guard d < 14 else { return }
    let role = (attr(e, kAXRoleAttribute) as? String) ?? ""
    if role == "AXWebArea" || role == "AXTextArea" {
        print("\(role) value=[\((attr(e, kAXValueAttribute) as? String) ?? "nil")]")
    }
    if let kids = attr(e, kAXChildrenAttribute) as? [AXUIElement] { for k in kids { walk(k, d + 1) } }
}
if let win = attr(ax, kAXFocusedWindowAttribute) {
    print("window title=\(attr(win as! AXUIElement, kAXTitleAttribute) ?? "nil" as AnyObject)")
    walk(win as! AXUIElement, 0)
}
