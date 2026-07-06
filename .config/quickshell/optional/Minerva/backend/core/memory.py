#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
ChromaDB — memoria a largo plazo y contexto de memorias para Minerva.

Expone:
  - chroma_client, memory_collection
  - CHROMADB_AVAILABLE, MEMORY_AVAILABLE
  - get_memory_context(text) → str con memorias relevantes para inyectar al system prompt
"""
import os
import sys

from .config import HOME

CHROMA_DB_PATH = os.path.join(HOME, ".local", "share", "quickshell", "minerva_tools")

# ─────────────────────────────────────────────────────────────────────────────
# Cliente ChromaDB
# ─────────────────────────────────────────────────────────────────────────────
try:
    import chromadb
    chroma_client     = chromadb.PersistentClient(path=CHROMA_DB_PATH)
    CHROMADB_AVAILABLE = True
except Exception as e:
    print(f"Error inicializando ChromaDB: {e}", file=sys.stderr)
    chroma_client      = None
    CHROMADB_AVAILABLE = False

# ─────────────────────────────────────────────────────────────────────────────
# Colección de memoria a largo plazo
# ─────────────────────────────────────────────────────────────────────────────
try:
    if chroma_client:
        memory_collection = chroma_client.get_or_create_collection(name="minerva_memory")
        MEMORY_AVAILABLE  = True
    else:
        memory_collection = None
        MEMORY_AVAILABLE  = False
except Exception as e:
    print(f"Error inicializando memoria en ChromaDB: {e}", file=sys.stderr)
    memory_collection = None
    MEMORY_AVAILABLE  = False


def get_memory_context(text: str, n_results: int = 3) -> str:
    """
    Consulta ChromaDB por memorias relevantes al texto dado.
    Retorna un string listo para inyectar en el system prompt, o '' si no hay nada.
    """
    if not MEMORY_AVAILABLE or not text.strip():
        return ""
    try:
        res = memory_collection.query(query_texts=[text], n_results=n_results)
        if res and res["documents"] and res["documents"][0]:
            return "\n- ".join(res["documents"][0])
    except Exception:
        pass
    return ""
