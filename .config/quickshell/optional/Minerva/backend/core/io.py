#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
I/O helpers y utilidades de seguridad para el backend Minerva.

Provee:
  - emit() / emit_error()          → comunicación JSON con el QML
  - is_safe_path() / classify_cmd() → seguridad de filesystem y comandos
"""
import json
import re
import sys
import pathlib

from .config import HOME

# ─────────────────────────────────────────────────────────────────────────────
# Patrones de seguridad para comandos
# ─────────────────────────────────────────────────────────────────────────────
DESTRUCTIVE_RE = re.compile(
    r"\brm\b"             # cualquier rm
    r"|\bdd\b"            # disk destroyer
    r"|\bmkfs\b"          # formatear sistema de archivos
    r"|\bshred\b"         # borrado seguro
    r"|\btruncate\b"      # truncar archivo
    r"|\bwipe\b"          # borrado de disco
    r"|\bmv\s+.*\s+/"     # mover a ruta absoluta
    r"|>\s*/(?!dev/null)" # redirigir a archivo del sistema
    r"|>>\s*/",           # añadir a archivo del sistema
    re.IGNORECASE
)
SUDO_RE = re.compile(r"\bsudo\b")


# ─────────────────────────────────────────────────────────────────────────────
# I/O — comunicación con QML vía stdout (JSON Lines)
# ─────────────────────────────────────────────────────────────────────────────
def emit(obj: dict) -> None:
    """Envía un objeto JSON al QML vía stdout (línea terminada en \\n)."""
    try:
        sys.stdout.write(json.dumps(obj, ensure_ascii=False) + "\n")
        sys.stdout.flush()
    except BrokenPipeError:
        import os
        os._exit(0)


def emit_error(msg: str) -> None:
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
