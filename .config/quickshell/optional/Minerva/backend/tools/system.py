#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Herramientas de sistema para Minerva: búsqueda web y lanzamiento de apps.
"""
import os
import re
import subprocess
import pathlib

from ..core.config import HOME, WEB_SEARCH_AVAILABLE


def tool_web_search(query: str, max_results: int = 5) -> str:
    """Busca en internet usando DuckDuckGo (sin API key)."""
    if not WEB_SEARCH_AVAILABLE:
        return "Error: el módulo 'ddgs' no está instalado en el entorno del plugin."
    max_results = max(1, min(10, int(max_results)))
    try:
        from ddgs import DDGS
        results = []
        with DDGS() as ddgs:
            for r in ddgs.text(query, max_results=max_results):
                results.append(r)
        if not results:
            return f"No se encontraron resultados para: {query}"
        lines = [f"Resultados de búsqueda para: '{query}'\n"]
        for i, r in enumerate(results, 1):
            title   = r.get("title",  "Sin título")
            href    = r.get("href",   "")
            snippet = r.get("body",   r.get("description", "Sin descripción"))
            lines.append(f"[{i}] {title}")
            lines.append(f"    URL: {href}")
            lines.append(f"    {snippet}")
            lines.append("")
        return "\n".join(lines).strip()
    except Exception as e:
        return f"Error al realizar la búsqueda web: {e}"


def tool_launch_app(query: str) -> str:
    """Busca una aplicación por nombre, palabra clave o sinónimo y la abre en segundo plano."""
    query = query.lower().strip()
    synonyms = {
        "navegador": ["firefox", "brave", "chrome", "chromium", "browser", "thorium"],
        "musica":    ["spotify", "youtube", "music"],
        "discord":   ["vesktop", "discord", "webcord", "armcord"],
        "archivos":  ["dolphin", "nautilus", "thunar", "files", "explorador"],
        "terminal":  ["kitty", "alacritty", "konsole", "wezterm"]
    }

    search_terms = [query]
    for key, vals in synonyms.items():
        if key in query:
            search_terms.extend(vals)

    desktop_dirs = [
        "/usr/share/applications",
        os.path.expanduser("~/.local/share/applications"),
        "/var/lib/flatpak/exports/share/applications"
    ]

    best_match = None
    best_score = 0
    best_exec  = None
    best_name  = None

    for d in desktop_dirs:
        if not os.path.isdir(d):
            continue
        for path in pathlib.Path(d).rglob("*.desktop"):
            try:
                content = path.read_text(encoding='utf-8')
                if "NoDisplay=true" in content:
                    continue

                name, exec_cmd, keywords, generic_name = "", "", "", ""
                in_desktop_entry = False
                for line in content.splitlines():
                    line = line.strip()
                    if line == "[Desktop Entry]":
                        in_desktop_entry = True
                        continue
                    elif line.startswith("[") and in_desktop_entry:
                        in_desktop_entry = False

                    if in_desktop_entry:
                        if line.startswith("Name=") and not name:
                            name = line[5:]
                        elif line.startswith("Exec=") and not exec_cmd:
                            exec_cmd = line[5:]
                        elif line.startswith("Keywords="):
                            keywords = line[9:].lower()
                        elif line.startswith("GenericName="):
                            generic_name = line[12:].lower()

                if not exec_cmd or not name:
                    continue

                score        = 0
                name_lower   = name.lower()
                generic_lower = generic_name.lower()

                for term in search_terms:
                    term = term.lower()
                    if not term:
                        continue
                    if term == name_lower:
                        score += 100
                    elif term in name_lower:
                        score += 50
                    elif term in generic_lower:
                        score += 30
                    elif term in keywords:
                        score += 20
                    elif term in path.name.lower():
                        score += 10

                if score > best_score:
                    best_score = score
                    best_match = path
                    best_exec  = exec_cmd
                    best_name  = name

            except Exception:
                continue

    if best_score > 0 and best_exec:
        clean_exec = re.sub(r'%[uUfFdDnNvmick]', '', best_exec).strip()
        try:
            subprocess.Popen(
                ["hyprctl", "dispatch", f"hl.dsp.exec_cmd([[{clean_exec}]])"],
                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
            )
            return f"Aplicación abierta: {best_name}. IMPORTANTE: Responde brevemente al usuario confirmando que has abierto la aplicación."
        except Exception as e:
            return f"Error abriendo aplicación: {e}. IMPORTANTE: Informa al usuario del error."

    return f"No se encontró ninguna aplicación gráfica para: {query}. IMPORTANTE: Informa al usuario que no la encontraste."
