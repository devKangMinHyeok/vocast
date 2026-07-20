import Foundation

/// What a paragraph of script looks like, language-wise.
enum ParagraphLanguage: Equatable {
    case korean
    case english
    /// Both scripts in meaningful amounts. This is the normal shape of Korean
    /// technical writing ("이 API를 사용하면...") and is never treated as a problem.
    case mixed
    /// Too little text to judge. Not a verdict, so it never flags.
    case undecided
}

enum ScriptLanguage {

    /// Decide a paragraph's language from the Hangul to Latin ratio.
    ///
    /// The thresholds leave a wide middle band on purpose. An inline English term
    /// inside a Korean sentence lands in `mixed`, and mixed never flags, so the
    /// common case stays quiet. Only a paragraph genuinely dominated by the other
    /// language reaches a verdict that can disagree with the voice.
    static func of(_ text: String) -> ParagraphLanguage {
        var hangul = 0, latin = 0
        for scalar in text.unicodeScalars {
            if (0xAC00...0xD7A3).contains(scalar.value) { hangul += 1 }
            else if ("A"..."Z").contains(Character(scalar)) || ("a"..."z").contains(Character(scalar)) { latin += 1 }
        }
        let total = hangul + latin
        guard total >= 4 else { return .undecided }
        let ratio = Double(hangul) / Double(total)
        if ratio >= 0.7 { return .korean }
        if ratio <= 0.15 { return .english }
        return .mixed
    }

    /// Split a script the way the engine does, on blank lines.
    static func paragraphs(_ script: String) -> [String] {
        script.components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    /// True when this paragraph is written in a language the voice does not speak.
    /// Undecided and mixed paragraphs are never a mismatch.
    static func mismatches(_ paragraph: String, voice: VoiceLanguage) -> Bool {
        switch of(paragraph) {
        case .korean:  return voice != .ko
        case .english: return voice != .en
        case .mixed, .undecided: return false
        }
    }

    /// The other language, for the "looks like X but speaks Y" copy.
    static func detected(_ paragraph: String) -> VoiceLanguage? {
        switch of(paragraph) {
        case .korean:  return .ko
        case .english: return .en
        case .mixed, .undecided: return nil
        }
    }
}

/// What the Studio should say about the script as a whole.
enum ScriptAdvice: Equatable {
    /// Nothing to say. Quiet is the default.
    case none
    /// Every paragraph matches, and at least one mixes scripts. Worth one calm line
    /// of reassurance so the user does not wonder whether mixing was a mistake.
    case mixedIsFine
    /// At least one whole paragraph is in a language the voice cannot speak.
    case mismatch(detected: VoiceLanguage)

    /// Read the script against the voice. Never blocks anything; this only decides
    /// which note, if any, sits above the editor.
    static func of(script: String, voice: VoiceLanguage) -> ScriptAdvice {
        let paras = ScriptLanguage.paragraphs(script)
        guard !paras.isEmpty else { return .none }
        for p in paras where ScriptLanguage.mismatches(p, voice: voice) {
            if let d = ScriptLanguage.detected(p) { return .mismatch(detected: d) }
        }
        let hasMixed = paras.contains { ScriptLanguage.of($0) == .mixed }
        return hasMixed ? .mixedIsFine : .none
    }
}
