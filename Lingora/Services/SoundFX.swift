import AVFoundation

/// Short right / wrong / done sounds, synthesised at launch (no audio files to ship).
@MainActor
enum SoundFX {
    enum Kind { case right, wrong, done }
    private static var players: [Kind: AVAudioPlayer] = [:]
    static var enabled = true

    static func play(_ k: Kind) {
        guard enabled else { return }
        if players[k] == nil, let p = try? AVAudioPlayer(data: wav(k)) { p.volume = 0.55; p.prepareToPlay(); players[k] = p }
        players[k]?.currentTime = 0
        players[k]?.play()
    }

    /// Notes as (frequency Hz, seconds).
    private static func notes(_ k: Kind) -> [(Double, Double)] {
        switch k {
        case .right: [(784, 0.09), (1175, 0.16)]                    // G5 → D6
        case .wrong: [(311, 0.12), (233, 0.2)]                      // E♭4 → B♭3
        case .done: [(523, 0.1), (659, 0.1), (784, 0.1), (1047, 0.28)] // C major arpeggio
        }
    }

    private static func wav(_ k: Kind) -> Data {
        let rate = 44_100.0
        var samples: [Int16] = []
        for (f, dur) in notes(k) {
            let n = Int(rate * dur)
            for i in 0..<n {
                let t = Double(i) / rate
                let env = min(1, Double(i) / 400) * exp(-3.2 * t / dur)   // soft attack, decay
                let v = (sin(2 * .pi * f * t) + 0.25 * sin(4 * .pi * f * t)) * env * 0.6
                samples.append(Int16(max(-1, min(1, v)) * Double(Int16.max)))
            }
        }
        var d = Data()
        func u32(_ v: UInt32) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }
        func u16(_ v: UInt16) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }
        let bytes = UInt32(samples.count * 2)
        d.append(contentsOf: Array("RIFF".utf8)); u32(36 + bytes); d.append(contentsOf: Array("WAVE".utf8))
        d.append(contentsOf: Array("fmt ".utf8)); u32(16); u16(1); u16(1); u32(44_100); u32(88_200); u16(2); u16(16)
        d.append(contentsOf: Array("data".utf8)); u32(bytes)
        samples.withUnsafeBytes { d.append(contentsOf: $0) }
        return d
    }
}
