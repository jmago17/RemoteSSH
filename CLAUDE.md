# RemoteSSH

> Contexto para Claude Code. Generado desde Minis (`/var/minis/shared/remotessh/ESTADO.md`).

## Identidad

- Repo: `jmago17/RemoteSSH.git`
- Carpeta en el Mac: `~/Documents/Developer/RemoteSSH`
- Proyecto: `RemoteSSH.xcodeproj`
- Scheme: `RemoteSSH`
- Bundle id: `com.maromeapps.RemoteSSH` (era `com.danobat.*` hasta
  2026-08-22; ver la seccion del rename al final)

Repo **publico** en GitHub. No commitear nada sensible.

## Donde esta ahora

**Publicado en GitHub como repo publico**: https://github.com/jmago17/RemoteSSH
`main` con tracking a `origin/main`, todas las ramas de feature mergeadas
(`feature/chat-view`, `chat-polish`, `claude-code-status`, `tmux-shortcuts`).

Las 5 fases previstas se completaron en sesiones anteriores (Brrr push,
generacion de claves in-app, pinning TOFU de host key, restore con
tmux-resurrect, multi-host). Despues vino rediseño + iPad + teclado, luego la
vista conversacional, el estado de Claude Code, los App Intents y el resumen
con Apple Intelligence.

Compila en verde en iPhone 17 Pro y iPad Pro 11" (M5), iOS 27.

**OJO con la documentacion de estado**: el `ESTADO.md` de `_MinisBackup` se
quedo anclado en `aea84dc` / "22 commits" mientras el repo seguia avanzando.
Antes de fiarte de cualquiera de los dos ficheros, contrasta con
`git log --oneline -5`.

## Pendiente

- **Verificar en hardware real** (no se pudo por simulador, ver Trabas):
  - menu de configuracion de slot con pulsacion larga
  - altura del `ExpandedKeyPanel` (260pt telefono / 300pt iPad)
- **Franja de atajos `⌘N new · ⌘R refresh · ⌘, settings`** del mock de diseño:
  no se llego a renderizar. Los atajos SI funcionan, solo falta el hint visual.
- Sin `README` de instalacion/uso orientado a terceros ahora que el repo es
  publico.


## Compilar

```sh
export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer
cd ~/Documents/Developer/RemoteSSH
pkill -f xcodebuild; pkill -f XCBBuildService
xcodebuild -project RemoteSSH.xcodeproj -scheme "RemoteSSH" \
  -destination "platform=iOS Simulator,name=iPhone 17 Pro" \
  -derivedDataPath /tmp/remotessh_build \
  build
```

- `DEVELOPER_DIR` es obligatorio: solo existe `Xcode-beta.app`, no `Xcode.app`.
  Sin el, `xcrun` falla con "unable to find utility simctl".
- `pkill` antes: los procesos colgados dejan el build mudo.
- `-derivedDataPath` distinto por build evita `build.db is locked`.

Simuladores disponibles (solo estos dos, en iOS 27):
**iPad Pro 11-inch (M5)** y **iPhone 17 Pro**.

## ATENCION: iCloud corrompe este repo

`~/Documents/Developer` esta dentro de iCloud Drive. Los ficheros *evicted*
(no descargados) producen errores que parecen de codigo:

```
fatal: mmap failed: Operation timed out
error: cannot find 'X' in scope        <- en ficheros que nadie toco
```

El 2026-08-20, `ImageCacheService.swift` estaba a **0 bytes** y rompio la
compilacion en cinco ficheros ajenos al cambio.

Ante un error raro, comprobar SIEMPRE primero:

```sh
find . -name "*.swift" -size 0
```

Si aparece algo, restaurarlo desde un clon integro. Un `git checkout` puede no
bastar si el pack tambien esta evicted.

## Firma / App Store Connect

