# Arquitectura del Backend Minerva

Este documento describe la estructura y el funcionamiento del backend en Python de Minerva, el cual se encarga de conectar la interfaz de usuario (QML) con los modelos de inteligencia artificial (Ollama y Gemini), además de proporcionar herramientas (tools) para interactuar con el sistema operativo, controlar Spotify, realizar búsquedas web y gestionar la memoria a largo plazo.

## 📂 Estructura de Directorios

La carpeta `backend/` está dividida en dos módulos principales: `core/` (lógica central y motores) y `tools/` (las herramientas que usa la IA).

```text
optional/Minerva/
├── main.py                    # Punto de entrada (servidor HTTP + bucle principal)
├── backend/
│   ├── core/
│   │   ├── config.py          # Constantes globales (modelo, rutas, flags de dependencias)
│   │   ├── io.py              # Funciones de I/O (emit, emit_error) y seguridad (is_safe_path, classify_cmd)
│   │   ├── voice.py           # Gestor de voz (TTS con Kokoro, STT con Whisper, Wake-word con Vosk)
│   │   ├── memory.py          # Cliente de ChromaDB para recuperar memoria a largo plazo
│   │   ├── ollama_engine.py   # Lógica del bucle de chat interactivo con Ollama (local)
│   │   └── gemini_engine.py   # Lógica del bucle de chat interactivo con Gemini (nube)
│   └── tools/
│       ├── __init__.py        # Exporta `dispatch_tool()` que unifica la ejecución de todas las tools
│       ├── definitions.py     # Contiene el SYSTEM_PROMPT y la lista `OLLAMA_TOOLS` (JSON schemas)
│       ├── filesystem.py      # Implementación de tools de sistema de archivos (list, read, delete, move...)
│       ├── system.py          # Implementación de tools del sistema (launch_app, web_search)
│       ├── spotify.py         # Implementación y gestor OAuth para `spotify_music`
│       └── memory_tool.py     # Implementación de la tool `memorize_fact`
```

---

## 🚀 Flujo de Ejecución (Cómo funciona)

1. **Arranque:** `main.py` se ejecuta e inicia un servidor HTTP en el puerto `11435`.
2. **Recepción de Mensajes:** La interfaz en QML envía peticiones POST en formato JSON Lines al servidor.
3. **Despacho (Routing):** El bucle principal en `main.py` lee el mensaje. Si es un chat, prepara el historial (inyectando la memoria y el system prompt) y decide si usar Ollama (`do_chat`) o Gemini (`do_chat_gemini`).
4. **Bucle Agentic:** El engine seleccionado se comunica con la IA y emite tokens de texto al vuelo. Si la IA decide usar herramientas, el engine interrumpe, llama a `dispatch_tool()` de `backend/tools/__init__.py`, y vuelve a enviar el resultado a la IA de manera iterativa.
5. **Comunicación al Frontend:** Cualquier resultado se manda a stdout mediante `emit()` (`backend/core/io.py`), donde QML lo interpreta para dibujar la interfaz de usuario.

---

## 🛠️ Cómo agregar una nueva herramienta (Tool)

Agregar una nueva herramienta para la IA es sencillo gracias a la estructura modular. Sigue estos pasos:

### 1. Definir el esquema JSON
Abre `backend/tools/definitions.py` y agrega tu nueva herramienta al arreglo `OLLAMA_TOOLS`. Por ejemplo:

```python
{
    "type": "function",
    "function": {
        "name": "get_weather",
        "description": "Obtiene el clima actual de una ciudad",
        "parameters": {
            "type": "object",
            "properties": {
                "city": {
                    "type": "string",
                    "description": "El nombre de la ciudad"
                }
            },
            "required": ["city"]
        }
    }
}
```

### 2. Implementar la lógica
Crea la función que ejecutará la acción real. Puedes colocarla en un archivo existente en `backend/tools/` o crear un archivo nuevo (por ejemplo, `backend/tools/weather.py`).

```python
# backend/tools/weather.py
def tool_get_weather(city: str) -> str:
    # Lógica para obtener el clima (ej. llamar a una API)
    return f"El clima en {city} es soleado y hace 25°C."
```

### 3. Registrar en el Despachador (Dispatcher)
Abre `backend/tools/__init__.py`. 
Primero importa tu nueva función:

```python
from .weather import tool_get_weather
```

Luego, agrégala al bloque `if/elif` dentro de la función `dispatch_tool()`:

```python
    elif tool_name == "get_weather":
        return tool_get_weather(args.get("city", ""))
```

¡Listo! La IA ahora sabe que la herramienta existe, y cuando decida usarla, el backend sabrá cómo ejecutarla y devolverle el resultado.

---

## ⚠️ Herramientas que requieren confirmación (`run_command`)

Por seguridad, comandos de terminal (`run_command`) pueden requerir confirmación (por ejemplo, al usar `sudo` o comandos destructivos como `rm`).

Cuando `dispatch_tool()` detecta esto, emite una solicitud al frontend (`confirm_required` o `sudo_required`) y retorna el valor especial `RUN_COMMAND_PENDING`. Los engines (`ollama_engine.py` y `gemini_engine.py`) están programados para salir del bucle inmediatamente al recibir esto. Una vez que el usuario confirma en la interfaz gráfica, el mensaje `"type": "run_confirmed"` o `"type": "run_sudo"` llega a `main.py`, se ejecuta el comando, se inyecta el resultado al historial, y **se reanuda el chat** llamando de nuevo al engine.

---

## 🧠 Memoria Vectorial y RAG

Minerva utiliza **ChromaDB** para dos propósitos distintos:

1. **Memoria de Herramientas (Tool RAG):** Para evitar saturar el contexto cuando el número de tools crezca, `backend/core/memory.py` ofrece `get_relevant_tools(prompt)`. Esto filtra el `OLLAMA_TOOLS` basándose en qué herramientas son semánticamente relevantes al último mensaje del usuario.
2. **Memoria a Largo Plazo:** Al recibir el mensaje del usuario en `main.py`, se consulta la colección `minerva_memory`. Los recuerdos relevantes se inyectan dinámicamente en el `SYSTEM_PROMPT` para que Minerva recuerde preferencias o datos de sesiones pasadas.
