#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Ollama AI Backend — Quickshell Dynamic Island Plugin
Protocolo: JSON Lines por stdin/stdout

Entrada (stdin, vía HTTP POST port 11435):
  {"type":"chat",         "message":"...", "history":[...]}
  {"type":"run_confirmed","command":"..."}
  {"type":"run_sudo",     "command":"..."}
  {"type":"ping"}

Salida (stdout, una línea JSON por evento):
  {"type":"ready",          "model":"...", "home":"..."}
  {"type":"token",          "content":"..."}
  {"type":"done",           "full_response":"..."}
  {"type":"tool_start",     "tool":"..."}
  {"type":"tool_result",    "tool":"...", "result":"..."}
  {"type":"run_command",    "command":"..."}
  {"type":"confirm_required","command":"...", "reason":"..."}
  {"type":"sudo_required",  "command":"..."}
  {"type":"command_result", "command":"...", "output":"...", "returncode":0, "success":true}
  {"type":"error",          "message":"..."}
"""

import sys
import json
import os
import re
import subprocess
import pathlib
import queue
import threading
from http.server import BaseHTTPRequestHandler, HTTPServer
import ollama

# ─────────────────────────────────────────────────────────────────────────────
# Configuración
# ─────────────────────────────────────────────────────────────────────────────
MODEL       = "Gemma4:e4b"
HOME        = str(pathlib.Path.home())
MAX_FILE    = 8_192   # 8 KiB máx por lectura de archivo
MAX_DIR     = 4_096   # 4 KiB máx por listado de directorio

# Patrones de comandos peligrosos
DESTRUCTIVE_RE = re.compile(
    r"\brm\b"            # cualquier rm
    r"|\bdd\b"           # disk destroyer
    r"|\bmkfs\b"         # formatear sistema de archivos
    r"|\bshred\b"        # borrado seguro
    r"|\btruncate\b"     # truncar archivo
    r"|\bwipe\b"         # borrado de disco
    r"|\bmv\s+.*\s+/"    # mover a ruta absoluta
    r"|>\s*/(?!dev/null)" # redirigir a archivo del sistema
    r"|>>\s*/",           # añadir a archivo del sistema
    re.IGNORECASE
)
SUDO_RE = re.compile(r"\bsudo\b")

SYSTEM_PROMPT = f"""Eres Minerva, una asistente inteligente integrada en el escritorio del usuario. Tu nombre viene de la diosa romana de la sabiduría.

## Tu personalidad
- Eres directa, eficiente y con un toque de ingenio sutil. No eres fría ni robótica — eres como una amiga técnica que sabe mucho.
- Respondes de forma natural y concisa. Nada de relleno.
- Tienes sentido del humor ligero cuando la situación lo permite, pero nunca forzado.

## Reglas CRÍTICAS de comunicación
- **NUNCA narres tus acciones.** No digas cosas como "Voy a ejecutar el siguiente comando", "Procederé a realizar esta acción", "Para hacer esto necesito ejecutar...", "Primero voy a verificar...". Simplemente HAZLO. Usa las herramientas directamente sin anunciarlas.
- Si el usuario te pide algo, actúa primero y después explica brevemente el resultado si es necesario.
- No hagas preguntas innecesarias. Si puedes resolver algo con la información disponible, hazlo.
- Sé breve. Las respuestas largas y redundantes aburren. Ve al grano.

## Reglas de seguridad
- Solo puedes acceder a archivos dentro de {HOME}
- Los comandos destructivos (rm, dd, mkfs, etc.) pedirán confirmación al usuario automáticamente
- Los comandos con sudo usarán pkexec (polkit) para autenticación gráfica
- Nunca inventes el contenido de archivos; usa read_file si necesitas ver uno
- Responde siempre en el idioma que use el usuario

