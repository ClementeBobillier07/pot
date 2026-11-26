# Prompt de traspaso — Pot (estado al 25-11-2026)

Copia todo lo que está bajo la línea en una nueva sesión de agente (Claude Code, Codex, etc.) abierta en esta repo, en un Mac con Xcode.

---

Estás continuando **Pot**, una app gratuita para macOS que convierte el uso local de Codex y Claude Code en una planta vectorial que crece según el ritmo de la persona, con estadísticas de tokens y un "Estimated API value" (nunca una factura). Lee primero `AGENTS.md`, `BASELINE.md`, `DECISIONS.md`, `BLOCKERS.md` y `PLAN.md`. El documento maestro del producto es "Pot documento maestro v1.1": no está en la repo y el dueño puede adjuntarlo. Las reglas de `AGENTS.md` son obligatorias: nada de publicar, desplegar, crear releases, activar analítica ni pedir secretos sin autorización explícita; nunca leer `auth.json`, credenciales ni contenido de conversaciones; no inventar precios, descargas ni datos.

## Cómo está construido

- Swift Package (macOS 14+). Targets:
  - `PotCore`: núcleo portable: adaptadores, SQLite, estadísticas, precios, motor de la planta.
  - `PotApp`: AppKit + SwiftUI: barra de menú, ventana principal y planta flotante en un `NSPanel` transparente que no se activa.
  - `PotDev`: herramientas de desarrollo; nunca se empaqueta.
  - `CZstd`: decodificador oficial zstd 1.5.7 incluido en el código (BSD).
  - `CSQLite`: SQLite del sistema.
- `landing/`: Next.js en inglés. La API de releases lee GitHub Releases y no hay analítica.
- Scripts: `scripts/build-macos.sh` (`.app` y DMG, firma ad-hoc o Developer ID), `scripts/notarize.sh`, `scripts/verify-distribution.sh`.
- CI: `.github/workflows/ci.yml` corre `swift test` en macOS y test, typecheck y build de la landing en Linux. `macos-validation.yml` es manual y genera un DMG local como artefacto.

## Comandos

```bash
swift test                                  # 47 pruebas
swift run Pot                               # app (preferencias en el dominio "Pot")
swift run Pot --show-window                 # abre el jardín directamente
swift run Pot --render-plants /tmp/plants   # renders sintéticos de la planta (no toca datos)
swift run -c release pot-dev reconcile      # conteos agregados de los registros reales, en una base temporal
scripts/build-macos.sh --arch universal --dmg
cd landing && npm ci && npm test && npm run typecheck && npm run build
```

Para reiniciar el estado de desarrollo: `rm -rf ~/Library/Application\ Support/Pot && defaults delete Pot`. El `.app` usa el dominio `com.pot.mac`.

## Lo que ya está verificado en un Mac real (macOS 27.0.1, Apple Silicon, Swift 6.4.2)

- Compila. Pasan 47/47 pruebas y el CI de GitHub está en verde.
- **Conteos reales idénticos a oráculos independientes:**
  - Codex: 6.357 llamadas y 1.392.511.987 tokens; coinciden las categorías de caché y de salida.
  - Claude Code: dedup exacto por `message.id`.
  - Reimportar agrega 0 eventos.
- 2,4 GB de registros importados en ~7 s, con unos 76 MB de memoria máxima. La app en reposo usa ~0,5 % de CPU y ~120 MB.
- La app arranca: onboarding, icono en la barra de menú, panel flotante transparente y jardín con datos reales.
- `.app` universal y DMG local generados con firma ad-hoc válida.
- Landing revisada en escritorio, a 390 px reales y en modo oscuro.

## Lo que se implementó (ver DECISIONS 15–22)

- **Formatos reales:**
  - Lectura de `.jsonl.zst`, que es el 97 % del historial de Codex.
  - Se saltan los registros sin tokens, que pueden pesar 10–17 MB, sin marcar el archivo como parcial.
  - Codex: `cache_write_input_tokens` y atribución por `session_meta.creator_account_id`.
  - Claude: `inference_geo: "global"` es precio estándar y los mensajes `<synthetic>` se ignoran.
  - Registros relevantes de hasta 16 MB; un `assistant` más grande se detecta igual y deja la cobertura parcial.
