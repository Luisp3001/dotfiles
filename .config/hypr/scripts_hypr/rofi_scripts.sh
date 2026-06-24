#!/bin/bash

SCRIPTS_DIR="$HOME/dotfiles/scripts"

case "$1" in
    # Si Rofi pasa una selección, la ejecutamos
    *)
        if [ -z "$1" ]; then
            # Si no hay argumentos → listar scripts
           find "$SCRIPTS_DIR" -maxdepth 1 -type f -executable -printf "%f\n"
        else
            # Si se seleccionó algo → ejecutarlo
            script="$SCRIPTS_DIR/$1"
            if [[ "$1" == *":root"* ]]; then
                pkexec "$script"
            else
                setsid -f "$script" >/dev/null 2>&1
            fi
        fi
        ;;
esac
