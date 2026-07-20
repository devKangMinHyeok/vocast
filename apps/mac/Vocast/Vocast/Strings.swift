import Foundation

// MARK: - The two languages
//
// Vocast has two language concepts and they are independent. Keeping them apart is
// the whole point of this layer, so they are separate types rather than two String
// properties that could be assigned to each other by accident.
//
//   InterfaceLanguage  the language of the UI chrome. Pure presentation, one per
//                      install, changeable at any time with no restart. Changing it
//                      must never touch a voice profile.
//   VoiceLanguage      the language a cloned voice speaks. It drives the guided
//                      script and the Whisper transcription that becomes the clone's
//                      reference text, so it affects quality, not just wording. Set
//                      once, before recording, and immutable afterwards.

/// The language of the app UI. Presentation only.
enum InterfaceLanguage: String, CaseIterable, Identifiable {
    case en, ko
    var id: String { rawValue }

    /// Always shown in its own language, the way a language picker should read.
    var nativeName: String { self == .ko ? "한국어" : "English" }

    /// What the Mac is set to, falling back to English.
    static var systemDefault: InterfaceLanguage {
        (Locale.preferredLanguages.first ?? "en").hasPrefix("ko") ? .ko : .en
    }
}

/// The language a voice speaks. Chosen before recording, then locked.
enum VoiceLanguage: String, CaseIterable, Identifiable {
    case en, ko
    var id: String { rawValue }

    var nativeName: String { self == .ko ? "한국어" : "English" }

    /// Quality gates, golden fixtures and the human baseline were measured on Korean
    /// only. Anything else scores against a baseline that does not apply, so the
    /// scorecard hides those numbers instead of implying they mean something.
    var hasQualityBaseline: Bool { self == .ko }

    /// Profiles created before voices carried a language are read as Korean, which
    /// is what the engine assumed at the time.
    init(profileCode: String?) { self = profileCode == "en" ? .en : .ko }
}

// MARK: - String table
//
// Every user-facing string resolves through here, keyed by the interface language.
// Taken verbatim from the design handoff's string table so the copy stays the
// reviewed copy. English is sentence case with no exclamation marks or emoji;
// Korean is 해요체, plain and unhyped, with product and technical names left in
// Latin (Vocast, MCP, API).

struct Strings {
    let lang: InterfaceLanguage
    private let t: [String: String]

    init(_ lang: InterfaceLanguage) {
        self.lang = lang
        self.t = lang == .ko ? Strings.ko : Strings.en
    }

    /// Look up a key. Falls back to English, then to the key itself, so a missing
    /// translation degrades to readable text rather than an empty label.
    subscript(_ key: String) -> String {
        t[key] ?? Strings.en[key] ?? key
    }

    /// Fill `{a}` and `{b}` placeholders, used by the mismatch and baseline copy.
    func f(_ key: String, a: String = "", b: String = "") -> String {
        self[key].replacingOccurrences(of: "{a}", with: a)
                 .replacingOccurrences(of: "{b}", with: b)
    }

    /// A language's name as it should appear inside a sentence in the current UI
    /// language, which is not the same as its native name.
    func nameOf(_ v: VoiceLanguage) -> String {
        v == .ko ? self["langOfKorean"] : self["langOfEnglish"]
    }

