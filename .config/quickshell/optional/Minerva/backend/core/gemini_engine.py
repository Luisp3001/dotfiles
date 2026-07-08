#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Engine de chat para Gemini (API compatible con OpenAI) — Minerva.

Maneja el loop agentic con streaming SSE, tool calls via delta chunks,
y re-invocación iterativa hasta obtener la respuesta final.
"""
import json
import re
import sys
import urllib.error
import urllib.request

from .io     import emit, emit_error
from .voice  import voice_mgr, VOICE_AVAILABLE
from ..tools import dispatch_tool, get_relevant_tools, OLLAMA_TOOLS, RUN_COMMAND_PENDING
from ..tools.screen import ScreenCapture

_GEMINI_URL = "https://generativelanguage.googleapis.com/v1beta/openai/chat/completions"


def do_chat_gemini(
    history:     list,
    max_iters:   int   = 6,
    model:       str   = "gemini-2.5-flash",
    api_key:     str   = "",
    temperature: float = 0.7,
) -> None:
    """
    Ejecuta un turno de chat usando la API compatible con OpenAI de Gemini.
    Emite tokens en tiempo real al QML vía stdout.
    """
    if not api_key:
        emit_error("API Key de Gemini no configurada en los ajustes del widget.")
        return

    if VOICE_AVAILABLE:
        voice_mgr.tts_stop_event.clear()

    # Obtener el último mensaje del usuario para el RAG de tools
    user_prompt = next(
        (m.get("content", "") for m in reversed(history) if m.get("role") == "user"),
        ""
    )
    dynamic_tools = get_relevant_tools(user_prompt, top_k=15) if user_prompt else OLLAMA_TOOLS

    # Claves válidas para la API OpenAI-compatible de Gemini
    _valid_keys = {"role", "content", "tool_calls", "tool_call_id", "name"}

    for _iteration in range(max_iters):
        full_response      = ""
        current_tool_calls = []
        buffer_frase       = ""

        clean_history = []
        for msg in history:
            clean_msg = {k: v for k, v in msg.items() if k in _valid_keys}
            if "image_b64" in msg:
                clean_msg["content"] = [
                    {"type": "text", "text": msg.get("content", "")},
                    {"type": "image_url", "image_url": {"url": f"data:image/jpeg;base64,{msg['image_b64']}"}}
                ]
            clean_history.append(clean_msg)

        req_data = {
            "model":       model,
            "messages":    clean_history,
            "tools":       dynamic_tools,
            "stream":      True,
            "temperature": temperature,
        }

        req = urllib.request.Request(
            _GEMINI_URL,
            data    = json.dumps(req_data).encode("utf-8"),
            headers = {
                "Authorization": f"Bearer {api_key}",
                "Content-Type":  "application/json"
            }
        )

        try:
            with urllib.request.urlopen(req) as resp:
                for line in resp:
                    line = line.decode("utf-8").strip()
                    if not line or line == "data: [DONE]":
                        continue
                    if not line.startswith("data: "):
                        continue
                    try:
                        chunk = json.loads(line[6:])
                    except json.JSONDecodeError:
                        continue

                    delta = chunk.get("choices", [{}])[0].get("delta", {})

                    # ── Tokens de texto ────────────────────────────────────
                    if delta.get("content"):
                        token          = delta["content"]
                        full_response += token
                        buffer_frase  += token
                        emit({"type": "token", "content": token})

                        if VOICE_AVAILABLE and not voice_mgr.tts_stop_event.is_set():
                            if re.search(r'[.!?\n:]', token) and len(buffer_frase.strip()) > 5:
                                clean_frase = buffer_frase.replace("*", "").replace("#", "").strip()
                                if clean_frase:
                                    voice_mgr.tts_queue.put(clean_frase)
                                buffer_frase = ""

                    # ── Tool calls (se construyen de forma incremental) ────
                    if "tool_calls" in delta:
                        for tc in delta["tool_calls"]:
                            idx = tc.get("index", 0)
                            while len(current_tool_calls) <= idx:
                                current_tool_calls.append({
                                    "id":       "",
                                    "type":     "function",
                                    "function": {"name": "", "arguments": ""}
                                })
                            for k, v in tc.items():
                                if k in ("index", "type"):
                                    continue
                                if k == "function":
                                    for fk, fv in v.items():
                                        if isinstance(fv, str):
                                            current_tool_calls[idx]["function"].setdefault(fk, "")
                                            current_tool_calls[idx]["function"][fk] += fv
                                        else:
                                            current_tool_calls[idx]["function"][fk] = fv
                                elif isinstance(v, str):
                                    current_tool_calls[idx].setdefault(k, "")
                                    current_tool_calls[idx][k] += v
                                else:
                                    current_tool_calls[idx][k] = v

        except urllib.error.HTTPError as e:
            err = e.read().decode("utf-8")
            emit_error(f"Error de Gemini API: {e.code} - {err}")
            return
        except Exception as e:
            emit_error(f"Error de conexión con Gemini: {e}")
            return

        # Sin tool calls → respuesta final
        if not current_tool_calls:
            if VOICE_AVAILABLE and buffer_frase.strip() and not voice_mgr.tts_stop_event.is_set():
                clean_frase = buffer_frase.replace("*", "").replace("#", "").strip()
                if clean_frase:
                    voice_mgr.tts_queue.put(clean_frase)
            emit({"type": "done", "full_response": full_response})
            return

        history.append({"role": "assistant", "content": full_response, "tool_calls": current_tool_calls})

        # Ejecutar herramientas
        for tc in current_tool_calls:
            tool_name = tc["function"]["name"]
            try:
                args = json.loads(tc["function"]["arguments"])
            except (json.JSONDecodeError, TypeError):
                args = {}

            emit({"type": "tool_start", "tool": tool_name})
            result = dispatch_tool(tool_name, args)

            if result is RUN_COMMAND_PENDING:
                # run_command ya emitió el evento; salir y esperar confirmación del QML
                return

            if isinstance(result, ScreenCapture):
                # Inyectar la captura como mensaje de usuario con imagen (formato OpenAI)
                emit({"type": "tool_result", "tool": tool_name, "result": result.summary_text()})
                history.append({
                    "role":      "user",
                    "content":   "Aquí está la captura de pantalla que tomé. Analízala y responde.",
                    "image_b64": result.b64
                })
            else:
                emit({"type": "tool_result", "tool": tool_name, "result": result})
                history.append({
                    "role":         "tool",
                    "tool_call_id": tc.get("id"),
                    "name":         tool_name,
                    "content":      result
                })

    emit_error("Demasiadas iteraciones de herramientas (límite: 6)")
