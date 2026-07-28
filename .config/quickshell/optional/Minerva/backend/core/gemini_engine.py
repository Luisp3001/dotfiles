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
from .job_manager import job_mgr, CommandJob
from ..tools import dispatch_tool, get_relevant_tools, OLLAMA_TOOLS
from ..tools.screen import ScreenCapture

_GEMINI_URL = "https://generativelanguage.googleapis.com/v1beta/openai/chat/completions"


def _split_concatenated_calls(raw_name: str, raw_args: str, known_names: set) -> list:
    """
    Gemini 2.5-flash con thinking a veces fusiona múltiples tool_calls en uno solo,
    concatenando nombres ("run_commandrun_commandlist_dir") y argumentos
    ('{"command":"ls"}{"command":"df -h"}{"path":"/"}').

    Intenta separar en [(name1, args_dict1), (name2, args_dict2), ...].
    Devuelve [] si la función parece ser un tool_call normal (no concatenado).
    """
    # Si el nombre es exactamente uno de los conocidos, no hay concatenación
    if raw_name in known_names:
        return []

    # Intentar separar el nombre usando los nombres conocidos (orden greedy, mayor primero)
    sorted_names = sorted(known_names, key=len, reverse=True)
    names_found = []
    remaining = raw_name
    while remaining:
        matched = False
        for n in sorted_names:
            if remaining.startswith(n):
                names_found.append(n)
                remaining = remaining[len(n):]
                matched = True
                break
        if not matched:
            return []  # no se pudo parsear, retornar vacío

    if len(names_found) <= 1:
        return []  # solo un nombre, no hay concatenación

    # Separar los argumentos JSON (múltiples objetos JSON concatenados)
    args_list = []
    decoder = json.JSONDecoder()
    pos = 0
    raw_args = raw_args.strip()
    while pos < len(raw_args):
        # Avanzar whitespace
        while pos < len(raw_args) and raw_args[pos] in " \t\n\r":
            pos += 1
        if pos >= len(raw_args):
            break
        try:
            obj, end_pos = decoder.raw_decode(raw_args, pos)
            args_list.append(obj)
            pos = end_pos
        except json.JSONDecodeError:
            return []  # no se pudo parsear, abandonar

    # Si el número de args coincide con el de nombres, emparejar
    if len(args_list) == len(names_found):
        return list(zip(names_found, args_list))

    # Si hay más nombres que args, rellenar los faltantes con {}
    if len(args_list) < len(names_found):
        args_list += [{}] * (len(names_found) - len(args_list))
        return list(zip(names_found, args_list))

    return []


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
                                elif k == "id":
                                    # El id puede llegar en varios chunks; si ya hay uno diferente,
                                    # probablemente es un tool call nuevo sin índice — incrementar.
                                    existing = current_tool_calls[idx].get("id", "")
                                    if existing and v and not v.startswith(existing) and not existing.startswith(v):
                                        # id diferente → es un tool_call nuevo
                                        current_tool_calls.append({
                                            "id":       v,
                                            "type":     "function",
                                            "function": {"name": "", "arguments": ""}
                                        })
                                    else:
                                        current_tool_calls[idx]["id"] = (existing + v) if v else existing
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

        # ── Post-proceso: separar tool_calls concatenados por Gemini thinking ────
        # Gemini 2.5 Flash con thinking puede fusionar M tool_calls en uno solo,
        # concatenando nombres y argumentos. Detectamos y separamos estos casos.
        expanded_tool_calls = []
        known_tool_names = {t["function"]["name"] for t in dynamic_tools}

        for tc in current_tool_calls:
            raw_name = tc["function"].get("name", "")
            raw_args = tc["function"].get("arguments", "")

            # Intentar separar nombres concatenados: "run_commandrun_commandlist_dir"
            # Detectar si el nombre contiene repeticiones de nombres de tools conocidas
            parts = _split_concatenated_calls(raw_name, raw_args, known_tool_names)
            if parts:
                for i, (p_name, p_args) in enumerate(parts):
                    new_tc = dict(tc)
                    new_tc["id"] = tc["id"] + (f"_{i}" if i > 0 else "")
                    new_tc["function"] = {"name": p_name, "arguments": json.dumps(p_args)}
                    expanded_tool_calls.append(new_tc)
            else:
                expanded_tool_calls.append(tc)

        current_tool_calls = expanded_tool_calls

        # Filtrar tool_calls sin ID válido o sin nombre (resultado del streaming anómalo de Gemini)
        current_tool_calls = [
            tc for tc in current_tool_calls 
            if tc.get("id") and tc.get("function", {}).get("name")
        ]

        # Sin tool calls válidos → respuesta final
        if not current_tool_calls:
            if VOICE_AVAILABLE and buffer_frase.strip() and not voice_mgr.tts_stop_event.is_set():
                clean_frase = buffer_frase.replace("*", "").replace("#", "").strip()
                if clean_frase:
                    voice_mgr.tts_queue.put(clean_frase)
            emit({"type": "done", "full_response": full_response})
            return

        # Guardar la respuesta del assistant.
        # IMPORTANTE: Gemini rechaza content="" cuando hay tool_calls — usar None en ese caso.
        history.append({
            "role":       "assistant",
            "content":    full_response or None,
            "tool_calls": current_tool_calls
        })

        # Ejecutar herramientas — procesamos TODAS antes de decidir si retornar.
        # Los run_command se acumulan como CommandJob; las demás se añaden al historial de inmediato.
        pending_jobs = []

        for tc in current_tool_calls:
            tool_name = tc["function"]["name"]
            try:
                args = json.loads(tc["function"]["arguments"])
            except (json.JSONDecodeError, TypeError):
                args = {}

            tc_id = tc.get("id", "")
            emit({"type": "tool_start", "tool": tool_name})
            result = dispatch_tool(tool_name, args, tool_call_id=tc_id)

            if isinstance(result, CommandJob):
                # run_command pendiente — acumular y continuar con el resto
                pending_jobs.append(result)
                continue

            if isinstance(result, ScreenCapture):
                emit({"type": "tool_result", "tool": tool_name, "result": result.summary_text()})
                history.append({
                    "role":         "tool",
                    "tool_call_id": tc_id,
                    "name":         tool_name,
                    "content":      result.summary_text() or "Captura tomada."
                })
                history.append({
                    "role":      "user",
                    "content":   "Aquí está la captura de pantalla que tomé. Analízala y responde.",
                    "image_b64": result.b64
                })
            else:
                emit({"type": "tool_result", "tool": tool_name, "result": result})
                history.append({
                    "role":         "tool",
                    "tool_call_id": tc_id,
                    "name":         tool_name,
                    "content":      str(result) if result is not None else "OK"
                })

        if pending_jobs:
            # Registrar el turno en el job manager; main.py retomará cuando todos terminen.
            job_mgr.start_turn([j.job_id for j in pending_jobs])
            return
        # Si no hubo run_command, continuar la iteración agentic normalmente

    emit_error("Demasiadas iteraciones de herramientas (límite: 6)")
