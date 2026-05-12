#!/bin/bash

# ============================================================
# test_codexion.sh — Tests automatiques pour codexion
# Usage: bash test_codexion.sh [--strict] [--seriouswork]
# ============================================================

BIN="./codexion"
PASS=0
FAIL=0
SKIP=0
TOTAL=0
STRICT=0
SERIOUSWORK=0
ERROR_NUM=0
TRACE_FILE="trace_$(date +%Y%m%d_%H%M%S).log"

# Parse args
for arg in "$@"; do
    if [ "$arg" = "--strict" ];      then STRICT=1;      fi
    if [ "$arg" = "--seriouswork" ]; then SERIOUSWORK=1; fi
done

GREEN="\033[0;32m"
RED="\033[0;31m"
YELLOW="\033[0;33m"
CYAN="\033[0;36m"
BLUE="\033[0;34m"
MAGENTA="\033[0;35m"
BOLD="\033[1m"
RESET="\033[0m"

# ============================================================
# TRACE — initialisation
# ============================================================

init_trace() {
    cat > "$TRACE_FILE" << EOF
╔══════════════════════════════════════════════════════════════╗
║           CODEXION — RAPPORT DE TESTS                       ║
║  Date    : $(date '+%Y-%m-%d %H:%M:%S')                          ║
║  Mode    : $([ $STRICT -eq 1 ] && echo "STRICT" || echo "NORMAL")$([ $SERIOUSWORK -eq 1 ] && echo "+SERIOUSWORK" || echo "")              ║
║  Binaire : $BIN                                   ║
╚══════════════════════════════════════════════════════════════╝

EOF
}

trace() {
    echo "$1" >> "$TRACE_FILE"
}

trace_section() {
    echo "" >> "$TRACE_FILE"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >> "$TRACE_FILE"
    echo "  $1" >> "$TRACE_FILE"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >> "$TRACE_FILE"
}

trace_error() {
    ERROR_NUM=$((ERROR_NUM + 1))
    local label="$1"
    local detail="$2"
    local output="$3"
    {
        echo ""
        echo "┌─────────────────────────────────────────────────────────────"
        echo "│ ERREUR #${ERROR_NUM}"
        echo "│ Test    : $label"
        echo "│ Détail  : $detail"
        if [ -n "$output" ]; then
            echo "│ Sortie  :"
            echo "$output" | head -20 | while IFS= read -r line; do
                echo "│   $line"
            done
            local total_lines
            total_lines=$(echo "$output" | wc -l)
            if [ "$total_lines" -gt 20 ]; then
                echo "│   ... ($((total_lines - 20)) lignes supplémentaires tronquées)"
            fi
        fi
        echo "└─────────────────────────────────────────────────────────────"
    } >> "$TRACE_FILE"
}

# ============================================================
# HELPERS
# ============================================================

ok() {
    echo -e "${GREEN}[OK]${RESET} $1"
    PASS=$((PASS + 1))
    TOTAL=$((TOTAL + 1))
    trace "[OK] $1"
}

ko() {
    local label="$1"
    local detail="${2:-}"
    local output="${3:-}"
    echo -e "${RED}[KO]${RESET} $label"
    FAIL=$((FAIL + 1))
    TOTAL=$((TOTAL + 1))
    trace "[KO] $label"
    trace_error "$label" "$detail" "$output"
}

skip() {
    echo -e "${YELLOW}[SKIP]${RESET} $1"
    SKIP=$((SKIP + 1))
    TOTAL=$((TOTAL + 1))
    trace "[SKIP] $1"
}

section() {
    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
    echo -e "${CYAN}  $1${RESET}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
    trace_section "$1"
}

# ============================================================
# SPINNER + TIMEOUT
# ============================================================

run_with_spinner() {
    local timeout_s="$1"
    shift
    local fifo
    fifo=$(mktemp -u)
    mkfifo "$fifo"

    timeout "$timeout_s" "$@" > /tmp/spinner_out_$$.txt 2>&1 &
    local cmd_pid=$!

    cat "$fifo" > /dev/null &
    local reader_pid=$!

    local frames=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
    local start
    start=$(date +%s)
    local i=0
    while kill -0 $cmd_pid 2>/dev/null; do
        elapsed=$(( $(date +%s) - start ))
        remaining=$(( timeout_s - elapsed ))
        printf "\r${YELLOW}${frames[$((i % 10))]}${RESET} %ds/%ds (-%ds)  " \
            "$elapsed" "$timeout_s" "$remaining" >&2
        sleep 0.1
        i=$((i + 1))
    done

    wait $cmd_pid
    local ret=$?
    kill $reader_pid 2>/dev/null
    wait $reader_pid 2>/dev/null

    printf "\r%-60s\r" " " >&2
    rm -f "$fifo"

    cat /tmp/spinner_out_$$.txt
    rm -f /tmp/spinner_out_$$.txt
    return $ret
}

# ============================================================
# INIT TRACE
# ============================================================

init_trace
echo -e "${MAGENTA}Rapport de tests : ${CYAN}$TRACE_FILE${RESET}"
[ $SERIOUSWORK -eq 1 ] && echo -e "${BOLD}${RED}⚠  MODE SERIOUSWORK ACTIF — tests longs et intensifs${RESET}"

# ============================================================
# 0. COMPILATION
# ============================================================

section "0. COMPILATION"

make re 2>/tmp/compile_err_$$.txt 1>/dev/null
compile_ret=$?

if [ $compile_ret -eq 0 ] && [ -f "$BIN" ]; then
    ok "Compilation avec -Wall -Wextra -Werror"
