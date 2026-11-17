// BeCa: acompañante flotante para Claude Code.
//
// La app solo lee ~/.axo/state, un archivo con una palabra que escriben los
// hooks de Claude Code. No abre conexiones de red ni lee prompts, respuestas,
// archivos o comandos.

import AppKit

let cellWidth = 192
let cellHeight = 208
let staleAfter = TimeInterval(ProcessInfo.processInfo.environment["AXO_STALE_SECONDS"] ?? "") ?? 600
let reviewHold: TimeInterval = 1.5
let celebrationHold: TimeInterval = 5.1
let failureHold: TimeInterval = 2.6
/// Ciclos de reposo antes de detenerse (unos 30 s). Después no queda ningún
/// temporizador activo hasta el siguiente evento.
let restCycles = 6
/// Repeticiones de "atención" antes de quedarse fijo (unos 5 minutos).
let attentionCycles = 300
/// Segundos que un clip sin usar sigue decodificado.
let clipKeepAlive: TimeInterval = 30
let soundVolume: Float = 0.4
/// Separación mínima entre sonidos, para que varios permisos seguidos no sean un coro.
let soundCooldown: TimeInterval = 2

// MARK: - Estados y clips

enum PetState: String {
    case ready, working, reviewing, completed, attention, failed, ended

    var label: String {
        switch self {
        case .ready: return "Esperando"
        case .working: return "Trabajando"
        case .reviewing: return "Revisando un cambio"
        case .completed: return "Terminó"
        case .attention: return "Necesita tu atención"
        case .failed: return "Error de la API"
        case .ended: return "En reposo"
        }
    }
}

struct Clip {
    let name: String
    let row: Int
    let durations: [TimeInterval]
}

enum Clips {
    // El primer cuadro de idle se sostiene para que el reposo sea discreto.
    static let idle = Clip(name: "idle", row: 0, durations: [4.0, 0.11, 0.16, 0.14, 0.14, 0.32])
    static let waving = Clip(name: "waving", row: 3, durations: [0.16, 0.16, 0.18, 0.30])
    static let jumping = Clip(name: "jumping", row: 4, durations: [0.14, 0.14, 0.14, 0.14, 0.28])
    static let failed = Clip(name: "failed", row: 5, durations: [0.14, 0.14, 0.14, 0.14, 0.14, 0.14, 0.14, 0.24])
    static let waiting = Clip(name: "waiting", row: 6, durations: [0.15, 0.15, 0.15, 0.15, 0.15, 0.26])
    static let working = Clip(name: "running", row: 7, durations: [0.12, 0.12, 0.12, 0.12, 0.12, 0.22])
    static let review = Clip(name: "review", row: 8, durations: [0.15, 0.15, 0.15, 0.15, 0.15, 0.28])
    // No sale del sprite sheet: la arma run/tools/make_play_clip.py, que imprime estas duraciones.
    static let play = Clip(name: "play", row: 9, durations: [
        0.12, 0.12, 0.12, 0.12, 0.16, 0.16, 0.22, 0.08, 0.08, 0.09, 0.09, 0.10,
        0.10, 0.16, 0.08, 0.09, 0.11, 0.10, 0.10, 0.11, 0.11, 0.11, 0.11, 0.11,
        0.09, 0.08, 0.08, 0.08, 0.08, 0.08, 0.10, 0.10, 0.13, 0.13, 0.13,
    ])
    static let all = [idle, waving, jumping, failed, waiting, working, review, play]
}

/// Un paso reproduce un clip `repeats` veces; 0 significa repetir sin fin.
struct Step {
    let clip: Clip
    let repeats: Int
}

