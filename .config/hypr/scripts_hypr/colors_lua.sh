#!/bin/bash

# --- Configuración ---
ARCHIVO_ENTRADA="/home/luisp/.cache/wal/colors"
ARCHIVO_SALIDA="/home/luisp/.config/hypr/colors.lua"

# 1. Verificar entrada
if [ ! -f "$ARCHIVO_ENTRADA" ]; then
    echo "Error: No se encontró el cache de pywal."
    exit 1
fi

# 2. Leer colores
mapfile -t COLORES < "$ARCHIVO_ENTRADA"

# 3. Función para convertir HEX (#RRGGBB) a rgb(RRGGBB)
# Quitamos el '#' y lo envolvemos en la función que Hyprland entiende.
format_hypr() {
    local hex="${1#\#}"
    echo "rgb($hex)"
}

# 4. Generar el archivo .lua
cat << EOF > "$ARCHIVO_SALIDA"
-- Colores para Hyprland v0.55+ (Formato compatible con la Wiki)
local M = {}

M.colors = {
    bg          = "$(format_hypr "${COLORES[0]}")",
    color1          = "$(format_hypr "${COLORES[2]}")",
    color2  = "$(format_hypr "${COLORES[15]}")"
}

return M
EOF

echo "¡Listo! Colores exportados en formato rgb() a $ARCHIVO_SALIDA"
