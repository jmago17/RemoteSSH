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

## Sesion 2026-08-22 (2): Codex, scrollback en la terminal, teclado

### Reconocer un pane de Codex

**El problema no era el parser, era el nombre del proceso.** tmux devuelve
`claude.exe` para Claude Code — inconfundible. Para Codex devuelve **`node`**, y
un `node` puede ser cualquier cosa. Con `alternate_on=0` (Codex NO usa pantalla
alternativa), el pane caia en `isShell == false` → *"a full-screen program
called node is running in this pane"*.

**Deteccion determinista, no heuristica**: `ps -o args= -p #{pane_pid}` devuelve
`node /opt/homebrew/bin/codex`. `TmuxService.snapshot` solo paga ese segundo
round trip cuando el comando es un interprete generico (`node`, `bun`, `deno`,
`python`, `python3`); `claude.exe`, `zsh` o `vim` ya se explican solos. El test
textual de `CodexRecogniser.looksLikeCodexFrame` es solo el plan B para cuando
`ps` no dice nada, y exige DOS marcas (composer `›` + status bar `modelo · /ruta`
como ultima linea no vacia) porque cualquiera de las dos sola da falsos
positivos.

**Diferencias medidas contra un pane real de Codex 0.147.0** (no de memoria):

| | Claude Code | Codex |
|---|---|---|
| `pane_current_command` | `claude.exe` | `node` |
| `alternate_on` | `1` | **`0`** |
| `pane_title` | la tarea | el **cwd**, con spinner braille `⠙` delante SOLO mientras trabaja |
| spinner | `✽ Verb… (7m 3s · ↓ 22.4k tokens)` | `• Verb (2s • esc to interrupt)` — **sin `…`** |
| composer | `❯` | `›` |
| pregunta | `❯ 1. Yes` | `› 1. Review hooks` + `Press enter to confirm` |

Consecuencias en el codigo: el spinner de Claude exige `…`, asi que su
`isSpinnerLine` NO vale para Codex (ancla en `esc to interrupt`). Y el `›` solo
no significa pregunta: **el composer en reposo tambien empieza por `›`**
(`› Improve documentation in @filename`), asi que el digito es lo que decide.

`task` se deja a `nil` para Codex a proposito: el titulo es el directorio, no
una tarea, y vestir una ruta de tarea seria mentir.

`ClaudeCodeStatus` pasa a llamarse **`AgentStatus`** (+ `AgentKind`), porque ya
describe dos agentes. `ClaudeCodeBanner` → `AgentBanner`.

**Lo que se dejo fuera adrede**: el resumen de conclusion sigue siendo solo de
Claude Code. `lastConclusion` busca el ultimo turno por el marcador `⏺`, y Codex
marca con `•`; apuntarlo a un frame de Codex resumiria lo que hubiera en la cola.
Hace falta un extractor de Codex verificado antes de encender esa tarjeta.

### BUG encontrado de paso: el estado se leia del scrollback

`ClaudeCodeRecogniser.status` recibia las **2000 lineas** capturadas, no la
pantalla. Una pregunta contestada hace una hora sigue en el scrollback → un pane
ocioso se anunciaba como **"Waiting for your answer"**. Afectaba tambien a
Claude Code. Lo destapo el arnes, no la lectura del codigo.

Arreglo: `PaneSnapshot.visibleScreen` = las ultimas `#{pane_height}` lineas. El
transcript sigue viendo las 2000; el ESTADO solo la pantalla. Funciona porque el
agente redibuja: un prompt contestado desaparece de la pantalla y solo sobrevive
en el historial (verificado: `capture-pane -p | grep -c "Review hooks"` → 0,
`capture-pane -p -S -2000 | grep -c` → 1).

**Verificado que el recorte es exacto**, no aproximado:

```sh
H=$(tmux display-message -p -t X '#{pane_height}')
diff <(tmux capture-pane -p -t X) <(tmux capture-pane -p -J -S -2000 -t X | tail -$H)
# IDENTICAS
```

### Scroll con historial en la terminal (copy-mode)

Entrar y salir van por **comando tmux sobre SSH**, no por el PTY: la ruta de
teclado es `prefix` + `[` y el prefijo es el que el usuario haya puesto (el de
Josu es `C-b`, pero eso no se puede suponer). `tmux copy-mode -t <pane>` no
depende del prefijo.

