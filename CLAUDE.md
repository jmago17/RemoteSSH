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

Repo publico: https://github.com/jmago17/RemoteSSH — `main` con tracking a
`origin/main`, todas las ramas de feature mergeadas.

**Se distribuye por TestFlight interno via Xcode Cloud.** El workflow es
"Internal TestFlight Build" y dispara solo con cada push a `main`. Compila en
verde para iPhone 17 Pro e iPad Pro 11" (M5), iOS 27.

Identidad: bundle id **`com.maromeapps.RemoteSSH`**, version **1.0**, App Apple
ID 6804001421.

**Como funciona hoy, una frase por pieza:**

- **La app lee el Mac por SSH bajo demanda.** No hay servidor, ni daemon, ni
  nada persistente que mantener — tmux ya es el daemon de PTYs.
- **El estado de los agentes lo publican sus propios hooks**, ya no se deduce de
  la pantalla: `~/.claude/settings.json` y `~/.codex/config.toml` ejecutan
  `~/.claude/hooks/remotessh-notify.sh`, que escribe
  `~/.remotessh/state/<pane>.json`. El parser de pantalla sigue como fallback.
- **Las notificaciones salen del propio Mac a APNs**, sin intermediarios: el
  hook firma un JWT ES256 con la clave `.p8` y hace POST a
  `api.push.apple.com`. Brrr queda de respaldo si eso falla.
- **El resumen de Apple Intelligence se genera en el Mac**, no en el telefono, y
  viaja ya hecho en el cuerpo de la notificacion.
- **El badge del icono** lo lleva `~/.remotessh/badge`: lo incrementa el hook y
  la app lo pone a cero al abrirse.

**Que NO se ha probado nunca en dispositivo** (el simulador arranca headless,
ver Trabas): el menu de slot con pulsacion larga, la altura del
`ExpandedKeyPanel`, y la barra de historial de copy-mode.

## Pendiente

- **Ver un push propio disparado por un agente de verdad.** El envio manual esta
  **verificado por Josu en el iPhone** (2026-08-26): notificacion de RemoteSSH
  entregada y **globo rojo en su icono**, que era el objetivo entero. Ojo a la
  distincion: que `apns-push` devuelva `OK` solo dice que APNs acepto el envio;
  que aparezca la notificacion con badge solo se puede confirmar mirando el
  telefono. Falta el camino entero cuando un agente termina solo. Se distingue en
  `~/.claude/hooks/remotessh-notify.log`: `sent via APNs` es el camino nuevo,
  `sent` a secas es el respaldo de Brrr.
- **Codex no publica `SessionEnd`/`StopFailure`** (no dispara nada al arrancar,
  probablemente no existen ahi). Sus tres eventos cubren working/idle/awaiting,
  que es lo que la UI muestra.
- **Retirar Brrr** cuando el push propio lleve tiempo sin fallar: mantener los
  dos duplica rutas de aviso.
- **Franja de atajos `⌘N · ⌘R · ⌘,`** del mock: los atajos funcionan, falta el
  hint visual. Ojo: **`⌘R` ya no existe** desde que se quito el menu `⋯`.
- Sin `README` de instalacion orientado a terceros, con el repo ya publico.
- **Sospecha sin confirmar**: la app deja panes a 1 fila de alto. Apunta a un
  `resize` enviado antes de conocer la altura de la vista.

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

**Ya NO esta bloqueado.** Lo que decia esta seccion — que App Store Connect
rechazaba los binarios del SDK beta y quedaba pendiente montar Xcode Cloud —
dejo de ser cierto el 2026-08-23. Se entrega a TestFlight con normalidad.

El llavero se re-bloquea solo y da `errSecInternalComponent` al firmar por
terminal. **No pedirle a Josu la contraseña del llavero**: se desbloquea con un
`Run` manual desde Xcode.

Lo aprendido peleandose con esto (detalle en las secciones de sesion):

- Xcode Cloud compila con un **SDK mas viejo** que el Mac.
- **ITMS-90626**: la metadata de App Intents no puede contener "mac".
- **Borrar un app record es un error**: hay que RESTAURARLO, no recrearlo.
- Export compliance declarado en el Info.plist.
- El workflow tenia **Manual** como unica start condition: por eso ningun push
  disparaba nada.
- El entitlement `aps-environment` exige que el App ID tenga **Push
  Notifications** habilitado, o la firma falla.

## Estado del proyecto

**Este fichero es la fuente de verdad.** El `ESTADO.md` de
`_MinisBackup/shared/remotessh/` al que apuntaba esta seccion **ya no existe**:
aquel directorio compartido perdio ficheros por conflictos de sincronizacion.
Git es lo unico fiable.

## Piezas que viven FUERA del repo

Nada de esto sale en `git log`, y sin ello la mitad de la app no funciona. Las
copias canonicas estan versionadas en `scripts/`; las que **corren** viven fuera
de iCloud a proposito, porque un fichero evicted a 0 bytes rompe en silencio.

