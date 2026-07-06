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
from .filesystem    import (
    tool_list_dir, tool_read_file, tool_delete_file,
    tool_create_directory, tool_move_file, tool_find_files, tool_search_text
)
from .system        import tool_web_search, tool_launch_app
from .spotify       import tool_spotify_music
from .memory_tool   import tool_memorize_fact
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

    elif tool_name == "delete_file":
        return tool_delete_file(args.get("path", ""))

    elif tool_name == "create_directory":
        return tool_create_directory(args.get("path", ""))

    elif tool_name == "move_file":
        return tool_move_file(args.get("source", ""), args.get("destination", ""))

    elif tool_name == "find_files":
        return tool_find_files(args.get("directory", ""), args.get("pattern", ""))

    elif tool_name == "search_text":
        return tool_search_text(args.get("path", ""), args.get("query", ""))

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
        elif cls == "destructive":
            emit({
                "type":    "confirm_required",
                "command": cmd,
                "reason":  "Este comando puede eliminar o modificar datos de forma irreversible"
            })
        else:
            emit({"type": "run_command", "command": cmd})
        # El engine debe return aquí; la ejecución real llega vía run_confirmed/run_sudo
        return RUN_COMMAND_PENDING

    else:
        return "Herramienta desconocida"
