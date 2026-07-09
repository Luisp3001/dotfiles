#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Paquete tools de Minerva.

Expone:
  - OLLAMA_TOOLS            → lista de esquemas JSON de herramientas
  - SYSTEM_PROMPT           → prompt del sistema
  - get_relevant_tools()    → RAG sobre ChromaDB para seleccionar tools relevantes
  - dispatch_tool()         → despachador centralizado (elimina la duplicación entre engines)
"""
import re
import sys

from .definitions   import OLLAMA_TOOLS, SYSTEM_PROMPT  # noqa: F401
from .filesystem    import tool_list_dir, tool_read_file, tool_read_pdf, tool_read_docx
from .system        import tool_web_search, tool_launch_app
from .spotify       import tool_spotify_music
from .memory_tool   import tool_memorize_fact
from .screen        import tool_capture_screen, ScreenCapture
from ..core.memory  import chroma_client, CHROMADB_AVAILABLE
from ..core.io      import classify_cmd, emit
from ..core.config  import HOME

# ─────────────────────────────────────────────────────────────────────────────
# Colección ChromaDB para RAG de tools
# ─────────────────────────────────────────────────────────────────────────────
_tool_collection = None
try:
    if chroma_client and CHROMADB_AVAILABLE:
        _tool_collection = chroma_client.get_or_create_collection(name="minerva_tools")
        _tool_docs = [t["function"]["description"] for t in OLLAMA_TOOLS]
        _tool_ids  = [t["function"]["name"]        for t in OLLAMA_TOOLS]
        _tool_collection.upsert(documents=_tool_docs, ids=_tool_ids)
except Exception as e:
    print(f"Error sincronizando tools en ChromaDB: {e}", file=sys.stderr)


def get_relevant_tools(prompt: str, top_k: int = 5) -> list:
    """
    Selecciona las herramientas más relevantes para el prompt usando ChromaDB.
    Si ChromaDB no está disponible, devuelve todas las tools.
    """
    if not _tool_collection or not prompt.strip():
        return OLLAMA_TOOLS
    try:
        results = _tool_collection.query(
            query_texts=[prompt],
            n_results=min(top_k, len(OLLAMA_TOOLS))
        )
        if not results["ids"] or not results["ids"][0]:
            return OLLAMA_TOOLS
        relevant_names = results["ids"][0]
        return [t for t in OLLAMA_TOOLS if t["function"]["name"] in relevant_names]
    except Exception as e:
        print(f"Error consultando ChromaDB: {e}", file=sys.stderr)
        return OLLAMA_TOOLS


# ─────────────────────────────────────────────────────────────────────────────
# Sentinel para herramientas que requieren confirmación externa
# ─────────────────────────────────────────────────────────────────────────────
class _RunCommandPending:
    """
    Valor centinela retornado por dispatch_tool() cuando run_command
    emitió una solicitud de confirmación (sudo / destructive / normal)
    y el engine debe salir del loop de herramientas.
    """
    pass

RUN_COMMAND_PENDING = _RunCommandPending()


# ─────────────────────────────────────────────────────────────────────────────
# Despachador centralizado
# ─────────────────────────────────────────────────────────────────────────────
def dispatch_tool(tool_name: str, args: dict) -> "str | _RunCommandPending":
    """
    Ejecuta la herramienta indicada con los argumentos dados.

    Retorna:
      - str  → resultado listo para agregar al historial como rol 'tool'
      - RUN_COMMAND_PENDING → la herramienta es run_command y ya emitió el
        evento apropiado (run_command / confirm_required / sudo_required).
        El engine debe hacer return inmediatamente para esperar confirmación.
    """
    if tool_name == "list_dir":
        return tool_list_dir(args.get("path", HOME))

    elif tool_name == "read_file":
        return tool_read_file(args.get("path", ""))

    elif tool_name == "read_pdf":
        return tool_read_pdf(args.get("path", ""))

    elif tool_name == "read_docx":
        return tool_read_docx(args.get("path", ""))


    elif tool_name == "web_search":
        try:
            max_res = int(args.get("max_results", 5))
        except (ValueError, TypeError):
            max_res = 5
        return tool_web_search(args.get("query", ""), max_res)

    elif tool_name == "memorize_fact":
        return tool_memorize_fact(args.get("fact", ""))

    elif tool_name == "launch_app":
        return tool_launch_app(args.get("query", ""))

    elif tool_name == "spotify_music":
        try:
            vol = int(args.get("volume", 50))
        except (ValueError, TypeError):
            vol = 50
        return tool_spotify_music(
            action      = args.get("action",      ""),
            query       = args.get("query",       ""),
            uri         = args.get("uri",         ""),
            search_type = args.get("search_type", "track"),
            volume      = vol
        )

    elif tool_name == "run_command":
        cmd = args.get("command", "").strip()
        cls = classify_cmd(cmd)
        if cls == "sudo":
            clean = re.sub(r"^\s*sudo\s+", "", cmd)
            emit({"type": "sudo_required", "command": clean})
            return RUN_COMMAND_PENDING
        elif cls == "destructive":
            emit({
                "type":    "confirm_required",
                "command": cmd,
                "reason":  "Este comando puede eliminar o modificar datos de forma irreversible"
            })
            return RUN_COMMAND_PENDING
        else:
            # Comandos safe: ejecutar directamente sin esperar confirmación
            emit({"type": "run_command", "command": cmd})
            try:
                import subprocess as _sp
                r = _sp.run(
                    ["bash", "-c", cmd],
                    capture_output=True, text=True, timeout=30,
                    cwd=HOME, env={**__import__("os").environ}
                )
                out = (r.stdout + r.stderr).strip()
                out = out[:4096] or "(sin salida)"
                returncode = r.returncode
            except _sp.TimeoutExpired:
                out, returncode = "Tiempo de espera agotado (30s)", -1
            except Exception as e:
                out, returncode = str(e), -1
            emit({
                "type":       "command_result",
                "command":    cmd,
                "output":     out,
                "returncode": returncode,
                "success":    returncode == 0
            })
            return out

    elif tool_name == "capture_screen":
        result = tool_capture_screen(output=args.get("output", ""))
        if isinstance(result, ScreenCapture):
            # Inyectar la imagen en el historial del motor (campo image_b64)
            # Los engines (ollama_engine, gemini_engine) ya saben manejar este campo.
            # Retornamos un dict especial que los engines detectan para hacer el inject.
            return result
        # Si hubo error, result es un str con el mensaje
        return result

    else:
        return "Herramienta desconocida"