macOS 27 no admite ninguna version estable de Xcode, asi que el unico SDK es
iOS 27 **beta** y App Store Connect rechaza esos binarios. Pendiente montar
Xcode Cloud (ver `_infra/TRASPASO_CLAUDE_CODE.md`).

El llavero se re-bloquea solo y da `errSecInternalComponent` al firmar.
**No pedirle a Josu la contraseña del llavero**: firmar con Run manual desde
Xcode.

## Estado del proyecto

La foto actual (decisiones, pendientes, trabas) vive en
`_MinisBackup/shared/remotessh/ESTADO.md` dentro de iCloud Drive, replicado
desde Minis. Merece la pena leerlo al empezar.


## Trabas especificas de este proyecto

- **`error: unable to attach DB ... build.db is locked`** — recurrente. Causa:
  el Xcode abierto de Josu + builds concurrentes de otros proyectos
  (`LiveActivities`, `Printables`) compartiendo DerivedData.
  Solucion: `-derivedDataPath /tmp/rssh_<algo>` distinto en cada build, y si
  persiste `pkill -f XCBBuildService`. Ver `_infra/ESTADO.md`.
- **`xcodebuild` por SSH agota el timeout de la herramienta**: lanzarlo
  detached con `nohup ... > /tmp/b.log 2>&1 &` y consultar el log con `delay`.
- **No se puede llegar a la pantalla de terminal en el simulador**: instalacion
  limpia = sin Keychain, sin hosts → nunca hay lista de sesiones poblada ni
  terminal viva que capturar. Para ver el key rail se monto un arnes
  desechable `/tmp/KeyRailPreviewApp.swift` + `/tmp/build_preview.sh`
  (`com.danobat.KRPreview`, dd en `/tmp/KRPreview`) que compila el
  `KeyRail.swift`/`DesignSystem.swift`/`SpecialKey` reales con `showAll = true`.
- **`xcrun simctl io ... tap` no existe** y no hay GUI/AppleScript por SSH → no
  se puede automatizar interaccion en el simulador. De ahi el arnes.
- **`switch must be exhaustive`** en `SettingsView.swift:268` al añadir un caso
  a `Pane`: hay que actualizar tambien `summary(for:)`.
- **El glifo `⌥` era casi invisible** renderizado como texto → `KeyCap` tiene
  ahora un init basado en SF Symbols (`square.grid.2x2`, `chevron.down`).
- **Homebrew no esta 


## Vista conversacional (sesion 2026-08-20, rama `feature/chat-view`)

Al tocar una sesion ya NO se cae en la terminal: se entra en `ChatScreen`, una
lectura tipo chat del scrollback. La terminal sigue intacta, a un toque.

**Ficheros nuevos**: `Services/TranscriptParser.swift`,
`ViewModels/ChatSessionModel.swift`, `Views/ChatScreen.swift`,
`Views/TranscriptTurnView.swift`.

### Como se llega a la terminal: `fullScreenCover`, no un push

`ChatScreen` presenta `TerminalScreen` con `.fullScreenCover`, no con
`navigationDestination`. Razon: el `NavigationStack` de `SessionListView` tiene
el path tipado a `[String]` (la seleccion va por NOMBRE por culpa del polling).
Meter un segundo tipo de ruta obligaria a migrar a `NavigationPath` y tocar la
navegacion, que es zona delicada. Ademas el cover da un punto inequivoco donde
refrescar el transcript al volver (`onChange(of: showingTerminal)`).

### El parser: en que se apoya y donde falla

`tmux capture-pane -p` no marca nada. La firma del prompt se INFIERE de la
ultima linea no vacia (el prompt vivo esperando input), no de regex genericas
ni del prefijo comun (el prefijo comun falla: el cwd cambia entre prompts, asi
que el prefijo literal suele ser la cadena vacia).

