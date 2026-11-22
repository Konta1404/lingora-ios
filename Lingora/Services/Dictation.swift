import Foundation
import Speech
import AVFoundation

/// Live speech-to-text in the language being practised (Speech framework, on-device when available).
/// Hold-to-talk: `press` starts recording, `release` stops it and keeps the final words.
@MainActor
final class Dictation: ObservableObject {
    @Published private(set) var isRecording = false
    @Published var error: String?

    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    /// False once the finger lifts — also covers a release while permissions are still being asked.
    private var held = false

    /// Maps Lingora language keys to speech locales.
    static func locale(for key: String?) -> Locale {
        let map = ["es": "es-ES", "it": "it-IT", "ja": "ja-JP", "de": "de-DE", "fr": "fr-FR", "pt": "pt-BR",
                   "en": "en-US", "ru": "ru-RU", "zh": "zh-CN", "ko": "ko-KR", "nl": "nl-NL", "sv": "sv-SE",
                   "pl": "pl-PL", "tr": "tr-TR", "ar": "ar-SA", "hi": "hi-IN", "el": "el-GR", "sr": "sr-RS"]
        guard let key, !key.hasPrefix("x-") else { return Locale.current }
        return Locale(identifier: map[key] ?? key)
    }

    func press(language key: String?, onText: @escaping (String) -> Void) {
        held = true
        cancel()
        Task { await start(language: key, onText: onText) }
    }

    /// Stops listening; the recogniser still delivers the last words, then finishes.
    func release() {
        held = false
        guard isRecording else { return }
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        isRecording = false
        Haptics.recordStop()
        deactivateSession()
    }

    private func start(language key: String?, onText: @escaping (String) -> Void) async {
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
        guard let recognizer = SFSpeechRecognizer(locale: Self.locale(for: key)), recognizer.isAvailable else {
            error = L("Dictation isn't available for this language on your iPhone.")
            return
        }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            // iOS mutes vibrations while the mic records unless this is allowed.
            try? session.setAllowHapticsAndSystemSoundsDuringRecording(true)
            try session.setActive(true, options: .notifyOthersOnDeactivation)

            let req = SFSpeechAudioBufferRecognitionRequest()
            req.shouldReportPartialResults = true
            if recognizer.supportsOnDeviceRecognition { req.requiresOnDeviceRecognition = true }
            request = req

            let input = engine.inputNode
            input.removeTap(onBus: 0)
            input.installTap(onBus: 0, bufferSize: 1024, format: input.outputFormat(forBus: 0)) { [weak req] buf, _ in
                req?.append(buf)
            }
            engine.prepare()
            try engine.start()
            isRecording = true
            Haptics.recordStart()

            task = recognizer.recognitionTask(with: req) { [weak self] result, err in
                Task { @MainActor in
                    guard let self else { return }
                    if let result { onText(result.bestTranscription.formattedString) }
                    if err != nil || result?.isFinal == true {
                        if self.isRecording { self.release() }
                        self.task = nil
                        self.request = nil
                    }
                }
            }
            // Released while the engine was starting.
            if !held { release() }
        } catch {
            self.error = error.localizedDescription
            release()
        }
    }

    /// Drops any recognition still finishing from a previous recording.
    private func cancel() {
        task?.cancel()
        task = nil
        request = nil
        if isRecording {
            engine.stop()
            engine.inputNode.removeTap(onBus: 0)
            isRecording = false
        }
    }

    func stop() {
        held = false
        release()
        task?.cancel()   // after Send, late words must not refill the field
        task = nil
        request = nil
    }

    private func deactivateSession() {
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
