// apns-push — manda una notificacion a RemoteSSH desde el Mac, hablando con
// APNs directamente. Sin intermediarios.
//
// POR QUE NO HAY UN WORKER EN MEDIO
// ---------------------------------
// APNs solo exige dos cosas: HTTP/2 y un JWT ES256. El Mac tiene las dos
// (URLSession habla HTTP/2; CryptoKit firma P256), y el hook ya corre ahi. Un
// relay en la nube solo anadiria una pieza que mantener, un secreto que rotar y
// un punto de fallo — y obligaria a subir la clave .p8 a un tercero.
//
// POR QUE NO BASTABA CON EL PROVEEDOR DE PUSH QUE YA HABIA
// -------------------------------------------------------
// Con un servicio de terceros la notificacion pertenece a SU app, asi que el
// globo rojo aparece en el icono de esa app y no en el de RemoteSSH. Eso no es
// un campo que falte en su API: es una consecuencia de quien recibe el push.
// Para que el badge salga en el icono correcto, el push tiene que ser nuestro.
//
// CONFIGURACION (fuera del repo, que es publico)
//   ~/.remotessh/apns.json         {"key_id","team_id","key_path","bundle_id"}
//   ~/.remotessh/apns-token.json   {"token","environment"}   <- lo escribe la app
//
// USO
//   apns-push --session NAME --subtitle S --body B [--badge N] [--level active]
//
// Nunca sale con codigo != 0 por un fallo de red: quien llama debe poder caer
// a otro transporte sin tratarlo como error fatal.
import Foundation
import CryptoKit

// MARK: - Configuración

struct APNSConfig: Decodable {
    let keyID: String, teamID: String, keyPath: String, bundleID: String
    enum CodingKeys: String, CodingKey {
        case keyID = "key_id", teamID = "team_id", keyPath = "key_path", bundleID = "bundle_id"
    }
}

struct DeviceToken: Decodable {
    let token: String
    /// `sandbox` para builds de Xcode, `production` para TestFlight y App Store.
    ///
    /// **Es la causa numero uno de "no llega y no dice por que".** Un token de
    /// sandbox contra el host de produccion devuelve `BadDeviceToken`, asi que
    /// la app graba cual le corresponde en vez de dejarlo a la adivinanza:
    /// depende de como se firmo el binario, no de una preferencia.
    let environment: String
}

let home = FileManager.default.homeDirectoryForCurrentUser
func loadJSON<T: Decodable>(_ type: T.Type, at path: String) -> T? {
    let url = path.hasPrefix("/") ? URL(fileURLWithPath: path)
                                  : home.appending(path: path.replacingOccurrences(of: "~/", with: ""))
    guard let data = try? Data(contentsOf: url) else { return nil }
    return try? JSONDecoder().decode(type, from: data)
}

// MARK: - Argumentos

var args: [String: String] = [:]
var i = 1
let argv = CommandLine.arguments
while i + 1 < argv.count {
    if argv[i].hasPrefix("--") { args[String(argv[i].dropFirst(2))] = argv[i + 1]; i += 2 } else { i += 1 }
}

func fail(_ message: String, code: Int32 = 1) -> Never {
    FileHandle.standardError.write(Data("apns-push: \(message)\n".utf8))
    exit(code)
}

guard let session = args["session"] else { fail("falta --session") }
guard let config = loadJSON(APNSConfig.self, at: "~/.remotessh/apns.json") else {
    fail("no hay ~/.remotessh/apns.json", code: 3)
}
guard let device = loadJSON(DeviceToken.self, at: "~/.remotessh/apns-token.json") else {
    // Normal hasta que la app se registre por primera vez. No es un error del
    // que haya que quejarse a gritos.
    fail("todavia no hay token de dispositivo", code: 4)
}

// MARK: - JWT