- Ancla = ultimo caracter del prompt vivo. `❯ ➜ » λ` son *safe* (1 coincidencia
  basta); `$ % # >` son *risky* (exigen pre-ancla no vacio, similitud ≥0.6 y
  **3** coincidencias). Ese `3` es la proteccion real contra falsos positivos.
- `similarity` compara **prefijo Y sufijo** y se queda con el mejor. Hace falta:
  el cwd varia por el final, el `✘ 1` del exit code de p10k varia por el
  principio. Solo con prefijo, los prompts con exit code no casaban.
- **Se descarto el criterio de "densidad de prompts ≤40%"** que recomienda la
  literatura: tumbaba las sesiones de comandos con salida corta (`echo a` da
  50% de densidad y es perfectamente estructurable). Verificado con el arnes.
- Si no hay confianza NO se inventan turnos: bloque `.raw` + nota que explica
  por que. Degradacion tambien por bloque, no solo global.

Fallara (asumido y documentado en el propio fichero): REPLs (`python3`, `psql`),
shells anidados (`ssh otrohost`), continuaciones PS2 / heredocs, cambio de
prompt a mitad de sesion (`source venv/bin/activate`), y salida que imita
prompts (un `cat` de un tutorial con lineas `$ cmd`).

### Detalles que costaron

- **`tmux send-keys` SIN `-l` interpreta nombres de tecla**: un comando llamado
  `Enter`, `Space` o `C-c` se enviaria como pulsacion, no como texto. Hay que
  usar `send-keys -l '<texto>'` y luego `send-keys Enter` aparte.
- **`capture-pane` necesita `-J`**: sin el, tmux parte las lineas al ancho del
  pane y las continuaciones parecen lineas nuevas → salidas atribuidas al
  comando equivocado.
- **`#{alternate_on}` convierte una heuristica en un hecho**: se pregunta a tmux
  si una app curses (vim/htop) posee la pantalla en vez de adivinarlo del texto.
  Cuesta unos bytes en la conexion que ya esta abierta.
- **`@concurrent` (SE-0461) compila con `SWIFT_VERSION = 6.0`**. Se usa en
  `TranscriptParser.parsed(_:)` para garantizar que el parseo de 2000 lineas no
  corre en el MainActor aunque algun dia se active Approachable Concurrency
  (que invierte la semantica de `nonisolated async`).
- El wrapper async NO puede llamarse `parse` como el sincrono: el overload hace
  que la version async se llame a si misma. Se llama `parsed`.

### UUID REALES de los simuladores (los de sesiones anteriores caducaron)

    iPhone 17 Pro          112C8364-7CD7-4782-9DB7-E7ECADE64402
    iPad Pro 11-inch (M5)  686E242B-5C89-44BE-BA28-F651DC729C20

No existe ningun iPad Air en esta maquina. Usar UUID, no nombre.

### Arnes para VER la vista sin conexion SSH

Mismo truco que el del KeyRail. `/tmp/ChatPreview/` (`project.yml` + xcodegen,
bundle `com.danobat.ChatPreview`, dd en `/tmp/ChatPreview/dd`) copia los
`TranscriptTurnView.swift` / `DesignSystem.swift` / `TranscriptParser.swift`
REALES y los renderiza con scrollbacks de ejemplo. Como `simctl io ... tap` no
existe, la pantalla se elige por argumento de lanzamiento:

    xcrun simctl launch <UDID> com.danobat.ChatPreview raw     # bloque sin estructurar
    xcrun simctl launch <UDID> com.danobat.ChatPreview long    # truncado "Show all"

Y `/tmp/parsercheck/` compila el parser real con `swiftc -swift-version 6`
contra 33 asserts (salida limpia, sin prompts, ANSI, vacia, trampa de `$`,
curses, exit code, cabeza truncada...). No hay target de tests en `project.yml`
y no se creo uno; el parser es puro justamente para poder comprobarlo asi.


## Sesion 2026-08-21: ancho del raw pane, teclado, latencia del resumen, Xcode Cloud