| Ruta (en el Mac) | Que es | Copia en el repo |
|---|---|---|
| `~/.claude/hooks/remotessh-notify.sh` | el hook: publica estado y manda el aviso | `scripts/remotessh-notify.sh` |
| `~/.claude/hooks/summarise-turn` | binario que resume el turno con FoundationModels | `scripts/summarise-turn.swift` |
| `~/.claude/hooks/apns-push` | binario que firma el JWT y habla con APNs | `scripts/apns-push.swift` |
| `~/.claude/hooks/remotessh-notify.log` | **el primer sitio donde mirar** cuando no llega un aviso | — |
| `~/.claude/settings.json` → `hooks` | registra 6 eventos de Claude Code | — |
| `~/.codex/config.toml` → `[[hooks.*]]` | 3 eventos de Codex. **NO tocar `notify`** (es de Computer Use) | — |
| `~/.remotessh/apns.json` + `AuthKey_*.p8` | credenciales de APNs, 0600 | — (secreto) |
| `~/.remotessh/apns-token.json` | lo escribe la APP por SSH | — |
| `~/.remotessh/state/<pane>.json` | estado de cada agente | — |
| `~/.remotessh/badge` | contador del globo rojo | — |

Recompilar los binarios tras tocar su fuente:

```sh
export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer
cd ~/Documents/Developer/RemoteSSH
xcrun swiftc -swift-version 6 -O scripts/summarise-turn.swift -o ~/.claude/hooks/summarise-turn
xcrun swiftc -swift-version 6 -O scripts/apns-push.swift     -o ~/.claude/hooks/apns-push
cp scripts/remotessh-notify.sh ~/.claude/hooks/remotessh-notify.sh
```

**Diagnostico rapido cuando no llega una notificacion**, por orden:

```sh
tail -20 ~/.claude/hooks/remotessh-notify.log   # ¿se disparo el hook siquiera?
```

- `skip (X): N client(s) attached` → estabas mirando esa sesion; es a proposito.
- `skip (X): turn took Ns` → turno de menos de 60s; a proposito.
- `sent via APNs (X)` → camino nuevo, todo bien.
- `sent (X)` a secas → cayo al respaldo de Brrr; mirar por que fallo APNs.
- **nada** → el hook no llego a correr: mirar `$TMUX_PANE` (¿el agente corre
  dentro de tmux?) y, en Codex, si el directorio esta **confiado**.

En la app, Ajustes → Notificaciones → fila **Push** dice si hay token y si
subio.

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

**Deteccion determinista, no heuristica**: `ps -t #{pane_tty} -o stat=,args=`,
buscando el binario `codex` entre los procesos cuyo estado lleva `+` (el grupo en
primer plano del terminal, la misma nocion que tmux publica como
`pane_current_command`). `TmuxService.snapshot` solo paga ese segundo round trip
cuando el comando es un interprete generico (`node`, `bun`, `deno`, `python`,
`python3`); `claude.exe`, `zsh` o `vim` ya se explican solos. Si `ps` no lo
prueba, cae al test textual de `CodexRecogniser.looksLikeCodexFrame`, que exige
DOS marcas (composer `›` + status bar `modelo · ~` o `modelo · /ruta` como ultima
linea no vacia) porque cualquiera de las dos sola da falsos positivos.

#### Los DOS bugs que hicieron que esto no funcionara (2026-08-23)

Se escribio el 22 usando `ps -o args= -p #{pane_pid}` y **no funcionaba en
absoluto**. Dos fallos independientes, y el segundo tapaba al primero:

**1. `#{pane_pid}` NO es el proceso en primer plano, es el shell raiz del pane.**
Cuando alguien abre un pane y teclea `codex`, el agente es un HIJO de ese shell,
asi que `ps -p #{pane_pid}` contesta **`-zsh`**. Solo parece correcto si el pane
se creo con el agente como su comando — que es exactamente como lo montaba el
primer arnes:

```sh
tmux new-session -d -s probe "codex"     # pane_pid ES codex  -> el arnes pasaba
tmux new-session -d -s probe; ...        # pane_pid es zsh, codex es hijo -> real
```

**Un arnes que no reproduce como se usa la cosa de verdad da confianza falsa.**
La prueba buena es correr el parser contra los panes que ya hay en la maquina.

El tty lo arregla porque lo comparte todo el grupo de procesos del pane. El
filtro por `+` importa: Codex deja MCP servers vivos (`safaridriver --mcp`,
`node_repl`, `codex-code-mode-host`) que heredan el tty y responderian "Codex"
despues de que Codex haya salido.

**2. El fallback textual exigia una ruta absoluta.** La status bar real de un
Codex en el home dice `gpt-5.6-terra medium · ~`, no `· /Users/...`. El patron
pedia `\s·\s/` y no casaba nunca con `~`.

**3. (de diseño) `isCodex` devolvia el veredicto de `ps` en cuanto su salida no
estaba vacia.** Como `ps` contestaba `-zsh` — no vacio — un pane de Codex real
quedaba DESCARTADO sin llegar al fallback. Ahora el frame se prueba siempre que
`ps` no lo haya probado, asi que un fallo del proceso ya no bloquea al texto.

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
maquina con el `display-message` exacto que manda la app. **Es el arnes que vale**,
porque usa panes creados como los crea Josu, no como los crearia un test. Pasada
del 2026-08-23, con un Codex arrancado a mano en un pane:

