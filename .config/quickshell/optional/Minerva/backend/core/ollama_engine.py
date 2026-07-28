#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Engine de chat para Ollama — Minerva.

Maneja el loop agentic: stream de tokens, tool calls nativos de ollama-python,
y re-invocación iterativa hasta obtener la respuesta final.
"""
import json
import re
import sys

import ollama

from .config      import MODEL
from .io          import emit, emit_error
from .voice       import voice_mgr, VOICE_AVAILABLE
from .job_manager import job_mgr, CommandJob
from ..tools      import dispatch_tool, get_relevant_tools, OLLAMA_TOOLS
from ..tools.screen import ScreenCapture


def do_chat(
    history:     list,
    max_iters:   int   = 6,
    model:       str   = MODEL,
    temperature: float = 0.7,
    num_ctx:     int   = 8192,
    thinking:    bool  = False,
) -> None:
    """
    Ejecuta un turno de chat con Ollama, manejando tool calls de manera iterativa.
    Emite los tokens de texto al QML en tiempo real vía stdout.
    """
    if VOICE_AVAILABLE:
        voice_mgr.tts_stop_event.clear()

    # Obtener el último mensaje del usuario para el RAG de tools
    user_prompt = next(
        (m.get("content", "") for m in reversed(history) if m.get("role") == "user"),
        ""
    )
    dynamic_tools = get_relevant_tools(user_prompt, top_k=15) if user_prompt else OLLAMA_TOOLS

    for _iteration in range(max_iters):
        full_response      = ""
        current_tool_calls = []
        buffer_frase       = ""

        clean_history = []
        for msg in history:
            clean_msg = dict(msg)
            if "image_b64" in clean_msg:
                clean_msg["images"] = [clean_msg.pop("image_b64")]
            clean_history.append(clean_msg)

        try:
            stream = ollama.chat(
                model    = model,
                messages = clean_history,
                stream   = True,
                tools    = dynamic_tools,
                options  = {"temperature": temperature, "num_ctx": num_ctx},
                think    = thinking  # Activa "thinking" nativo en ollama-python >= 0.6
            )

            for chunk in stream:
                msg = chunk.message
                if msg.content:
                    token          = msg.content
                    full_response += token
                    buffer_frase  += token
                    emit({"type": "token", "content": token})

                    if VOICE_AVAILABLE and not voice_mgr.tts_stop_event.is_set():
                        if re.search(r'[.!?\n:]', token) and len(buffer_frase.strip()) > 5:
                            clean_frase = buffer_frase.replace("*", "").replace("#", "").strip()
                            if clean_frase:
                                voice_mgr.tts_queue.put(clean_frase)
                            buffer_frase = ""

                if msg.tool_calls:
                    current_tool_calls = msg.tool_calls

        except Exception as e:
            emit_error(f"Error de Ollama: {e}")
            return

        # Sin tool calls → respuesta final
        if not current_tool_calls:
            if VOICE_AVAILABLE and buffer_frase.strip() and not voice_mgr.tts_stop_event.is_set():
                clean_frase = buffer_frase.replace("*", "").replace("#", "").strip()
                if clean_frase:
                    voice_mgr.tts_queue.put(clean_frase)
            emit({"type": "done", "full_response": full_response})
            return

        calls_dict = [
            {"id": f"tc_{i}", "function": {"name": tc.function.name, "arguments": tc.function.arguments}}
            for i, tc in enumerate(current_tool_calls)
        ]
        history.append({"role": "assistant", "content": full_response, "tool_calls": calls_dict})

        # Ejecutar herramientas — procesamos TODAS antes de decidir si retornar.
        # Los run_command se acumulan como CommandJob; las demás se añaden al historial de inmediato.
        pending_jobs = []

        for i, tc in enumerate(current_tool_calls):
            tool_name = tc.function.name
            args      = tc.function.arguments  # ya es dict en ollama-python
            tc_id     = f"tc_{i}"              # Ollama no provee id, generamos uno

            emit({"type": "tool_start", "tool": tool_name})
            result = dispatch_tool(tool_name, args, tool_call_id=tc_id)

            if isinstance(result, CommandJob):
                # run_command pendiente — acumular y continuar con el resto
                pending_jobs.append(result)
                continue

            if isinstance(result, ScreenCapture):
                emit({"type": "tool_result", "tool": tool_name, "result": result.summary_text()})
                history.append({
                    "role":      "user",
                    "content":   "Aquí está la captura de pantalla que tomé. Analízala y responde.",
                    "image_b64": result.b64
                })
            else:
                emit({"type": "tool_result", "tool": tool_name, "result": result})
                history.append({"role": "tool", "name": tool_name, "content": result})

        if pending_jobs:
            # Registrar el turno en el job manager; main.py retomará cuando todos terminen.
            job_mgr.start_turn([j.job_id for j in pending_jobs])
            return
        # Si no hubo run_command, continuar la iteración agentic normalmente

    emit_error("Demasiadas iteraciones de herramientas (límite: 6)")
