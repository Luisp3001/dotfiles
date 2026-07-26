#!/usr/bin/env bash

last_run=0
debounce_seconds=1

udevadm monitor --subsystem-match=power_supply --property --udev | while read -r line; do
    if echo "$line" | grep -q "POWER_SUPPLY_NAME=AC"; then
        now=$(date +%s)
        if (( now - last_run >= debounce_seconds )); then
            hyprctl reload
            last_run=$now
        fi
    fi
done