```
[NewsRaider] cmd=node  -> agent=codex / working("Working")   summary=Working · 5s
[RemoteSSH]  cmd=claude.exe -> claudeCode / working("Scampering") · 4m 24s · ↓11.8k
[sidenotes]  cmd=claude.exe -> claudeCode / working("Grooving") · 2m 9s · ↓6.9k
```

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

### DESBLOQUEADO: el build 11 llego a TestFlight (2026-08-23)

Tras restaurar el app record y subir `MARKETING_VERSION` a 1.0, Xcode Cloud
**vuelve a entregar**: el build **11** paso validacion y se instalo desde
TestFlight en el iPad. Se acabo el "Preparing build for App Store Connect
failed".

Cual de las dos cosas lo arreglo no se sabe por separado — se hicieron a la vez.

**Como saber que lleva un build sin mirar numeros** (util porque los arreglos
internos no se ven): en la lista de sesiones, el boton `⋯` **desaparecio** el
2026-08-22 y en su sitio hay un **engranaje** junto al `+`. Y en la pantalla de
una sesion hay un `⋯` junto a *Terminal* (el de Kill Session). Si se ve el `⋯`
en la LISTA, el build es anterior a `800e1f8`.

El build 11 lleva hasta `e18f11b` incluido, pero **NO** el arreglo del
reconocedor de Codex (`5c09bd5`), que es posterior. De ahi que Codex siguiera
saliendo como `node` en el iPad con el 11 instalado.

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

## Sesion 2026-08-24: arranque lento y la app que no volvia del background

Dos sintomas, **una raiz**: nada de lo que toca la red tenia limite de tiempo, y
nada se cancelaba al pasar a segundo plano.

### 1. Tardaba 30s en decir que el Mac esta apagado

**No era que faltase un timeout: es que no le pasabamos el nuestro.**
`SSHClient.connect` de Citadel acepta `connectTimeout` y su default es
**30 segundos** (verificado en el checkout, no de memoria):

```swift
// Citadel/Sources/Citadel/Client.swift:288
connectTimeout: TimeAmount = .seconds(30)
```

Dos cambios:

- `SSHConnector.connectTimeout = .seconds(4)`, explicito. Un Mac despierto
  contesta en milisegundos por LAN o Tailscale; 4s es generoso.
- **Sondeo previo** en `HostReachability`, antes de intentar SSH siquiera.

**Por que NO un ping ICMP** (fue la primera idea): en iOS un ping necesita un
raw socket, que no se concede sin un entitlement especial. El equivalente
practico es un **connect TCP al puerto 22 con `NWConnection`** — nativo, sin
permisos, y ademas prueba lo que de verdad importa (que el puerto SSH conteste),
no que una maquina responda a un echo.

Bonus: separa dos fallos que antes se veian igual — *el Mac duerme* (no hay
nadie) vs *el Mac esta vivo pero SSH nos rechaza* (credencial, host key, tmux).

**Medido** con `<scratchpad>/reach/`, que compila el `HostReachability.swift`
REAL:

| caso | resultado |
|---|---|
| `127.0.0.1:22` con sshd escuchando | reachable en **6 ms** |
| `127.0.0.1:9` sin nada escuchando | no reachable en **0 ms** |
| `192.0.2.1:22` (TEST-NET, no enrutable — un Mac dormido se ve asi) | no reachable en **1587 ms** |
| host que no resuelve | no reachable en **49 ms** |

**Decision de producto de Josu (2026-08-24)**: cuando el sondeo falla, la app
**ofrece** despertar el Mac, no lo hace sola. Despertarlo en cada apertura seria
intrusivo: abrir la app para mirar no deberia encender el Mac.

La lista de sesiones **no se vacia** cuando el sondeo falla. Que el Mac se
duerma no significa que las sesiones hayan desaparecido, y borrar la pantalla
cada vez que se cierra la tapa pierde lo ultimo que estabas mirando.

### 2. Al volver de otra app, nunca volvia: habia que forzar el cierre

`startPolling()` estaba en `.onAppear` y `stopPolling()` en `.onDisappear`, y
**`onDisappear` NO se dispara al pasar a segundo plano** — para SwiftUI la vista
sigue en pantalla. Secuencia del cuelgue:

1. La app pasa a background con un `refresh()` esperando un socket SSH.
2. iOS suspende el proceso con el socket abierto.
3. Al volver, el socket esta muerto, pero el `await` dentro del bucle **no se
   entera nunca** y no reanuda.
4. `pollTask` sigue != nil → `startPolling()` no hace nada.
5. `isRefreshing` se quedo en `true` y su `defer` no llega a correr → la UI gira
   para siempre.

Arreglo: `.onChange(of: scenePhase)` en `SessionListView` — `.background` para
el poller, `.active` lo arranca de nuevo. Funciona **aunque la tarea colgada no
llegue a enterarse de que la cancelaron**, porque la nueva no comparte su socket.
`stopPolling()` ademas baja `isRefreshing`, que es lo que dejaba la rueda dando
vueltas.

`.inactive` se ignora a proposito: es transitorio (app switcher, una llamada), no
suspende el proceso, y ademas se dispara durante el arranque.

### Xcode Cloud no disparaba solo: el workflow solo tenia "Manual"

Del 2026-08-22 al 24, **ningun push disparo un build**. Habia que lanzarlos a
mano desde App Store Connect. La causa: el workflow **"Internal TestFlight
Build"** tenia como unica start condition **Manual**. No estaba roto nada, es que
nunca se le dijo que escuchara la rama.

