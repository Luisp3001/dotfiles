#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Herramientas de sistema de archivos para Minerva.

Todas las funciones reciben rutas y retornan strings (resultado o error).
La validación de seguridad (is_safe_path) se aplica en todas las operaciones.
"""
import pathlib
import shutil
import subprocess

from ..core.config import HOME, MAX_FILE, MAX_DIR
from ..core.io import is_safe_path


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


def tool_read_pdf(path: str) -> str:
    exp = str(pathlib.Path(path).expanduser())
    if not is_safe_path(exp):
        return f"Acceso denegado: solo se permite dentro de {HOME}"
    try:
        p = pathlib.Path(exp)
        if not p.exists() or not p.is_file():
            return f"Archivo inválido o no existe: {exp}"
        r = subprocess.run(["pdftotext", exp, "-"], capture_output=True, text=True, timeout=10)
        text = r.stdout
        if r.returncode != 0:
            return f"Error extrayendo PDF: {r.stderr}"
        if len(text) > MAX_FILE:
            text = text[:MAX_FILE] + f"\n\n[... truncado: mostrando {MAX_FILE} de {len(text)} bytes ...]"
        return text
    except Exception as e:
        return f"Error leyendo PDF: {e}"


def tool_read_docx(path: str) -> str:
    exp = str(pathlib.Path(path).expanduser())
    if not is_safe_path(exp):
        return f"Acceso denegado: solo se permite dentro de {HOME}"
    try:
        p = pathlib.Path(exp)
        if not p.exists() or not p.is_file():
            return f"Archivo inválido o no existe: {exp}"
        r = subprocess.run(["pandoc", "-f", "docx", "-t", "markdown", exp], capture_output=True, text=True, timeout=10)
        text = r.stdout
        if r.returncode != 0:
            return f"Error extrayendo DOCX: {r.stderr}"
        if len(text) > MAX_FILE:
            text = text[:MAX_FILE] + f"\n\n[... truncado: mostrando {MAX_FILE} de {len(text)} bytes ...]"
        return text
    except Exception as e:
        return f"Error leyendo DOCX: {e}"
