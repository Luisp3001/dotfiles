#!/bin/bash

# Definimos el icono (asegúrate de que la ruta sea correcta)
ICON="$HOME/Pictures/icon/arch.png"

# 1. Limpiar caché de paquetes instalados (mantiene los últimos 3)
# 2. Limpiar caché de paquetes NO instalados (mantiene 0)
if pkexec paccache -r && pkexec paccache -rk0; then
    notify-send -i "$ICON" "Mantenimiento" "Caché de Pacman optimizada.\nSe conservaron las últimas 3 versiones."
else
    notify-send -u critical -i "$ICON" "Error" "No se pudo limpiar la caché. ¿Cancelaste la contraseña?"
fi