func program(for state: PetState) -> [Step] {
    switch state {
    case .ready: return [Step(clip: Clips.waving, repeats: 2), Step(clip: Clips.idle, repeats: restCycles)]
    case .working: return [Step(clip: Clips.working, repeats: 0)]
    case .reviewing: return [Step(clip: Clips.review, repeats: 0)]
    case .completed:
        return [
            Step(clip: Clips.jumping, repeats: 4),
            Step(clip: Clips.waving, repeats: 2),
            Step(clip: Clips.idle, repeats: restCycles),
        ]
    case .attention: return [Step(clip: Clips.waiting, repeats: attentionCycles)]
    case .failed: return [Step(clip: Clips.failed, repeats: 1)]
    case .ended: return [Step(clip: Clips.idle, repeats: restCycles)]
    }
}

// MARK: - Rutas

enum Paths {
    static let home: URL = {
        if let custom = ProcessInfo.processInfo.environment["AXO_HOME"], !custom.isEmpty {
            return URL(fileURLWithPath: custom, isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".axo", isDirectory: true)
    }()
    static let state = home.appendingPathComponent("state")
    static let disabled = home.appendingPathComponent("disabled")
    static let hidden = home.appendingPathComponent("hidden")
    static let muted = home.appendingPathComponent("muted")
    // Va en una subcarpeta para no despertar al vigilante de ~/.axo.
    static let statusDir = home.appendingPathComponent("status", isDirectory: true)
    static let displayed = statusDir.appendingPathComponent("displayed")
    static let lastSound = statusDir.appendingPathComponent("last-sound")
}

// MARK: - Vista

final class SpriteView: NSView {
    var onRightClick: ((NSEvent) -> Void)?
    var onClick: (() -> Void)?
    private var dragStart: (mouse: NSPoint, origin: NSPoint)?
    private var isDragging = false

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        layer?.contentsGravity = .resizeAspect
        layer?.magnificationFilter = .linear
        layer?.minificationFilter = .linear
    }

    required init?(coder: NSCoder) { fatalError("no se usa") }

    func show(_ image: CGImage) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer?.contents = image
        CATransaction.commit()
    }

    // La vista mueve la ventana ella misma: si lo hiciera el sistema, no habría
    // forma de distinguir un clic de un arrastre.
    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func rightMouseDown(with event: NSEvent) { onRightClick?(event) }

    override func mouseDown(with event: NSEvent) {
        guard let window else { return }
        dragStart = (NSEvent.mouseLocation, window.frame.origin)
        isDragging = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard let window, let start = dragStart else { return }
        let mouse = NSEvent.mouseLocation
        let deltaX = mouse.x - start.mouse.x
        let deltaY = mouse.y - start.mouse.y
        // Un temblor de la mano al hacer clic no cuenta como arrastre.
        if !isDragging && hypot(deltaX, deltaY) < 4 { return }
        isDragging = true
        window.setFrameOrigin(NSPoint(x: start.origin.x + deltaX, y: start.origin.y + deltaY))
    }

    override func mouseUp(with event: NSEvent) {
        if !isDragging { onClick?() }
        dragStart = nil
    }
}

// MARK: - Clips en memoria

/// Decodifica cada clip al usarlo. Mientras hay actividad conserva los recientes,
/// para que cambiar de estado no vuelva a decodificar; en reposo solo queda el que
/// está en pantalla.
final class ClipStore {
    private var loaded: [String: [CGImage]] = [:]
    private var lastUsed: [String: Date] = [:]

    func retain(_ clips: [Clip]) {
        let now = Date()
        for clip in clips {
            if loaded[clip.name] == nil { loaded[clip.name] = Self.decode(clip) }
            lastUsed[clip.name] = now
        }
        for (name, used) in lastUsed where now.timeIntervalSince(used) > clipKeepAlive {
            loaded[name] = nil
            lastUsed[name] = nil
        }
    }

    func releaseAll(except clip: Clip) {
        loaded = loaded.filter { $0.key == clip.name }
        lastUsed = lastUsed.filter { $0.key == clip.name }
    }

    func frames(_ clip: Clip) -> [CGImage]? { loaded[clip.name] }