/// APNs pide un JWT ES256 firmado con la clave .p8. Apple exige renovarlo al
/// menos cada hora y **no mas de una vez cada 20 minutos**, asi que se cachea en
/// disco: un hook es un proceso efimero y sin cache firmaria uno por aviso.
func bearerToken(_ config: APNSConfig) throws -> String {
    let cacheURL = home.appending(path: ".remotessh/apns-jwt.json")
    struct Cached: Codable { let jwt: String; let issued: Double }
    if let data = try? Data(contentsOf: cacheURL),
       let cached = try? JSONDecoder().decode(Cached.self, from: data),
       Date().timeIntervalSince1970 - cached.issued < 45 * 60 {
        return cached.jwt
    }

    let keyURL = config.keyPath.hasPrefix("/")
        ? URL(fileURLWithPath: config.keyPath)
        : home.appending(path: config.keyPath.replacingOccurrences(of: "~/", with: ""))
    let pem = try String(contentsOf: keyURL, encoding: .utf8)
    let key = try P256.Signing.PrivateKey(pemRepresentation: pem)

    func b64url(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
    let issued = Date().timeIntervalSince1970
    let header = try JSONSerialization.data(withJSONObject: ["alg": "ES256", "kid": config.keyID])
    let claims = try JSONSerialization.data(withJSONObject: ["iss": config.teamID, "iat": Int(issued)] as [String: Any])
    let signingInput = "\(b64url(header)).\(b64url(claims))"
    // rawRepresentation es r||s, que es exactamente lo que JWS espera para
    // ES256 — NO la codificacion DER que devuelven otras librerias.
    let signature = try key.signature(for: Data(signingInput.utf8)).rawRepresentation
    let jwt = "\(signingInput).\(b64url(signature))"

    try? JSONEncoder().encode(Cached(jwt: jwt, issued: issued)).write(to: cacheURL)
    return jwt
}

// MARK: - Envío

let jwt: String
do { jwt = try bearerToken(config) } catch { fail("no se pudo firmar el JWT: \(error)", code: 5) }

let host = device.environment == "sandbox" ? "api.sandbox.push.apple.com" : "api.push.apple.com"
var request = URLRequest(url: URL(string: "https://\(host)/3/device/\(device.token)")!)
request.httpMethod = "POST"
request.setValue("bearer \(jwt)", forHTTPHeaderField: "authorization")
request.setValue(config.bundleID, forHTTPHeaderField: "apns-topic")
request.setValue("alert", forHTTPHeaderField: "apns-push-type")
request.setValue("10", forHTTPHeaderField: "apns-priority")

var alert: [String: Any] = ["title": session]
if let subtitle = args["subtitle"] { alert["subtitle"] = subtitle }
if let body = args["body"] { alert["body"] = body }

var aps: [String: Any] = [
    "alert": alert,
    "sound": "default",
    // Agrupa por sesion en el centro de notificaciones, igual que un hilo de
    // chat. Es el equivalente nativo del thread_id que ya se usaba.
    "thread-id": "remotessh-\(session)",
    "interruption-level": args["level"] ?? "active",
]
// El motivo entero de tener push propio: un proveedor de terceros no puede
// poner esto en el icono de OTRA app.
if let badge = args["badge"].flatMap(Int.init) { aps["badge"] = badge }
// Registrada en la app; habilita las acciones de la notificacion cuando existan.
if let category = args["category"] { aps["category"] = category }

let payload: [String: Any] = ["aps": aps, "session": session]
request.httpBody = try! JSONSerialization.data(withJSONObject: payload)

let semaphore = DispatchSemaphore(value: 0)
var exitCode: Int32 = 0
URLSession.shared.dataTask(with: request) { data, response, error in
    defer { semaphore.signal() }
    if let error {
        FileHandle.standardError.write(Data("apns-push: red: \(error.localizedDescription)\n".utf8))
        exitCode = 6
        return
    }
    let status = (response as? HTTPURLResponse)?.statusCode ?? 0
    if status == 200 {
        print("OK")
    } else {
        // El cuerpo trae el motivo real (BadDeviceToken, ExpiredProviderToken,
        // TopicDisallowed…). Sin esto, depurar APNs es adivinar.
        let reason = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
        FileHandle.standardError.write(Data("apns-push: HTTP \(status) \(reason)\n".utf8))
        exitCode = 7
    }
}.resume()
_ = semaphore.wait(timeout: .now() + 15)
exit(exitCode)