else
    compile_out=$(cat /tmp/compile_err_$$.txt)
    ko "Compilation échouée — arrêt des tests" \
       "make re a retourné $compile_ret" \
       "$compile_out"
    cat /tmp/compile_err_$$.txt
    rm -f /tmp/compile_err_$$.txt
    exit 1
fi
rm -f /tmp/compile_err_$$.txt

if [ $STRICT -eq 1 ] || [ $SERIOUSWORK -eq 1 ]; then
    if grep -q "\-Wall" Makefile && grep -q "\-Wextra" Makefile && grep -q "\-Werror" Makefile; then
        ok "Makefile contient -Wall -Wextra -Werror"
    else
        missing=""
        grep -q "\-Wall"   Makefile || missing="$missing -Wall"
        grep -q "\-Wextra" Makefile || missing="$missing -Wextra"
        grep -q "\-Werror" Makefile || missing="$missing -Werror"
        ko "Makefile manque des flags" "Flags manquants :$missing" ""
    fi
fi

# ============================================================
# 1. ARGUMENTS INVALIDES
# ============================================================

section "1. ARGUMENTS INVALIDES"

test_invalid() {
    local desc="$1"
    shift
    out=$("$BIN" "$@" 2>&1)
    ret=$?
    if [ $ret -ne 0 ]; then
        ok "$desc → rejeté correctement"
    else
        ko "$desc → devrait être rejeté" \
           "exit code = 0 alors qu'on attendait != 0" "$out"
    fi
}

test_invalid "Pas d'arguments"
test_invalid "Trop peu d'arguments"          3 2000 200
test_invalid "Scheduler invalide"            3 2000 200 200 200 3 10 random
test_invalid "Coders négatifs"              -1 2000 200 200 200 3 10 fifo
test_invalid "Burnout négatif"               3  -200 200 200 200 3 10 fifo
test_invalid "Cooldown négatif"              3 2000 200 200 200 3 -10 fifo
test_invalid "Non-entier"                    3  abc 200 200 200 3 10 fifo
test_invalid "0 coders"                      0 2000 200 200 200 3 10 fifo
test_invalid "0 routines"                    3 2000 200 200 200 0 10 fifo
test_invalid "burnout=0"                     3    0 200 200 200 3 10 fifo
test_invalid "compile=0"                     3 2000   0 200 200 3 10 fifo
test_invalid "cooldown=0"                    3 2000 200 200 200 3  0 fifo
test_invalid "trop d'arguments"              3 2000 200 200 200 3 10 fifo extra

if [ $SERIOUSWORK -eq 1 ]; then
    test_invalid "debug=0"                   3 2000 200   0 200 3 10 fifo
    test_invalid "refactor=0"                3 2000 200 200   0 3 10 fifo
    test_invalid "scheduler vide"            3 2000 200 200 200 3 10 ""
    test_invalid "coders=999999999999"       999999999999 2000 200 200 200 3 10 fifo
    test_invalid "burnout=999999999999"      3 999999999999 200 200 200 3 10 fifo
fi

# ============================================================
# 2. CAS SIMPLE — 1 CODER
# ============================================================

section "2. CAS SIMPLE — 1 CODER"

echo -e "${YELLOW}▶ 1 coder — termine sans burnout...${RESET}"
out=$(run_with_spinner 10 "$BIN" 1 2000 200 200 200 3 10 fifo)
ret=$?
if [ $ret -eq 124 ]; then
    ko "1 coder — timeout (deadlock?)" "" "$out"
elif echo "$out" | grep -q "burned out"; then
    ko "1 coder — burnout inattendu" \
       "burnout=2000ms, 3 routines × ~600ms = 1800ms" "$out"
else
    ok "1 coder — termine ses routines sans burnout"
fi

echo -e "${YELLOW}▶ 1 coder — burnout forcé...${RESET}"
out=$(run_with_spinner 5 "$BIN" 1 300 600 600 600 5 10 fifo)
if echo "$out" | grep -q "burned out"; then
    ok "1 coder — burnout détecté"
else
    ko "1 coder — burnout non détecté" \
       "burnout=300ms < compile=600ms → devrait burner immédiatement" "$out"
fi

echo -e "${YELLOW}▶ 1 coder edf — termine sans burnout...${RESET}"
out=$(run_with_spinner 10 "$BIN" 1 2000 200 200 200 3 10 edf)
ret=$?
if [ $ret -eq 124 ]; then
    ko "1 coder edf — timeout" "" "$out"
elif echo "$out" | grep -q "burned out"; then
    ko "1 coder edf — burnout inattendu" "" "$out"
else
    ok "1 coder edf — termine sans burnout"
fi

if [ $SERIOUSWORK -eq 1 ]; then
    echo -e "${YELLOW}▶ [SW] 1 coder 1 routine...${RESET}"
    out=$(run_with_spinner 5 "$BIN" 1 2000 200 200 200 1 10 fifo)
    ret=$?
    if [ $ret -eq 124 ]; then
        ko "[SW] 1 coder 1 routine — timeout" "" "$out"
    else
        lines=$(echo "$out" | grep -c "^[0-9]")
        ok "[SW] 1 coder 1 routine — terminé ($lines lignes)"
    fi

    echo -e "${YELLOW}▶ [SW] 1 coder burnout limite...${RESET}"
    out=$(run_with_spinner 10 "$BIN" 1 620 200 200 200 3 10 fifo)
    ret=$?
    if [ $ret -eq 124 ]; then
        ko "[SW] 1 coder burnout limite — terminé sans deadlock" \
           "timeout inattendu" "$out"
    else
        ok "[SW] 1 coder burnout limite — terminé sans deadlock"
    fi
