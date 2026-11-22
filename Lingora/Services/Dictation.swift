import Foundation
import Speech
import AVFoundation

/// Microphone capture on its own queue: activating the audio session and starting the engine can take
/// a few hundred milliseconds, which would freeze the UI on the main thread.
final class AudioCapture: @unchecked Sendable {
    private let engine = AVAudioEngine()
    private let queue = DispatchQueue(label: "lingora.audio", qos: .userInteractive)
    private var active = false
    /// Where microphone buffers go right now (nil between recordings).
    private var target: SFSpeechAudioBufferRecognitionRequest?
    private let lock = NSLock()
    private var idleStop: DispatchWorkItem?
    /// Starting the microphone costs ~0.6 s, so it stays on briefly after a recording: the next press is instant.
    private let keepWarm: TimeInterval = 20

    private func setTarget(_ r: SFSpeechAudioBufferRecognitionRequest?) {
        lock.lock(); target = r; lock.unlock()
    }

    func warmUp() {
        queue.async { [self] in
            let s = AVAudioSession.sharedInstance()
            try? s.setCategory(.record, mode: .measurement, options: .duckOthers)
            try? s.setAllowHapticsAndSystemSoundsDuringRecording(true)
            _ = engine.inputNode
        }
    }

    func start(feeding req: SFSpeechAudioBufferRecognitionRequest, done: @escaping (Error?) -> Void) {
        queue.async { [self] in
            idleStop?.cancel()
            idleStop = nil
            setTarget(req)
            if engine.isRunning { done(nil); return }   // still warm: nothing to start
            do {
                if !active {
                    let s = AVAudioSession.sharedInstance()
                    try s.setCategory(.record, mode: .measurement, options: .duckOthers)
                    // iOS mutes vibrations while the mic records unless this is allowed.
                    try? s.setAllowHapticsAndSystemSoundsDuringRecording(true)
                    try s.setActive(true, options: .notifyOthersOnDeactivation)
                    active = true
                }
                let input = engine.inputNode
                input.removeTap(onBus: 0)
                input.installTap(onBus: 0, bufferSize: 1024, format: input.outputFormat(forBus: 0)) { [weak self] buf, _ in
                    guard let self else { return }
                    self.lock.lock(); let t = self.target; self.lock.unlock()
                    t?.append(buf)
                }
                engine.prepare()
                try engine.start()
                done(nil)
            } catch {
                setTarget(nil)
                done(error)
            }
        }
    }

    /// Stops feeding the recogniser; the microphone itself turns off after a short idle period.
    func stop(then: (() -> Void)? = nil) {
        queue.async { [self] in
            setTarget(nil)
            then?()
            idleStop?.cancel()
            let work = DispatchWorkItem { [weak self] in self?.turnOff(deactivate: true) }
            idleStop = work
            queue.asyncAfter(deadline: .now() + keepWarm, execute: work)
        }
    }

    func deactivate() {
        queue.async { [self] in
            idleStop?.cancel()
            idleStop = nil
            turnOff(deactivate: true)
        }
    }

    private func turnOff(deactivate: Bool) {
        setTarget(nil)
        if engine.isRunning { engine.stop() }
        engine.inputNode.removeTap(onBus: 0)
        if deactivate && active {
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            active = false
        }
    }
}

/// Live speech-to-text in the language being practised (Speech framework, on-device when available).
/// Hold-to-talk: `press` starts recording, `release` stops it and keeps the final words.
@MainActor
final class Dictation: ObservableObject {
    @Published private(set) var isRecording = false
    @Published var error: String?

    private let audio = AudioCapture()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    /// False once the finger lifts — also covers a release while permissions are still being asked.
    private var held = false
    private var recognizers: [String: SFSpeechRecognizer] = [:]
    /// Each press gets a number so late callbacks from an older recording are ignored.
    private var generation = 0
    private var t0 = CFAbsoluteTimeGetCurrent()
    private var gotFirstWords = false

    private func log(_ what: String) {
        print(String(format: "[Dictation] +%4.0f ms  %@", (CFAbsoluteTimeGetCurrent() - t0) * 1000, what))
    }

