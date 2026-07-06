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


def tool_delete_file(path: str) -> str:
    exp = str(pathlib.Path(path).expanduser())
    if not is_safe_path(exp):
        return f"Acceso denegado: solo {HOME}"
    try:
        p = pathlib.Path(exp)
        if not p.exists():
            return f"No existe: {exp}"
        if p.is_dir():
            shutil.rmtree(exp)
        else:
            p.unlink()
        return f"Eliminado exitosamente: {exp}"
    except Exception as e:
        return f"Error eliminando: {e}"


def tool_create_directory(path: str) -> str:
    exp = str(pathlib.Path(path).expanduser())
    if not is_safe_path(exp):
        return f"Acceso denegado: solo {HOME}"
    try:
        pathlib.Path(exp).mkdir(parents=True, exist_ok=True)
        return f"Directorio creado: {exp}"
    except Exception as e:
        return f"Error creando directorio: {e}"


def tool_move_file(source: str, destination: str) -> str:
    src_exp = str(pathlib.Path(source).expanduser())
    dst_exp = str(pathlib.Path(destination).expanduser())
    if not is_safe_path(src_exp) or not is_safe_path(dst_exp):
        return f"Acceso denegado: origen y destino deben estar en {HOME}"
    try:
        if not pathlib.Path(src_exp).exists():
            return f"Origen no existe: {src_exp}"
        shutil.move(src_exp, dst_exp)
        return f"Movido exitosamente a: {dst_exp}"
    except Exception as e:
        return f"Error moviendo: {e}"


def tool_find_files(directory: str, pattern: str) -> str:
    exp = str(pathlib.Path(directory).expanduser())
    if not is_safe_path(exp):
        return f"Acceso denegado: solo {HOME}"
    try:
        r = subprocess.run(
            ["find", exp, "-name", pattern],
            capture_output=True, text=True, timeout=10
        )
        out = r.stdout if r.returncode == 0 else r.stderr
        return out[:MAX_DIR] if out else "No se encontraron resultados"
    except Exception as e:
        return f"Error buscando archivos: {e}"


def tool_search_text(path: str, query: str) -> str:
    exp = str(pathlib.Path(path).expanduser())
    if not is_safe_path(exp):
        return f"Acceso denegado: solo {HOME}"
    try:
        r = subprocess.run(
            ["grep", "-rn", query, exp],
            capture_output=True, text=True, timeout=10
        )
        out = r.stdout if r.returncode == 0 else r.stderr
        return out[:MAX_FILE] if out else "No se encontraron coincidencias"
    except Exception as e:
        return f"Error buscando texto: {e}"