## Contexto del sistema
- Home del usuario: {HOME}
- Sistema operativo: Arch Linux
- Shell: bash
"""

OLLAMA_TOOLS = [
    {
        "type": "function",
        "function": {
            "name": "list_dir",
            "description": "Lista el contenido de un directorio en el sistema de archivos",
            "parameters": {
                "type": "object",
                "properties": {
                    "path": {
                        "type": "string",
                        "description": "La ruta absoluta del directorio a listar"
                    }
                },
                "required": ["path"]
            }
        }
    },
    {
        "type": "function",
        "function": {
            "name": "read_file",
            "description": "Lee el contenido de texto de un archivo en el sistema",
            "parameters": {
                "type": "object",
                "properties": {
                    "path": {
                        "type": "string",
                        "description": "La ruta absoluta del archivo a leer"
                    }
                },
                "required": ["path"]
            }
        }
    },
    {
        "type": "function",
        "function": {
            "name": "run_command",
            "description": "Ejecuta un comando de bash en el sistema",
            "parameters": {
                "type": "object",
                "properties": {
                    "command": {
                        "type": "string",
                        "description": "El comando de bash a ejecutar"
                    }
                },
                "required": ["command"]
            }
        }
    }
]

# ─────────────────────────────────────────────────────────────────────────────
# I/O helpers
# ─────────────────────────────────────────────────────────────────────────────
def emit(obj: dict):
    """Envía un objeto JSON al QML vía stdout (línea terminada en \n)."""
    sys.stdout.write(json.dumps(obj, ensure_ascii=False) + "\n")
    sys.stdout.flush()

def emit_error(msg: str):
    emit({"type": "error", "message": msg})

# ─────────────────────────────────────────────────────────────────────────────
# Seguridad
# ─────────────────────────────────────────────────────────────────────────────
def is_safe_path(p: str) -> bool:
    """Verifica que la ruta esté dentro de $HOME."""
    try:
        resolved = str(pathlib.Path(p).expanduser().resolve())
        return resolved.startswith(HOME)
    except Exception:
        return False

def classify_cmd(cmd: str) -> str:
    """Clasifica un comando como 'sudo', 'destructive' o 'safe'."""
    if SUDO_RE.search(cmd):
        return "sudo"
    if DESTRUCTIVE_RE.search(cmd):
        return "destructive"
    return "safe"

# ─────────────────────────────────────────────────────────────────────────────
# Herramientas del sistema
# ─────────────────────────────────────────────────────────────────────────────
def tool_list_dir(path: str) -> str:
    exp = str(pathlib.Path(path).expanduser())
    if not is_safe_path(exp):
        return f"Acceso denegado: solo se permite dentro de {HOME}"
    try:
        r = subprocess.run(
            ["ls", "-la", "--color=never", exp],
            capture_output=True, text=True, timeout=5
        )
        return (r.stdout if r.returncode == 0 else r.stderr)[:MAX_DIR]
    except Exception as e:
        return f"Error al listar directorio: {e}"

def tool_read_file(path: str) -> str:
    exp = str(pathlib.Path(path).expanduser())
    if not is_safe_path(exp):
        return f"Acceso denegado: solo se permite dentro de {HOME}"
    try:
        p = pathlib.Path(exp)
        if not p.exists():
            return f"No existe: {exp}"
        if p.is_dir():
            return "Es un directorio; usa list_dir en su lugar"
        if not p.is_file():
            return "No es un archivo regular"
        raw  = p.read_bytes()
        text = raw[:MAX_FILE].decode("utf-8", errors="replace")
        if len(raw) > MAX_FILE:
            text += f"\n\n[... truncado: mostrando {MAX_FILE} de {len(raw)} bytes ...]"
        return text
    except Exception as e:
        return f"Error leyendo archivo: {e}"

# ─────────────────────────────────────────────────────────────────────────────
# Bucle de chat con tool calls nativos
# ─────────────────────────────────────────────────────────────────────────────
def do_chat(history: list, max_iters: int = 6):
    """
    Ejecuta un turno de chat, manejando tool calls de manera iterativa.
    Emite los tokens de texto al QML en tiempo real.
    """
    for iteration in range(max_iters):
        full_response = ""
        current_tool_calls = []
        
        try:
            stream = ollama.chat(
                model=MODEL,
                messages=history,
                stream=True,
                tools=OLLAMA_TOOLS,
                think=False  # Desactiva "thinking" tags nativamente en ollama-python >= 0.6
            )
            
            for chunk in stream:
                msg = chunk.message
                if msg.content:
                    token = msg.content
                    full_response += token
                    emit({"type": "token", "content": token})
                
                if msg.tool_calls:
                    current_tool_calls = msg.tool_calls

        except Exception as e:
            emit_error(f"Error de Ollama: {e}")
            return

        # Si no hubo llamadas a herramientas, la IA terminó su respuesta final
        if not current_tool_calls:
            emit({"type": "done", "full_response": full_response})
            return

        # Hubo llamadas a herramientas
        # ollama-python espera que tool_calls sea un array de diccionarios, pero `current_tool_calls` son objetos pydantic
        # Necesitamos pasarlos a diccionarios puros
        calls_dict = []
        for tc in current_tool_calls:
            calls_dict.append({
                "function": {
                    "name": tc.function.name,
                    "arguments": tc.function.arguments
                }
            })
            
        history.append({"role": "assistant", "content": full_response, "tool_calls": calls_dict})
        
        global current_history
        current_history = history
        
        # Procesamos las herramientas
        for tc in current_tool_calls:
            tool_name = tc.function.name
            args = tc.function.arguments
            
            emit({"type": "tool_start", "tool": tool_name})
            
            if tool_name == "list_dir":
                result = tool_list_dir(args.get("path", HOME))
                emit({"type": "tool_result", "tool": tool_name, "result": result})
                history.append({"role": "tool", "name": tool_name, "content": result})
                
            elif tool_name == "read_file":
                result = tool_read_file(args.get("path", ""))
                emit({"type": "tool_result", "tool": tool_name, "result": result})
                history.append({"role": "tool", "name": tool_name, "content": result})
                
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

                # Salimos del bucle completamente, esperamos confirmación desde QML
                # El historial ya está guardado globalmente con el assistant tool_call.
                return
            else:
                emit({"type": "tool_result", "tool": tool_name, "result": "Herramienta desconocida"})
                history.append({"role": "tool", "name": tool_name, "content": "Herramienta desconocida"})
                
        # Continúa el bucle while al iterador (Siguiente turno de la IA para que analice el role: tool)
        
    emit_error("Demasiadas iteraciones de herramientas (límite: 6)")

# ─────────────────────────────────────────────────────────────────────────────
# Servidor HTTP y Bucle principal
# ─────────────────────────────────────────────────────────────────────────────
msg_queue = queue.Queue()
current_history = []

class BackendHTTPHandler(BaseHTTPRequestHandler):
    def do_POST(self):
        content_length = int(self.headers.get('Content-Length', 0))
        post_data = self.rfile.read(content_length).decode('utf-8')
        msg_queue.put(post_data)
        self.send_response(200)
        self.send_header('Content-Type', 'application/json')
        self.end_headers()
        self.wfile.write(b'{"status":"ok"}')
    def log_message(self, format, *args):
        pass # Silenciar logs

def run_server():
    server = HTTPServer(('127.0.0.1', 11435), BackendHTTPHandler)
    server.serve_forever()

def main():
    emit({"type": "ready", "model": MODEL, "home": HOME})
    
    t = threading.Thread(target=run_server, daemon=True)
    t.start()

    while True:
        raw_line = msg_queue.get()
        raw_line = raw_line.strip()
        if not raw_line:
            continue

        try:
            msg = json.loads(raw_line)
        except json.JSONDecodeError as e:
            emit_error(f"JSON inválido: {e}")
            continue

        msg_type = msg.get("type")
        global current_history

        # ── Chat ──────────────────────────────────────────────────────────
        if msg_type == "chat":
            text = msg.get("message", "").strip()
            hist = msg.get("history", [])
            if not text:
                continue

            current_history = [{"role": "system", "content": SYSTEM_PROMPT}]
            current_history.extend(hist)
            current_history.append({"role": "user", "content": text})
            do_chat(current_history)

        # ── Confirmación de comando normal ────────────────────────────────
        elif msg_type == "run_confirmed":
            cmd = msg.get("command", "").strip()
            if not cmd:
                continue
            try:
                r = subprocess.run(
                    ["bash", "-c", cmd],
                    capture_output=True, text=True, timeout=30,
                    cwd=HOME, env={**os.environ}
                )
                out = (r.stdout + r.stderr).strip()
                emit({
                    "type":       "command_result",
                    "command":    cmd,
                    "output":     out[:4096] or "(sin salida)",
                    "returncode": r.returncode,
                    "success":    r.returncode == 0
                })
            except subprocess.TimeoutExpired:
                out = "Tiempo de espera agotado (30s)"
                emit({"type": "command_result", "command": cmd, "output": out, "returncode": -1, "success": False})
            except Exception as e:
                out = str(e)
                emit({"type": "command_result", "command": cmd, "output": out, "returncode": -1, "success": False})
            
            # Retomar conversación agregando la respuesta de la tool
            if current_history and current_history[-1].get("tool_calls"):
                # Asumimos que es para la última tool_call
                current_history.append({"role": "tool", "name": "run_command", "content": out[:4096] or "(sin salida)"})
                do_chat(current_history)

        # ── Comando sudo via pkexec ───────────────────────────────────────
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
                out = (r.stdout + r.stderr).strip()
                emit({
                    "type":       "command_result",
                    "command":    f"sudo {cmd}",
                    "output":     out[:4096] or "(sin salida)",
                    "returncode": r.returncode,
                    "success":    r.returncode == 0
                })
            except subprocess.TimeoutExpired:
                out = "Tiempo de espera agotado (30s)"
                emit({"type": "command_result", "command": f"sudo {cmd}", "output": out, "returncode": -1, "success": False})
            except Exception as e:
                out = str(e)
                emit({"type": "command_result", "command": f"sudo {cmd}", "output": out, "returncode": -1, "success": False})
            
            if current_history and current_history[-1].get("tool_calls"):
                current_history.append({"role": "tool", "name": "run_command", "content": out[:4096] or "(sin salida)"})
                do_chat(current_history)

        # ── Ping / Cancel ─────────────────────────────────────────────────
        elif msg_type == "ping":
            emit({"type": "ready", "model": MODEL, "home": HOME})
            
        elif msg_type == "cancel":
            pass

if __name__ == "__main__":
    main()
