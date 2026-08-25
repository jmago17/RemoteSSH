// summarise-turn — condensa el mensaje final de un agente en una linea, para
// que quepa en el cuerpo de una notificacion.
//
// Lee el texto por stdin y escribe el resumen por stdout. Si algo va mal, no
// escribe nada y sale con codigo != 0: quien lo llama debe quedarse entonces
// con el texto original recortado. Un resumidor NUNCA debe ser la razon de que
// no llegue un aviso.
//
// Corre en el MAC, dentro del hook, y no en el iPhone. El Mac es quien tiene el
// texto completo antes de mandar el push, no tiene los limites de memoria de
// una extension de notificacion, y asi el resumen viaja ya hecho dentro del
// campo `message` — sin necesidad de APNs propio ni de una NSE.
//
// Compilar:
//   xcrun swiftc -swift-version 6 -O scripts/summarise-turn.swift \
//     -o ~/.claude/hooks/summarise-turn
import Foundation
import FoundationModels

let maxCharacters = 170
let deadlineSeconds: Double = 8

// Autolimite duro. El hook corre en la ruta critica de un aviso: mas vale un
// mensaje sin resumir que un aviso que llega tarde o no llega.
DispatchQueue.global().asyncAfter(deadline: .now() + deadlineSeconds) { exit(2) }

/// Recorta sin partir palabras. El modelo respeta el limite casi siempre, pero
/// cuando se pasa un `prefix` a pelo deja cosas como "se reconocieran correc",
/// que parece que la notificacion se ha roto.
func clipped(_ s: String) -> String {
    guard s.count > maxCharacters else { return s }
    let cut = String(s.prefix(maxCharacters - 1))
    guard let lastSpace = cut.lastIndex(of: " "), cut.distance(from: cut.startIndex, to: lastSpace) > maxCharacters / 2 else {
        return cut + "…"
    }
    return cut[cut.startIndex..<lastSpace].trimmingCharacters(in: .punctuationCharacters.union(.whitespaces)) + "…"
}

let input = String(data: FileHandle.standardInput.readDataToEndOfFile(), encoding: .utf8) ?? ""
let text = input.trimmingCharacters(in: .whitespacesAndNewlines)

// Demasiado corto para ganar nada: ya cabe.
guard text.count > maxCharacters else {
    print(text)
    exit(text.isEmpty ? 1 : 0)
}
guard case .available = SystemLanguageModel.default.availability else { exit(3) }

let instructions = """
Resumes en español lo que acaba de hacer un agente de programación, para el \
cuerpo de una notificación del móvil.

Reglas:
- UNA sola frase, menos de \(maxCharacters - 25) caracteres.
- Empieza por el verbo en pasado. Nada de "El agente…", nada de preámbulos.
- Concreta: qué tocó y con qué resultado. Nada de "ha completado la tarea".
- Sin markdown, sin comillas, sin viñetas, sin emoji.
"""

do {
    let session = LanguageModelSession(instructions: instructions)
    let response = try await session.respond(
        to: text,
        // Greedy para que el mismo turno se resuma igual dos veces: el aviso se
        // reintenta y una notificación que cambia de texto sola parece un bug.
        options: GenerationOptions(sampling: .greedy, maximumResponseTokens: 90)
    )
    let summary = response.content
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .replacingOccurrences(of: "\n", with: " ")
    guard !summary.isEmpty else { exit(4) }
    print(clipped(summary))
} catch {
    FileHandle.standardError.write(Data("summarise-turn: \(error)\n".utf8))
    exit(5)
}