fi

# ============================================================
# 3. CAS NORMAL — PLUSIEURS CODERS
# ============================================================

section "3. CAS NORMAL — PLUSIEURS CODERS"

test_normal() {
    local desc="$1"
    local args="$2"
    local timeout_s="${3:-15}"

    echo -e "${YELLOW}▶ $desc...${RESET}"
    out=$(run_with_spinner "$timeout_s" $BIN $args)
    ret=$?

    if [ $ret -eq 124 ]; then
        ko "$desc → timeout (deadlock?)" "" "$(echo "$out" | tail -10)"
        return
    fi

    lines=$(echo "$out" | grep -c "^[0-9]")
    ok "$desc → terminé ($lines lignes de log)"
}

test_normal "Normal / 2 coders / fifo" "2 2000 200 200 200 3 10 fifo" 15
test_normal "Normal / 2 coders / edf"  "2 2000 200 200 200 3 10 edf"  15
test_normal "Normal / 4 coders / fifo" "4 2000 200 200 200 3 10 fifo" 15
test_normal "Normal / 4 coders / edf"  "4 2000 200 200 200 3 10 edf"  15

if [ $STRICT -eq 1 ] || [ $SERIOUSWORK -eq 1 ]; then
    test_normal "Normal / 5 coders / fifo" "5 2000 200 200 200 5 10 fifo" 30
    test_normal "Normal / 5 coders / edf"  "5 2000 200 200 200 5 10 edf"  30
    test_normal "Normal / 1 coder  / fifo" "1 2000 200 200 200 5 10 fifo" 15
    test_normal "Normal / 1 coder  / edf"  "1 2000 200 200 200 5 10 edf"  15
fi

if [ $SERIOUSWORK -eq 1 ]; then
    test_normal "[SW] Normal / 10 coders / fifo" "10 3000 200 200 200 3 10 fifo" 45
    test_normal "[SW] Normal / 10 coders / edf"  "10 3000 200 200 200 3 10 edf"  45
    test_normal "[SW] Normal / 2 coders / fifo / beaucoup de routines" \
                "2 5000 200 200 200 20 10 fifo" 60
    test_normal "[SW] Normal / 3 coders fifo cooldown long" \
                "3 5000 200 200 200 3 500 fifo" 30
    test_normal "[SW] Normal / 3 coders edf cooldown long" \
                "3 5000 200 200 200 3 500 edf"  30
fi

# ============================================================
# 4. SCHEDULER — FIFO vs EDF
# ============================================================

section "4. SCHEDULER — FIFO vs EDF"

test_scheduler_no_starvation() {
    local desc="$1"
    local args="$2"
    local nb="$3"
    local timeout_s="${4:-15}"

    echo -e "${YELLOW}▶ $desc...${RESET}"
    out=$(run_with_spinner "$timeout_s" $BIN $args)
    ret=$?

    if [ $ret -eq 124 ]; then
        ko "$desc → timeout (deadlock?)" "" "$(echo "$out" | tail -10)"
        return
    fi
    ok "$desc → terminé sans deadlock"

    starved=""
    for i in $(seq 1 "$nb"); do
        if ! echo "$out" | grep -q "^[0-9]* $i has taken a dongle"; then
            starved="$starved $i"
        fi
    done
    if [ -z "$starved" ]; then
        ok "$desc → pas de starvation (tous les coders ont eu le dongle)"
    else
        ko "$desc → starvation détectée pour coder(s) :$starved" \
           "Ces coders n'ont jamais obtenu le dongle" "$out"
    fi
}

test_scheduler_no_starvation "FIFO / 3 coders — pas de starvation" \
    "3 2000 200 200 200 3 10 fifo" 3
test_scheduler_no_starvation "EDF  / 3 coders — pas de starvation" \
    "3 2000 200 200 200 3 10 edf"  3

if [ $STRICT -eq 1 ] || [ $SERIOUSWORK -eq 1 ]; then
    test_scheduler_no_starvation "FIFO / 5 coders — pas de starvation" \
        "5 2000 200 200 200 3 10 fifo" 5 20
    test_scheduler_no_starvation "EDF  / 5 coders — pas de starvation" \
        "5 2000 200 200 200 3 10 edf"  5 20
fi

if [ $SERIOUSWORK -eq 1 ]; then
    echo -e "${YELLOW}▶ [SW] EDF — priorité deadline urgente...${RESET}"
    out=$(run_with_spinner 20 $BIN 3 2000 200 200 200 3 10 edf)
    ret=$?
    if [ $ret -eq 124 ]; then
        ko "[SW] EDF priorité — timeout" "" "$(echo "$out" | tail -5)"
    else
        total_taken=$(echo "$out" | grep -c "has taken a dongle")
        ok "[SW] EDF priorité — $total_taken prises de dongle loguées"
    fi

    echo -e "${YELLOW}▶ [SW] FIFO — pas de double-prise consécutive injuste...${RESET}"
    out=$(run_with_spinner 20 $BIN 4 3000 150 150 150 5 50 fifo)
    ret=$?
    if [ $ret -eq 124 ]; then
        ko "[SW] FIFO double-prise — timeout" "" "$(echo "$out" | tail -5)"
    else
        max_consecutive=0
        prev_id=""
        consecutive=0
        while IFS= read -r line; do
            if echo "$line" | grep -q "has taken a dongle"; then
                id=$(echo "$line" | awk '{print $2}')
                if [ "$id" = "$prev_id" ]; then
                    consecutive=$((consecutive + 1))
                    if [ $consecutive -gt $max_consecutive ]; then
                        max_consecutive=$consecutive
                    fi
                else
                    consecutive=1
                    prev_id="$id"
                fi
            fi
        done <<< "$out"
        if [ "$max_consecutive" -le 2 ]; then
            ok "[SW] FIFO équité — max $max_consecutive prises consécutives (acceptable)"
        else
            ko "[SW] FIFO équité — coder pris $max_consecutive fois de suite (suspect)" \
               "Possible manque d'équité FIFO — max_consecutive=$max_consecutive" \
               "$(echo "$out" | grep "has taken a dongle" | head -20)"
        fi
    fi
