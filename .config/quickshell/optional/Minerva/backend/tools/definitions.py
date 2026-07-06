#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Definiciones de herramientas (OLLAMA_TOOLS) y system prompt de Minerva.
"""
from ..core.config import HOME

# ─────────────────────────────────────────────────────────────────────────────
# System prompt
# ─────────────────────────────────────────────────────────────────────────────
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
- **NUNCA uses formato markdown (como asteriscos, negritas o cursivas).** El usuario te escucha a través de voz y los símbolos se leerían en voz alta (ej: "asterisco hola asterisco"). Genera solo texto plano.

## Herramientas disponibles
- **Filesystem**: Puedes listar directorios (list_dir) y leer archivos (read_file) dentro de {HOME}.
- **Comandos**: Puedes ejecutar comandos bash (run_command). Los destructivos o con sudo pedirán confirmación.
- **Búsqueda web** (web_search): Tienes acceso a internet en tiempo real. Úsala cuando:
  - El usuario pregunte por noticias, eventos recientes o información que puede haber cambiado.
  - Necesites precios, versiones de software, estadísticas actuales, o cualquier dato perecedero.
  - Tu conocimiento interno pueda estar desactualizado.
  - Te pregunten "¿cuál es la última versión de...?", "¿qué pasó con...?", "precio de...", etc.
  - NO la uses para información atemporal o conceptual que ya conoces.
- **Memoria a largo plazo** (memorize_fact): Úsala para guardar preferencias del usuario, datos personales o hechos importantes que el usuario mencione, para recordarlos en futuras sesiones.
- **Spotify** (spotify_music): Controla Spotify del usuario. Acciones disponibles:
  - "search": Buscar canciones, artistas, albums o playlists. Requiere "query".
  - "play": Reproducir. Puedes pasar un "uri" de Spotify o un "query" para buscar y reproducir directamente.
  - "pause": Pausar la reproduccion actual.
  - "resume": Reanudar la reproduccion.
  - "next": Saltar a la siguiente cancion.
  - "previous": Volver a la cancion anterior.
  - "volume": Cambiar volumen. Requiere "volume" (0-100).
  - "current": Ver que se esta reproduciendo ahora.
  - "queue": Agregar una cancion a la cola. Usa "uri" o "query".
  - Si el usuario pide musica de un artista o cancion especifica, usa "play" con query directamente.
  - Requiere Spotify Premium para controles de reproduccion.

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
- Fecha/hora actual: {{fecha_actual}}
"""

