#!/usr/bin/env swift
// ime-drive.swift (port từ fork xkhanhs/vtx PR#19, 15/09/2026) — drive the frontmost app with REAL key events (CGEvent on the HID
// tap) under a chosen input source, so a typing bug can be reproduced without a
// human at the keyboard and lined up against the VietTelex log by timestamp.
//
//   swiftc -O -o /tmp/ime-drive Scripts/ime-drive.swift
//   /tmp/ime-drive sel:com.viettelex.inputmethod.telex.vi "t:mootj" ms:200 bs:2 "t:t"
//
// Args run in order:
//   sel:<inputSourceID>  TISSelectInputSource, then print the LIVE keyboard layout
//   layout               print the live layout id and its char→keycode map
//   t:<text>             type text; keycodes come from the live layout (UCKeyTranslate),
//                        so select the layout you want to type on FIRST — under VietTelex
//                        Colemak with remap ON (live ≠ pinned) letters get permuted
//   bs:<n>  del  tab  ret  cmd:<c>  ms:<n>
// Every key is printed with a HH:mm:ss.SSS stamp to line up with `log show --start`.
//
// Needs Accessibility for the process running it. Lessons (13/09/2026, MarkEdit):
//   • ⌘N needs ~1 s before the new tab takes keys — typing earlier lands in whatever
//     document was frontmost.
//   • `log stream` DROPS messages at this key rate; query `log show --start` after.
//   • Read the result back with Scripts/ax-read-text.swift when screenshots are blocked.
import Cocoa
import Carbon

func str(_ s: TISInputSource, _ k: CFString) -> String {
    guard let p = TISGetInputSourceProperty(s, k) else { return "nil" }
    return Unmanaged<CFString>.fromOpaque(p).takeUnretainedValue() as String
}
func pump(_ ms: Int) { CFRunLoopRunInMode(.defaultMode, Double(ms)/1000, false) }

func currentLayoutMap() -> (String, [Character: (UInt16, Bool)]) {
    let layout = TISCopyCurrentKeyboardLayoutInputSource().takeRetainedValue()
    let id = str(layout, kTISPropertyInputSourceID)
    var map: [Character: (UInt16, Bool)] = [:]
    guard let p = TISGetInputSourceProperty(layout, kTISPropertyUnicodeKeyLayoutData) else { return (id, map) }
    let data = Unmanaged<CFData>.fromOpaque(p).takeUnretainedValue() as Data
    data.withUnsafeBytes { raw in
        let ptr = raw.bindMemory(to: UCKeyboardLayout.self).baseAddress!
        for shift in [false, true] {
            for kc: UInt16 in 0..<60 {
                var dead: UInt32 = 0
                var chars = [UniChar](repeating: 0, count: 4)
                var len = 0
                let mods: UInt32 = shift ? UInt32(shiftKey >> 8) : 0
                let r = UCKeyTranslate(ptr, kc, UInt16(kUCKeyActionDown), mods, UInt32(LMGetKbdType()),
                                       UInt32(kUCKeyTranslateNoDeadKeysMask), &dead, 4, &len, &chars)
                guard r == noErr, len == 1 else { continue }
                let c = Character(UnicodeScalar(chars[0])!)
                if map[c] == nil { map[c] = (kc, shift) }
            }
        }
    }
    return (id, map)
}

let fmt: DateFormatter = { let f = DateFormatter(); f.dateFormat = "HH:mm:ss.SSS"; return f }()
func post(_ kc: UInt16, flags: CGEventFlags = [], gap: Int = 45, label: String = "") {
    print("\(fmt.string(from: Date())) key \(kc) \(label)")
    let d = CGEvent(keyboardEventSource: nil, virtualKey: kc, keyDown: true)!
    d.flags = flags; d.post(tap: .cghidEventTap)
    pump(8)
    let u = CGEvent(keyboardEventSource: nil, virtualKey: kc, keyDown: false)!
    u.flags = flags; u.post(tap: .cghidEventTap)
    pump(gap)
}

var (layoutID, map) = currentLayoutMap()
for arg in CommandLine.arguments.dropFirst() {
    if arg.hasPrefix("sel:") {
        let id = String(arg.dropFirst(4))
        let filter = [kTISPropertyInputSourceID as String: id] as CFDictionary
        let list = TISCreateInputSourceList(filter, false).takeRetainedValue() as NSArray
        guard let s = list.firstObject else { print("NOT FOUND \(id)"); exit(1) }
        let src = s as! TISInputSource
        let err = TISSelectInputSource(src)
        pump(400)
        let cur = TISCopyCurrentKeyboardInputSource().takeRetainedValue()
        (layoutID, map) = currentLayoutMap()
        print("select \(id): err=\(err) now=\(str(cur, kTISPropertyInputSourceID)) layout=\(layoutID)")
    } else if arg == "layout" {
        (layoutID, map) = currentLayoutMap()
        print("layout=\(layoutID)")
        print(map.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value.0)\($0.value.1 ? "S" : "")" }.joined(separator: " "))
    } else if arg.hasPrefix("t:") {
        for c in arg.dropFirst(2) {
            if c == " " { post(49, label: "␠"); continue }
            guard let (kc, sh) = map[c] else { print("no key for \(c) in \(layoutID)"); continue }
            post(kc, flags: sh ? .maskShift : [], label: String(c))
        }
    } else if arg.hasPrefix("bs:") {
        for _ in 0..<(Int(arg.dropFirst(3)) ?? 1) { post(51, label: "⌫") }
    } else if arg.hasPrefix("ms:") {
        pump(Int(arg.dropFirst(3)) ?? 100)
    } else if arg.hasPrefix("cmd:") {
        let c = arg.dropFirst(4).first!
        guard let (kc, _) = map[c] else { print("no key for \(c)"); continue }
        post(kc, flags: .maskCommand, gap: 150)
    } else if arg == "tab" { post(48, label: "⇥") }
    else if arg == "ret" { post(36, label: "⏎") }
    else if arg == "del" { post(117, label: "⌦") }
    else { print("unknown arg \(arg)") }
}