    static let en: [String: String] = [
        "korean": "Korean", "english": "English",
        "langOfEnglish": "English", "langOfKorean": "Korean",

        "search": "Search", "library": "Library", "settings": "Settings",
        "offline1": "On this Mac, offline", "offline2": "Nothing leaves your device",
        "nStudio": "Studio", "nVoices": "Voices", "nDenoise": "Denoise", "nTasks": "Tasks",
        "subStudio": "Write, render, and narrate", "subVoices": "Clone and manage your voice",
        "subDenoise": "Clean up audio and video", "subTasks": "Running, queued, and done",
        "newNarration": "New narration", "newVoice": "New voice",
        "importAudio": "Import audio", "clearFinished": "Clear finished",

        "scriptPlaceholder": "Paste or write your script. Up to 20,000 characters.",
        "nothingYet": "Nothing yet.", "pasteSample": "Paste a sample script",
        "renderBlurb": "Render turns your script into editable paragraph blocks. Each block can be replayed, re-rendered, and scored on its own.",
        "renderNarration": "Render narration", "blocks": "Blocks", "karaoke": "Karaoke",
        "blocksTotal": "blocks", "totalSuffix": "total",
        "exportSel": "Export selection", "exportNarration": "Export narration",

        "yourVoices": "Your voices", "storedHere": "stored on this Mac",
        "newVoiceHint": "Record about 90 seconds of guided lines to clone your voice.",
        "createProfile": "Create a voice profile",
        "pickLangTitle": "What language will this voice speak?",
        "pickLangBody": "The guided lines and the transcription that trains the clone are written for this language. Choose before you record, it can't be changed afterwards.",
        "pickLangLocked": "Locked once recording starts. To use another language, create a new voice.",
        "startRecording": "Start recording", "changeLang": "Change",
        "readEachLine": "Read each line aloud in your normal speaking voice. About 90 seconds total.",
        "voiceLangLabel": "Voice language", "lineOf": "Line", "of": "of", "captured": "captured",
        "readThisLine": "Read this line", "focus": "Focus", "coach": "Coaching",
        "record": "Record", "stop": "Stop", "reRecord": "Re-record", "retake": "Retake",
        "nextLine": "Next line", "buildProfile": "Build profile",
        "grpKorean": "Korean voices", "grpEnglish": "English voices",
        "profiles": "profiles", "similarity": "Similarity",
        "baselineValidated": "baseline validated", "noBaselineYet": "no baseline yet",

        "mismatchTag": "Different language",
        "mismatchBanner": "This paragraph looks like {a}, but the voice speaks {b}. It will still render, quality may drop.",
        "mixedOk": "Mixed script is fine: {b} with the occasional {a} term reads normally.",
        "tryMismatch": "Try a script in another language",

        "noBaselineGate": "No quality baseline for {b} yet",
        "noBaselineBody": "Vocast has not validated a scoring baseline for {b}. Prosody scores are hidden rather than shown against a baseline that doesn't apply.",
        "measured": "measured", "hidden": "no baseline",
        "qualityScorecard": "Quality scorecard", "block": "block",
        "gatePass": "Passed quality gate",
        "qualityReport": "Quality report", "jobDetailT": "Job detail", "inspectorT": "Inspector",
        "hintStudio": "Render your script to see a quality scorecard for each block here.",
        "hintVoices": "Select a voice, or open a profile to see its versions and source clips.",
        "hintDenoise": "Import a file and run a cleanup to see the quality report here.",
        "hintGeneric": "Contextual detail appears here.",

        "setGeneral": "General", "setModels": "Models", "setAudio": "Audio",
        "setPrivacy": "Privacy", "setMcp": "MCP server", "setAbout": "About",
        "setLanguage": "Language", "setLangTitle": "Language",
        "setLangBlurb": "Set the interface language. Each voice keeps its own language, chosen when you create it.",
        "interfaceLanguage": "Interface language",
        "interfaceLangDetail": "The language of buttons, labels, and text in Vocast",
        "applyNow": "Applied immediately, no restart",
        "voiceLangSetting": "Voice languages",
        "voiceLangSettingDetail": "Set per voice when you create it, not here",
        "guaranteeNote": "Changing the interface language does not change any voice. Each voice keeps the language it was recorded in.",
        "obLangTitle": "Choose your language",
        "obLangBody": "This sets the language of the Vocast interface. You choose each voice's language later, when you create it.",
        "obLangHint": "Detected from macOS. You can change this anytime in Settings.",
        "continue": "Continue",
    ]

