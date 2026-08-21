import Foundation
import FoundationModels

/// Turns Claude Code's just-finished conclusion into a short, skimmable card
/// using the on-device Apple Intelligence model.
///
/// **Why summarise at all.** The raw pane already shows the conclusion
/// verbatim — this doesn't replace that, it sits above it. The point is the
/// phone-sized case: you glance at the app, see the working→idle transition
/// happened, and want the *gist* in two seconds without reading a paragraph
/// of prose that was written for a terminal, not a screen this size.
///
/// **Why on-device Apple Intelligence and not a bigger model.** This project
/// already talks to a real LLM over SSH (Claude Code itself) — piping its
/// own output through a *second*, cloud, subscription-gated model to
/// summarise would be an odd and heavy dependency for "shorten this
/// paragraph". `FoundationModels` is free, local, and iOS 26+ already matches
/// this app's deployment target.
///
/// **Why this must never invent.** A summary that hallucinates a result Claude
/// Code didn't actually report is worse than no summary — the whole app's
/// design principle (`TranscriptParser`, `ClaudeCodeRecogniser`) is "degrade
/// honestly rather than guess wrong". The instructions below say so bluntly,
/// and `ConclusionSummary` is intentionally *not* a pass/fail verdict field:
/// the model is not asked to judge success, only to compress what was said.
enum ClaudeCodeSummariser {

    /// A short card: one headline plus a handful of bullet points, whichever
    /// reads better for the specific conclusion — a guided type rather than
    /// parsed markdown, so there's no "did it forget to bullet one line" risk.
    @Generable(description: "A short, skimmable summary of what an AI coding assistant just reported, for someone glancing at their phone.")
    struct ConclusionSummary: Codable {
        @Guide(description: "One short sentence capturing the essence of what was reported. Plain text, no markdown, no trailing period is fine either way.")
        var headline: String

        // Three, not five. Every bullet is tokens generated one at a time on
        // the Neural Engine, and the tail bullets were where the model padded
        // — the fourth and fifth restated the headline more often than they
        // added a fact. Cutting them shortens the wait and sharpens the card.
        @Guide(description: "0 to 3 short bullet points with the concrete specifics (what changed, what was found, file names, errors) — omit entirely if the headline already says it all.", .count(0...3))
        var bullets: [String]
    }

    enum SummariserError: LocalizedError {
        case unavailable(String)
        case tooShort
        case generationFailed

        var errorDescription: String? {
            switch self {
            case .unavailable(let reason): return reason
            case .tooShort: return "Nothing substantial enough to summarise."
            case .generationFailed: return "Couldn't generate a summary right now."
            }
        }
    }

    /// `SystemLanguageModel.default.availability` is the documented way to
    /// check before ever creating a session — the alternative is discovering
    /// unavailability only after `respond` throws.
    static var isAvailable: Bool {
        SystemLanguageModel.default.availability == .available
    }

    // MARK: Latency

    /// Why this file works the way it does.
    ///
    /// The first version created a `LanguageModelSession` at the moment the
    /// summary was wanted and waited for the whole answer. That put three
    /// avoidable costs on the user's clock, all of them *after* the moment
    /// they started waiting:
    ///
    /// 1. Loading the on-device model.
    /// 2. Prefilling the instructions below — a fixed prefix, identical every
    ///    time, that has nothing to do with the text being summarised.
    /// 3. Generating every token before showing any of them.
    ///
    /// The input was never the problem, which is worth writing down because
    /// it is the obvious suspect: measured against a real Claude Code pane,
    /// `lastConclusion` returns about 1,600 characters — a few hundred tokens.
    /// The wait was the model warming up and then writing.
    ///
    /// So: warm a session up front (`prepare()`), while Claude Code is still
    /// working and nobody is waiting; stream the answer so the headline lands
    /// as soon as it exists; and cap how much the model may write.

    /// A session that has already paid for model load and instruction
    /// prefill, waiting to be used.
    ///
    /// Deliberately handed out **once**. `LanguageModelSession` accumulates a
    /// transcript, so reusing one across summaries would feed every previous
    /// conclusion back in as context — steadily slower, and with the previous
    /// session's text available to bleed into the next answer.
    @MainActor private static var warmed: LanguageModelSession?

    /// Warms a session for the *next* summary. Cheap to call repeatedly: it
    /// does nothing if one is already waiting, and nothing at all when Apple
    /// Intelligence isn't available on this device.
    ///
    /// Call it when Claude Code starts working — that's a window of seconds
    /// to minutes where the device is idle and the user is not waiting on us.
    @MainActor
    static func prepare() {
        guard isAvailable, warmed == nil else { return }
        let session = LanguageModelSession(instructions: instructions)
        // Includes the fixed prompt prefix, so the only thing left to prefill
        // when the real call arrives is the conclusion text itself.
        session.prewarm(promptPrefix: Prompt(promptPrefix))
        warmed = session
    }

    @MainActor
    private static func takeWarmedSession() -> LanguageModelSession {
        defer { warmed = nil }
        return warmed ?? LanguageModelSession(instructions: instructions)
    }