Cuatro cosas que Josu reporto usando la app de verdad, mas el fallo de CI.

### 1. Xcode Cloud: "a resolved file is required"

```
a resolved file is required when automatic dependency resolution is disabled
and should be placed at .../RemoteSSH.xcodeproj/project.xcworkspace/
xcshareddata/swiftpm/Package.resolved
```

**Causa**: Xcode Cloud resuelve paquetes con la resolucion automatica
DESACTIVADA, asi que un `Package.resolved` ausente es un fallo duro, no un
"pues lo resuelvo yo". Y su ruta natural cae dentro de `RemoteSSH.xcodeproj/`,
que esta gitignorado porque lo genera XcodeGen. El fichero nunca llegaba a CI.

**Arreglo**: la copia fijada se versiona en `swiftpm/Package.resolved` (raiz del
repo) y `ci_post_clone.sh` la copia a su sitio **despues** de `xcodegen
generate`. La linea generica `Package.resolved` salio del `.gitignore` — esta
documentado ahi mismo para que nadie la reponga.

**Mantenimiento**: al cambiar una version de dependencia hay que refrescarla:
```sh
cp RemoteSSH.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved swiftpm/
```
Si no, CI compila los pines viejos sin avisar.

**De paso**: el resolved fija `swift-nio-ssh` a
`https://github.com/Wellz26/swift-nio-ssh.git` 0.3.6 — un **fork de un
tercero**, no el repo de Apple. Viene de Citadel 0.12.1, no lo metimos
nosotros, pero conviene saberlo: es codigo ajeno en la ruta SSH de una app
publicada.

### 2. El raw pane sigue sin mostrar la linea entera (iPhone)

El arreglo del 20 (`maxWidth: .infinity` al `ScrollView`) era **correcto pero
insuficiente**, y por eso el sintoma no cambio: resolvia el desbordamiento del
marco, no la anchura del texto. La causa real es aritmetica pura:

| | |
|---|---|
| Ancho del pane de Claude Code | **61 columnas** (`#{pane_width}`) |
| Ancho de linea a 12.5pt mono | 61 × 0.6 × 12.5 ≈ **460pt** |
| Columna del transcript en iPhone 17 Pro | **374pt** (402 − 28 de padding) |

Faltaban ~90pt. Ningun `frame` arregla eso; solo cabe encoger la letra, que es
lo que hace cualquier terminal movil.

**Arreglo** (`TranscriptTurnView`): `outputFontSize` escala el texto para que la
linea real mas ancha quepa, con suelo en **7.5pt** — por debajo se vuelve al
scroll horizontal. El ratio de avance del monoespaciado se **mide** de
`UIFont.monospacedSystemFont`, no se supone.

**Las reglas decorativas se excluyen del calculo y se recortan al dibujar.**
`capture-pane -S -2000` alcanza scrollback escrito cuando el pane tenia otro
ancho, asi que una sesion de 61 columnas arrastra lineas `────` de **240 y 183
caracteres** de cuando la ventana era ancha. Sin filtrarlas, el ajuste encogia
todo a un cuarto del tamaño necesario y el scroll horizontal medía cuatro veces
mas que el texto: casi todo el arrastre recorria una raya.

**Dos trampas que costaron una iteracion cada una** (ambas verificadas con
screenshot, no razonadas):

- **`.onGeometryChange` va ANTES de `.padding`**, no despues. `.padding()`
  devuelve una vista *mas ancha* que su contenido, asi que medir despues
  reporta el ancho de pantalla (402) en vez del de columna (374) — 28pt de mas,
  que es exactamente un bloque que sigue cortando ~4 caracteres por linea.
- **El suelo estaba en 8.5pt** y el caso real pedia 8.09 en la medida erronea.
  Un suelo demasiado alto convierte el ajuste en un no-op silencioso.

### 3. Teclado: fuera el boton Done