**Como se diagnostico sin acceso a App Store Connect**, por si vuelve a pasar.
Xcode Cloud publica un check run en cada commit que compila, y eso SI se ve
desde el repo:

```sh
for SHA in $(git log --format=%H -8 origin/main); do
  gh api "repos/jmago17/RemoteSSH/commits/$SHA/check-runs" \
    --jq '.check_runs[] | "\(.app.slug):\(.name):\(.conclusion // .status)"'
done
```

Lo que se saca de ahi:

- Si aparece `xcode-cloud:...`, la **GitHub App esta instalada y con acceso** —
  la conexion no es el problema. Si no apareciera en ningun commit, habria que
  mirar la instalacion de la app.
- `gh api repos/jmago17/RemoteSSH/hooks` sale **vacio y es normal**: Xcode Cloud
  usa la GitHub App, no un webhook clasico. Un `/hooks` vacio NO prueba nada.
- **Un check run NO distingue un build automatico de uno manual.** Aqui se
  interpretaron tres checks sueltos como "el disparo automatico funciona a
  veces", y eran los tres builds que Josu habia lanzado a mano. La pista real
  era que no correlacionaban ni con los ficheros tocados (un commit de solo
  `CLAUDE.md` disparo; uno de `Sources/` no) ni con el tiempo.
- `gh api /user/installations` **no sirve** con el token normal de `gh`: da 403,
  hace falta un token autorizado para una GitHub App.

**Arreglo (solo en App Store Connect)**: Workflow → Edit Workflow → Start
Conditions → `+` → **Branch Changes** → Source Branch `main`.

Dos avisos al configurarlo:

- **Files and Folders**: sin filtro, cada push consume un build, y en este repo
  hay muchos commits de solo documentacion. El filtro util seria `Sources/`,
  `project.yml`, `ci_scripts/`, `swiftpm/` — pero mal puesto devuelve el
  sintoma "no dispara nunca", que es mas caro de diagnosticar que unos builds de
  mas.
- **Auto-cancel Builds**: con disparo por rama, varios pushes seguidos encolan
  builds; con auto-cancel el nuevo cancela al anterior.

## Sesion 2026-08-24 (2): el estado deja de leerse de la pantalla

Hasta ahora el estado de un agente se **deducia de su salida**: buscar un
spinner `…(Nm Ns` para "trabajando", perderlo para "parado". Funciona hasta que
el agente cambia como se dibuja — y Claude Code **rota el glifo y el verbo**
(`✽`/`·`/`✻`/`✢`, "Beaming", "Hullaballooing"), asi que lo unico anclable era la
forma del cronometro entre parentesis. Es inferencia sobre un dibujo, no una
señal del proceso.

Ahora los **hooks de ciclo de vida** publican el estado real. Idea tomada de
Superset (superset.sh), que resuelve lo mismo asi.

### Lo que YA existia (no se partia de cero)

`~/.claude/hooks/remotessh-notify.sh` ya servia a Claude Code y a Codex desde el
2026-08-21: sacaba la sesion tmux de `$TMUX_PANE` y empujaba a Brrr. La pieza de
identidad que Superset resuelve con una env var propia (`SUPERSET_TERMINAL_ID`)
aqui ya salia gratis de `$TMUX_PANE`, sin necesidad del wrapper de comando en el
PATH que ellos instalan.

### La decision de arquitectura: DOS canales, no uno

| | Pregunta | Vida | Transporte |
|---|---|---|---|
| **Estado** | "¿que hace ahora?" | perdura, se consulta | **fichero en el Mac, leido por SSH** |
| **Aviso** | "acaba de terminar" | efimero, se empuja | push (Brrr) — ya existia |

**Cloudflare no pinta nada aqui**, aunque fuera la primera idea. Un Worker
añadiria un intermediario que autenticar, un secreto que rotar y un punto de
fallo, para transportar un dato que ya viaja por un canal autenticado y abierto:
la propia conexion SSH de la app. El Mac sigue sin exponerse a internet.

### Que escribe el hook

`~/.remotessh/state/<pane>.json`, **uno por PANE** (no por sesion: dos agentes
en dos panes de la misma sesion se pisarian). Escritura **atomica** (tmp + `mv`
en el mismo filesystem) para que la app no pueda leer medio registro.

```json
{"v":1,"pane":"%12","session":"NewsRaider","agent":"claude-code",
 "state":"working","since":1756070000,"updated":1756070042,
 "session_id":"abc-123","last_message":null,"question":null}
```

Eventos registrados en `~/.claude/settings.json` (merge, respetando lo que
hubiera): `SessionStart`, `UserPromptSubmit`, `Stop`, **`StopFailure`**,
`Notification`, `SessionEnd`.

**`StopFailure` es el que faltaba y no es cosmetico**: es el hook de error de
API y *la sesion sigue viva*, asi que sin el un turno fallido dejaba el estado
clavado en "working" esperando un `Stop` que no iba a llegar.

### Las tres guardas, que son lo que hace esto correcto

