import Foundation

// Drives a Debug build of Mousse without touching the keyboard or mouse.
// Usage: swift scripts/debug_trigger.swift highlightOn|highlightOff|find|menuShow|menuHide
let command = CommandLine.arguments.dropFirst().first ?? "find"
DistributedNotificationCenter.default().postNotificationName(
    Notification.Name("com.zzanggi.mousse.debug"),
    object: command,
    userInfo: nil,
    deliverImmediately: true
)