    private static func decode(_ clip: Clip) -> [CGImage]? {
        guard
            let url = Bundle.main.url(forResource: clip.name, withExtension: "png", subdirectory: "clips"),
            let source = CGImageSourceCreateWithURL(url as CFURL, nil),
            let strip = CGImageSourceCreateImageAtIndex(
                source, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary)
        else { return nil }
        return (0..<clip.durations.count).compactMap { column in
            strip.cropping(to: CGRect(x: column * cellWidth, y: 0, width: cellWidth, height: cellHeight))
        }
    }
}

// MARK: - Reproductor

final class Player {
    private let store: ClipStore
    private let view: SpriteView
    private var steps: [Step] = []
    private var stepIndex = 0
    private var frameIndex = 0
    private var playedLoops = 0
    private var finished = false
    private var timer: Timer?
    var isPaused = false {
        didSet {
            guard isPaused != oldValue else { return }
            if isPaused {
                timer?.invalidate()
                timer = nil
            } else if !finished && !steps.isEmpty {
                render()
            }
        }
    }
    var onClipChange: ((String) -> Void)?

    init(store: ClipStore, view: SpriteView) {
        self.store = store
        self.view = view
    }

    func play(_ newSteps: [Step]) {
        store.retain(newSteps.map(\.clip))
        steps = newSteps
        stepIndex = 0
        frameIndex = 0
        playedLoops = 0
        finished = false
        onClipChange?(steps[0].clip.name)
        render()
    }

    private func render() {
        // Una sola cadena de temporizadores, sin importar quién llame.
        timer?.invalidate()
        timer = nil
        let clip = steps[stepIndex].clip
        guard let image = store.frames(clip)?[frameIndex] else { return }
        view.show(image)
        guard !isPaused else { return }
        let duration = clip.durations[frameIndex]
        let next = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { [weak self] _ in
            self?.advance()
        }
        // Deja que el sistema agrupe despertares; a esta velocidad no se nota.
        next.tolerance = duration * 0.1
        timer = next
    }

    private func advance() {
        guard !isPaused, !finished, !steps.isEmpty else { return }
        let step = steps[stepIndex]
        frameIndex += 1
        if frameIndex >= step.clip.durations.count {
            frameIndex = 0
            playedLoops += 1
            if step.repeats > 0 && playedLoops >= step.repeats {
                if stepIndex + 1 < steps.count {
                    stepIndex += 1
                    playedLoops = 0
                    onClipChange?(steps[stepIndex].clip.name)
                } else {
                    // Fin del programa: se queda en el último cuadro, sin temporizador.
                    finished = true
                    timer = nil
                    frameIndex = step.clip.durations.count - 1
                    if let image = store.frames(step.clip)?[frameIndex] { view.show(image) }
                    store.releaseAll(except: step.clip)
                    return
                }
            }
        }
        render()
    }
}

// MARK: - Sonido

enum Sound: String {
    case attention, completed, failed, click
}

/// Carga cada sonido al usarlo y lo suelta al terminar: no queda nada en memoria.
final class SoundPlayer: NSObject, NSSoundDelegate {
    private var playing: NSSound?
    private var lastPlayed = Date.distantPast

    func play(_ sound: Sound) {
        guard
            !FileManager.default.fileExists(atPath: Paths.muted.path),
            Date().timeIntervalSince(lastPlayed) >= soundCooldown,
            let url = Bundle.main.url(forResource: sound.rawValue, withExtension: "m4a", subdirectory: "sounds"),
            let next = NSSound(contentsOf: url, byReference: true)
        else { return }
        playing?.stop()
        next.volume = soundVolume
        next.delegate = self
        guard next.play() else { return }
        playing = next
        lastPlayed = Date()
        try? "\(sound.rawValue)\n".write(to: Paths.lastSound, atomically: true, encoding: .utf8)
    }

    func sound(_ sound: NSSound, didFinishPlaying flag: Bool) {
        if sound === playing { playing = nil }
    }
}

