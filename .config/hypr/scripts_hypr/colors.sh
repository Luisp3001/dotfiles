#!/bin/bash

# --- Configuración ---
ARCHIVO_ENTRADA="/home/luisp/.cache/wal/colors"
ARCHIVO_SALIDA="/home/luisp/.config/rofi/colors/colors.rasi"

# --- Script Principal ---

# 1. Verificar que el archivo de entrada exista
if [ ! -f "$ARCHIVO_ENTRADA" ]; then
    echo "Error: El archivo de entrada '$ARCHIVO_ENTRADA' no fue encontrado."
    echo "Asegúrate de que existe y contiene los 6 códigos de color."
    exit 1
fi

# 2. Leer los colores del archivo de entrada en un array.
# La opción -t quita el carácter de nueva línea y -d '' usa un delimitador nulo (para leer cada línea).
# Usamos mapfile (o readarray) para leer cada línea en un elemento del array.
mapfile -t COLORES < "$ARCHIVO_ENTRADA"

# 3. Asignar los elementos del array a variables para mayor claridad
# Los índices de los arrays en Bash comienzan en 0.
COLOR_BG=${COLORES[0]}
COLOR_BG_ALT=${COLORES[0]}
COLOR_FG=${COLORES[15]}
COLOR_SEL=${COLORES[1]}
COLOR_ACT=${COLORES[2]}
COLOR_URG=${COLORES[5]}
COLOR_BORDER=${COLORES[6]}
COLOR_BORDER_ALT=${COLORES[3]}

# 4. Generar el archivo de salida usando un 'heredoc' (<< EOF)
# Esto permite escribir bloques de texto de varias líneas, sustituyendo las variables.
cat << EOF > "$ARCHIVO_SALIDA"
* {
    background:      $COLOR_BG;
    background-alt:  $COLOR_BG_ALT;
    foreground:      $COLOR_FG;
    selected:        $COLOR_SEL;
    active:          $COLOR_ACT;
    urgent:          $COLOR_URG;
    border:          $COLOR_BORDER;
    border-alt:      $COLOR_BORDER_ALT;
}
EOF


exit 0