Sustituido por el gesto de las apps de mensajeria: **tocar la burbuja enfoca,
tocar cualquier otro sitio esconde**.

- El `ToolbarItemGroup(placement: .keyboard)` colgado del `TextField` era ademas
  el sospechoso del descuadre que veia Josu (la burbuja bajo la barra de
  predicciones y luego encima del Done): instala su propio input accessory view
  y su altura pelea con el inset de safe area que SwiftUI ya aplica al
  compositor.
- El dismiss va con `.simultaneousGesture(TapGesture())` sobre `content(chat)`,
  no con `.onTapGesture`: el transcript esta lleno de cosas que deben seguir
  respondiendo al mismo toque ("Show all", el banner, "Try Again", texto
  seleccionable).
- `.scrollDismissesKeyboard` pasa de `.interactively` a `.immediately`: un
  teclado arrastrado a medias deja el compositor parado a mitad de animacion,
  que es justo el estado "la burbuja se ha descuadrado".
- La pastilla entera enfoca (`contentShape` + `onTapGesture`), no solo el
  `TextField`.

### 4. El resumen de Apple Intelligence tardaba demasiado

**Premisa descartada primero**: no era que cogiera demasiado texto. Medido con
el `ClaudeCodeRecogniser` real contra un pane real de `newsRaider`,
`lastConclusion` devuelve **1.589 caracteres / 32 lineas** — unos cientos de
tokens. La espera era el modelo arrancando y escribiendo.

Tres costes, todos *despues* del instante en que el usuario empieza a esperar:
carga del modelo, prefill de las instrucciones (prefijo fijo, identico siempre)
y generacion completa antes de mostrar nada.

**Arreglo** (`ClaudeCodeSummariser`):
- `prepare()` precalienta una sesion **mientras Claude Code trabaja**, que es
  una ventana de minutos con el dispositivo ocioso. Lo dispara
  `ChatSessionModel.refresh()` al ver `.working`.
- `session.prewarm(promptPrefix:)` incluye el prefijo fijo del prompt, asi que
  al llegar la llamada real solo queda prefilar la conclusion.
- **Una sesion por resumen, nunca reutilizada**: `LanguageModelSession` acumula
  transcript, y reusarla realimentaria cada conclusion anterior como contexto —
  cada vez mas lenta y con texto ajeno disponible para colarse en la respuesta.
- `streamResponse` en vez de `respond`: la tarjeta pinta el titular en cuanto
  existe. `ClaudeCodeConclusionCard` muestra un `ProgressView` mini junto a
  SUMMARY mientras sigue escribiendo, para que no parezca una tarjeta acabada
  que cambia sola.
- `GenerationOptions(samplingMode: .greedy, maximumResponseTokens: 220)`.
  Greedy es el modo mas rapido y ademas hace que la misma conclusion se resuma
  igual dos veces — importa porque el cache por digest de contenido hace que
  una tarjeta que se reescribe sola parezca un bug.
- Bullets de 0...5 a **0...3**: los dos ultimos repetian el titular mas veces
  de las que aportaban un dato.

**NO verificado**: el resumen sigue sin poder probarse end-to-end. El simulador
no tiene el modelo on-device aprovisionado (`ModelManagerError 1026`), asi que
la mejora de latencia esta razonada y compilada, **no medida**. Hace falta un
iPhone real con Apple Intelligence activo.

### Arnes de ancho (reproducible)

`/tmp/.../scratchpad/WidthPreview/` — app xcodegen (`com.danobat.WidthPreview`)
que compila los `TranscriptTurnView.swift` / `DesignSystem.swift` /
`TranscriptParser.swift` / `ClaudeCodeRecogniser.swift` REALES y los renderiza
sobre un `capture-pane` REAL guardado en `Resources/pane.txt`. La pantalla se
elige por argumento porque `simctl io ... tap` no existe:

