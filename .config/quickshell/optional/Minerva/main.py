#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Minerva — Punto de entrada del backend.

Protocolo: JSON Lines por stdin/stdout (HTTP POST → port 11435)

Entrada:
  {"type":"chat",          "message":"...", "history":[...], "settings":{...}}
  {"type":"run_confirmed", "command":"..."}
  {"type":"run_sudo",      "command":"..."}
  {"type":"ping"}
  {"type":"cancel"}
  {"type":"stop_tts"}
  {"type":"toggle_voice"}

Salida (una línea JSON por evento):
  {"type":"ready",           "model":"...", "home":"..."}
  {"type":"token",           "content":"..."}
  {"type":"done",            "full_response":"..."}
  {"type":"tool_start",      "tool":"..."}
  {"type":"tool_result",     "tool":"...", "result":"..."}
  {"type":"run_command",     "command":"..."}
  {"type":"confirm_required","command":"...", "reason":"..."}
  {"type":"sudo_required",   "command":"..."}
  {"type":"command_result",  "command":"...", "output":"...", "returncode":0, "success":true}
  {"type":"voice_recording_started"}
  {"type":"voice_recording_stopped"}
  {"type":"voice_transcribing"}
  {"type":"voice_recognized","text":"..."}
  {"type":"wake_word_detected"}
  {"type":"silence_detected"}
  {"type":"error",           "message":"..."}