1. **Subagentes.** `agent_id` solo aparece cuando el hook se dispara DENTRO de
   un subagente (Task tool). Sin filtrarlo, cada subagente que acaba dispara
   `Stop` y marca la sesion como parada mientras el hilo principal sigue.
   **Esto era un bug real del script desde el 21**: avisaba "ha terminado" a
   mitad de trabajo.
2. **Nunca asumir `Stop`.** Si el payload no se puede parsear o el evento no se
   reconoce, el script **no toca el estado**. Un estado perdido se corrige en el
   siguiente evento; un "ha terminado" falso te manda al Mac para nada.
3. **Estado escrito ANTES de las guardas de notificacion.** "Ya lo estas
   mirando" y "el turno duro menos de 60s" son razones para no INTERRUMPIRTE,
   no para dejar que la app muestre un estado viejo.

### Estado obsoleto, sin boton manual

Un hook no puede publicar "me han matado": un `kill -9` no dispara nada. Superset
lo resuelve con un boton "Clear Status". Aqui no hace falta: la app **ya pregunta
a tmux que corre en el pane**, asi que si el registro dice `working` pero el pane
volvio a ser un shell, el registro es mentira y se descarta. Ademas caduca a las
24h y se rechaza cualquier `v` distinto de 1.

### Quien manda cuando ambos hablan

El hook decide **el estado**; la pantalla aporta **el adorno** (el verbo real que
Claude Code esta usando ahora, los tokens) y solo **si coincide** con el hook. Si
discrepan, gana el hook y lo de la pantalla se descarta entero — nunca un banner
mitad de una fuente y mitad de otra. `AgentStatus.source` (`.hook` / `.screen`)
deja rastrear de donde salio cada lectura.

**El parser de pantalla NO se borra**: es el fallback para agentes lanzados antes
de instalar los hooks, o en otra maquina. La app nunca queda peor que antes.

### Lo que gana el resumen de Apple Intelligence

`lastConclusion` reconstruia el texto raspando el pane y deshaciendo el
hard-wrap de Claude Code — el trozo mas fragil de todo el pipeline. El payload
de `Stop` trae `last_assistant_message` **intacto**. Ademas, como ese texto no
depende del marcador `⏺`, **Codex tambien puede tener tarjeta de conclusion**
cuando el estado viene del hook.

### Arneses

- `<scratchpad>/hooktest.sh` — dispara el hook REAL con payloads de cada evento
  y comprueba el fichero resultante, incluidas las tres guardas.
- `<scratchpad>/hookstate/` — mete el `TranscriptParser` REAL por 9 casos:
  hook+pantalla de acuerdo, hook `idle` ganando a una pantalla que aun muestra
  spinner, `error` → `failed`, registro obsoleto por pane y por antiguedad,
  ausencia de registro (no regresion), version futura, y JSONL corrupto.

**Trampa de las pruebas**: `echo '...\n...'` en zsh convierte `\n` en salto real
y deja el JSON invalido. Al depurar el hook, parecia que `Stop` no escribia
estado; en realidad el script hacia lo correcto (no reconocer el evento → no
tocar nada). Usar `printf '%s'`.

**Sin probar en dispositivo**: todo esto compila y pasa arneses contra panes
reales, pero no se ha visto en el iPhone.

### Codex tambien publica estado (2026-08-25)

**Codex usa EL MISMO contrato de payload que Claude Code** — verificado
capturando payloads reales, no supuesto: `hook_event_name`, `session_id`,
`last_assistant_message`. Nada de `type` ni `sessionId`. Por eso un solo script
sirve a los dos, y por eso el nombre del evento **no** distingue quien lo manda.

**El bug que eso provocaba**: la primera version adivinaba el agente por un
campo `type` que Codex no envia, asi que **toda sesion de Codex se etiquetaba
"Claude Code"** en la app. El estado era correcto; la identidad no.

**El discriminador bueno es `transcript_path`**, porque cada agente escribe su
transcript en su propia casa:

```
Codex:       ~/.codex/sessions/2026/08/25/rollout-….jsonl
Claude Code: ~/.claude/projects/…
```

Cascada, por si algun dia falta ese campo: `transcript_path` → variables
`CODEX_*` del entorno (`CODEX_MANAGED_PACKAGE_ROOT` esta presente en la
instalacion por npm) → el campo `model` (`claude*` / `gpt*`).

**Eventos de Codex: se dejan los tres que ya tenia** (`UserPromptSubmit`,
`Stop`, `PermissionRequest`) y NO se añaden `SessionStart`/`SessionEnd`/
`StopFailure`. Comprobado que **Codex no dispara nada al arrancar**, asi que
esos eventos probablemente ni existen ahi; y lo unico que aportaria `SessionEnd`
es borrar un fichero que la app ya descarta por obsoleto en cuanto el pane deja
de correr un agente. Tocar `config.toml` tiene riesgo (ahi vive Computer Use) y
beneficio marginal.

**Recordatorio**: los hooks de Codex solo cargan si el directorio esta
**confiado**. Al abrir Codex en una carpeta nueva pregunta *"Do you trust the
contents of this directory?"*, y responder que no significa, textualmente, que
no se carguen hooks — o sea, ningun estado y ninguna notificacion para esa
sesion.

**Depuracion de payloads**, ya integrada en el script:

```sh
touch ~/.claude/hooks/DEBUG     # empieza a volcar a ~/.claude/hooks/payloads.jsonl
rm    ~/.claude/hooks/DEBUG     # para
```