    /// Maps Lingora language keys to speech locales.
    static func locale(for key: String?) -> Locale {
        let map = ["es": "es-ES", "it": "it-IT", "ja": "ja-JP", "de": "de-DE", "fr": "fr-FR", "pt": "pt-BR",
                   "en": "en-US", "ru": "ru-RU", "zh": "zh-CN", "ko": "ko-KR", "nl": "nl-NL", "sv": "sv-SE",
                   "pl": "pl-PL", "tr": "tr-TR", "ar": "ar-SA", "hi": "hi-IN", "el": "el-GR", "sr": "sr-RS"]
        guard let key, !key.hasPrefix("x-") else { return Locale.current }
        return Locale(identifier: map[key] ?? key)
    }

    /// Call when the input bar appears (cheap; the audio work runs off the main thread).
    func prepare(language key: String?) {
        _ = recognizer(for: key)
        audio.warmUp()
    }

    private func recognizer(for key: String?) -> SFSpeechRecognizer? {
        let id = Self.locale(for: key).identifier
        if let r = recognizers[id] { return r }
        let r = SFSpeechRecognizer(locale: Locale(identifier: id))
        r?.defaultTaskHint = .dictation
        recognizers[id] = r
        return r
    }

    private var permissionsGranted: Bool {
        SFSpeechRecognizer.authorizationStatus() == .authorized && AVAudioApplication.shared.recordPermission == .granted
    }

    func press(language key: String?, onText: @escaping (String) -> Void) {
        t0 = CFAbsoluteTimeGetCurrent()
        log("press")
        held = true
        cancelTask()
        if permissionsGranted {
            begin(language: key, onText: onText)
        } else {
            Task { await askThenStart(language: key, onText: onText) }
        }
    }

    /// Stops listening; the recogniser still delivers the last words, then finishes.
    func release() {
        log("release")
        held = false
        guard isRecording else { return }
        isRecording = false
        Haptics.recordStop()
        let req = request
        audio.stop { req?.endAudio() }
    }

    private func askThenStart(language key: String?, onText: @escaping (String) -> Void) async {
        error = nil
        let speechOK = await withCheckedContinuation { c in
            SFSpeechRecognizer.requestAuthorization { c.resume(returning: $0 == .authorized) }
        }
        let micOK = await AVAudioApplication.requestRecordPermission()
        guard speechOK, micOK else {
            error = L("Allow Microphone and Speech Recognition in Settings to dictate.")
            return
        }
        // The first time, the permission alerts take the touch — the user lifts their finger meanwhile.
        guard held else { return }
        begin(language: key, onText: onText)
    }

    private func begin(language key: String?, onText: @escaping (String) -> Void) {
        error = nil
        guard let recognizer = recognizer(for: key), recognizer.isAvailable else {
            error = L("Dictation isn't available for this language on your iPhone.")
            return
        }
        generation += 1
        let gen = generation
        gotFirstWords = false

        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        req.taskHint = .dictation
        let onDevice = recognizer.supportsOnDeviceRecognition
        if onDevice { req.requiresOnDeviceRecognition = true }
        request = req
        log("recogniser \(recognizer.locale.identifier), on-device: \(onDevice)")

        task = recognizer.recognitionTask(with: req) { [weak self] result, err in
            let text = result?.bestTranscription.formattedString
            let final = result?.isFinal == true
            Task { @MainActor in
                guard let self, gen == self.generation else { return }
                if let text {
                    if !self.gotFirstWords { self.gotFirstWords = true; self.log("first words") }
                    onText(text)
                }
                if err != nil || final {
                    self.log(final ? "final" : "ended: \(err?.localizedDescription ?? "")")
                    if self.isRecording { self.release() }
                    self.task = nil
                    self.request = nil
                }
            }
        }

        audio.start(feeding: req) { [weak self] err in
            DispatchQueue.main.async {
                guard let self, gen == self.generation else { return }
                if let err {
                    self.error = err.localizedDescription
                    self.log("audio failed: \(err.localizedDescription)")
                    self.cancelTask()
                    return
                }
                self.log("mic listening")
                self.isRecording = true   // the button already vibrated on touch-down
                // Released while the mic was starting.
                if !self.held { self.release() }
            }
        }
    }

    /// Drops any recognition still finishing from a previous recording.
    private func cancelTask() {
        task?.cancel()
        task = nil
        request = nil
        if isRecording {
            isRecording = false
            audio.stop()
        }
    }

    /// Send: stop at once; late words must not refill the field.
    func stop() {
        held = false
        generation += 1
        if isRecording { isRecording = false; audio.stop() }
        request?.endAudio()
        task?.cancel()
        task = nil
        request = nil
    }

    /// Leaving the chat: stop everything and give the audio back to other apps.
    func shutdown() {
        stop()
        audio.deactivate()
    }
}