"""

import os
import sys

# Compatibilidad para GPUs AMD RX 6000 (RDNA 2) en PyTorch ROCm — debe ir primero
if "HSA_OVERRIDE_GFX_VERSION" not in os.environ:
    os.environ["HSA_OVERRIDE_GFX_VERSION"] = "10.3.0"

import base64
import datetime
import json
import queue
import subprocess
import tempfile
import threading
from http.server import BaseHTTPRequestHandler, HTTPServer

from backend.core.config        import MODEL, HOME
from backend.core.io            import emit, emit_error
from backend.core.voice         import voice_mgr, VOICE_AVAILABLE
from backend.core.memory        import memory_collection, MEMORY_AVAILABLE, get_memory_context
from backend.core.ollama_engine import do_chat
from backend.core.gemini_engine import do_chat_gemini
from backend.tools              import SYSTEM_PROMPT

# Importaciones opcionales de voz para el handler de toggle_voice
if VOICE_AVAILABLE:
    import numpy as np
    import soundfile as sf
    from pywhispercpp.model import Model as WhisperModel

# ─────────────────────────────────────────────────────────────────────────────
# Estado global del servidor
# ─────────────────────────────────────────────────────────────────────────────
msg_queue       = queue.Queue()
current_history: list = []
current_settings: dict = {}


# ─────────────────────────────────────────────────────────────────────────────
# Servidor HTTP (recibe mensajes del QML vía POST)
# ─────────────────────────────────────────────────────────────────────────────
class BackendHTTPHandler(BaseHTTPRequestHandler):
    def do_POST(self):
        content_length = int(self.headers.get("Content-Length", 0))
        post_data = self.rfile.read(content_length).decode("utf-8")
        msg_queue.put(post_data)
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.end_headers()
        self.wfile.write(b'{"status":"ok"}')

    def log_message(self, fmt, *args):
        pass  # Silenciar logs


def run_server():
    try:
        HTTPServer.allow_reuse_address = True
        server = HTTPServer(("127.0.0.1", 11435), BackendHTTPHandler)
        server.serve_forever()
    except Exception as e:
        print(f"Server error: {e}", file=sys.stderr)
        os._exit(1)


# ─────────────────────────────────────────────────────────────────────────────
# Helpers para despachar chat según provider
# ─────────────────────────────────────────────────────────────────────────────
def _dispatch_chat(history: list, settings: dict) -> None:
    """Llama al engine correcto según el provider configurado."""
    provider = settings.get("provider", "Ollama")

    if provider == "Gemini":
        req_model   = settings.get("gemini_model",  "gemini-2.5-flash")
        req_api_key = settings.get("gemini_api_key", "")
        try:
            req_temp = float(settings.get("temperature", "0.7"))
        except ValueError:
            req_temp = 0.7
        do_chat_gemini(history, model=req_model, api_key=req_api_key, temperature=req_temp)
    else:
        req_model = settings.get("model", MODEL)
        try:
            req_temp = float(settings.get("temperature", "0.7"))
        except ValueError:
            req_temp = 0.7
        try:
            req_ctx = int(settings.get("num_ctx", "8192"))
        except ValueError:
            req_ctx = 8192
        req_think = bool(settings.get("thinking", False))
        do_chat(history, model=req_model, temperature=req_temp, num_ctx=req_ctx, thinking=req_think)


def _run_command(cmd: str) -> tuple[str, int]:
    """Ejecuta un comando bash y retorna (output, returncode)."""
    try:
        r = subprocess.run(
            ["bash", "-c", cmd],
            capture_output=True, text=True, timeout=30,
            cwd=HOME, env={**os.environ}
        )
        out = (r.stdout + r.stderr).strip()
        return out[:4096] or "(sin salida)", r.returncode
    except subprocess.TimeoutExpired:
        return "Tiempo de espera agotado (30s)", -1
    except Exception as e:
        return str(e), -1


# ─────────────────────────────────────────────────────────────────────────────
# Bucle principal
# ─────────────────────────────────────────────────────────────────────────────
def main():
    # Monitorear stdin: cuando el QML cierra el proceso, salimos
    def _monitor_stdin():
        try:
            sys.stdin.read()
        except Exception:
            pass
        os._exit(0)

    threading.Thread(target=_monitor_stdin, daemon=True).start()

    emit({"type": "ready", "model": MODEL, "home": HOME})

    threading.Thread(target=run_server, daemon=True).start()

    global current_history, current_settings

    while True:
        raw_line = msg_queue.get().strip()
        if not raw_line:
            continue

        try:
            msg = json.loads(raw_line)
        except json.JSONDecodeError as e:
            emit_error(f"JSON inválido: {e}")
            continue

        msg_type = msg.get("type")

        # ── Chat ──────────────────────────────────────────────────────────────
        if msg_type == "chat":
            text     = msg.get("message", "").strip()
            image    = msg.get("image", "").strip()
            hist     = msg.get("history",  [])
            settings = msg.get("settings", {})
            if not text:
                continue

            current_settings = settings

            fecha_actual             = datetime.datetime.now().strftime("%A, %d de %B de %Y, %H:%M")
            system_prompt_with_date  = SYSTEM_PROMPT.replace("{fecha_actual}", fecha_actual)

            # Inyectar memorias relevantes al system prompt
            memories = get_memory_context(text)
            if memories:
                system_prompt_with_date += f"\n\n## Recuerdos relevantes a largo plazo:\n- {memories}"

            current_history = [{"role": "system", "content": system_prompt_with_date}]
            current_history.extend(hist)
            
            user_msg = {"role": "user", "content": text}
            if image and os.path.exists(image):
                try:
                    with open(image, "rb") as f:
                        image_b64 = base64.b64encode(f.read()).decode("utf-8")
                        user_msg["image_b64"] = image_b64
                except Exception as e:
                    emit_error(f"Error al leer imagen: {e}")
            
            current_history.append(user_msg)

            _dispatch_chat(current_history, current_settings)

        # ── Confirmación de comando normal ────────────────────────────────────
        elif msg_type == "run_confirmed":
            cmd = msg.get("command", "").strip()
            if not cmd:
                continue
            out, returncode = _run_command(cmd)
            emit({
                "type":       "command_result",
                "command":    cmd,
                "output":     out,
                "returncode": returncode,
                "success":    returncode == 0
            })
            # Retomar conversación con el resultado de la tool
            if current_history and current_history[-1].get("tool_calls"):
                t_id = current_history[-1]["tool_calls"][-1].get("id", "")
                current_history.append({
                    "role": "tool", "tool_call_id": t_id,
                    "name": "run_command", "content": out
                })
                _dispatch_chat(current_history, current_settings)

        # ── Comando sudo via pkexec ───────────────────────────────────────────
        elif msg_type == "run_sudo":
            cmd = msg.get("command", "").strip()
            if not cmd:
                continue
            try:
                r = subprocess.run(
                    ["pkexec", "bash", "-c", cmd],
                    capture_output=True, text=True, timeout=30,
                    cwd=HOME, env={**os.environ}
                )
                out         = (r.stdout + r.stderr).strip()
                returncode  = r.returncode
            except subprocess.TimeoutExpired:
                out, returncode = "Tiempo de espera agotado (30s)", -1
            except Exception as e:
                out, returncode = str(e), -1

            out = out[:4096] or "(sin salida)"
            emit({
                "type":       "command_result",
                "command":    f"sudo {cmd}",
                "output":     out,
                "returncode": returncode,
                "success":    returncode == 0
            })
            if current_history and current_history[-1].get("tool_calls"):
                t_id = current_history[-1]["tool_calls"][-1].get("id", "")
                current_history.append({
                    "role": "tool", "tool_call_id": t_id,
                    "name": "run_command", "content": out
                })
                _dispatch_chat(current_history, current_settings)

        # ── Ping ──────────────────────────────────────────────────────────────
        elif msg_type == "ping":
            emit({"type": "ready", "model": MODEL, "home": HOME})

        # ── Cancelar / Stop TTS ───────────────────────────────────────────────
        elif msg_type in ("cancel", "stop_tts"):
            if VOICE_AVAILABLE:
                voice_mgr.stop_tts()

        # ── Voz ───────────────────────────────────────────────────────────────
        elif msg_type == "toggle_voice":
            if not VOICE_AVAILABLE:
                emit_error("Dependencias de voz no instaladas")
                continue

            if not voice_mgr.is_recording:
                res = voice_mgr.toggle_recording()
                if res == "started":
                    emit({"type": "voice_recording_started"})
                else:
                    emit_error("No se pudo iniciar la grabación")
            else:
                voice_mgr.is_recording = False
                if voice_mgr.stream:
                    voice_mgr.stream.stop()
                    voice_mgr.stream.close()

                emit({"type": "voice_recording_stopped"})

                if not voice_mgr.audio_data:
                    continue

                audio_np = np.concatenate(voice_mgr.audio_data, axis=0)
                emit({"type": "voice_transcribing"})

                def _transcribe_async(audio_data):
                    try:
                        with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as tmp:
                            sf.write(tmp.name, audio_data, 16000)
                            tmp_name = tmp.name

                        if not voice_mgr.whisper_model:
                            voice_mgr.whisper_model = WhisperModel(
                                "small", language="es",
                                print_realtime=False, print_progress=False
                            )

                        segments = voice_mgr.whisper_model.transcribe(tmp_name)
                        text     = " ".join([s.text for s in segments]).strip()
                        os.remove(tmp_name)

                        if not text or "[BLANK_AUDIO]" in text or len(text) < 2:
                            return

                        emit({"type": "voice_recognized", "text": text})
                    except Exception as e:
                        emit_error(f"Error al transcribir: {e}")

                threading.Thread(target=_transcribe_async, args=(audio_np,), daemon=True).start()


if __name__ == "__main__":
    main()
