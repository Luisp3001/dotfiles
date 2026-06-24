#!/usr/bin/env bash

dir="$HOME/.config/rofi/launchers/style-10.rasi"
magick ~/.cache/wallpaper.jpg -blur 0x5 ~/.cache/wallpaper-blur.jpg

## Run
if [ $1 == "--script" ]; then
    rofi \
        -show scripts \
        -theme ${dir}
else
    rofi \
        -show drun \
        -theme ${dir}
fi
