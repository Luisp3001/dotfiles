#!/bin/bash

# --- Configuración ---
# La ruta al archivo de variables de color generado por Pywal.
# Si tu archivo tiene otro nombre o ruta, ajústalo aquí.
PYWAL_COLORS_FILE="/home/luisp/.cache/wal/colors.json"

# Archivo de prueba
THEME_CONF_FILE="/usr/share/sddm/themes/sugar-candy/theme.conf"

# Las líneas a modificar en theme.conf (línea 47 para AccentColor, línea 50 para MainColor)
# ---------------------

# 1. Verificar si el archivo de Pywal existe
# 2. Cargar las variables de color de Pywal en el script
# Pywal usa variables como 'color1' (accent) y 'color7' o 'foreground' (main color/texto).
# Vamos a usar 'color4' (un color de acento vibrante) para AccentColor y 'color7' para MainColor.
# Pywal genera el color en formato HEX sin el '#' inicial en algunas variables, así que lo añadimos si es necesario.
# NOTA: Pywal tiene varias variables (color0 - color15, foreground, background, etc.).
# 'color4' (azul/cyan) y 'color7' (blanco/gris claro) suelen ser buenas opciones,
# pero puedes cambiarlas (e.g., usar 'color1' para AccentColor si prefieres rojo).


# Si $color4 no tiene un '#' delante, lo añadimos (Pywal puede variar su output, pero es más seguro)
main_color=$(jq -r '.colors.color1' "$PYWAL_COLORS_FILE")
accent_color=$(jq -r '.colors.color3' "$PYWAL_COLORS_FILE")

# 3. Modificar el archivo theme.conf con sed
# Utilizamos 'sed -i' para editar el archivo directamente.
# La sintaxis es: 'NÚMERO_DE_LÍNEA c NUEVA_LÍNEA'
# Usamos comillas dobles para que Bash expanda las variables.

# Para AccentColor (Línea 47)
sed -i "s/^AccentColor=.*/AccentColor=\"$main_color\"/" "$THEME_CONF_FILE"
sed -i "s/^BackgroundColor=.*/BackgroundColor=\"$accent_color\"/" "$THEME_CONF_FILE"

echo "🎉 Archivo $THEME_CONF_FILE actualizado con éxito."
