#!/bin/sh
echo -ne '\033c\033]0;circle_simulation\a'
base_path="$(dirname "$(realpath "$0")")"
"$base_path/circle_simulator.x86_64" "$@"