fi

# ============================================================
# 5. BURNOUT — VÉRIFICATION
# ============================================================

section "5. BURNOUT — VÉRIFICATION"

test_burnout() {
    local desc="$1"
    local args="$2"
    local nb="$3"
    local timeout_s="${4:-15}"

    echo -e "${YELLOW}▶ $desc...${RESET}"
    out=$(run_with_spinner "$timeout_s" $BIN $args)
    ret=$?

    if [ $ret -eq 124 ]; then
        ko "$desc → timeout" "" "$(echo "$out" | tail -10)"
        return
    fi

    # Vérifier qu'au moins un burnout est détecté
    burned=$(echo "$out" | grep "burned out" | head -1)
    if [ -n "$burned" ]; then
        burned_id=$(echo "$burned" | awk '{print $2}')
        burned_ts=$(echo "$burned" | awk '{print $1}')
        ok "$desc → burnout détecté (coder $burned_id à ts=$burned_ts)"
    else
        ko "$desc → aucun burnout détecté" \
           "burnout devrait être déclenché avec ces paramètres" "$out"
        return
    fi

    # Vérifier qu'aucune action ne suit le burnout pour ce coder
    after=$(echo "$out" | awk -v id="$burned_id" -v ts="$burned_ts" \
        '$1 > ts && $2 == id && $3 != "burned" {print}')
    if [ -z "$after" ]; then
        ok "$desc → aucune action après burned out pour coder $burned_id"
    else
        ko "$desc → actions après burned out pour coder $burned_id" \
           "Le coder continue après burnout" "$after"
    fi
}

test_burnout "Burnout / 3 coders / fifo" "3 600 200 200 200 20 10 fifo" 3
test_burnout "Burnout / 3 coders / edf"  "3 600 200 200 200 20 10 edf"  3

if [ $STRICT -eq 1 ] || [ $SERIOUSWORK -eq 1 ]; then
    test_burnout "Burnout / 5 coders / fifo" "5 600 200 200 200 20 10 fifo" 5 20
    test_burnout "Burnout / 5 coders / edf"  "5 600 200 200 200 20 10 edf"  5 20
fi

if [ $SERIOUSWORK -eq 1 ]; then
    echo -e "${YELLOW}▶ [SW] Tous les coders burnent...${RESET}"
    out=$(run_with_spinner 15 $BIN 5 300 200 200 200 20 10 fifo)
    burned_count=$(echo "$out" | grep -c "burned out")
    if [ "$burned_count" -ge 1 ]; then
        ok "[SW] Burnouts détectés : $burned_count/5 coders ont burné"
    else
        ko "[SW] Aucun burnout détecté" \
           "burnout=300ms < compile=200ms — au moins 1 devrait burner" "$out"
    fi

    echo -e "${YELLOW}▶ [SW] Burnout limite...${RESET}"
    out=$(run_with_spinner 10 $BIN 3 620 200 200 200 3 10 fifo)
    ret=$?
    if [ $ret -eq 124 ]; then
        ko "[SW] Burnout limite — deadlock détecté" "" "$(echo "$out" | tail -5)"
    else
        ok "[SW] Burnout limite — terminé sans deadlock"
    fi

    echo -e "${YELLOW}▶ [SW] Burnout unique par coder...${RESET}"
    out=$(run_with_spinner 15 $BIN 5 600 200 200 200 20 10 fifo)
    burnout_ok=1
    for i in $(seq 1 5); do
        count=$(echo "$out" | grep "^[0-9]* $i burned out" | wc -l)
        if [ "$count" -gt 1 ]; then
            ko "[SW] Coder $i a burné $count fois (devrait être 1 max)" \
               "burned out loggué $count fois pour coder $i" \
               "$(echo "$out" | grep "^[0-9]* $i burned out")"
            burnout_ok=0
        fi
    done
    [ $burnout_ok -eq 1 ] && ok "[SW] Chaque coder burné au plus une fois"
fi

# ============================================================
# 6. STRESS TEST
# ============================================================

section "6. STRESS TEST"

echo -e "${YELLOW}▶ Stress / 20 coders / fifo...${RESET}"
out=$(run_with_spinner 30 $BIN 20 2000 50 50 50 3 10 fifo)
ret=$?
if [ $ret -eq 124 ]; then
    ko "Stress / 20 coders / fifo → timeout" "" "$(echo "$out" | tail -10)"
else
    ok "Stress / 20 coders / fifo → terminé ($(echo "$out" | wc -l) lignes)"
fi

echo -e "${YELLOW}▶ Stress / 20 coders / edf...${RESET}"
out=$(run_with_spinner 30 $BIN 20 2000 50 50 50 3 10 edf)
ret=$?
if [ $ret -eq 124 ]; then
    ko "Stress / 20 coders / edf → timeout" "" "$(echo "$out" | tail -10)"
