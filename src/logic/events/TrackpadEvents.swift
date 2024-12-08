import Cocoa

private var mtDevices: [MTDevice]?
private var shouldBeEnabled: Bool = false

//TODO: Should we add a sensitivity setting instead of these magic numbers?
private let SHOW_UI_THRESHOLD: Float = 1
private let CYCLE_THRESHOLD: Float = 5

// gesture tracking state
private var totalDisplacement = (x: Float(0), y: Float(0))
private var extendNextXThreshold = false
private var lastFingerCount: Int = 0

class TrackpadEvents {
    static func observe() {
        observe_()
    }

    static func toggle(_ enabled: Bool) {
        for device in mtDevices ?? [] {
            if enabled && !shouldBeEnabled {
                MTDeviceStart(device, 0)
            } else if !enabled && shouldBeEnabled {
                MTDeviceStop(device, 0)
            }
        }
        shouldBeEnabled = enabled
    }
}

private func observe_() {
    mtDevices = (MTDeviceCreateList().takeUnretainedValue() as? [MTDevice]) ?? []
    print("mtDevices: \(mtDevices)")

    for device in mtDevices ?? [] {
        MTRegisterContactFrameCallback(device) { (device, touches, numTouches, timestamp, frame) in
            handleTouchFrame(touches: touches!, numTouches: Int(numTouches))
            return 0
        }
    }
}

private func handleTouchFrame(touches: UnsafePointer<Finger>, numTouches: Int) {
    let requiredFingers = Preferences.gesture == .fourFingerSwipe ? 4 : 3

    // Handle touch end or incorrect finger count
    if numTouches != requiredFingers {
        if lastFingerCount >= requiredFingers && App.app.appIsBeingUsed
            && App.app.shortcutIndex == 5
            && Preferences.shortcutStyle[App.app.shortcutIndex] == .focusOnRelease
        {
            DispatchQueue.main.async { App.app.focusTarget() }
        }
        clearState()
        lastFingerCount = numTouches
        return
    }

    lastFingerCount = numTouches

    // Calculate average displacement
    var sumDelta = (x: Float(0), y: Float(0))
    var allRight = true
    var allLeft = true
    var allUp = true
    var allDown = true

    for i in 0..<numTouches {
        let touch = touches[i]
        let delta = (
            x: touch.normalized.velocity.x,
            y: touch.normalized.velocity.y
        )

        allRight = allRight && delta.x > 0
        allLeft = allLeft && delta.x < 0
        allUp = allUp && delta.y > 0
        allDown = allDown && delta.y < 0

        sumDelta.x += delta.x
        sumDelta.y += delta.y
    }

    // All fingers should move in the same direction
    if !allRight && !allLeft && !allUp && !allDown { return }

    let displacement = (
        x: totalDisplacement.x + (sumDelta.x / Float(numTouches)),
        y: totalDisplacement.y + (sumDelta.y / Float(numTouches))
    )
    totalDisplacement = displacement

    // handle showing the app initially
    if !App.app.appIsBeingUsed {
        if abs(displacement.x) > SHOW_UI_THRESHOLD && abs(displacement.y) < SHOW_UI_THRESHOLD {
            DispatchQueue.main.async { App.app.showUiOrCycleSelection(5) }
            resetDisplacement(x: true, y: false)
            extendNextXThreshold = true
        }
        return
    }

    // handle swipes when the app is open
    if abs(displacement.x) > CYCLE_THRESHOLD {
        // if extendNextXThreshold is set, extend the threshold for a right swipe to account for the show ui swipe
        if !extendNextXThreshold || displacement.x < 0
            || displacement.x > 2 * CYCLE_THRESHOLD - SHOW_UI_THRESHOLD
        {
            let direction: Direction = displacement.x < 0 ? .left : .right
            DispatchQueue.main.async { App.app.cycleSelection(direction, allowWrap: false) }
            resetDisplacement(x: true, y: false)
            extendNextXThreshold = false
        }
    }
    if abs(displacement.y) > CYCLE_THRESHOLD {
        let direction: Direction = displacement.y < 0 ? .down : .up
        DispatchQueue.main.async { App.app.cycleSelection(direction, allowWrap: false) }
        resetDisplacement(x: false, y: true)
    }
}

private func clearState() {
    resetDisplacement()
    extendNextXThreshold = false
}

private func resetDisplacement(x: Bool = true, y: Bool = true) {
    if x && y {
        totalDisplacement = (0, 0)
    } else if x {
        totalDisplacement.x = 0
    } else if y {
        totalDisplacement.y = 0
    }
}