// MARK: - Aplicación

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var playsNext = false
    private var panel: NSPanel!
    private var spriteView: SpriteView!
    private var player: Player!
    private var statusItem: NSStatusItem!
    private let menu = NSMenu()
    private let stateItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let visibilityItem = NSMenuItem(title: "", action: #selector(toggleVisibility), keyEquivalent: "")
    private let integrationItem = NSMenuItem(
        title: "Integración con Claude Code", action: #selector(toggleIntegration), keyEquivalent: "")
    private let soundItem = NSMenuItem(title: "Sonido", action: #selector(toggleSound), keyEquivalent: "")
    private let sounds = SoundPlayer()
    private var sizeItems: [NSMenuItem] = []

    private var current: PetState = .ended
    private var pending: PetState?
    private var holdUntil = Date.distantPast
    private var lastEvent = Date()
    private var lastStateStamp = ""
    private var watcher: DispatchSourceFileSystemObject?
    private var integrationEnabled = true
    private var expiryTimer: Timer?

    private let sizes: [(title: String, scale: CGFloat)] = [("Chico", 0.5), ("Mediano", 0.75), ("Grande", 1.0)]

    func applicationDidFinishLaunching(_ notification: Notification) {
        try? FileManager.default.createDirectory(at: Paths.statusDir, withIntermediateDirectories: true)
        // Abrir la app siempre la muestra.
        try? FileManager.default.removeItem(at: Paths.hidden)

        let store = ClipStore()
        store.retain([Clips.idle])
        guard let firstFrame = store.frames(Clips.idle)?.first else {
            NSLog("BeCa: no se pudieron cargar los clips")
            NSApp.terminate(nil)
            return
        }
        buildPanel()
        buildMenu(icon: menuIcon(from: firstFrame))
        player = Player(store: store, view: spriteView)
        player.onClipChange = { [weak self] clip in
            self?.writeDisplayed(clip: clip)
            self?.saveDiagnosticSnapshot(clip: clip)
        }

        // Tapada por otra ventana, con la pantalla bloqueada o apagada: nadie la ve.
        NotificationCenter.default.addObserver(
            forName: NSWindow.didChangeOcclusionStateNotification, object: panel, queue: .main
        ) { [weak self] _ in self?.updatePause() }

        integrationEnabled = !FileManager.default.fileExists(atPath: Paths.disabled.path)
        apply(initialState())
        watchStateDirectory()
        syncVisibility()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        setVisible(true)
        return false
    }

    func applicationWillTerminate(_ notification: Notification) {
        try? FileManager.default.removeItem(at: Paths.displayed)
    }

    /// Copia reducida, para que el ícono no retenga la tira completa de idle.
    private func menuIcon(from image: CGImage) -> NSImage? {
        guard
            let space = CGColorSpace(name: CGColorSpace.sRGB),
            let context = CGContext(
                data: nil, width: 40, height: 43, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: 40, height: 43))
        return context.makeImage().map { NSImage(cgImage: $0, size: NSSize(width: 20, height: 21)) }
    }

    // MARK: Ventana

    private var scale: CGFloat {
        let stored = UserDefaults.standard.double(forKey: "scale")
        return stored > 0 ? CGFloat(stored) : 0.75
    }

    private func buildPanel() {
        let size = NSSize(width: CGFloat(cellWidth) * scale, height: CGFloat(cellHeight) * scale)
        panel = NSPanel(
            contentRect: NSRect(origin: savedOrigin(for: size), size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.title = "BeCa"

        spriteView = SpriteView(frame: NSRect(origin: .zero, size: size))
        spriteView.autoresizingMask = [.width, .height]
        spriteView.onRightClick = { [weak self] event in
            guard let self else { return }
            self.refreshMenu()
            NSMenu.popUpContextMenu(self.menu, with: event, for: self.spriteView)
        }
        spriteView.onClick = { [weak self] in self?.reactToClick() }
        panel.contentView = spriteView

        NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification, object: panel, queue: .main
        ) { [weak self] _ in
            guard let origin = self?.panel.frame.origin else { return }
            UserDefaults.standard.set(Double(origin.x), forKey: "originX")
            UserDefaults.standard.set(Double(origin.y), forKey: "originY")
        }
    }

    private func savedOrigin(for size: NSSize) -> NSPoint {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: "originX") != nil {
            let origin = NSPoint(x: defaults.double(forKey: "originX"), y: defaults.double(forKey: "originY"))
            let rect = NSRect(origin: origin, size: size)
            if NSScreen.screens.contains(where: { $0.visibleFrame.intersects(rect) }) { return origin }
        }
        let visible = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1280, height: 800)
        return NSPoint(x: visible.maxX - size.width - 24, y: visible.minY + 24)
    }

    private func setVisible(_ visible: Bool) {
        if visible {
            try? FileManager.default.removeItem(at: Paths.hidden)
        } else {
            FileManager.default.createFile(atPath: Paths.hidden.path, contents: nil)
        }
        syncVisibility()
    }

    /// El archivo `hidden` manda, para que el menú y `axo ocultar` sigan el mismo camino.
    private func syncVisibility() {
        let hidden = FileManager.default.fileExists(atPath: Paths.hidden.path)
        if hidden == panel.isVisible {
            if hidden {
                panel.orderOut(nil)
            } else {
                panel.orderFrontRegardless()
            }
            writeDisplayed(clip: nil)
        }
        updatePause()
    }

    private func updatePause() {
        player.isPaused = !panel.isVisible || !panel.occlusionState.contains(.visible)
    }

    // MARK: Menú

    private func buildMenu(icon: NSImage?) {
        menu.autoenablesItems = false
        menu.delegate = self
        stateItem.isEnabled = false
        menu.addItem(stateItem)
        menu.addItem(.separator())
        visibilityItem.target = self
        menu.addItem(visibilityItem)
        integrationItem.target = self
        menu.addItem(integrationItem)
        soundItem.target = self
        menu.addItem(soundItem)

        let sizeMenu = NSMenu()
        for (index, entry) in sizes.enumerated() {
            let item = NSMenuItem(title: entry.title, action: #selector(changeSize(_:)), keyEquivalent: "")
            item.target = self
            item.tag = index
            sizeMenu.addItem(item)
            sizeItems.append(item)
        }
        let sizeParent = NSMenuItem(title: "Tamaño", action: nil, keyEquivalent: "")
        sizeParent.submenu = sizeMenu
        menu.addItem(sizeParent)

        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Salir de BeCa", action: #selector(quit), keyEquivalent: "")
        quit.target = self
        menu.addItem(quit)

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let icon {
            statusItem.button?.image = icon
        } else {
            statusItem.button?.title = "BeCa"
        }
        statusItem.button?.toolTip = "BeCa"
        statusItem.menu = menu
    }

    func menuWillOpen(_ menu: NSMenu) { refreshMenu() }

    private func refreshMenu() {
        stateItem.title = integrationEnabled ? "BeCa: \(current.label)" : "BeCa: integración desactivada"
        visibilityItem.title = panel.isVisible ? "Ocultar a BeCa" : "Mostrar a BeCa"
        integrationItem.state = integrationEnabled ? .on : .off
        soundItem.state = FileManager.default.fileExists(atPath: Paths.muted.path) ? .off : .on
        for (index, item) in sizeItems.enumerated() {
            item.state = sizes[index].scale == scale ? .on : .off
        }
    }

    @objc private func toggleVisibility() { setVisible(!panel.isVisible) }

    @objc private func toggleIntegration() {
        if integrationEnabled {
            FileManager.default.createFile(atPath: Paths.disabled.path, contents: nil)
        } else {
            try? FileManager.default.removeItem(at: Paths.disabled)
        }
        refreshFromDisk()
    }

    @objc private func toggleSound() {
        if FileManager.default.fileExists(atPath: Paths.muted.path) {
            try? FileManager.default.removeItem(at: Paths.muted)
        } else {
            FileManager.default.createFile(atPath: Paths.muted.path, contents: nil)
        }
    }

    @objc private func changeSize(_ sender: NSMenuItem) {
        let newScale = sizes[sender.tag].scale
        UserDefaults.standard.set(Double(newScale), forKey: "scale")
        let size = NSSize(width: CGFloat(cellWidth) * newScale, height: CGFloat(cellHeight) * newScale)
        var frame = panel.frame
        frame.origin.y += frame.height - size.height
        frame.size = size
        panel.setFrame(frame, display: true)
    }

    @objc private func quit() { NSApp.terminate(nil) }

    // MARK: Estado

    private func stateStamp() -> (stamp: String, modified: Date)? {
        guard
            let attributes = try? FileManager.default.attributesOfItem(atPath: Paths.state.path),
            let modified = attributes[.modificationDate] as? Date,
            let inode = attributes[.systemFileNumber] as? NSNumber
        else { return nil }
        return ("\(inode)-\(modified.timeIntervalSince1970)", modified)
    }

    private func readState() -> PetState? {
        guard let data = try? Data(contentsOf: Paths.state), data.count <= 32 else { return nil }
        let text = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return PetState(rawValue: text)
    }

    private func initialState() -> PetState {
        guard integrationEnabled, let info = stateStamp(), let state = readState() else { return .ended }
        lastStateStamp = info.stamp
        lastEvent = info.modified
        // Un estado viejo no describe lo que pasa ahora.
        return Date().timeIntervalSince(info.modified) < staleAfter ? state : .ended
    }

    private func watchStateDirectory() {
        let descriptor = open(Paths.home.path, O_EVTONLY)
        guard descriptor >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor, eventMask: [.write, .rename, .delete], queue: .main)
        source.setEventHandler { [weak self] in self?.refreshFromDisk() }
        source.setCancelHandler { close(descriptor) }
        source.resume()
        watcher = source
    }

    private func refreshFromDisk() {
        syncVisibility()
        let enabled = !FileManager.default.fileExists(atPath: Paths.disabled.path)
        if enabled != integrationEnabled {
            integrationEnabled = enabled
            pending = nil
            apply(.ended)
        }
        guard integrationEnabled, let info = stateStamp(), info.stamp != lastStateStamp else { return }
        lastStateStamp = info.stamp
        lastEvent = Date()
        if let state = readState() { receive(state) }
    }

    private func receive(_ state: PetState) {
        if state == current {
            pending = nil
            if state == .reviewing { holdUntil = Date().addingTimeInterval(reviewHold) }
            return
        }
        // "Revisando" dura lo mínimo para verse entre herramientas rápidas, y el
        // fin de sesión espera al festejo o al error: en sesiones cortas llega
        // casi junto a Stop o StopFailure. Los demás cambios son inmediatos.
        let waits =
            (state == .working && current == .reviewing)
            || (state == .ended && (current == .completed || current == .failed))
        if waits && Date() < holdUntil {
            pending = state
            let wait = holdUntil.timeIntervalSinceNow
            Timer.scheduledTimer(withTimeInterval: max(wait, 0.01), repeats: false) { [weak self] _ in
                guard let self, let next = self.pending else { return }
                self.pending = nil
                self.apply(next)
            }
            return
        }
        pending = nil
        let previous = current
        apply(state)
        playSound(from: previous, to: state)
    }

    /// Una decisión real llega a media tarea. El aviso de inactividad llega con
    /// Claude ya terminado, y ese se queda en silencio. Así se distinguen sin
    /// cambiar los hooks, que mandan la misma palabra en ambos casos.
    private func playSound(from previous: PetState, to state: PetState) {
        switch state {
        case .attention:
            if previous == .working || previous == .reviewing { sounds.play(.attention) }
        case .completed:
            sounds.play(.completed)
        case .failed:
            sounds.play(.failed)
        case .ready, .working, .reviewing, .ended:
            break
        }
    }

    /// Clic sobre BeCa: alterna saludo y juego con Clawd, y sigue con lo suyo, sin
    /// cambiar el estado de Claude. En reposo lo despierta: respira un rato y vuelve
    /// a quedarse quieto. Si llega un evento de Claude a media jugada, el evento gana.
    private func reactToClick() {
        let resume: [Step]
        switch current {
        case .ready, .completed, .ended: resume = [Step(clip: Clips.idle, repeats: restCycles)]
        case .working, .reviewing, .attention, .failed: resume = program(for: current)
        }
        let reaction = playsNext ? Step(clip: Clips.play, repeats: 1) : Step(clip: Clips.waving, repeats: 2)
        playsNext.toggle()
        player.play([reaction] + resume)
        sounds.play(.click)
    }

    private func apply(_ state: PetState) {
        current = state
        if state == .reviewing { holdUntil = Date().addingTimeInterval(reviewHold) }
        if state == .completed { holdUntil = Date().addingTimeInterval(celebrationHold) }
        if state == .failed { holdUntil = Date().addingTimeInterval(failureHold) }
        spriteView.toolTip = "BeCa: \(state.label)"
        player.play(program(for: state))
        armExpiry()
    }

    /// Claude Code no avisa cuando interrumpes un turno, así que "trabajando"
    /// podría quedarse fijo. Un solo temporizador, y solo en esos estados.
    private func armExpiry() {
        expiryTimer?.invalidate()
        expiryTimer = nil
        guard current == .working || current == .reviewing else { return }
        let remaining = max(staleAfter - Date().timeIntervalSince(lastEvent), 0.5)
        let timer = Timer.scheduledTimer(withTimeInterval: remaining, repeats: false) { [weak self] _ in
            self?.expireStaleState()
        }
        timer.tolerance = min(15, staleAfter * 0.1)
        expiryTimer = timer
    }

    private func expireStaleState() {
        guard current == .working || current == .reviewing else { return }
        if Date().timeIntervalSince(lastEvent) >= staleAfter {
            apply(.ended)
        } else {
            armExpiry()
        }
    }

    /// Solo para pruebas: con AXO_SNAPSHOT_DIR guarda lo que dibuja la capa.
    /// Sirve porque capturar la ventana desde fuera exige grabación de pantalla.
    private func saveDiagnosticSnapshot(clip: String) {
        guard let directory = ProcessInfo.processInfo.environment["AXO_SNAPSHOT_DIR"] else { return }
        let name = "\(current.rawValue)-\(clip).png"
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            guard
                let layer = self?.spriteView.layer,
                let rep = NSBitmapImageRep(
                    bitmapDataPlanes: nil, pixelsWide: cellWidth, pixelsHigh: cellHeight,
                    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
                let context = NSGraphicsContext(bitmapImageRep: rep)?.cgContext
            else { return }
            context.scaleBy(
                x: CGFloat(cellWidth) / layer.bounds.width, y: CGFloat(cellHeight) / layer.bounds.height)
            layer.render(in: context)
            let url = URL(fileURLWithPath: directory).appendingPathComponent(name)
            try? rep.representation(using: .png, properties: [:])?.write(to: url)
        }
    }

    private var lastClip = "idle"

    /// Deja solo identificadores para `axo status` y las pruebas.
    private func writeDisplayed(clip: String?) {
        if let clip { lastClip = clip }
        let visibility = panel.isVisible ? "visible" : "oculto"
        let line = "\(current.rawValue) \(lastClip) \(visibility)\n"
        try? line.write(to: Paths.displayed, atomically: true, encoding: .utf8)
    }
}

let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate
application.setActivationPolicy(.accessory)
application.run()