```sh
xcrun simctl launch <UDID> com.danobat.WidthPreview before   # availableWidth = 0
xcrun simctl launch <UDID> com.danobat.WidthPreview after    # ancho medido
```

**El arnes necesita `UILaunchScreen`**. Sin el, iOS lo ejecuta en modo
compatibilidad a 320×568 (un iPhone SE virtual) y mide una columna de 320pt en
un telefono de 402pt — media hora perdida persiguiendo un fantasma. En
`project.yml` del arnes: `INFOPLIST_KEY_UILaunchScreen_Generation: "YES"`.

## Sesion 2026-08-22: bundle id `com.danobat.*` → `com.maromeapps.*`

Motivo: danobat es la empresa donde trabaja Josu, no quien publica la app.

**Los seis sitios donde vive la identidad.** Un `sed` sobre `com.danobat.`
(con punto final) **se deja uno**: `bundleIdPrefix: com.danobat` en
`project.yml` no lleva punto detras. Lista completa:

| Fichero | Que hay |
|---|---|
| `project.yml` | `bundleIdPrefix`, `PRODUCT_BUNDLE_IDENTIFIER`, `CFBundleURLName` |
| `Sources/Services/KeychainStore.swift` | `service = "com.maromeapps.RemoteSSH.credentials"` |
| `scripts/com.maromeapps.remotessh.notify.plist` | el `Label` **y el nombre del fichero** |
| `docs/notifications-brrr.md` | rutas del `cp` / `launchctl` |
| `README.md` | identidad y ruta del plist |
| `Sources/Views/DesignSystem.swift` | `danobat-api` era el hostname de ejemplo del doc-comment de `SessionTile` |

`RemoteSSH-Info.plist` y `project.pbxproj` **no se editan a mano**: los
regenera `xcodegen generate` desde `project.yml`. Script reproducible en
`<scratchpad>/rename_bundle.sh` (idempotente, imprime las menciones que
sobrevivan).

**`xcodegen generate` NO se lleva por delante el `Package.resolved`** que vive
dentro del `.xcodeproj` (verificado: identico a la copia de `swiftpm/` despues
de regenerar). O sea que el arreglo de Xcode Cloud del 2026-08-21 sobrevive a
un regenerate.

**Verificado**: `BUILD SUCCEEDED` en simulador y `CFBundleIdentifier` leido del
`RemoteSSH.app` compilado, no solo del yml:

```sh
/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" \
  /tmp/rssh_rename/Build/Products/Debug-iphonesimulator/RemoteSSH.app/Info.plist
# com.maromeapps.RemoteSSH
```

**Lo que se pierde al instalarla** (iOS la trata como app nueva): credenciales
del Keychain, los hosts (el KVS de iCloud se indexa por `CFBundleIdentifier`
via `com.apple.developer.ubiquity-kvstore-identifier`) y el pinning TOFU de
host-keys. **Borrar la app vieja del iPhone antes de instalar** o las dos se
pelean por el scheme `remotessh://`.

**Firma en dispositivo**: `CODE_SIGN_STYLE: Automatic` con team `ES2766ARHJ`.
El App ID `com.maromeapps.RemoteSSH` no existe todavia en el portal; lo crea
Xcode al hacer **Run manual** (por terminal el llavero se re-bloquea y Josu
prohibio que se le pida la contraseña).

**El LaunchAgent de notificaciones del repo es solo plantilla.** No hay ningun
`~/Library/LaunchAgents/*remotessh*` instalado ni proceso `tmux-notify.sh`
corriendo (verificado con `launchctl list` y `pgrep`), asi que el rename del
plist no rompio nada en marcha. Las notificaciones que Josu ve vienen de los
hooks de Claude Code, no de este watcher.

**Corregido respecto a notas anteriores**: `gh` **si** tiene credencial en el
Mac (`gh auth status` → `jmago17`, keyring, scopes `repo`/`workflow`). El
pendiente "token caducado" ya no aplica.
