import AVFoundation
import Combine
import Speech
import SwiftUI

// MARK: - Speaking an amount
//
// Typing a number is already fast; saying one is faster, and it's the
// difference between logging a coffee while walking and deciding not to bother.
//
// The privacy constraint shapes the whole implementation. `SFSpeechRecognizer`
// will happily stream audio to Apple's servers for transcription, and for an
// app whose first promise is "nothing leaves your phone" that would be a lie
// told in the one place it costs most. So:
//
// * `requiresOnDeviceRecognition` is forced on, always.
// * If the device can't do on-device recognition for the current locale, the
//   feature refuses to run rather than silently falling back to the network.
// * The microphone is live only while the button is held down, and the audio
//   buffer is never written anywhere.

@MainActor
final class VoiceAmountListener: ObservableObject {

    enum State: Equatable {
        case idle
        case listening
        /// Something stopped it. Carries a line fit to show the user.
        case unavailable(String)
    }

    @Published private(set) var state: State = .idle
    /// What's been heard so far, for live feedback while speaking.
    @Published private(set) var transcript = ""
    /// The number found in the transcript, if there is one yet.
    @Published private(set) var amount: Double?
    /// Whatever was said that wasn't the number — usually the place.
    @Published private(set) var remainder = ""

    private let recognizer = SFSpeechRecognizer(locale: .current)
    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?

    var isListening: Bool { state == .listening }

    /// Whether it's worth offering the button at all. False on a device or in a
    /// locale with no on-device model, since we won't use the network one.
    var isSupported: Bool {
        guard let recognizer else { return false }
        return recognizer.isAvailable && recognizer.supportsOnDeviceRecognition
    }

    // MARK: Control

    func start() async {
        guard state != .listening else { return }
        transcript = ""
        amount = nil
        remainder = ""

        guard let recognizer, recognizer.supportsOnDeviceRecognition else {
            state = .unavailable("This device can't transcribe speech without sending it away, so this is switched off.")
            return
        }
        guard await requestPermissions() else {
            state = .unavailable("Microphone and speech access are needed for this. You can turn them on in Settings.")
            return
        }

        do {
            try beginListening(with: recognizer)
            state = .listening
            Haptics.selected()
        } catch {
            state = .unavailable("Couldn't start listening just now.")
            teardown()
        }
    }

    func stop() {
        guard state == .listening else { return }
        teardown()
        state = .idle
    }

    // MARK: Plumbing

    private func requestPermissions() async -> Bool {
        let speech = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
        guard speech == .authorized else { return false }

        return await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { continuation.resume(returning: $0) }
        }
    }

    private func beginListening(with recognizer: SFSpeechRecognizer) throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement, options: .duckOthers)
        try session.setActive(true, options: .notifyOthersOnDeactivation)

        let request = SFSpeechAudioBufferRecognitionRequest()
        // The whole reason this feature is allowed to exist.
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = true
        self.request = request

        let input = engine.inputNode
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: input.outputFormat(forBus: 0)) {
            buffer, _ in
            request.append(buffer)
        }

        engine.prepare()
        try engine.start()

        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }
            Task { @MainActor in
                if let result {
                    self.consume(result.bestTranscription.formattedString)
                }
                if error != nil || result?.isFinal == true {
                    self.stop()
                }
            }
        }
    }

    private func consume(_ heard: String) {
        transcript = heard
        let parsed = VoiceAmountParser.parse(heard)
        if let value = parsed.amount { amount = value }
        remainder = parsed.remainder
    }

    private func teardown() {
        engine.inputNode.removeTap(onBus: 0)
        if engine.isRunning { engine.stop() }
        request?.endAudio()
        task?.cancel()
        request = nil
        task = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}

// MARK: - Reading a number out of a sentence

/// Pulls an amount, and whatever else was said, out of a spoken phrase.
///
/// Speech recognition is inconsistent about numbers — "twelve fifty" can come
/// back as `12.50`, `12 50`, or `twelve fifty` depending on the phrase and the
/// device. All three have to work, because a user who says the same thing twice
/// and gets different results stops trusting the button.
enum VoiceAmountParser {

    static func parse(_ phrase: String) -> (amount: Double?, remainder: String) {
        let cleaned = phrase.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return (nil, "") }

