# Minerva

Minerva es una asistente de inteligencia artificial integrada en el escritorio, construida como un plugin de [Quickshell](https://github.com/quickshell-mirror/quickshell). Combina un frontend en QML (interfaz gráfica nativa Wayland) con un backend en Python que conecta modelos de lenguaje (Ollama local o Gemini en la nube) con herramientas del sistema operativo: ejecución de comandos, sistema de archivos, búsqueda web, control de Spotify, captura de pantalla y memoria persistente a largo plazo.

El nombre viene de la diosa romana de la sabiduría.

---

## Características principales

- **Dual engine:** Ollama (local, offline) y Gemini (API de Google Cloud) con streaming de tokens.
- **Agentic loop:** La IA puede invocar herramientas de forma iterativa (hasta 6 turnos) para completar tareas complejas.
- **Ejecución de comandos asíncrona** con streaming de salida en tiempo real — no se congela mientras espera.
- **Sistema de voz completo:** Wake word ("Minerva"), STT (Whisper), TTS (Piper) y detección de silencio.
- **SiriOrb:** Visualización animada por GPU (fragment shader) que reacciona al audio en tiempo real con RMS y 4 bandas FFT.
- **Memoria a largo plazo:** ChromaDB vectorial para recordar preferencias y contexto entre sesiones.
- **Proactividad (Tareas):** Conexión a PostgreSQL para gestionar tareas con alertas visuales sutiles en el SiriOrb. Soporta **tareas recurrentes** (diaria, semanal, mensual, anual) con auto-renovación en segundo plano.
- **Tool RAG:** Selección inteligente de herramientas relevantes vía embedding semántico para no saturar el contexto.
- **Seguridad:** Clasificación automática de comandos (safe / destructive / sudo) con confirmación en la UI.
- **Captura de pantalla:** Visión multimodal — Minerva puede ver tu pantalla y analizarla.
- **Spotify:** Control completo de reproducción vía OAuth2 (buscar, reproducir, pausar, cola, volumen).

---

## Estructura del proyecto

```text
optional/Minerva/
│
│  ── Frontend (QML) ──────────────────────────────────────────────────
│
├── plugin.json                  # Manifiesto del plugin (id, nombre, versión, autor)
├── qmldir                       # Registro de componentes QML (ChatWidget, SiriOrb)
├── Main.qml                     # Punto de entrada del plugin:
│                                #   - Inicia el proceso Python como subproceso
│                                #   - Servidor HTTP local (POST → backend)
│                                #   - Lee stdout del backend (JSON Lines → QML)
│                                #   - Estado global: configuración IA, grabación, transcripción
│                                #   - Expone barIcon, centerWidget y expandedPanel
├── ChatWidget.qml               # Interfaz de chat completa:
│                                #   - Burbujas de usuario e IA con streaming de tokens
│                                #   - Tarjetas de comando (pending / running / success / error)
│                                #   - Streaming de salida de comandos en tiempo real
│                                #   - Diálogo de confirmación para comandos destructivos/sudo
│                                #   - Input con micrófono, adjuntar imagen, placeholder dinámico
├── SiriOrb.qml                  # Orbe animado tipo Siri (GPU ShaderEffect):
│                                #   - Estados: idle, recording, transcribing, thinking, speaking
│                                #   - Recibe audioRms + 4 bandas FFT como uniforms
│                                #   - Acumulador de fase continuo (~60fps) para evitar saltos
│
├── shaders/
│   ├── siri_orb.frag            # Fragment shader GLSL: Simplex Noise + 4 ondas de color
│   └── siri_orb.frag.qsb       # Shader precompilado (Qt Shader Baker)
│
├── voice/                       # Modelos locales de voz
│   ├── es_MX-claude-high.onnx   # Modelo Piper TTS (español México, calidad alta)
│   ├── es_MX-claude-high.onnx.json
│   └── vosk-model-es/           # Modelo Vosk STT para wake word
│
│  ── Backend (Python) ────────────────────────────────────────────────
│
├── main.py                      # Punto de entrada del backend:
│                                #   - Servidor HTTP en 127.0.0.1:11435
│                                #   - Bucle principal: despacha mensajes (chat, run_confirmed,
│                                #     run_sudo, toggle_voice, cancel, ping, stop_tts)
│                                #   - Ejecución asíncrona de comandos (Popen + hilo)
│                                #   - Transcripción de voz (Whisper)
├── requirements.txt             # Dependencias pip del entorno virtual
├── .venv/                       # Entorno virtual de Python
│
└── backend/
    ├── __init__.py
    ├── README.md                # Documentación del backend (cómo agregar tools, etc.)
    ├── .env                     # Variables de entorno (credenciales de DB, etc.)
    │
    ├── core/                    # Lógica central y motores de IA
    │   ├── config.py            # Constantes globales:
    │   │                        #   - MODEL, HOME, MAX_FILE, MAX_DIR
    │   │                        #   - Paths de Spotify, voz
    │   │                        #   - Flags de disponibilidad (VOICE_AVAILABLE, etc.)
    │   ├── io.py                # Comunicación con QML:
    │   │                        #   - emit() / emit_error() → JSON Lines a stdout
    │   │                        #   - is_safe_path() → verificación $HOME
    │   │                        #   - classify_cmd() → safe / destructive / sudo
    │   ├── ollama_engine.py     # Engine de chat con Ollama (API REST local):
    │   │                        #   - Streaming de tokens, tool calls nativas
    │   │                        #   - Agentic loop con re-invocación iterativa
    │   ├── gemini_engine.py     # Engine de chat con Gemini (API OpenAI-compatible):
    │   │                        #   - SSE streaming, tool calls incrementales (delta chunks)
    │   │                        #   - Soporte multimodal (imágenes en base64)
    │   ├── voice.py             # VoiceManager (singleton voice_mgr):
    │   │                        #   - TTS: Piper (modelo ONNX) con cola de frases
    │   │                        #   - STT: Whisper (pywhispercpp)
    │   │                        #   - Wake word: Vosk con stream de audio continuo
    │   │                        #   - Detección de silencio para fin de grabación
    │   ├── audio_analyzer.py    # AudioAnalyzer: RMS + FFT de 4 bandas
    │   │                        #   - Suavizado exponencial
    │   │                        #   - Ventana Hann para reducir spectral leakage
    │   │                        #   - Alimenta los uniforms del shader SiriOrb
    │   └── memory.py            # ChromaDB: cliente persistente
    │                            #   - Colección minerva_memory (memoria a largo plazo)
    │                            #   - get_memory_context() para inyección en system prompt
    │   ├── tasks_db.py          # Conexión a PostgreSQL (CRUD de tareas + recurrencia):
    │                            #   - init_db(): crea tabla y agrega columnas recurrence/recurrence_day
    │                            #   - add_task(): inserta tarea; si es recurrente y no tiene due_date,
    │                            #     calcula automáticamente la primera ocurrencia futura
    │                            #   - complete_task(): marca como completada
    │                            #   - get_pending_tasks(): retorna pendientes con due_date y recurrencia
    │                            #   - renew_recurring_tasks(): renueva tareas vencidas actualizando
    │                            #     due_date a la próxima ocurrencia (UPDATE in-place, no INSERT)
    │                            #   - _next_due_date(): calcula siguiente ocurrencia (daily/weekly/monthly/yearly)
    │                            #   - _initial_due_date(): calcula primera ocurrencia para tareas nuevas
    │
    └── tools/                   # Herramientas que la IA puede invocar
        ├── __init__.py          # Exporta dispatch_tool() (despachador centralizado),
        │                        # OLLAMA_TOOLS, SYSTEM_PROMPT, get_relevant_tools() (RAG)
        ├── definitions.py       # SYSTEM_PROMPT (personalidad, reglas, contexto)
        │                        # OLLAMA_TOOLS (esquemas JSON de todas las herramientas)
        ├── filesystem.py        # list_dir, read_file, read_pdf, read_docx
        ├── system.py            # web_search (DuckDuckGo), launch_app (busca .desktop)
        ├── spotify.py           # spotify_music: OAuth2 completo, control de reproducción
        ├── screen.py            # capture_screen: grim → base64 → multimodal
        ├── memory_tool.py       # memorize_fact: guarda hechos en ChromaDB
        └── tasks.py             # manage_tasks: Gestiona tareas en PostgreSQL
                                 #   - Acciones: add, complete, list
                                 #   - Soporte de recurrence ('daily','weekly','monthly','yearly')
                                 #     recurrence_day (día del mes o semana) y recurrence_month (mes del año)
```

---

## Flujo de comunicación

El frontend y el backend se comunican mediante dos canales distintos:

```
┌──────────────────────┐          HTTP POST           ┌──────────────────────┐
│                      │  ──────────────────────────▶  │                      │
│      QML (Main.qml)  │    127.0.0.1:11435           │   Python (main.py)   │
│                      │                              │                      │
│                      │  ◀──────────────────────────  │                      │
│                      │     stdout (JSON Lines)       │                      │
└──────────────────────┘                              └──────────────────────┘
```

**QML → Python (peticiones):** La interfaz envía objetos JSON via HTTP POST al servidor local del backend. Los tipos de mensaje incluyen:

| Tipo              | Descripción                                          |
|-------------------|------------------------------------------------------|
| `chat`            | Mensaje del usuario con historial, imagen y settings |
| `run_confirmed`   | Confirmación para ejecutar un comando normal         |
| `run_sudo`        | Confirmación para ejecutar un comando con pkexec     |
| `toggle_voice`    | Iniciar/detener grabación de voz                     |
| `cancel`          | Cancelar operación en curso                          |
| `stop_tts`        | Detener la síntesis de voz                           |
| `ping`            | Health check (retorna `ready`)                       |

**Python → QML (eventos):** El backend escribe una línea JSON por evento a stdout, que QML lee vía `SplitParser`. Los tipos de evento incluyen:

| Tipo                     | Descripción                                            |
|--------------------------|--------------------------------------------------------|
| `tasks_pending`          | Señal silenciosa: hay tareas pendientes (incluye `urgent: bool`) |
| `tasks_cleared`          | Señal silenciosa: no hay tareas pendientes             |
| `ready`                  | Backend inicializado, modelo y home disponibles        |
| `token`                  | Token de texto generado por la IA (streaming)          |
| `done`                   | Respuesta completa de la IA                            |
| `tool_start`             | La IA comienza a usar una herramienta                  |
| `tool_result`            | Resultado de la herramienta (interno)                  |
| `run_command`            | Comando seguro auto-ejecutable                         |
| `command_start`          | Inicio de ejecución asíncrona de un comando            |
| `command_output`         | Línea de salida parcial del comando en ejecución       |
| `command_result`         | Resultado final del comando (output, returncode)       |
| `confirm_required`       | Comando destructivo que necesita confirmación           |
| `sudo_required`          | Comando que necesita privilegios elevados (pkexec)     |
| `voice_recording_started`| Grabación de micrófono iniciada                        |
| `voice_recording_stopped`| Grabación detenida                                     |
| `voice_transcribing`     | Transcribiendo audio con Whisper                       |
| `voice_recognized`       | Texto transcrito listo                                 |
| `wake_word_detected`     | Se detectó "Minerva" via Vosk                          |
| `silence_detected`       | Silencio detectado, fin de dictado                     |
| `voice_speaking_started` | TTS comienza a hablar                                  |
| `voice_speaking_stopped` | TTS terminó de hablar                                  |
| `audio_data`             | Métricas de audio en tiempo real (rms + 4 bandas FFT)  |
| `error`                  | Error genérico                                         |

---

## Flujo de un mensaje de chat

```
Usuario escribe → QML envía POST {"type":"chat"} → main.py recibe
    │
    ├── Inyecta fecha al SYSTEM_PROMPT
    ├── Consulta ChromaDB por memorias relevantes → las agrega al prompt
    ├── Construye historial [system, ...history, user]
    │
    └── _dispatch_chat() → elige engine según provider
            │
            ├── Ollama: do_chat() → API REST local, streaming
            └── Gemini: do_chat_gemini() → API SSE, streaming
                    │
                    ├── Emite tokens → QML los muestra en la burbuja de IA
                    │
                    ├── Si la IA decide usar tool_calls:
                    │       ├── dispatch_tool() ejecuta la herramienta
                    │       ├── Si es run_command:
                    │       │       ├── safe → emite "run_command" → QML auto-confirma
                    │       │       │          → main.py ejecuta async con Popen
                    │       │       │          → streaming de output → command_result
                    │       │       │          → reanuda chat con el resultado
                    │       │       ├── destructive → emite "confirm_required"
                    │       │       └── sudo → emite "sudo_required"
                    │       ├── Si es otra tool → ejecuta, inyecta resultado, reitera
                    │       └── Máximo 6 iteraciones
                    │
                    └── Sin tool calls → emite "done" → fin del turno
```

---

## Sistema de voz

Minerva tiene un pipeline de voz completo con tres subsistemas independientes:

**Wake word (siempre activo):** Un hilo dedicado escucha el micrófono continuamente usando Vosk con un modelo de español. Cuando detecta la palabra "minerva" en el flujo de audio, emite `wake_word_detected` y la UI activa la grabación automáticamente.

**STT (Speech-to-Text):** Al activar la grabación (botón de micrófono o wake word), el audio del micrófono se acumula en un búfer. Cuando se detiene la grabación (manual o por detección de silencio), el audio se transcribe con Whisper (pywhispercpp, modelo small) y el texto resultante se envía como si el usuario lo hubiera escrito.

**TTS (Text-to-Speech):** Mientras la IA genera tokens, las frases completadas (detectadas por puntuación: `.!?:\n`) se envían a una cola. Un hilo TTS las sintetiza con Piper (modelo ONNX es_MX) y otro hilo las reproduce secuencialmente. Durante la reproducción, un `AudioAnalyzer` calcula métricas (RMS + FFT) que se envían al frontend para animar el SiriOrb en sincronía con la voz.

---

## Herramientas disponibles para la IA

| Herramienta       | Archivo                | Descripción                                                      |
|-------------------|------------------------|------------------------------------------------------------------|
| `list_dir`        | `tools/filesystem.py`  | Lista el contenido de un directorio (dentro de $HOME)            |
| `read_file`       | `tools/filesystem.py`  | Lee el contenido de texto de un archivo                          |
| `read_pdf`        | `tools/filesystem.py`  | Extrae texto de un PDF                                           |
| `read_docx`       | `tools/filesystem.py`  | Extrae contenido de un archivo Word (.docx) a markdown           |
| `run_command`     | `tools/__init__.py`    | Ejecuta un comando bash (con clasificación de seguridad)         |
| `web_search`      | `tools/system.py`      | Busca en internet via DuckDuckGo (ddgs)                          |
| `launch_app`      | `tools/system.py`      | Busca y abre una app gráfica por nombre o sinónimo               |
| `spotify_music`   | `tools/spotify.py`     | Control de Spotify (play, pause, search, queue, volume, etc.)    |
| `capture_screen`  | `tools/screen.py`      | Captura la pantalla con grim → base64 → visión multimodal       |
| `memorize_fact`   | `tools/memory_tool.py` | Guarda un hecho en la memoria permanente (ChromaDB)              |
| `manage_tasks`    | `tools/tasks.py`       | Lee, crea y completa tareas en PostgreSQL. Soporta tareas recurrentes con `recurrence` y `recurrence_day` |

---

## Proactividad y Tareas (PostgreSQL)

Minerva puede gestionar tus pendientes usando una base de datos PostgreSQL remota o local (configurada en `backend/.env`). Esto le permite funcionar como un asistente proactivo real:

1. **Inyección de Contexto**: Al chatear, Minerva lee tus tareas pendientes y las inyecta en su `SYSTEM_PROMPT` para conocerlas y recordártelas de forma natural.
2. **Worker en Segundo Plano**: Un hilo en `main.py` sondea la BD cada 3 minutos. Antes de consultar pendientes, llama a `renew_recurring_tasks()` para renovar automáticamente cualquier tarea recurrente vencida.
3. **Indicador Visual Silencioso**: QML captura el evento y muestra el SiriOrb en el centro de tu pantalla por 20 segundos y deja un aviso en el widget. El orbe reacciona visualmente según el nivel de urgencia máximo con tinte de color en GPU y una animación de respiración/pulso: **Verde esmeralda** (baja urgencia, > 3 días), **Amarillo/Ámbar** (media urgencia, 1 a 3 días) o **Rojo vibrante parpadeante** (alta urgencia / vencida, < 24 horas).
4. **Herramienta IA**: Minerva tiene la tool `manage_tasks` para añadir nuevas tareas, ponerles fecha de vencimiento (`due_date`) o marcarlas como completadas. `manage_tasks` está **siempre disponible** en el Tool RAG (se inyecta aunque el embedding semántico no la seleccione) para garantizar que la IA la use ante cualquier pregunta sobre fechas o cobros.

### Tareas recurrentes

Las tareas pueden repetirse automáticamente configurando dos campos adicionales:

| Campo            | Tipo        | Descripción                                                                                  |
|------------------|-------------|----------------------------------------------------------------------------------------------|
| `recurrence`     | `VARCHAR(10)` | Frecuencia: `'daily'`, `'weekly'`, `'monthly'`, `'yearly'`. `NULL` = tarea única.          |
| `recurrence_day` | `INTEGER`   | Día de anclaje. Para `monthly`/`yearly`: día del mes (1-31). Para `weekly`: día de semana (0=lun…6=dom). |
| `recurrence_month` | `INTEGER` | Mes de anclaje (1-12). Solo usado para recurrencia `'yearly'` (ej. cumpleaños). |

**Flujo de renovación:** El worker llama a `renew_recurring_tasks()` cada 3 minutos. Si una tarea recurrente tiene `due_date < NOW()`, se calcula la próxima ocurrencia con `_next_due_date()` y se hace un `UPDATE` in-place (`due_date = próxima, status = 'pending'`). Si el backend estuvo apagado varios ciclos, avanza en bucle hasta quedar en el futuro. No se crean filas nuevas: el historial no crece.

**Primera ocurrencia:** Si se agrega una tarea recurrente sin `due_date` explícito, `add_task()` llama a `_initial_due_date()` para calcular la próxima ocurrencia futura antes de insertar. Ejemplo: si hoy es el 23 de julio y `recurrence='monthly', recurrence_day=11`, el `due_date` se fija automáticamente al `2026-08-11 08:00:00`.

**Esquema de la tabla `minerva_tasks`:**

```sql
CREATE TABLE minerva_tasks (
    id             SERIAL PRIMARY KEY,
    description    TEXT          NOT NULL,
    status         VARCHAR(20)   DEFAULT 'pending',  -- 'pending' | 'completed'
    due_date       TIMESTAMP     NULL,
    created_at       TIMESTAMP     DEFAULT CURRENT_TIMESTAMP,
    recurrence       VARCHAR(10)   NULL,               -- 'daily' | 'weekly' | 'monthly' | 'yearly'
    recurrence_day   INTEGER       NULL,               -- día de anclaje según recurrence
    recurrence_month INTEGER       NULL                -- mes de anclaje (para yearly)
);
```

---

## Seguridad de comandos

El módulo `io.py` clasifica cada comando en tres categorías usando expresiones regulares:

- **safe**: Se ejecuta inmediatamente y de forma asíncrona. El resultado se muestra en streaming.
- **destructive** (rm, dd, mkfs, shred, etc.): Requiere confirmación explícita del usuario en la UI.
- **sudo** (sudo, pkexec, pacman -S, systemctl start/stop, etc.): Se ejecuta via `pkexec` (polkit) tras confirmación.

---

## Memoria y RAG

Minerva usa ChromaDB para dos propósitos:

1. **Memoria a largo plazo** (colección `minerva_memory`): Almacena hechos, preferencias y contexto del usuario. Al inicio de cada chat, se consultan las memorias más relevantes semánticamente y se inyectan en el system prompt. La IA guarda nuevas memorias de forma proactiva cuando detecta información personal relevante.

2. **Tool RAG** (colección `minerva_tools`): Evita enviar las 10+ definiciones de herramientas en cada request. En su lugar, usa embeddings para seleccionar las herramientas más relevantes al mensaje del usuario (top-k configurable). `manage_tasks` se inyecta siempre en el resultado, independientemente del score semántico, para evitar que la IA use `run_command` para responder preguntas sobre tareas.

Base de datos persistida en: `~/.local/share/quickshell/minerva_tools/`

---

## Dependencias opcionales

El backend detecta automáticamente qué dependencias están instaladas y desactiva funcionalidades que no estén disponibles:

| Flag                 | Dependencias requeridas                  | Funcionalidad             |
|----------------------|------------------------------------------|---------------------------|
| `VOICE_AVAILABLE`    | sounddevice, soundfile, pywhispercpp     | Grabación y transcripción |
| `VOSK_AVAILABLE`     | vosk                                     | Wake word                 |
| `WEB_SEARCH_AVAILABLE`| ddgs                                    | Búsqueda web              |
| `CHROMADB_AVAILABLE` | chromadb                                 | Memoria y Tool RAG        |

Piper TTS se carga bajo demanda (lazy-load) al primer uso de voz.

---

## Configuración

Los ajustes de la IA se gestionan desde la UI de Quickshell y se pasan al backend en cada petición de chat:

| Ajuste            | Propiedad QML   | Descripción                                     |
|-------------------|-----------------|--------------------------------------------------|
| Proveedor         | `aiProvider`    | `"Ollama"` o `"Gemini"`                          |
| API Key Gemini    | `geminiApiKey`  | Clave de API para Google Generative AI           |
| Modelo Gemini     | `geminiModel`   | Ej: `gemini-2.5-flash`                           |
| Modelo Ollama     | `aiModel`       | Ej: `qwen3.5:9b`                                |
| Temperatura       | `aiTemperature` | Creatividad del modelo (0.0 – 1.0)              |
| Contexto          | `aiNumCtx`      | Ventana de contexto para Ollama (tokens)         |
| Thinking          | `aiThinking`    | Activar razonamiento extendido (Ollama)          |
