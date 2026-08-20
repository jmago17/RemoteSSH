# RemoteSSH

> Contexto para Claude Code. Generado desde Minis (`/var/minis/shared/remotessh/ESTADO.md`).

## Identidad

- Repo: `jmago17/RemoteSSH.git`
- Carpeta en el Mac: `~/Documents/Developer/RemoteSSH`
- Proyecto: `RemoteSSH.xcodeproj`
- Scheme: `RemoteSSH`

Repo **publico** en GitHub. No commitear nada sensible.

## Donde esta ahora

**Publicado en GitHub como repo publico**: https://github.com/jmago17/RemoteSSH
22 commits, rama `main` con tracking a `origin/main`. Arbol limpio, nada sin
pushear.

Las 5 fases previstas ya estaban completas de una sesion anterior (Brrr push,
generacion de claves in-app, pinning TOFU de host key, restore con
tmux-resurrect, multi-host). Esta sesion fue rediseño + iPad + teclado.

Ultimos commits:
- `aea84dc` feat(keys): configurable key rail slots + full special-key panel replacing keyboard
- `47f578c` feat(ipad): first-class iPad layout with NavigationSplitView, adaptive settings, keyboard shortcuts
- `a21dcc0` fix: suppress SwiftTerm native accessory bar (duplicated custom KeyCap rail)
- `8abb863` wip: before Claude Design redesign (baseline green build)  ← baseline pre-rediseño

Compila en verde en iPhone 17 y iPad Air 13" (M4).

**Verificado 2026-08-20 11:04**: `HEAD` sigue en `aea84dc`, `main...origin/main`
sin divergencia, `git status --porcelain` vacio. Nada pendiente de commit ni de
push; el trabajo de la sesion del 19 quedo integro en el remoto.

## Pendiente

- **`gh auth login -h github.com` en el Mac**: el token de `gh` para `jmago17`
  esta caducado. El push de hoy se hizo con `GITHUB_TOKEN` del entorno de Minis,
  **sin dejar credencial en el Mac** → un `git push` local pedira auth.
- **Untrackear `.wrangler/cache/pages.json`** y añadir `.wrangler/` a
  `.gitignore`. Es estado local de Cloudflare Worker, sin credenciales
  (verificado), pero no deberia estar versionado. Sigue trackeado a
  2026-08-20. Comando:
  ```sh
  cd ~/Documents/Developer/RemoteSSH
  git rm -r --cached .wrangler
  printf '\n## Cloudflare Worker local state\n.wrangler/\n' >> .gitignore
  git commit -m "chore: untrack .wrangler local state"
  ```
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