- **Precios:** catálogo con Opus, Sonnet y Haiku 5.5, incluidos los dos tramos de Haiku según el largo del prompt. `codex-auto-review` queda sin precio a propósito.
- **Motor de la planta:**
  - La calibración sigue la mediana observada hasta tener 7 días activos.
  - Motor de crecimiento 2: un mismo ritmo para todos (energía diaria = log2(1 + trabajo ÷ 10 M), máximo 3; el trabajo pondera lecturas de caché ×0,1 y salida ×5). Crecer cuesta energía y marchitarse es rápido: sin cambio el primer día sin uso, luego −0,18 por día, mínimo 0,15; se recupera en unos 3 días de uso. No hay pausa ni renombrar plantas. Detalle en `docs/ENGINE.md`.
  - Las ramas crecen equilibradas.
- **App:**
  - Arranque AppKit puro (ya no aparece la ventana vacía "Pot Settings") y menú mínimo para los atajos.
  - La cuenta con sesión iniciada ya no crea una planta vacía.
  - La primera importación es rápida; los escaneos se agrupan y solo se reprograman si avanzan.
  - Períodos Today / 7 days / 30 days / All, cobertura, exportación JSON sin identificadores, selector de esquina en el onboarding y en Ajustes, y submenú Presentation en la barra.
  - Ilustración nativa con el estilo de la landing: Codex como eucalipto en maceta salvia y Claude con hojas finas en terracota; salud visible y siete etapas de flor.
- **Kit:** `docs/BETA.md` con la plantilla de issue, `docs/RELEASE.md` y `docs/MAC_QA.md`.

## Lo que falta (en orden)

1. **QA interactiva en el Mac** (`docs/MAC_QA.md`). Nunca se probó con clics reales:
   - Deslizar con dos dedos sobre la planta flotante cambia de planta (una por gesto). En la ventana: flechas junto al nombre, puntos de página, cuadrícula del jardín (⌘G) con movimiento sutil, y en Ajustes las cuentas conectadas (email, método y plan).
   - Hover: que aparezca la X (círculo blanco con borde negro, arriba a la derecha de la planta) y que pulsarla oculte la planta sin abrir la app. En el escritorio no hay flechas: las plantas se cambian dentro de Pot.
   - Clic en la planta: abre la app con ese perfil.
   - Arrastre y posición guardada.
   - Clics que atraviesan las zonas transparentes.
   - Que la planta no robe el foco mientras escribes en otra app.
   - Las cuatro esquinas con el Dock a la izquierda, abajo y a la derecha.
   - Spaces, pantalla completa y Stage Manager.
   - Varios monitores, incluso desconectando el que guardó la posición.
   - Suspensión y reactivación.
   - Inicio de sesión desde `/Applications`.
   - VoiceOver y movimiento reducido.
   - La exportación.

   Corrige lo que falle con pruebas y capturas solo de las ventanas de Pot (`screencapture -l <windowID>`).
2. **Ajustes de producto con evidencia de la beta** (`docs/BETA.md`):
   - Ajustar el día de referencia (10 M unidades de trabajo) y la velocidad de marchitamiento con el uso real de la beta.
   - Precio de `codex-auto-review`.
   - Hay mucho espacio vacío sobre las plantas pequeñas en la ventana principal.
   - Si conviene un selector de esquina más visual.
3. **Beta con 5–10 personas:** días 1 y 7, más `pot-dev reconcile` para validar otras versiones de Codex y Claude Code.
4. **Decisiones del dueño:** licencia del código, dominio, bundle ID definitivo (hoy `com.pot.mac`), macOS mínimo y soporte Intel (el build universal existe, pero nunca se ejecutó en un Mac Intel).
5. **Lanzamiento** (`docs/RELEASE.md`, cada paso con autorización explícita):
   - Apple Developer Program, certificado Developer ID y perfil de `notarytool`.
   - Build firmado y notarizado.
   - Prueba en un Mac limpio con el DMG descargado en cuarentena.
   - Tag y GitHub Release.
   - Deploy de la landing con `POT_GITHUB_REPOSITORY`; verificar el botón de descarga y el contador.

## Advertencias

- Las preferencias de `swift run Pot` viven en el dominio `Pot`. Antes de entregar, limpia cualquier dato de prueba creado en el Mac del dueño.
- No imprimas rutas, emails ni contenido de los registros. Para inspeccionar formatos, solo claves y tipos.
- Claude Code borra sus sesiones antiguas por retención propia; Pot conserva lo que ya importó.
- La planta nace el día de la instalación: el historial importado alimenta las estadísticas, pero no vuelve adulta a la planta.
