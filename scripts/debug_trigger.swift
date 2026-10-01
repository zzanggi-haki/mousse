import Foundation

// Drives a Debug build of Mousse without touching the keyboard or mouse.
// Usage: swift scripts/debug_trigger.swift <command>
//   highlightOn | highlightOff | find | menuShow | menuHide
//   drawOn | drawOff | drawRect | drawPen | drawDemo
//   settingsShow[:<tab 0-3>] | settingsHide | dump:<file>  (state for scripts)
let command = CommandLine.arguments.dropFirst().first ?? "find"
DistributedNotificationCenter.default().postNotificationName(
    Notification.Name("com.zzanggi.mousse.debug"),
    object: command,
    userInfo: nil,
    deliverImmediately: true
)
