.pragma library

// ScreenInfo exposes display bounds, not per-screen availableGeometry. Reserve
// room for decorations; Bring here also provides explicit recovery. Compositors
// may override these hints. All dimensions are Qt logical pixels.
function fit(saved, screens, fallback, recover) {
    let target = fallback || screens[0]
    let matched = false
    if (!recover) {
        for (let i = 0; i < screens.length; ++i) {
            if (screens[i].name === saved.screen) {
                target = screens[i]
                matched = true
                break
            }
        }
    }
    if (!target) return null
    const width = Math.max(240, Math.min(saved.width, target.width - 32))
    const height = Math.max(180, Math.min(saved.height, target.height - 80))
    const minX = target.virtualX + 16
    const minY = target.virtualY + 40
    const x = matched && saved.positioned ? saved.x : minX + (target.width - width - 32) / 2
    const y = matched && saved.positioned ? saved.y : minY + (target.height - height - 80) / 2
    return {
        screen: target, width: width, height: height,
        x: Math.round(Math.max(minX, Math.min(x, target.virtualX + target.width - width - 16))),
        y: Math.round(Math.max(minY, Math.min(y, target.virtualY + target.height - height - 40)))
    }
}