Paginar SI va por el PTY, porque `PageUp`/`PageDown` estan bindeadas igual en
las tablas emacs y vi de copy-mode y no necesitan prefijo — y asi el scroll es
instantaneo en vez de una conexion SSH por pagina. Los dos extremos vuelven a ir
por SSH (`history-top` / `history-bottom`) porque esos SI cambian de tabla.

Todo comprobado contra un tmux vivo (`send-keys` sin `-X` entrega la tecla igual
que la entregaria el PTY):

```sh
tmux copy-mode -t X                      # entra
tmux send-keys -t X PPage                # sube una pagina  → scroll_position 11
tmux send-keys -t X NPage                # baja             → 0
tmux send-keys -X -t X history-top       # al principio
tmux send-keys -X -t X cancel            # sale
tmux display-message -p -t X '#{pane_in_mode} #{scroll_position}'
```

Se sale de copy-mode al abandonar la pantalla: un pane dejado en copy-mode no
sigue la salida en vivo y **parece colgado** al siguiente que se conecte.

### Teclado y el `ExpandedKeyPanel`

La nota pendiente decia "ocultar el teclado al abrir el panel" y estaba mal
planteada: eso YA lo hacia (`aea84dc`). Lo roto era lo contrario — al **cerrar**
el panel nadie devolvia el foco, porque `didFocus` solo disparaba una vez. Ahora
`TerminalHostView(wantsKeyboard:)` gobierna las dos direcciones, sobre la
`TerminalView` concreta (no un `sendAction(_:to:nil…)` a ciegas) y **solo cuando
el valor cambia**, para que un `updateUIView` por cualquier otra causa no vuelva
a subir el teclado que el usuario acaba de bajar.

### Arneses (reproducibles, fuera del repo)

`<scratchpad>/codexharness/` — compila los `CodexRecogniser.swift` /
`ClaudeCodeRecogniser.swift` REALES con `swiftc` y los corre contra frames
capturados de un Codex vivo (14 casos: deteccion, falsos positivos con un dev
server de vite, working/idle/approval, capado del verbo).

`<scratchpad>/bothagents/` — mete el parser REAL por todos los panes tmux de la
maquina con el `display-message` exacto que manda la app. Es la prueba de
no-regresion de Claude Code: en la ultima pasada dio
`claudeCode / working("Infusing") · 21m 53s · ↓66.9k`, `codex / idle`, y `zsh`
→ no es agente.

Dos trampas de `swiftc` sueltas: el fichero del arnes **debe llamarse
`main.swift`** (si no, *"expressions are not allowed at the top level"*), y con
`-swift-version 6` las funciones globales que tocan un `var` global necesitan
`@MainActor`.

**NO verificado**: nada de esto se ha visto en un iPhone. Compila y pasa los
arneses; la barra de historial, el foco del teclado y el banner de Codex no se
han tocado con un dedo.

### Xcode Cloud compila con un SDK MAS VIEJO que el Mac

Build fallido el 2026-08-22 sobre `c1c05be`:

```
ClaudeCodeSummariser.swift:155
Incorrect argument label in call
(have 'samplingMode:maximumResponseTokens:', expected 'sampling:maximumResponseTokens:')
```

**No era un error de codigo.** En el SDK de iOS 27 beta que hay en el Mac
conviven los dos inits de `GenerationOptions` (comprobado en el
`.swiftinterface` del SDK, no de memoria):

```swift
@available(*, deprecated, renamed: "samplingMode")
public init(sampling: SamplingMode?, temperature: Double? = nil, maximumResponseTokens: Int? = nil)
public init(samplingMode: SamplingMode? = nil, temperature: Double? = nil, maximumResponseTokens: Int? = nil)
```

Xcode Cloud corre un Xcode anterior, cuyo SDK tiene **solo `sampling:`**. Por eso
compilaba en local y moria en CI.

**Parche aplicado**: usar `sampling:` (deprecado en el SDK nuevo, presente en
ambos). NO devolverlo a `samplingMode:` hasta que el workflow de Xcode Cloud
este en una version de Xcode que lo tenga, o CI vuelve a romperse.

**Arreglo de fondo (pendiente, lo tiene que hacer Josu)**: en App Store Connect
→ el workflow → Environment → subir la version de Xcode a la beta que coincida
con `/Applications/Xcode-beta.app` (27.0, build 27A5194q). La version NO se
configura desde el repo, asi que no se puede arreglar por commit.