Ojo al usarlo: el fichero crece tambien con las reinyecciones de prueba, asi que
un `tail -1` puede no ser el payload que crees. Filtrar por
`grep '"hook_event_name":"Stop"'`. Y borrarlo al terminar: lleva los prompts y
los cwd reales.

### El raw pane se descuadraba al llegar texto nuevo (2026-08-25)

Sintoma (iPhone): al volver de la vista terminal el bloque se ve bien, **hasta
que el agente imprime una linea nueva**; entonces se desconfigura.

**Causa**: `TranscriptTurnView` escalaba la fuente para que cupiera **la linea
mas larga del contenido** (`contentColumns`). Esa medida cambia cada vez que
llega salida, asi que el tamaño de letra cambiaba con ella y **el bloque entero
se re-dibujaba**. Volver de la terminal se veia bien justo porque acababa de
recalcularse; la siguiente linea lo deshacia.

Medido con el arnes `<scratchpad>/width/`, alimentado por el parser real:

```
sin pane_width:  12.50pt -> 7.50pt   al llegar una linea larga   <- el descuadre
con pane_width:   9.56pt -> 9.56pt   (no depende del texto)
```

**Arreglo**: sizear a `#{pane_width}`, las columnas REALES del pane, que es la
regla que sigue un terminal — y que solo cambia cuando cambia el pane, no cuando
cambia el texto. El scrollback escrito cuando el pane era mas ancho se sale al
scroll horizontal, exactamente como en un terminal.

`contentColumns` se conserva como fallback para cuando tmux no dio el ancho
(un `PaneSnapshot` construido desde texto plano).

**Leccion general**: cualquier medida derivada del CONTENIDO es inestable en una
vista que se refresca sola. Anclar a la geometria de la fuente del dato — aqui,
el pane — no al dato.

### Scroll horizontal en el raw pane: la anchura era IMPOSIBLE, no mal escalada

El arreglo anterior (sizear a `#{pane_width}` en vez de al contenido) era
correcto pero **no bastaba**, y conviene entender por que antes de tocar nada
mas.

**Los numeros**: un pane de escritorio mide **162 columnas**. Meter 162 columnas
en los ~374pt de un iPhone pide **3.6pt** de letra. El suelo es 7.5pt. **No cabe
de ninguna manera** — ningun ajuste de fuente arregla una anchura imposible.

**Dos medidas mal leidas por el camino, que costaron tiempo:**

1. `awk '{print length($0)}'` cuenta **BYTES**, no caracteres. Las lineas salian
   de 486 y el pane era de 162: son las reglas `────`, **3 bytes por glifo**
   (162 × 3 = 486). Para medir columnas de verdad hay que contar caracteres:
   ```sh
   tmux capture-pane -p -J -t X | python3 -c "import sys;print(max(len(l.rstrip()) for l in sys.stdin))"
   ```
2. De ahi se dedujo que la culpa era del flag `-J` (unir lineas envueltas).
   **Falso**: sin `-J` las lineas miden lo mismo. `-J` sigue haciendo falta para
   el parser de turnos.

**Por que "al volver de la terminal se ve bien y luego se estropea"**: abrir la
terminal adjunta un cliente, y tmux (con `window-size latest`) encoge la ventana
a lo que ese cliente puede mostrar. Al cerrarla el cliente se va y la ventana
vuelve a las dimensiones del Mac. La app ya provocaba el arreglo **por
accidente**.

**Arreglo**: hacerlo a proposito. `TmuxService.fitWindow` pide
`resize-window -x <columnas que caben>` al abrir la sesion. Tres guardas:

- **`#{session_attached}` debe ser 0.** Si hay un terminal abierto en el Mac,
  reflowear la ventana bajo las manos del usuario no es asunto de la app.
- **Solo estrecha, nunca ensancha.**
- **Una vez por pantalla abierta**, no en cada refresco: si el usuario ensancha
  la ventana desde su mesa, la app no debe pelearse con el.

Es **reversible solo**: al hacer attach desde el Mac, `window-size latest` la
devuelve a su tamano.

**La anchura objetivo son ~61 columnas**, no las 77 que caben al suelo de 7.5pt:
`TranscriptTurnView.readableFontSize` (9.5pt) es el tamano al que se quiere leer,
y `columnsThatFit` calcula la anchura que lo consigue. Cambiar la barra de scroll
por una lupa no es un arreglo.

**Verificado contra tmux real**, con las guardas:

```
NewsRaider (0 clientes, 162col) -> __RESIZED__ -> 61col, lineas de 61 chars
RemoteSSH  (1 cliente,  122col) -> no hace nada
```

### El resumen se genera en el MAC, no en el iPhone (2026-08-25)

El resumen de Apple Intelligence se generaba en la app, en primer plano, al
abrirla. Ahora lo genera el **Mac**, dentro del hook, y viaja ya hecho en el
campo `message` del push.

**Por que ahi y no en una Notification Service Extension** (que era la idea
obvia para "resumen dentro de la notificacion"): una NSE solo se ejecuta si el
push lleva `mutable-content: 1`, y **Brrr no expone ese campo**, asi que ni
arrancaria. Y aunque se montara APNs propio, seria resolver en el sitio dificil
—una extension con limite de memoria bajo y ~30s— lo que el Mac hace gratis: es
quien tiene el texto completo en el momento de construir el aviso.