    static let ko: [String: String] = [
        "korean": "한국어", "english": "English",
        "langOfEnglish": "영어", "langOfKorean": "한국어",

        "search": "검색", "library": "라이브러리", "settings": "설정",
        "offline1": "이 맥에서, 오프라인", "offline2": "기기 밖으로 나가지 않아요",
        "nStudio": "스튜디오", "nVoices": "보이스", "nDenoise": "잡음 제거", "nTasks": "작업",
        "subStudio": "쓰고, 생성하고, 낭독하기", "subVoices": "목소리를 복제하고 관리하기",
        "subDenoise": "오디오와 영상 잡음 정리", "subTasks": "진행·대기·완료",
        "newNarration": "새 낭독", "newVoice": "새 목소리",
        "importAudio": "오디오 가져오기", "clearFinished": "완료 항목 정리",

        "scriptPlaceholder": "원고를 붙여넣거나 직접 쓰세요. 최대 20,000자.",
        "nothingYet": "아직 비어 있어요.", "pasteSample": "샘플 원고 붙여넣기",
        "renderBlurb": "생성하면 원고가 편집 가능한 문단 블록으로 나뉘어요. 블록마다 다시 재생·재생성하고 품질을 채점할 수 있어요.",
        "renderNarration": "낭독 생성", "blocks": "블록", "karaoke": "가라오케",
        "blocksTotal": "블록", "totalSuffix": "합계",
        "exportSel": "선택 내보내기", "exportNarration": "낭독 내보내기",

        "yourVoices": "내 목소리", "storedHere": "개 · 이 맥에 저장됨",
        "newVoiceHint": "안내 문장을 약 90초 낭독하면 목소리가 복제돼요.",
        "createProfile": "목소리 프로필 만들기",
        "pickLangTitle": "이 목소리는 어떤 언어로 말하나요?",
        "pickLangBody": "안내 문장과, 클론을 학습시키는 전사(轉寫)가 이 언어 기준으로 작성돼요. 녹음 전에 고르세요. 시작한 뒤에는 바꿀 수 없어요.",
        "pickLangLocked": "녹음을 시작하면 잠겨요. 다른 언어를 쓰려면 새 목소리를 만드세요.",
        "startRecording": "녹음 시작", "changeLang": "변경",
        "readEachLine": "평소 말하는 목소리로 각 문장을 소리 내어 읽어 주세요. 전체 약 90초예요.",
        "voiceLangLabel": "목소리 언어", "lineOf": "문장", "of": "/", "captured": "녹음됨",
        "readThisLine": "이 문장을 읽어 주세요", "focus": "초점", "coach": "코칭",
        "record": "녹음", "stop": "정지", "reRecord": "다시 녹음", "retake": "다시 하기",
        "nextLine": "다음 문장", "buildProfile": "프로필 빌드",
        "grpKorean": "한국어 목소리", "grpEnglish": "영어 목소리",
        "profiles": "개 프로필", "similarity": "유사도",
        "baselineValidated": "기준선 검증됨", "noBaselineYet": "기준선 없음",

        "mismatchTag": "다른 언어",
        "mismatchBanner": "이 문단은 {a}처럼 보이는데, 이 목소리는 {b}를 말해요. 생성은 되지만 품질이 떨어질 수 있어요.",
        "mixedOk": "섞인 표기는 괜찮아요. {b}에 {a} 용어가 가끔 섞이는 건 자연스럽게 읽혀요.",
        "tryMismatch": "다른 언어 원고로 시도해 보기",

        "noBaselineGate": "아직 {b} 품질 기준선이 없어요",
        "noBaselineBody": "Vocast가 {b}의 채점 기준선을 아직 검증하지 않았어요. 운율 점수는 맞지 않는 기준에 대보이는 대신 숨겨요.",
        "measured": "측정됨", "hidden": "기준선 없음",
        "qualityScorecard": "품질 스코어카드", "block": "블록",
        "gatePass": "품질 게이트 통과",
        "qualityReport": "품질 리포트", "jobDetailT": "작업 상세", "inspectorT": "인스펙터",
        "hintStudio": "원고를 생성하면 여기에 블록별 품질 스코어카드가 보여요.",
        "hintVoices": "목소리를 선택하거나 프로필을 열면 버전과 원본 클립을 볼 수 있어요.",
        "hintDenoise": "파일을 가져와 정리를 실행하면 여기에 품질 리포트가 보여요.",
        "hintGeneric": "맥락에 맞는 상세 정보가 여기에 보여요.",

        "setGeneral": "일반", "setModels": "모델", "setAudio": "오디오",
        "setPrivacy": "개인정보", "setMcp": "MCP 서버", "setAbout": "정보",
        "setLanguage": "언어", "setLangTitle": "언어",
        "setLangBlurb": "인터페이스 언어를 설정해요. 각 목소리는 만들 때 고른 자기 언어를 그대로 유지해요.",
        "interfaceLanguage": "인터페이스 언어",
        "interfaceLangDetail": "Vocast의 버튼·라벨·문구가 쓰는 언어예요",
        "applyNow": "즉시 적용, 재시작 없음",
        "voiceLangSetting": "목소리 언어",
        "voiceLangSettingDetail": "여기가 아니라, 목소리를 만들 때 각각 정해요",
        "guaranteeNote": "인터페이스 언어를 바꿔도 목소리는 바뀌지 않아요. 각 목소리는 녹음된 언어를 그대로 유지해요.",
        "obLangTitle": "언어를 선택하세요",
        "obLangBody": "Vocast 인터페이스의 언어를 정하는 설정이에요. 각 목소리의 언어는 나중에 만들 때 따로 골라요.",
        "obLangHint": "macOS에서 감지했어요. 설정에서 언제든 바꿀 수 있어요.",
        "continue": "계속",
    ]
}