# ─────────────────────────────────────────────────────────────────────────────
# Esquemas JSON de herramientas para la IA
# ─────────────────────────────────────────────────────────────────────────────
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
    },
    {
        "type": "function",
        "function": {
            "name": "web_search",
            "description": "Busca información actualizada en internet usando DuckDuckGo. Úsala para noticias, versiones de software, precios, eventos recientes, o cualquier información que pueda haber cambiado desde tu entrenamiento.",
            "parameters": {
                "type": "object",
                "properties": {
                    "query": {
                        "type": "string",
                        "description": "La consulta de búsqueda en lenguaje natural o palabras clave"
                    },
                    "max_results": {
                        "type": "integer",
                        "description": "Número máximo de resultados a devolver (1-10, por defecto 5)"
                    }
                },
                "required": ["query"]
            }
        }
    },
    {
        "type": "function",
        "function": {
            "name": "spotify_music",
            "description": "Controla Spotify: buscar musica, reproducir, pausar, saltar cancion, volumen, ver que suena. Requiere Spotify Premium para reproduccion.",
            "parameters": {
                "type": "object",
                "properties": {
                    "action": {
                        "type": "string",
                        "description": "La accion a realizar: 'search', 'play', 'pause', 'resume', 'next', 'previous', 'volume', 'current', 'queue'",
                        "enum": ["search", "play", "pause", "resume", "next", "previous", "volume", "current", "queue"]
                    },
                    "query": {
                        "type": "string",
                        "description": "Texto de busqueda (para 'search', 'play', 'queue'). Ej: 'Bohemian Rhapsody Queen'"
                    },
                    "uri": {
                        "type": "string",
                        "description": "URI de Spotify (ej: 'spotify:track:xxx'). Opcional si se proporciona query."
                    },
                    "search_type": {
                        "type": "string",
                        "description": "Tipo de busqueda: 'track', 'artist', 'album', 'playlist'. Por defecto 'track'."
                    },
                    "volume": {
                        "type": "integer",
                        "description": "Nivel de volumen 0-100 (solo para accion 'volume')"
                    }
                },
                "required": ["action"]
            }
        }
    },
    {
        "type": "function",
        "function": {
            "name": "delete_file",
            "description": "Elimina un archivo o directorio vacío de forma permanente (solo dentro de HOME)",
            "parameters": {
                "type": "object",
                "properties": {
                    "path": {
                        "type": "string",
                        "description": "La ruta absoluta del archivo o directorio a eliminar"
                    }
                },
                "required": ["path"]
            }
        }
    },
    {
        "type": "function",
        "function": {
            "name": "create_directory",
            "description": "Crea un nuevo directorio (solo dentro de HOME)",
            "parameters": {
                "type": "object",
                "properties": {
                    "path": {
                        "type": "string",
                        "description": "La ruta absoluta del directorio a crear"
                    }
                },
                "required": ["path"]
            }
        }
    },
    {
        "type": "function",
        "function": {
            "name": "move_file",
            "description": "Mueve o renombra un archivo o directorio (solo dentro de HOME)",
            "parameters": {
                "type": "object",
                "properties": {
                    "source": {
                        "type": "string",
                        "description": "La ruta absoluta de origen"
                    },
                    "destination": {
                        "type": "string",
                        "description": "La ruta absoluta de destino"
                    }
                },
                "required": ["source", "destination"]
            }
        }
    },
    {
        "type": "function",
        "function": {
            "name": "find_files",
            "description": "Busca archivos o directorios por patrón de nombre",
            "parameters": {
                "type": "object",
                "properties": {
                    "directory": {
                        "type": "string",
                        "description": "Directorio donde iniciar la busqueda"
                    },
                    "pattern": {
                        "type": "string",
                        "description": "El patron de busqueda, ej: '*.txt' o '*nombre*'"
                    }
                },
                "required": ["directory", "pattern"]
            }
        }
    },
    {
        "type": "function",
        "function": {
            "name": "search_text",
            "description": "Busca texto específico dentro de archivos o directorios usando grep",
            "parameters": {
                "type": "object",
                "properties": {
                    "path": {
                        "type": "string",
                        "description": "Ruta absoluta del archivo o directorio donde buscar"
                    },
                    "query": {
                        "type": "string",
                        "description": "El texto o expresión regular a buscar"
                    }
                },
                "required": ["path", "query"]
            }
        }
    },
    {
        "type": "function",
        "function": {
            "name": "memorize_fact",
            "description": "Guarda un hecho importante, preferencia del usuario o recuerdo a largo plazo en la memoria permanente de ChromaDB.",
            "parameters": {
                "type": "object",
                "properties": {
                    "fact": {
                        "type": "string",
                        "description": "El hecho o preferencia a recordar. Debe ser claro y autodescriptivo."
                    }
                },
                "required": ["fact"]
            }
        }
    },
    {
        "type": "function",
        "function": {
            "name": "launch_app",
            "description": "Busca y abre una aplicación gráfica en el sistema (ej: navegador, discord, spotify, calculadora). Entiende sinónimos y categorías.",
            "parameters": {
                "type": "object",
                "properties": {
                    "query": {
                        "type": "string",
                        "description": "El nombre, sinónimo o tipo de aplicación a abrir (ej: 'discord', 'navegador', 'vesktop')"
                    }
                },
                "required": ["query"]
            }
        }
    }
]
