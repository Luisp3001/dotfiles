#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Herramienta de memoria a largo plazo para Minerva.
Guarda hechos en ChromaDB para recuperarlos en futuras sesiones.
"""
import uuid

from ..core.memory import memory_collection, MEMORY_AVAILABLE


def tool_memorize_fact(fact: str) -> str:
    """Guarda un hecho o preferencia del usuario en la memoria permanente (ChromaDB)."""
    if not MEMORY_AVAILABLE:
        return "Error: Base de datos de memoria no disponible."
    try:
        doc_id = str(uuid.uuid4())
        memory_collection.add(documents=[fact], ids=[doc_id])
        return f"Recuerdo guardado exitosamente: '{fact}'"
    except Exception as e:
        return f"Error al guardar recuerdo: {e}"