    /// Generation limit. The card is a headline plus at most three short
    /// bullets; anything beyond this is the model running on, and waiting for
    /// it costs the user real seconds.
    private static let responseTokenLimit = 220

    /// Defensive cap on input. Real conclusions measure ~1,600 characters, but
    /// `lastConclusion` falls back to "the last 40 lines" when it can't find a
    /// `⏺` marker, and 40 lines of a 240-column pane is a different order of
    /// magnitude. The tail is kept because the conclusion ends at the bottom.
    private static let inputCharacterLimit = 4000

    /// - Parameters:
    ///   - conclusion: the text from `ClaudeCodeRecogniser.lastConclusion`.
    ///   - onPartial: called on the main actor each time the model produces
    ///     more of the answer, so the card can fill in as it arrives rather
    ///     than sitting on a spinner until the last token.
    static func summarise(
        _ conclusion: String,
        onPartial: @escaping @MainActor (ConclusionSummary) -> Void = { _ in }
    ) async throws -> ConclusionSummary {
        guard isAvailable else {
            throw SummariserError.unavailable(unavailabilityReason())
        }
        // A one- or two-word tail ("Done.") isn't worth a model round trip,
        // and guided generation on near-empty input is where small models are
        // most likely to pad with invented specifics.
        let trimmed = conclusion.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > 12 else {
            throw SummariserError.tooShort
        }

        let session = await takeWarmedSession()
        // Whatever happens here, start warming the next one: the common case
        // is another command right after reading this card.
        defer { Task { @MainActor in prepare() } }

        let options = GenerationOptions(
            // Greedy is both the fastest sampling mode and the one that makes
            // the same conclusion summarise the same way twice — which matters
            // because `ChatSessionModel` caches by content digest, and a card
            // that silently rewords itself on a re-read reads as a bug.
            samplingMode: .greedy,
            maximumResponseTokens: responseTokenLimit
        )

        do {
            let stream = session.streamResponse(
                to: promptPrefix + String(trimmed.suffix(inputCharacterLimit)),
                generating: ConclusionSummary.self,
                options: options
            )

            var latest: ConclusionSummary.PartiallyGenerated?
            for try await snapshot in stream {
                latest = snapshot.content
                if let partial = assembled(snapshot.content) {
                    await onPartial(partial)
                }
            }

            guard let finished = latest.flatMap(assembled) else {
                throw SummariserError.generationFailed
            }
            return finished
        } catch {
            // `isAvailable` above only means the model is *nominally* ready —
            // generation can still fail for reasons outside that check. The
            // one actually observed: Simulator without the on-device model
            // provisioned throws a deeply nested ModelManagerError. Surface a
            // plain sentence rather than that raw NSError chain.
            throw SummariserError.generationFailed
        }
    }

    /// A partial snapshot is only worth showing once the headline exists —
    /// bullets without a headline would pop in above nothing.
    private static func assembled(_ partial: ConclusionSummary.PartiallyGenerated) -> ConclusionSummary? {
        guard let headline = partial.headline, !headline.isEmpty else { return nil }
        return ConclusionSummary(headline: headline, bullets: partial.bullets ?? [])
    }

    private static let promptPrefix = "Here is what the assistant just reported:\n\n"

    /// The instructions, written the same way the rest of this codebase's
    /// heuristics are documented: state the constraint, then say why, so a
    /// future edit doesn't casually relax the "don't invent" rule.
    private static let instructions = """
    You summarise status reports from an AI coding assistant (Claude Code) for \
    someone glancing at their phone, mid-task, on a small screen.

    Ground rules, in order of importance:
    1. Only report what is explicitly stated in the text you're given. Never \
       infer success, failure, or a verdict that isn't stated outright — if the \
       assistant didn't say a fix worked, don't say it worked either. Getting \
       this wrong is worse than a bland summary: it makes someone trust code \
       or a diagnosis that was never confirmed.
    2. Prefer concrete nouns over vague ones: a file name, an error message, a \
       count, a command — not "some issues" or "a few changes".
    3. Keep it short. This replaces two seconds of reading, not two minutes. \
       If the text is genuinely one simple fact, the headline alone is enough \
       and bullets should be empty — don't pad with filler bullets.
    4. Write in the same language as the source text (Spanish stays Spanish, \
       English stays English).
    5. No markdown syntax (no #, no **, no backticks) — this is rendered as \
       plain styled text, not markdown.
    """

    private static func unavailabilityReason() -> String {
        switch SystemLanguageModel.default.availability {
        case .unavailable(.deviceNotEligible):
            return "This device doesn't support Apple Intelligence."
        case .unavailable(.appleIntelligenceNotEnabled):
            return "Apple Intelligence is turned off in Settings."
        case .unavailable(.modelNotReady):
            return "The on-device model isn't ready yet (still downloading)."
        case .unavailable:
            return "Apple Intelligence isn't available right now."
        case .available:
            return "" // unreachable — guarded by isAvailable above
        }
    }
}
