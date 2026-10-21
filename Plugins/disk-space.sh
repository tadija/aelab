#!/usr/bin/env bash
# Read-only probe: root filesystem usage. Stdout contains only the protocol report.
set -euo pipefail
[[ "$#" == 1 && "$1" == --aelab-probe ]] || { echo 'Expected --aelab-probe' >&2; exit 2; }
platform=$(uname -s)
scope='Root filesystem'
if [[ "$platform" == Darwin ]]; then scope='Shared APFS space (total minus available)'; fi
used=$(LC_ALL=C df -Pk / | awk -v platform="$platform" '
    END {
        if (platform == "Darwin") {
            # APFS Used is per-volume, but Available is shared across the container.
            if ($2 !~ /^[0-9]+$/ || $4 !~ /^[0-9]+$/ || $2 <= 0 || $4 > $2) exit 1
            print int((100 * ($2 - $4) + $2 - 1) / $2)
        } else {
            if ($5 !~ /^[0-9]+%$/) exit 1
            sub(/%$/, "", $5); print $5
        }
    }') || { echo 'Cannot read filesystem usage' >&2; exit 1; }
[[ "$used" =~ ^[0-9]+$ ]] || { echo 'Cannot read filesystem usage' >&2; exit 1; }
status=ok
if (( used >= 90 )); then status=critical; elif (( used >= 80 )); then status=warning; fi
printf '{"version":1,"status":"%s","summary":"Root filesystem: %s%% used","details":[{"label":"Mount","value":"/"},{"label":"Scope","value":"%s"},{"label":"Used","value":"%s%%"}]}\n' "$status" "$used" "$scope" "$used"