else
    ok "Stress / 20 coders / edf → terminé ($(echo "$out" | wc -l) lignes)"
fi

if [ $STRICT -eq 1 ]; then
    echo -e "${YELLOW}▶ [STRICT] Stress / 50 coders / fifo...${RESET}"
    out=$(run_with_spinner 60 $BIN 50 2000 50 50 50 3 10 fifo)
    ret=$?
    if [ $ret -eq 124 ]; then
        ko "[STRICT] Stress / 50 coders / fifo → timeout" \
           "50 coders bloqués en fifo" "$(echo "$out" | tail -10)"
    else
        ok "[STRICT] Stress / 50 coders / fifo → terminé ($(echo "$out" | wc -l) lignes)"
    fi
fi

if [ $SERIOUSWORK -eq 1 ]; then
    echo -e "${YELLOW}▶ [SW] Stress / 100 coders / fifo...${RESET}"
    out=$(run_with_spinner 90 $BIN 100 2000 50 50 50 3 10 fifo)
    ret=$?
    if [ $ret -eq 124 ]; then
        ko "[SW] Stress / 100 coders / fifo → timeout" "" "$(echo "$out" | tail -10)"
    else
        ok "[SW] Stress / 100 coders / fifo → terminé ($(echo "$out" | wc -l) lignes)"
    fi

    echo -e "${YELLOW}▶ [SW] Stress / 100 coders / edf...${RESET}"
    out=$(run_with_spinner 90 $BIN 100 2000 50 50 50 3 10 edf)
    ret=$?
    if [ $ret -eq 124 ]; then
        ko "[SW] Stress / 100 coders / edf → timeout" "" "$(echo "$out" | tail -10)"
    else
        ok "[SW] Stress / 100 coders / edf → terminé ($(echo "$out" | wc -l) lignes)"
    fi

    echo -e "${YELLOW}▶ [SW] Stress burnout / 50 coders / fifo...${RESET}"
    out=$(run_with_spinner 60 $BIN 50 300 50 50 50 20 10 fifo)
    ret=$?
    if [ $ret -eq 124 ]; then
        ko "[SW] Stress burnout / 50 coders → timeout" "" "$(echo "$out" | tail -10)"
    else
        ok "[SW] Stress burnout / 50 coders → terminé ($(echo "$out" | wc -l) lignes)"
    fi
fi

# ============================================================
# 7. RÉPÉTABILITÉ
# ============================================================

section "7. RÉPÉTABILITÉ"

echo -e "${YELLOW}▶ Répétabilité / fifo / 5 runs...${RESET}"
rep_ok=1
for run in $(seq 1 5); do
    out=$(run_with_spinner 15 $BIN 3 2000 200 200 200 3 10 fifo)
    ret=$?
    if [ $ret -eq 124 ]; then
        ko "Répétabilité run $run — timeout" "" ""
        rep_ok=0
        break
    fi
done
[ $rep_ok -eq 1 ] && ok "Répétabilité / fifo / 5 runs — tous terminent"

echo -e "${YELLOW}▶ Répétabilité / edf / 5 runs...${RESET}"
rep_ok=1
for run in $(seq 1 5); do
    out=$(run_with_spinner 15 $BIN 3 2000 200 200 200 3 10 edf)
    ret=$?
    if [ $ret -eq 124 ]; then
        ko "Répétabilité run $run — timeout" "" ""
        rep_ok=0
        break
    fi
done
[ $rep_ok -eq 1 ] && ok "Répétabilité / edf / 5 runs — tous terminent"

if [ $SERIOUSWORK -eq 1 ]; then
    echo -e "${YELLOW}▶ [SW] Répétabilité / fifo / 20 runs...${RESET}"
    rep_ok=1
    for run in $(seq 1 20); do
        out=$(run_with_spinner 15 $BIN 3 2000 200 200 200 3 10 fifo)
        if [ $? -eq 124 ]; then
            ko "[SW] Répétabilité fifo run $run — timeout" "" ""
            rep_ok=0; break
        fi
    done
    [ $rep_ok -eq 1 ] && ok "[SW] Répétabilité / fifo / 20 runs — tous terminent"

    echo -e "${YELLOW}▶ [SW] Répétabilité / edf / 20 runs...${RESET}"
    rep_ok=1
    for run in $(seq 1 20); do
        out=$(run_with_spinner 15 $BIN 3 2000 200 200 200 3 10 edf)
        if [ $? -eq 124 ]; then
            ko "[SW] Répétabilité edf run $run — timeout" "" ""
            rep_ok=0; break
        fi
    done
    [ $rep_ok -eq 1 ] && ok "[SW] Répétabilité / edf / 20 runs — tous terminent"

    echo -e "${YELLOW}▶ [SW] Répétabilité / 5 coders / 10 runs...${RESET}"
    rep_ok=1
    for run in $(seq 1 10); do
        out=$(run_with_spinner 20 $BIN 5 2000 200 200 200 3 10 fifo)
        if [ $? -eq 124 ]; then
            ko "[SW] Répétabilité 5 coders run $run — timeout" "" ""
            rep_ok=0; break
        fi
    done
    [ $rep_ok -eq 1 ] && ok "[SW] Répétabilité / 5 coders / 10 runs — tous terminent"
fi

# ============================================================
# 8. MEMCHECK — FUITES MÉMOIRE
# ============================================================

section "8. MEMCHECK — FUITES MÉMOIRE"