**Comprobado que el resto SI vale**: `LanguageModelSession.prewarm(promptPrefix:)`
NO lleva `@available(iOS 27)` propio — hereda el `@available(iOS 26.0)` de la
clase, asi que existe tambien en el SDK viejo. Era el otro candidato a romper y
no lo es.

**Como comprobar la firma real de una API del SDK** (en vez de suponerla):

```sh
D=/Applications/Xcode-beta.app/Contents/Developer
grep -n "struct GenerationOptions" -A 30 \
  $D/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS.sdk/System/Library/Frameworks/\
FoundationModels.framework/Modules/FoundationModels.swiftmodule/arm64e-apple-ios.swiftinterface
```

### ITMS-90626: la metadata de App Intents no puede decir "mac"

Build 10 (Version 1.0) **entregado a App Store Connect y rechazado** el
2026-08-22 — nota primero la buena noticia enterrada: Xcode Cloud ya compila y
entrega, el bloqueo de "no se puede subir nada" quedó atrás.

```
ITMS-90626: Invalid Siri Support - App Intent description 'Sends a command to a
tmux session on your Mac over SSH, …' cannot contain 'mac'
```

**Es una subcadena, no una palabra**: `machine` y `macOS` tambien la contienen y
tambien caerian.

**Alcance real: TODO lo que se extrae al bundle de App Intents**, no solo la
cadena que Apple cita. El rechazo nombro el `IntentDescription`, pero
`@Parameter(description:)` sale al mismo sitio y habria costado OTRO ciclo de
build. Se limpiaron las dos a la vez, mas el `errorDescription`.

**Los comentarios NO cuentan** (verificado dos veces, no supuesto): el
doc-comment de la linea 3 decia "on the configured Mac" en el build 10 y Apple
no lo menciono; y `grep -rl "configured Mac" RemoteSSH.app` no encuentra nada.
Por eso el aviso de "no vuelvas a poner esta palabra" puede quedarse escrito en
el propio fichero.

**Los `Text`/`TextField` de la UI SI pueden decir "Mac"** y deben: el usuario
piensa en su Mac, no en "un host". La regla es solo de App Intents / Siri.

**Comprobarlo ANTES de gastar un ciclo de build** (el bundle lo genera cualquier
build local):

```sh
APP=/tmp/<dd>/Build/Products/Debug-iphonesimulator/RemoteSSH.app
grep -rioE "mac[a-z]*" "$APP/Metadata.appintents/"     # debe salir vacio
grep -oE "Sends a command[^\"]*" "$APP/Metadata.appintents/extract.actionsdata"
```

### App Store Connect tras el rename: lo que pasó de verdad

**CORRECCION (2026-08-23).** La primera version de esta seccion decia que el app
record estaba atado a `com.danobat.RemoteSSH` y que no existia ninguno para el
bundle nuevo. **Es falso.** Al intentar recrearlo, Apple contesto:

```
App record with bundle identifier "com.maromeapps.RemoteSSH" was previously
removed from App Store Connect for team "Josu Martinez Gonzalez".
Go to App Store Connect to restore the app.
```

O sea que el record **si existia con el bundle NUEVO**, y era el unico de la
cuenta. Reconstruccion correcta: el rename se pusheo por la mañana, Xcode Cloud
creo el record con `com.maromeapps.RemoteSSH`, y el **build 10** salio de ahi —
por eso llevaba todavia la descripcion vieja del App Intent y lo tumbo
ITMS-90626. No era un build del bundle antiguo, como se dedujo entonces.

**Queda sin confirmar** por que fallaba "Preparing build for App Store Connect".
Con el record existente, la hipotesis viva es la que se descarto demasiado
pronto: el binario se presentaba como `0.1.0` mientras el record hablaba de
`1.0`. Por eso se subio `MARKETING_VERSION` a 1.0 — si tras restaurar el record
el build entra, era eso.

**Un App ID NO es un app record** (esto si sigue siendo cierto y vale la pena
recordarlo). Son dos cosas en dos sitios: el **App ID** de
developer.apple.com lo crea Xcode solo al firmar — el de
`com.maromeapps.RemoteSSH` existe desde el 2026-08-22 04:29Z, con iCloud
incluido — mientras que el **app record** de App Store Connect es otra entidad.
Comprobar las capabilities de un App ID sin entrar al portal:

```sh
P=~/Library/Developer/Xcode/UserData/Provisioning\ Profiles
for f in "$P"/*.mobileprovision; do
  D=$(security cms -D -i "$f")
  echo "$D" | plutil -extract Entitlements.application-identifier raw -
  echo "$D" | plutil -extract Entitlements xml1 -o - - | grep ubiquity
done
```

### Borrar el app record fue un error: hay que RESTAURARLO, no recrearlo

Una vez se ha subido un build a un bundle id, **ese bundle id no se puede
reutilizar** para una app nueva. Con el build 10 ya subido a
`com.maromeapps.RemoteSSH`, crear otro record con ese id **no es una salida**:
la unica via es restaurar el eliminado.

Ruta exacta (doc de Apple, "Remove an app"):

> Apps → la flecha junto a **All Statuses** (arriba a la derecha) → **Removed
> Apps** → elegir la app → **App Information** en la barra lateral →
> **Additional Information** → **Restore App** → Full Access → Restore.

- Hace falta rol **Account Holder o Admin**.
- Si la eliminada es la unica app de la cuenta, sale directamente en Apps sin
  filtrar.
- **No se puede restaurar si el nombre ya lo ha cogido otra cuenta.** Es el
  unico impedimento real, y es una carrera contra terceros: cuanto antes.

**Versiones**: `MARKETING_VERSION` pasa a **1.0** el 2026-08-22 (era `0.1.0`),
para que coincida con la version que se le pone al app record nuevo. Verificado
en el binario compilado, no solo en el yml:

```sh
/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" <app>/Info.plist   # 1.0
```

`CURRENT_PROJECT_VERSION` sigue en `1` y NO se toca: el numero de build lo
incrementa Xcode Cloud (por eso el ultimo iba por el 10).

**El record viejo se borro el 2026-08-22** — solo habia uno, asi que el nombre
"RemoteSSH" queda libre para el nuevo.

### Export compliance: `ITSAppUsesNonExemptEncryption`

Sin esta clave, App Store Connect hace las preguntas de cifrado **en cada
subida**, y mientras no se contesten el build **no llega a TestFlight**. Puesta
en `project.yml` → `info.properties`, sale al `Info.plist` y se acaban las
preguntas.

Declarado **`false`**. **Decision consciente de Josu (2026-08-23), no una
deduccion de la tabla de Apple** — que dice lo contrario, y conviene que quede
escrito tal cual para que nadie lo "arregle" creyendo que fue un descuido:

| Cifrado que usa la app | Documentacion que pide Apple |
|---|---|
| Limitado al del sistema operativo de Apple | **Ninguna** |
| **Estandar de la industria, NO provisto por el OS** | **Declaracion francesa de cifrado** |
| Algoritmos propietarios | CCATS + declaracion francesa |

**RemoteSSH cae en la fila del medio, no en la primera.** El canal SSH lo cifra
`swift-nio-ssh` **enlazada en la app**: algoritmos estandar (Ed25519, AES,
ECDH), pero no los provee iOS. La primera fila es para apps que solo usan HTTPS
por `URLSession`, Keychain y Data Protection — aunque la app tambien llame a
`CryptoKit`, el cifrado del transporte no sale del OS.

Las cinco exenciones del cuestionario de ASC tampoco encajan: medica, propiedad
intelectual, **solo autenticacion/firma/descifrado**, banca, compresion fija.
SSH no se limita a autenticar, cifra toda la sesion.

**Contexto que sostiene la decision**: la declaracion francesa se exige por
distribuir en Francia, y esto va a **TestFlight interno**, al iPhone de Josu. No
hay distribucion publica.

**Si algun dia se publica de verdad**, esto hay que revisarlo: `true` +
subir la declaracion francesa en App Store Connect (App Information → Export
Compliance). Es un formulario de Apple, una sola vez, no por build. El CCATS
solo haria falta con cripto propietaria, que aqui no hay.

**Lo que la app usa de verdad** (por si cambia y hay que reevaluar): `CryptoKit`
(`SHA256`, `Curve25519`) y las librerias open source de Apple `swift-nio-ssh` /
`swift-crypto`. Ninguna criptografia propia.

Verificado donde importa — el binario, no el yml:

```sh
/usr/libexec/PlistBuddy -c "Print :ITSAppUsesNonExemptEncryption" <app>/Info.plist   # false
```
