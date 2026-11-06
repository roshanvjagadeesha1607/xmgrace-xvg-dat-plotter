#!/usr/bin/env bash
set -euo pipefail

die() {
    echo "Error: $*" >&2
    exit 1
}

cleanup() {
    [[ -n "${BATCH_FILE:-}" && -f "${BATCH_FILE:-}" ]] && rm -f "$BATCH_FILE"
}
trap cleanup EXIT

[[ $# -le 1 ]] || die "Usage: $(basename "$0") [input.xvg | input.dat]"

XMGRACE=""
for cand in xmgrace gracebat grace; do
    if command -v "$cand" >/dev/null 2>&1; then
        XMGRACE="$cand"
        break
    fi
done
[[ -n "$XMGRACE" ]] || die "XMGrace is not installed or not in PATH (looked for xmgrace, gracebat, grace)."

process_file() {
    INPUT="$1"

    [[ -e "$INPUT" ]]            || die "Input file '$INPUT' does not exist."
    [[ -f "$INPUT" ]]            || die "Input '$INPUT' is not a regular file."
    [[ -r "$INPUT" ]]            || die "Input file '$INPUT' is not readable."
    [[ "$INPUT" == *.xvg || "$INPUT" == *.dat ]] \
        || die "Input file '$INPUT' must have a .xvg or .dat extension."

    case "$INPUT" in
        *.xvg)
            OUTPUT="${INPUT%.xvg}.png"
            DATA_OUTPUT="${INPUT%.xvg}.dat"
            ;;
        *.dat)
            OUTPUT="${INPUT%.dat}.png"
            DATA_OUTPUT="$INPUT"
            ;;
    esac

    NSETS=$(grep -Eo '@[[:space:]]*s[0-9]+[[:space:]]+legend' "$INPUT" 2>/dev/null \
                | grep -Eo 's[0-9]+' | grep -Eo '[0-9]+' | sort -n | tail -1 || true)

    if [[ -n "${NSETS:-}" ]]; then
        NSETS=$((NSETS + 1))
    else
        COLS=$(grep -Ev '^[[:space:]]*[@#&]' "$INPUT" 2>/dev/null \
                   | grep -E '[0-9]' | head -1 | awk '{print NF}' || true)
        if [[ -n "${COLS:-}" && "$COLS" -gt 1 ]]; then
            NSETS=$((COLS - 1))
        else
            NSETS=1
        fi
    fi
    [[ "$NSETS" -ge 1 ]] || NSETS=1

    read -r XMIN XMAX < <(awk '
        BEGIN {
            num = "^[[:space:]]*[+-]?(([0-9]+([.][0-9]*)?)|([.][0-9]+))([eEdD][+-]?[0-9]+)?[[:space:]]*$"
        }

        /^[[:space:]]*[@#&]/ {
            next
        }

        NF >= 2 {
            x = $1
            gsub(/[dD]/, "e", x)

            if (x ~ num) {
                x += 0

                if (!seen) {
                    min = x
                    max = x
                    seen = 1
                }

                if (x < min) min = x
                if (x > max) max = x
            }
        }

        END {
            if (seen) {
                printf "%.10g %.10g\n", min, max
            }
        }
    ' "$INPUT" 2>/dev/null || true)

    BATCH_FILE="$(mktemp)" || die "Could not create temporary batch file."

    {
        echo 'title ""'
        echo 'subtitle ""'
        echo 'xaxis label font "Helvetica-Bold"'
        echo 'yaxis label font "Helvetica-Bold"'
        echo 'xaxis ticklabel font "Helvetica-Bold"'
        echo 'yaxis ticklabel font "Helvetica-Bold"'
        echo 'frame linewidth 2.0'
        echo 'xaxis bar linewidth 2.0'
        echo 'yaxis bar linewidth 2.0'
        echo 'xaxis tick major linewidth 2.0'
        echo 'yaxis tick major linewidth 2.0'
        echo 'xaxis tick minor ticks 0'
        echo 'yaxis tick minor ticks 0'

        for ((i = 0; i < NSETS; i++)); do
            echo "s${i} line linewidth 2.0"
            echo "s${i} line color 2"
            echo "s${i} legend font \"Helvetica-Bold\""
        done

        echo 'legend font "Helvetica-Bold"'
        echo 'legend box linestyle 0'
        echo 'legend char size 4.200000'
        echo 'autoscale'

        if [[ -n "${XMIN:-}" && -n "${XMAX:-}" && "$XMIN" != "$XMAX" ]]; then
            echo "world xmin ${XMIN}"
            echo "world xmax ${XMAX}"
            echo 'autoticks'
        fi

        echo 'view 0.150000, 0.50000, 0.600000, 0.850000'
        echo 'redraw'

        if [[ "$INPUT" == *.xvg ]]; then
            printf 'saveall "%s"\n' "$DATA_OUTPUT"
        fi
    } > "$BATCH_FILE"

    if ! "$XMGRACE" "$INPUT" \
            -batch "$BATCH_FILE" \
            -nosafe -noask \
            -hardcopy \
            -hdevice PNG \
            -printfile "$OUTPUT" >/dev/null 2>&1; then
        die "XMGrace failed to generate the plot from '$INPUT'."
    fi

    [[ -s "$OUTPUT" ]] || die "Output PNG '$OUTPUT' was not created or is empty."

    if [[ "$INPUT" == *.xvg ]]; then
        [[ -s "$DATA_OUTPUT" ]] || die "Output DAT '$DATA_OUTPUT' was not created or is empty."
        echo "Successfully generated: $OUTPUT"
        echo "Successfully generated: $DATA_OUTPUT"
    else
        echo "Successfully generated: $OUTPUT"
    fi

    rm -f "$BATCH_FILE"
    BATCH_FILE=""
}

if [[ $# -eq 1 ]]; then
    process_file "$1"
else
    shopt -s nullglob
    XVG_FILES=( *.xvg )
    [[ ${#XVG_FILES[@]} -gt 0 ]] || die "No .xvg files found in current folder."

    for file in "${XVG_FILES[@]}"; do
        process_file "$file"
    done
fi