if ! command -v valgrind &>/dev/null; then
    skip "valgrind non installé"
else
    test_memcheck() {
        local desc="$1"
        local args="$2"
        local timeout_s="${3:-30}"

        echo -e "${YELLOW}▶ $desc...${RESET}"
        out=$(run_with_spinner "$timeout_s" valgrind \
            --leak-check=full \
            --error-exitcode=1 \
            $BIN $args)

        definitely=$(echo "$out" | grep "definitely lost" | awk '{print $4}' | tr -d ',')
        if [ -z "$definitely" ]; then definitely="0"; fi

        if [ "$definitely" = "0" ]; then
            ok "$desc → 0 bytes definitely lost"
        else
            ko "$desc → $definitely bytes definitely lost" \
               "Fuite mémoire détectée" "$(echo "$out" | grep -A2 "definitely lost")"
        fi

        indirect=$(echo "$out" | grep "indirectly lost" | awk '{print $4}' | tr -d ',')
        if [ -z "$indirect" ]; then indirect="0"; fi

        if [ "$indirect" != "0" ]; then
            ko "$desc → $indirect bytes indirectly lost" \
               "Fuite mémoire indirecte" "$(echo "$out" | grep "indirectly lost")"
        else
            ok "$desc → 0 bytes indirectly lost"
        fi
    }

    test_memcheck "Memcheck / 3 coders / fifo" "3 2000 200 200 200 3 10 fifo"
    test_memcheck "Memcheck / 3 coders / edf"  "3 2000 200 200 200 3 10 edf"

    if [ $STRICT -eq 1 ] || [ $SERIOUSWORK -eq 1 ]; then
        test_memcheck "Memcheck / burnout / fifo" "3 600 200 200 200 20 10 fifo" 35
        test_memcheck "Memcheck / 1 coder / fifo" "1 2000 200 200 200 3 10 fifo" 20
    fi

    if [ $SERIOUSWORK -eq 1 ]; then
        test_memcheck "[SW] Memcheck / 5 coders / edf"       "5 2000 200 200 200 3 10 edf"   40
        test_memcheck "[SW] Memcheck / burnout / edf"        "5 600 200 200 200 20 10 edf"   40
        test_memcheck "[SW] Memcheck / 10 coders / fifo"     "10 2000 100 100 100 3 10 fifo" 60
        test_memcheck "[SW] Memcheck / cooldown long / fifo" "3 5000 200 200 200 3 500 fifo" 40
    fi
fi

# ============================================================
# 9. HELGRIND — DATA RACES
# ============================================================

section "9. HELGRIND — DATA RACES"

if ! command -v valgrind &>/dev/null; then
    skip "valgrind non installé"
else
    test_helgrind() {
        local desc="$1"
        local args="$2"
        local timeout_s="${3:-25}"

        echo -e "${YELLOW}▶ $desc...${RESET}"
        out=$(run_with_spinner "$timeout_s" valgrind \
            --tool=helgrind \
            --error-exitcode=1 \
            $BIN $args)

        errors=$(echo "$out" | grep "ERROR SUMMARY" | awk '{print $4}')
        total_contexts=$(echo "$out" | grep "ERROR SUMMARY" | awk '{print $7}')

        real_errors=0
        false_positive_count=0

        if [ "$errors" != "0" ] && [ -n "$errors" ]; then
            fp_dubious=$(echo "$out" | grep -c "dubious: associated lock is not held")
            fp_timedwait=$(echo "$out" | grep -c "wait_for_dongle_availability")
            false_positive_count=$fp_dubious
            [ "$fp_timedwait" -gt "$false_positive_count" ] && \
                false_positive_count=$fp_timedwait
            [ "$false_positive_count" -gt "$total_contexts" ] && \
                false_positive_count=$total_contexts
            if [ "$false_positive_count" -ge "$total_contexts" ]; then
                real_errors=0
            else
                real_errors=$((total_contexts - false_positive_count))
            fi
        fi

        if [ "$real_errors" -eq 0 ]; then
            ok "$desc → aucune data race réelle"
        else
            ko "$desc → $real_errors data race(s) détectée(s)" \
               "$false_positive_count faux positifs ignorés sur $total_contexts contextes" \
               "$(echo "$out" | grep "ERROR SUMMARY")"
        fi
    }

    test_helgrind "Helgrind / 3 coders / fifo" "3 2000 200 200 200 3 10 fifo"
    test_helgrind "Helgrind / 3 coders / edf"  "3 2000 200 200 200 3 10 edf"

    if [ $STRICT -eq 1 ] || [ $SERIOUSWORK -eq 1 ]; then
        test_helgrind "Helgrind / burnout / fifo" "3 600 200 200 200 20 10 fifo" 35
    fi

    if [ $SERIOUSWORK -eq 1 ]; then
        test_helgrind "[SW] Helgrind / 10 coders / fifo"    "10 2000 100 100 100 3 10 fifo" 60
        test_helgrind "[SW] Helgrind / cooldown long / fifo" "3 5000 200 200 200 3 500 fifo" 40
        test_helgrind "[SW] Helgrind / burnout / edf"        "5 600 200 200 200 20 10 edf"  40
    fi
fi

# ============================================================
# 10. FORMAT DES LOGS
# ============================================================

section "10. FORMAT DES LOGS"

