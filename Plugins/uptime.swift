#!/usr/bin/env swift
// Read-only probe. Run with Swift or compile to a standalone executable using swiftc.
import Foundation

guard Array(CommandLine.arguments.dropFirst()) == ["--aelab-probe"] else {
    FileHandle.standardError.write(Data("Expected --aelab-probe\n".utf8)); exit(2)
}
let seconds = Int(ProcessInfo.processInfo.systemUptime)
let report: [String: Any] = [
    "version": 1, "status": "ok", "summary": "Uptime: \(seconds / 86400)d \(seconds / 3600 % 24)h \(seconds / 60 % 60)m",
    "details": [["label": "Uptime seconds", "value": String(seconds)],
                ["label": "Operating system", "value": ProcessInfo.processInfo.operatingSystemVersionString]]
]
let data = try JSONSerialization.data(withJSONObject: report, options: [.sortedKeys])
FileHandle.standardOutput.write(data); FileHandle.standardOutput.write(Data([10]))
