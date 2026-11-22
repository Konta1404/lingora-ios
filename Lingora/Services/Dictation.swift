import Foundation
import Speech
import AVFoundation

/// Live speech-to-text in the language being practised (Speech framework, on-device when available).
@MainActor
final class Dictation: ObservableObject {
    @Published private(set) var isRecording = false
    @Published var error: String?

    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?

    /// Maps Lingora language keys to speech locales.
    static func locale(for key: String?) -> Locale {
        let map = ["es": "es-ES", "it": "it-IT", "ja": "ja-JP", "de": "de-DE", "fr": "fr-FR", "pt": "pt-BR",
                   "en": "en-US", "ru": "ru-RU", "zh": "zh-CN", "ko": "ko-KR", "nl": "nl-NL", "sv": "sv-SE",
                   "pl": "pl-PL", "tr": "tr-TR", "ar": "ar-SA", "hi": "hi-IN", "el": "el-GR", "sr": "sr-RS"]
        guard let key, !key.hasPrefix("x-") else { return Locale.current }
        return Locale(identifier: map[key] ?? key)
    }

    func toggle(language key: String?, prefix: String, onText: @escaping (String) -> Void) {
        if isRecording { stop() } else { Task { await start(language: key, prefix: prefix, onText: onText) } }
    }

    func start(language key: String?, prefix: String, onText: @escaping (String) -> Void) async {
        error = nil
        let speechOK = await withCheckedContinuation { c in
            SFSpeechRecognizer.requestAuthorization { c.resume(returning: $0 == .authorized) }
        }
        let micOK = await AVAudioApplication.requestRecordPermission()
        guard speechOK, micOK else {
            error = L("Allow Microphone and Speech Recognition in Settings to dictate.")
            return
        }
        guard let recognizer = SFSpeechRecognizer(locale: Self.locale(for: key)), recognizer.isAvailable else {
            error = L("Dictation isn't available for this language on your iPhone.")
            return
        }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
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

            let base = prefix.isEmpty || prefix.hasSuffix(" ") ? prefix : prefix + " "
            task = recognizer.recognitionTask(with: req) { [weak self] result, err in
                Task { @MainActor in
                    guard let self else { return }
                    if let result { onText(base + result.bestTranscription.formattedString) }
                    if err != nil || result?.isFinal == true { self.stop() }
                }
            }
        } catch {
            self.error = error.localizedDescription
            stop()
        }
    }

    func stop() {
        guard isRecording || task != nil else { return }
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        task?.finish()
        task = nil
        request = nil
        isRecording = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
