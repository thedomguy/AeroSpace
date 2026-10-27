import Foundation

@MainActor private var lastKnownNativeFocusedWindowId: UInt32? = nil

/// The window AeroSpace most recently asked macOS to focus, see `MacApp.nativeFocus`.
/// Workaround for https://github.com/nikitabobko/AeroSpace/issues/101: app activation is
/// asynchronous, and once it settles macOS restores the app's own last key window. If that
/// window lives on another monitor, adopting it would yank AeroSpace onto its workspace.
@MainActor private var pendingFocusRequest: (windowId: UInt32, pid: Int32, deadline: Date, retriesLeft: Int)? = nil

private let focusRequestTtl: TimeInterval = 1.0
private let staleReadingTtl: TimeInterval = 0.3

@MainActor func recordNativeFocusRequest(windowId: UInt32, pid: Int32) {
    pendingFocusRequest = (windowId, pid, Date().addingTimeInterval(focusRequestTtl), 3)
}

/// The data should flow (from nativeFocused to focused) and
///                      (from nativeFocused to lastKnownNativeFocusedWindowId)
/// Alternative names: takeFocusFromMacOs, syncFocusFromMacOs
@MainActor func updateFocusCache(_ nativeFocused: Window?) {
    if nativeFocused?.parent is MacosPopupWindowsContainer {
        return
    }
    if reassertPendingFocusRequestIfHijacked(nativeFocused) {
        nativeFocused?.macAppUnsafe.lastNativeFocusedWindowId = nativeFocused?.windowId
        return
    }
    if nativeFocused?.windowId != lastKnownNativeFocusedWindowId {
        _ = nativeFocused?.focusWindow()
        lastKnownNativeFocusedWindowId = nativeFocused?.windowId
    }
    nativeFocused?.macAppUnsafe.lastNativeFocusedWindowId = nativeFocused?.windowId
}

/// Returns true if the macOS focus must not be adopted because it contradicts the window AeroSpace just requested:
/// - a sibling window of the same app on another workspace: the #101 hijack, focus the requested window again
/// - another app shortly after the request: a stale reading taken before the activation landed
@MainActor private func reassertPendingFocusRequestIfHijacked(_ nativeFocused: Window?) -> Bool {
    guard let request = pendingFocusRequest else { return false }
    guard Date() < request.deadline, request.retriesLeft > 0 else {
        pendingFocusRequest = nil
        return false
    }
    // Keep the request alive until the deadline: the hijack can arrive after macOS briefly honored the request
    guard let nativeFocused, nativeFocused.windowId != request.windowId,
          let requested = Window.get(byId: request.windowId),
          focus.windowOrNil == requested,
          nativeFocused.visualWorkspace != requested.visualWorkspace
    else { return false }
    if nativeFocused.app.pid != request.pid {
        // Activation lands within ~100ms. Past that, another app taking focus is the user (cmd-tab, click, Spotlight)
        if request.deadline.timeIntervalSinceNow > focusRequestTtl - staleReadingTtl {
            return true
        }
        pendingFocusRequest = nil
        return false
    }
    requested.nativeFocus()
    // nativeFocus records a fresh request; keep the original deadline so retries stay bounded
    pendingFocusRequest = (request.windowId, request.pid, request.deadline, request.retriesLeft - 1)
    return true
}
