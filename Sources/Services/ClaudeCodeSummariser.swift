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
    struct ConclusionSummary {
        @Guide(description: "One short sentence capturing the essence of what was reported. Plain text, no markdown, no trailing period is fine either way.")
        var headline: String

        @Guide(description: "0 to 5 short bullet points with the concrete specifics (what changed, what was found, file names, errors) — omit entirely if the headline already says it all.", .count(0...5))
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

    /// - Parameter conclusion: the text from `ClaudeCodeRecogniser.lastConclusion`.
    static func summarise(_ conclusion: String) async throws -> ConclusionSummary {
        guard isAvailable else {
            throw SummariserError.unavailable(unavailabilityReason())
        }
        // A one- or two-word tail ("Done.") isn't worth a model round trip,
        // and guided generation on near-empty input is where small models are
        // most likely to pad with invented specifics.
        guard conclusion.trimmingCharacters(in: .whitespacesAndNewlines).count > 12 else {
            throw SummariserError.tooShort
        }

        let session = LanguageModelSession(instructions: instructions)
        do {
            let response = try await session.respond(
                to: "Here is what the assistant just reported:\n\n\(conclusion)",
                generating: ConclusionSummary.self
            )
            return response.content
        } catch {
            // `isAvailable` above only means the model is *nominally* ready —
            // generation can still fail for reasons outside that check. The
            // one actually observed: Simulator without the on-device model
            // provisioned throws a deeply nested ModelManagerError. Surface a
            // plain sentence rather than that raw NSError chain.
            throw SummariserError.generationFailed
        }
    }

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