        if let digits = digitAmount(in: cleaned) { return digits }
        if let words = spelledAmount(in: cleaned) { return words }
        return (nil, strippedOfFillers(cleaned))
    }

    /// "12.50", "$12.50", "12 50" (which is how "twelve fifty" often arrives).
    ///
    /// One regex over the whole phrase rather than a second pass for the pence,
    /// so every range stays in the phrase's own coordinates — computing a range
    /// inside a substring and mapping it back is where this went wrong the
    /// first time, and it left the pence sitting in the leftover text.
    private static func digitAmount(in phrase: String) -> (Double?, String)? {
        // whole part, then either a written decimal, or a separate two-digit
        // group spoken as pence. `(?!\d)` stops "12 500" folding into 12.50.
        let pattern = #"(\d+)(?:[.,](\d{1,2}))?(?:\s+(\d{2})(?!\d))?"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: phrase,
                                           range: NSRange(phrase.startIndex..., in: phrase)),
              let whole = group(1, in: match, of: phrase)
        else { return nil }

        let written = group(2, in: match, of: phrase)
        let spoken = group(3, in: match, of: phrase)
        // A separately-spoken pence group only counts when no decimal was
        // written; "12.50 30" is two numbers, not twelve pounds fifty-thirty.
        let fraction = written ?? (written == nil ? spoken : nil)

        let text = fraction.map { "\(whole).\($0)" } ?? whole
        guard let value = Double(text), value > 0 else { return nil }

        guard let consumed = Range(match.range, in: phrase) else { return nil }
        var leftover = phrase
        leftover.removeSubrange(consumed)
        return (value, strippedOfFillers(leftover))
    }

    private static func group(_ index: Int, in match: NSTextCheckingResult,
                              of phrase: String) -> String? {
        guard let range = Range(match.range(at: index), in: phrase) else { return nil }
        return String(phrase[range])
    }

    /// "twelve", "twenty-five" — whatever `NumberFormatter` can read back.
    ///
    /// Multi-word candidates are only accepted **hyphenated**, and that
    /// restriction is load-bearing. Given "twenty five" spelled out with a
    /// space, `NumberFormatter` returns 2005; given "twelve fifty" it returns
    /// 1250 when the speaker plainly meant 12.50. Both are hundredfold errors
    /// on somebody's money, arrived at silently. Refusing to guess is the only
    /// safe answer — the transcript is on screen, and typing four digits beats
    /// discovering next month that a coffee went in as twelve hundred.
    private static func spelledAmount(in phrase: String) -> (Double?, String)? {
        let formatter = NumberFormatter()
        formatter.numberStyle = .spellOut
        formatter.locale = .current

        let words = phrase.split(separator: " ").map(String.init)
        guard !words.isEmpty else { return nil }

        // Longest run first, so "twenty-five" beats "twenty". Four words is
        // enough for "one hundred and five"; longer runs simply fail to parse
        // and fall through, so the cap costs nothing but time.
        for length in stride(from: min(words.count, 4), through: 1, by: -1) {
            for start in 0...(max(0, words.count - length)) {
                guard start + length <= words.count else { continue }
                let run = words[start..<(start + length)]
                    .map { $0.trimmingCharacters(in: .punctuationCharacters).lowercased() }
                guard !run.contains(where: \.isEmpty) else { continue }

                // Both spellings have to be tried: "twenty-five" only parses
                // hyphenated, "one hundred" only parses spaced. The round-trip
                // check below is what makes accepting the spaced form safe.
                let forms = length == 1
                    ? [run[0]]
                    : [run.joined(separator: "-"), run.joined(separator: " ")]

                guard let number = forms.lazy.compactMap({ form -> NSNumber? in
                    guard let parsed = formatter.number(from: form),
                          parsed.doubleValue > 0,
                          parsed.doubleValue == parsed.doubleValue.rounded(),
                          parsed.doubleValue < 1_000_000,
                          roundTrips(parsed, from: form, using: formatter)
                    else { return nil }
                    return parsed
                }).first
                else { continue }

                var rest = words
                rest.removeSubrange(start..<(start + length))
                var value = number.doubleValue

                // "twelve fifty" is 12.50, not twelve with the word "fifty"
                // left over. It only reaches here when the hyphenated form
                // failed, which is exactly the case where the two words are a
                // pounds-and-pence pair rather than a single number.
                //
                // Restricted to a following value of 10–99 on purpose: "twelve
                // five" could be 12.05 or 12.50 and there's no way to tell, so
                // it's left alone rather than guessed at.
                let next = start + length
                if next < words.count,
                   let pence = formatter.number(
                       from: words[next].trimmingCharacters(in: .punctuationCharacters).lowercased()
                   )?.doubleValue,
                   pence >= 10, pence <= 99, pence == pence.rounded() {
                    value += pence / 100
                    rest.removeAll { $0 == words[next] }
                }

                return (value, strippedOfFillers(rest.joined(separator: " ")))
            }
        }
        return nil
    }

    /// Drops the scaffolding words people say around an amount, so the leftover
    /// is a usable place name rather than "dollars at".
    private static let fillers: Set<String> = [
        "dollars", "dollar", "pounds", "pound", "euros", "euro", "bucks",
        "quid", "cents", "pence", "p", "at", "on", "for", "in", "to", "from",
        "spent", "spend", "log", "add", "a", "an", "the", "and", "of", "please",
    ]

    /// Whether spelling the parsed number back out reproduces what was said.
    ///
    /// This is the guard that makes reading multi-word numbers safe.
    /// `NumberFormatter` will cheerfully turn "twenty five" into 2005 and
    /// "twelve fifty" into 1250 by running the words together, and both are
    /// hundredfold errors on money. Spelling the answer back catches every one
    /// of them: 2005 reads as "two thousand five", which is not what was said,
    /// so it's rejected — while 100 reads back as "one hundred", which is.
    private static func roundTrips(_ number: NSNumber, from candidate: String,
                                   using formatter: NumberFormatter) -> Bool {
        guard let spelled = formatter.string(from: number) else { return false }
        return normalise(spelled) == normalise(candidate)
    }

    private static func normalise(_ text: String) -> String {
        text.lowercased()
            .replacingOccurrences(of: "-", with: " ")
            .components(separatedBy: .whitespaces)
            .filter { !$0.isEmpty && $0 != "and" }
            .joined(separator: " ")
    }

    /// Currency marks left behind once the number is lifted out — "$12.50"
    /// leaves a stray "$" that would otherwise become part of the place name.
    private static let symbols = CharacterSet(charactersIn: "$£€¥₹,")

    static func strippedOfFillers(_ text: String) -> String {
        let kept = text
            .components(separatedBy: CharacterSet.whitespacesAndNewlines)
            .map { $0.trimmingCharacters(in: symbols) }
            .filter { word in
                let bare = word.trimmingCharacters(in: .punctuationCharacters).lowercased()
                return !bare.isEmpty && !fillers.contains(bare)
            }
        return kept.joined(separator: " ").trimmingCharacters(in: .whitespaces)
    }
}
