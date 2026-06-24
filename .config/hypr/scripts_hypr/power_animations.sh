#!/bin/bash

# Activa o desactiva las animaciones de Hyprland dependiendo si la
# laptop está conectada a la corriente (AC).

LAST_STATUS=""

update_animations() {
    # Buscar el dispositivo de corriente AC
    AC_PATH=$(ls /sys/class/power_supply | grep -iE 'ac|adp|mac' | head -n 1)
    
    if [ -n "$AC_PATH" ]; then
        STATUS=$(cat "/sys/class/power_supply/$AC_PATH/online")
        # Solo actuar si el estado ha cambiado
        if [ "$STATUS" != "$LAST_STATUS" ]; then
            if [ "$STATUS" -eq 1 ]; then
                # Conectado a la corriente: Activar animaciones
                hyprctl eval "hl.config({animations = {enabled = true}})"
                hyprctl eval "hl.config({decoration = {blur = { size = 10, passes = 2}}})"
                notify-send -i /home/luisp/Pictures/icon/arch.png " Sistema" "Entrando a maximo rendimiento"
            else
                # Desconectado (batería): Desactivar animaciones
                hyprctl eval "hl.config({animations = {enabled = false}})"
                hyprctl eval "hl.config({decoration = {blur = { size = 3, passes = 2}}})"
                notify-send -i /home/luisp/Pictures/icon/arch.png " Sistema" "Entrando a modo ahorro de energía"
            fi
            LAST_STATUS="$STATUS"
        fi
    fi
}

# 1. Actualizar el estado inicial al arrancar
update_animations

# 2. Escuchar eventos de udev (solo UDEV para evitar duplicados)
udevadm monitor --subsystem-match=power_supply --udev | while read -r line; do
    # Cuando hay un cambio, actualiza las animaciones
    if echo "$line" | grep -q "change"; then
        update_animations
    fi
done