`scripts/summarise-turn.swift` → binario en `~/.claude/hooks/summarise-turn`:

```sh
xcrun swiftc -swift-version 6 -O scripts/summarise-turn.swift \
  -o ~/.claude/hooks/summarise-turn
```

Verificado en este Mac: `SystemLanguageModel.default.availability` → **available**
(el simulador NO lo tiene, ver la sesion del 21). Medido: **~4.3s** para un turno
de 576 caracteres; el timeout del hook `Stop` es de 30s. Un texto ya corto sale
en 10ms **sin invocar el modelo**.

Salvaguardas, porque esto vive en la ruta critica de un aviso:

- Autolimite de **8s** dentro del binario (`asyncAfter` + `exit`).
- Cualquier fallo → el hook cae al texto crudo recortado. **Un resumidor no
  puede ser la razon de que no llegue una notificacion.**
- El resumen se genera **despues** de las guardas de ruido, asi que una sesion
  que estas mirando no gasta 4s de modelo: medido, 69ms.
- Corte por palabra, no `prefix` a pelo: cortar a medias deja cosas como
  "se reconocieran correc" y parece que la notificacion se ha roto.

Payload real capturado (con un servidor local en vez de Brrr):

```
title      Kaffa
subtitle   ha terminado
message    Reescribí el reconocedor de Codex usando el tty del pane y arreglé
           el fallback textual con rutas relativas, logrando que los tres…
open_url   remotessh://open/Kaffa
```

### El globo rojo del icono: lo que se puede y lo que no

**Campos que acepta Brrr** (doc oficial, verificado): `title`, `subtitle`,
`message`, `thread_id`, `sound`, `volume`, `open_url`, `image_url`, `icon_url`,
`expiration_date`, `filter_criteria`, `interruption_level`.

**NO acepta `badge`. Ni `category`, ni `mutable-content`.**

Consecuencia que no es obvia: **el globo rojo al llegar el aviso necesita
exactamente la misma infraestructura que responder desde la notificacion**
(APNs propio: key `.p8`, un Worker que firme el JWT y hable con
`api.push.apple.com`, y el device token). No es el objetivo barato que parece.

Lo que SI se hizo sin nada de eso: `SessionListModel.refreshBadge()` pone en el
icono el numero de sesiones con `hasUnread`, via
`UNUserNotificationCenter.setBadgeCount`. Se actualiza en cada refresco y al
marcar una sesion como leida.

**Su limite, con todas las letras**: solo corre mientras la app corre. Es
correcto justo despues de mirar la app, y se queda viejo mientras esta cerrada
— que es precisamente cuando un badge seria mas util. Sirve para no perder el
rastro de sesiones sin leer al salir; NO para enterarte de algo nuevo sin abrir.

### Push propio: el Mac habla con APNs directamente (2026-08-25)

**Por que no vale un proveedor de push de terceros**: la notificacion pertenece
a SU app, asi que el globo rojo aparece en el icono de esa app, no en el de
RemoteSSH. No es un campo que falte en su API — se deduce de quien recibe el
push. Para badgear nuestro icono, el push tiene que ser nuestro.

**Por que NO hay un Worker de Cloudflare en medio**, que era el plan inicial.
APNs solo exige dos cosas y el Mac tiene las dos (verificado, no supuesto):

```
curl del sistema        -> HTTP2
api.push.apple.com      -> responde HTTP/2 desde este Mac
CryptoKit P256          -> firma de 64 bytes r||s, que es lo que pide JWS
```

El hook ya corre en el Mac. Un relay solo anadiria una pieza que mantener, un
secreto que rotar, un punto de fallo, y obligaria a subir la clave `.p8` a un
tercero. **El coste de Cloudflare no era el problema (todo cabia en el plan
gratuito): el problema era la pieza de mas.**

**Piezas**

| Fichero | Que hace |
|---|---|
| `scripts/apns-push.swift` → `~/.claude/hooks/apns-push` | firma el JWT y hace POST a APNs |
| `scripts/setup-apns.sh` | deja `~/.remotessh/apns.json` listo a partir del `.p8` |
| `Sources/Services/APNSRegistration.swift` | la app sube su device token **por SSH** |
| `~/.remotessh/badge` | contador que lleva el Mac; la app lo pone a 0 al abrirse |

**Trampas de APNs, todas ya cubiertas en el codigo:**

- **`sandbox` vs `production`**: depende de como se firmo el binario, no de una
  preferencia. Debug → sandbox, TestFlight/App Store → production. Cruzarlos da
  `BadDeviceToken` y **no llega nada, sin explicacion**. Por eso la app graba el
  entorno junto al token en vez de dejar que el emisor lo adivine.
- **`aps-environment: development`** en el entitlement es lo correcto tambien
  para TestFlight: Apple re-firma y lo convierte a production. Ponerlo a
  production a mano rompe los builds de desarrollo.
- **El JWT se cachea** en `~/.remotessh/apns-jwt.json` (45 min): Apple exige
  renovarlo al menos cada hora y **no mas de una vez cada 20 minutos**. Un hook
  es un proceso efimero y sin cache firmaria uno por aviso.