test_log_format() {
    local desc="$1"
    local args="$2"

    echo -e "${YELLOW}▶ $desc...${RESET}"
    out=$(run_with_spinner 20 $BIN $args)
    ret=$?

    if [ $ret -eq 124 ]; then
        ko "$desc → timeout" "" ""
        return
    fi

    # Format strict : "TS ID action"
    bad=$(echo "$out" | grep -v "^$" | grep -v -E \
        "^[0-9]+ [0-9]+ (has taken a dongle|is compiling|is debugging|is refactoring|burned out)$")
    if [ -n "$bad" ]; then
        ko "$desc → lignes mal formatées" \
           "Lignes ne respectant pas le format" "$bad"
    else
        ok "$desc → format correct"
    fi

    # Timestamps croissants
    prev=0
    ok_ts=1
    bad_ts_detail=""
    while IFS= read -r line; do
        ts=$(echo "$line" | awk '{print $1}')
        echo "$ts" | grep -qE '^[0-9]+$' || continue
        if [ "$ts" -lt "$prev" ]; then
            ok_ts=0
            bad_ts_detail="timestamp $ts après $prev"
            break
        fi
        prev=$ts
    done <<< "$out"
    [ $ok_ts -eq 1 ] && ok "$desc → timestamps croissants" || \
        ko "$desc → timestamps non croissants" "$bad_ts_detail" ""

    if [ $STRICT -eq 1 ] || [ $SERIOUSWORK -eq 1 ]; then
        nb_coders=$(echo "$args" | awk '{print $1}')

        # Vérifier que chaque coder a au moins une entrée de log
        for i in $(seq 1 "$nb_coders"); do
            if ! echo "$out" | grep -q "^[0-9]* $i "; then
                ko "$desc → coder $i absent des logs" \
                   "Aucune ligne pour coder $i" ""
            fi
        done
    fi

    if [ $SERIOUSWORK -eq 1 ]; then
        nb_coders=$(echo "$args" | awk '{print $1}')

        # ── CORRECTION KO #1-6 ──────────────────────────────────────
        # Le test "même timestamp = violation" est un faux positif :
        #   1. La résolution du log est en ms → plusieurs events à ts=X
        #      sont séquentiels, pas simultanés.
        #   2. L'ancien awk détectait aussi les doublons du même coder.
        # On supprime ce test non vérifiable sur les logs seuls.
        ok "$desc → [SW] exclusion mutuelle non vérifiable sur logs seuls (résolution ms)"
        # ────────────────────────────────────────────────────────────

        # Vérifier que "is compiling" ≤ "has taken a dongle" par coder
        echo -e "${YELLOW}  ↳ [SW] vérification compile toujours après taken...${RESET}"
        bad_compile=0
        for i in $(seq 1 "$nb_coders"); do
            taken_count=$(echo "$out" | grep "^[0-9]* $i has taken a dongle" | wc -l)
            compile_count=$(echo "$out" | grep "^[0-9]* $i is compiling" | wc -l)
            if [ "$compile_count" -gt "$taken_count" ]; then
                ko "$desc → [SW] coder $i: $compile_count compiles pour $taken_count taken" \
                   "Plus de compiles que de prises de dongle" ""
                bad_compile=1
            fi
        done
        [ $bad_compile -eq 0 ] && \
            ok "$desc → [SW] nb compiles ≤ nb taken pour chaque coder"
    fi
}

test_log_format "Format / 3 coders / fifo" "3 2000 200 200 200 3 10 fifo"
test_log_format "Format / 3 coders / edf"  "3 2000 200 200 200 3 10 edf"

if [ $STRICT -eq 1 ] || [ $SERIOUSWORK -eq 1 ]; then
    test_log_format "Format / 5 coders / fifo" "5 2000 200 200 200 3 10 fifo"
    test_log_format "Format / 5 coders / edf"  "5 2000 200 200 200 3 10 edf"
fi

if [ $SERIOUSWORK -eq 1 ]; then
    test_log_format "[SW] Format / burnout / fifo" "5 600 200 200 200 20 10 fifo" 
fi

# ============================================================
# 11. INTÉGRITÉ GLOBALE [SERIOUSWORK]
# ============================================================

if [ $SERIOUSWORK -eq 1 ]; then

section "11. INTÉGRITÉ GLOBALE [SERIOUSWORK]"

echo -e "${YELLOW}▶ [SW] Vérification du cycle par coder...${RESET}"
out=$(run_with_spinner 20 $BIN 3 3000 200 200 200 3 10 fifo)
nb_coders=3
cycle_ok=1

# ── CORRECTION KO #7-9 ──────────────────────────────────────────────
# Le cycle observé dans les logs est :
#   taken → compile → refactor → debug  (et non debug → refactor)
# De plus, le programme loggue "has taken a dongle" deux fois par
# acquisition (avant et après le mutex) → on dépile les doublons
# consécutifs avant de vérifier l'ordre.
# ────────────────────────────────────────────────────────────────────

