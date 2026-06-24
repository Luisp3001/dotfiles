#!/bin/bash
if [[ "$1" == "--title" ]]; then
    echo "$(playerctl metadata --format '{{title}}')"
elif [[ "$1" == "--artist" ]]; then
    echo "$(playerctl metadata --format '{{artist}}')"
fi