- **`rawRepresentation`** de la firma P256 es `r||s`, que es lo que espera JWS —
  NO la codificacion DER que devuelven otras librerias.
- El cuerpo de la respuesta de error trae el motivo real (`BadDeviceToken`,
  `ExpiredProviderToken`, `TopicDisallowed`). Se registra: sin eso, depurar APNs
  es adivinar.

**Migracion sin apagar nada**: el hook usa APNs **solo si** existe
`~/.remotessh/apns.json` Y el binario. Si falla el envio, cae al proveedor de
siempre. Verificado que con APNs sin configurar el camino viejo funciona igual,
resumen incluido.

**Estado (2026-08-25)**: clave creada y **configurada en este Mac**
(`~/.remotessh/apns.json`, key `ZXZM9K4NJ4`, permisos 600). La `.p8` se copio
FUERA de iCloud a proposito: venia de `iCloud Drive/Downloads` y un `.p8`
evicted a 0 bytes tumbaria las notificaciones en silencio, igual que ya paso con
ficheros `.swift`.

**Como validar la mitad servidor sin tener el telefono delante**: mandar un push
con un token de dispositivo falso.

```sh
printf '{"token":"%s","environment":"production"}' "$(printf '0%.0s' {1..64})" \
  > ~/.remotessh/apns-token.json
~/.claude/hooks/apns-push --session Test --body x
# -> HTTP 400 {"reason":"BadDeviceToken"}   = JWT ACEPTADO, todo bien
# -> InvalidProviderToken / ExpiredProviderToken = la clave o el JWT estan mal
```

`BadDeviceToken` es el resultado BUENO en esa prueba: significa que Apple
autentico el JWT y solo rechazo el destino, que era falso.

**Falta**: abrir la app una vez en el iPhone con un build que lleve el
entitlement `aps-environment` (build 14 en adelante). La app escribe sola el
token en `~/.remotessh/apns-token.json` por SSH.

**Nota de seguridad**: `~/.remotessh/apns-jwt.json` se escribe con **0600**. Es
una credencial valida una hora: quien la lea puede mandar notificaciones a esta
app. Por defecto el fichero salia legible por cualquiera.

### El token de APNs no subia: una carrera que podia perderse SIEMPRE

Build 22 (`ee7ecb2`) instalado, con el entitlement y la capability correctos, y
aun asi `~/.remotessh/apns-token.json` no aparecia nunca. El badge SI se
escribia (`~/.remotessh/badge`, por SSH), asi que el canal funcionaba: el fallo
estaba antes.

**La causa**: el token se subia directamente desde el callback del delegate,
detras de un `guard isConfigured, let credential = …`. iOS entrega el token a
los pocos instantes del arranque, **normalmente antes de que el modelo haya
leido las credenciales SSH**. El guard fallaba, el token se tiraba, y **nada
reintentaba**. No es una carrera que a veces falle: puede fallar todas.

**Arreglo**: `APNSRegistration.remember` guarda el token en cuanto llega, pase
lo que pase, y `uploadPendingIfNeeded` lo sube en el primer `refresh()` con
credenciales — que es el primer momento en que se sabe que funcionan. Idempotente,
asi que en el caso normal no hace nada.

**El error de fondo, que es el que hay que no repetir**: los dos caminos de
fallo eran **silenciosos**. `didFailToRegisterForRemoteNotifications` no dejaba
rastro "para que un fallo de push no molestara", y el `catch` de la subida
estaba vacio. Desde el Mac, "no hay fichero de token" se ve igual tanto si iOS
nunca dio token, como si la subida fallo, como si la app no se ha abierto. Sin
esa distincion no se puede arreglar nada — solo adivinar.

Ahora hay una fila **Push** en Ajustes → Notificaciones con el estado real:

| Estado | Que significa |
|---|---|
| `Not registered yet` | iOS aun no ha dado token |
| `Registration failed: …` | iOS rechazo el registro, con el motivo |
| `Token held, not yet sent to the Mac` | hay token, falta subirlo (o la subida fallo) |
| `Sent to the Mac (production)` | listo; el entorno debe cuadrar con la clave |

**Regla general**: en algo que solo se puede diagnosticar desde el otro lado de
un cable, un fallo silencioso no es prudencia, es quedarse ciego.

### FUNCIONA: primer push propio entregado y VISTO en el iPhone (2026-08-26)

```
~/.claude/hooks/apns-push --session Prueba --body "…" --badge 3   ->  OK
```

Token en el Mac: `~/.remotessh/apns-token.json`, entorno **production** (viene
de TestFlight, como debe). Notificacion entregada por RemoteSSH, con globo rojo
en SU icono — que era el objetivo entero y lo unico que un proveedor de terceros
no puede dar.

**Un despiste que costo un rato**: la fila "Push" de Ajustes decia
`Token held, not yet sent to the Mac` cuando el token YA estaba subido. La fila
leia `APNSRegistration.status` (que consulta UserDefaults) al construir la
vista, y SwiftUI no tiene motivo para observar UserDefaults: la subida ocurre en
el primer `refresh()` con credenciales, que perfectamente puede pasar despues.
Arreglado releyendo en `onAppear`. **Un indicador de diagnostico que se queda
viejo es peor que no tenerlo**: manda a buscar donde no es.