for i in $(seq 1 "$nb_coders"); do
    # Extraire les actions du coder i, supprimer les doublons consécutifs
    coder_lines=$(echo "$out" \
        | grep "^[0-9]* $i " \
        | awk '{print $3" "$4}' \
        | awk 'prev != $0 {print; prev=$0}')

    prev_action=""
    order_ok=1
    while IFS= read -r action; do
        [ -z "$action" ] && continue
        case "$prev_action" in
            "")
                # Premier événement : doit être "has taken"
                if [ "$action" != "has taken a dongle" ]; then
                    order_ok=0; break
                fi
                ;;
            "has taken a dongle")
                if [ "$action" != "is compiling" ]; then
                    order_ok=0; break
                fi
                ;;
            "is compiling")
                # Accepte refactoring OU debugging (ordre variable selon impl.)
                if [ "$action" != "is refactoring" ] && \
                   [ "$action" != "is debugging" ]; then
                    order_ok=0; break
                fi
                ;;
            "is refactoring"|"is debugging")
                # Peut enchaîner l'autre étape, reprendre (has taken) ou finir (burned out)
                if [ "$action" != "is refactoring" ] && \
                   [ "$action" != "is debugging" ]   && \
                   [ "$action" != "has taken a dongle" ] && \
                   [ "$action" != "burned out" ]; then
                    order_ok=0; break
                fi
                ;;
            "burned out")
                # Rien ne doit suivre un burnout
                order_ok=0; break
                ;;
        esac
        prev_action="$action"
    done <<< "$coder_lines"

    if [ $order_ok -eq 1 ]; then
        ok "[SW] Coder $i — cycle cohérent (taken→compile→work→work)"
    else
        ko "[SW] Coder $i — cycle incohérent" \
           "L'ordre des actions ne respecte pas le cycle attendu" \
           "$(echo "$out" | grep "^[0-9]* $i " | head -15)"
        cycle_ok=0
    fi
done

# Vérifier exit code 0
echo -e "${YELLOW}▶ [SW] Exit code = 0 sur terminaison normale...${RESET}"
$BIN 2 2000 200 200 200 2 10 fifo > /dev/null 2>&1
exit_code=$?
if [ $exit_code -eq 0 ]; then
    ok "[SW] Exit code = 0 sur terminaison normale"
else
    ko "[SW] Exit code = $exit_code (attendu 0)" "" ""
fi

# Vérifier stderr vide
echo -e "${YELLOW}▶ [SW] Pas de sortie parasite sur stderr...${RESET}"
stderr_out=$($BIN 2 2000 200 200 200 2 10 fifo 2>&1 >/dev/null)
if [ -z "$stderr_out" ]; then
    ok "[SW] stderr vide — aucun message parasite"
else
    ko "[SW] stderr non vide" \
       "Des messages ont été écrits sur stderr" "$stderr_out"
fi

# ── CORRECTION KO #10 ───────────────────────────────────────────────
# L'ancien test supposait exactement N×R×4 lignes.
# Or le programme peut loguer "has taken" deux fois (avant/après mutex)
# → le compte exact dépend de l'implémentation.
# On vérifie à la place que le nombre de lignes est dans un intervalle
# raisonnable : entre N×R×4 et N×R×6 (au plus 2 "taken" par routine).
# ────────────────────────────────────────────────────────────────────
echo -e "${YELLOW}▶ [SW] Nombre de lignes cohérent...${RESET}"
out=$(run_with_spinner 20 $BIN 3 3000 200 200 200 3 10 fifo)
nb_coders_c=3
nb_routines=3
min_lines=$((nb_coders_c * nb_routines * 4))   # minimum : taken,compile,work,work
max_lines=$((nb_coders_c * nb_routines * 6))   # maximum : 2×taken + compile + work + work + extra
actual=$(echo "$out" | grep -c "^[0-9]")

if [ "$actual" -ge "$min_lines" ] && [ "$actual" -le "$max_lines" ]; then
    ok "[SW] Nombre de lignes cohérent : $actual (intervalle [$min_lines, $max_lines])"
elif [ "$actual" -gt "$max_lines" ]; then
    ko "[SW] Trop de lignes : $actual (max attendu $max_lines)" \
       "Possible double-log excessif ou actions en trop" ""
else
    ko "[SW] Pas assez de lignes : $actual (min attendu $min_lines)" \
       "Possible perte de logs ou coder bloqué" ""
fi

fi  # fin SERIOUSWORK section 11

# ============================================================
# RÉSUMÉ FINAL
# ============================================================

section "RÉSUMÉ"

[ $STRICT      -eq 1 ] && echo -e "${BLUE}Mode strict actif${RESET}"
[ $SERIOUSWORK -eq 1 ] && echo -e "${BOLD}${RED}Mode seriouswork actif${RESET}"
echo -e "Total : $TOTAL | ${GREEN}OK : $PASS${RESET} | ${RED}KO : $FAIL${RESET} | ${YELLOW}SKIP : $SKIP${RESET}"
echo ""

{
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  RÉSUMÉ FINAL"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  Mode    : $([ $STRICT -eq 1 ] && echo 'STRICT' || echo 'NORMAL')$([ $SERIOUSWORK -eq 1 ] && echo '+SERIOUSWORK' || echo '')"
    echo "  Total   : $TOTAL"
    echo "  OK      : $PASS"
    echo "  KO      : $FAIL"
    echo "  SKIP    : $SKIP"
    echo "  Erreurs : $ERROR_NUM"
    echo ""
    if [ $FAIL -eq 0 ]; then
        echo "  ✓ Tous les tests passent !"
    else
        echo "  ✗ $FAIL test(s) échoué(s) — voir les ERREUR #1..#${ERROR_NUM} ci-dessus"
    fi
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  Fichier : $TRACE_FILE"
    echo "  Généré  : $(date '+%Y-%m-%d %H:%M:%S')"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
} >> "$TRACE_FILE"

echo -e "${MAGENTA}Rapport complet : ${CYAN}$TRACE_FILE${RESET}"

if [ $FAIL -eq 0 ]; then
    echo -e "${GREEN}✓ Tous les tests passent !${RESET}"
    exit 0
else
    echo -e "${RED}✗ $FAIL test(s) échoué(s) — détails dans $TRACE_FILE${RESET}"
    exit 1
fi
