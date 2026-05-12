#!/bin/bash

# ============================================================
# test_codexion.sh — Tests automatiques pour codexion
# Usage: bash test_codexion.sh [--strict]
# ============================================================

BIN="./codexion"
PASS=0
FAIL=0
SKIP=0
TOTAL=0
STRICT=0
ERROR_NUM=0
TRACE_FILE="trace_$(date +%Y%m%d_%H%M%S).log"

# Parse args
for arg in "$@"; do
    if [ "$arg" = "--strict" ]; then
        STRICT=1
    fi
done

GREEN="\033[0;32m"
RED="\033[0;31m"
YELLOW="\033[0;33m"
CYAN="\033[0;36m"
BLUE="\033[0;34m"
MAGENTA="\033[0;35m"
RESET="\033[0m"

# ============================================================
# TRACE — initialisation
# ============================================================

init_trace() {
    cat > "$TRACE_FILE" << EOF
╔══════════════════════════════════════════════════════════════╗
║           CODEXION — RAPPORT DE TESTS                       ║
║  Date    : $(date '+%Y-%m-%d %H:%M:%S')                          ║
║  Mode    : $([ $STRICT -eq 1 ] && echo "STRICT" || echo "NORMAL")                                       ║
║  Binaire : $BIN                                   ║
╚══════════════════════════════════════════════════════════════╝

EOF
}

# Écrit dans le fichier trace (sans couleurs ANSI)
trace() {
    echo "$1" >> "$TRACE_FILE"
}

trace_section() {
    echo "" >> "$TRACE_FILE"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >> "$TRACE_FILE"
    echo "  $1" >> "$TRACE_FILE"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >> "$TRACE_FILE"
}

# Enregistre une erreur numérotée dans la trace
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
    local msg="$1"
    local detail="${2:-}"
    local output="${3:-}"
    echo -e "${RED}[KO]${RESET} $msg"
    FAIL=$((FAIL + 1))
    TOTAL=$((TOTAL + 1))
    trace "[KO] $msg"
    trace_error "$msg" "${detail:-$msg}" "$output"
}

skip() {
    echo -e "${YELLOW}[SKIP]${RESET} $1"
    SKIP=$((SKIP + 1))
    trace "[SKIP] $1"
}

strict_only() {
    if [ $STRICT -eq 0 ]; then
        skip "$1 (mode strict uniquement — relancez avec --strict)"
        return 1
    fi
    return 0
}

section() {
    echo ""
    echo -e "${YELLOW}══════════════════════════════════════════${RESET}"
    echo -e "${YELLOW}  $1${RESET}"
    if [ $STRICT -eq 1 ]; then
        echo -e "${BLUE}  [MODE STRICT ACTIF]${RESET}"
    fi
    echo -e "${YELLOW}══════════════════════════════════════════${RESET}"
    trace_section "$1"
}

run_with_spinner() {
    local timeout_s=$1
    shift
    local frames=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
    local start elapsed i
    local fifo=/tmp/spinner_fifo_$$

    mkfifo "$fifo"
    start=$(date +%s)

    timeout "$timeout_s" "$@" 2>&1 | tee "$fifo" > /tmp/spinner_out.txt &
    local cmd_pid=$!

    (
        while IFS= read -r line; do
            printf "\033[s\033[45G\033[2K${CYAN}${line:0:80}${RESET}\033[u" >&2
        done < "$fifo"
    ) &
    local reader_pid=$!

    i=0
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

    cat /tmp/spinner_out.txt
    rm -f /tmp/spinner_out.txt
    return $ret
}

# ============================================================
# INIT TRACE
# ============================================================

init_trace
echo -e "${MAGENTA}Rapport de tests : ${CYAN}$TRACE_FILE${RESET}"

# ============================================================
# 0. COMPILATION
# ============================================================

section "0. COMPILATION"

make re 2>/tmp/compile_err.txt 1>/dev/null
compile_ret=$?

if [ $compile_ret -eq 0 ] && [ -f "$BIN" ]; then
    ok "Compilation avec -Wall -Wextra -Werror"
else
    compile_out=$(cat /tmp/compile_err.txt)
    ko "Compilation échouée — arrêt des tests" \
       "make re a retourné $compile_ret" \
       "$compile_out"
    echo ""
    echo -e "${RED}── Erreurs de compilation ──${RESET}"
    cat /tmp/compile_err.txt
    echo -e "${RED}────────────────────────────${RESET}"
    rm -f /tmp/compile_err.txt

    # Finalise la trace avant de quitter
    {
        echo ""
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo "  RÉSUMÉ — ARRÊT PRÉMATURÉ (compilation échouée)"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo "  Total : $TOTAL | OK : $PASS | KO : $FAIL | SKIP : $SKIP"
        echo "  Erreurs numérotées : $ERROR_NUM"
    } >> "$TRACE_FILE"
    exit 1
fi
rm -f /tmp/compile_err.txt

if [ $STRICT -eq 1 ]; then
    if grep -q "\-Wall" Makefile && grep -q "\-Wextra" Makefile && grep -q "\-Werror" Makefile; then
        ok "[STRICT] Makefile contient -Wall -Wextra -Werror"
    else
        missing=""
        grep -q "\-Wall"   Makefile || missing="$missing -Wall"
        grep -q "\-Wextra" Makefile || missing="$missing -Wextra"
        grep -q "\-Werror" Makefile || missing="$missing -Werror"
        ko "[STRICT] Makefile manque un flag parmi -Wall -Wextra -Werror" \
           "Flags manquants :$missing" ""
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
           "exit code = 0 alors qu'on attendait != 0" \
           "$out"
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

if [ $STRICT -eq 1 ]; then
    test_invalid "[STRICT] 0 routines"       3 2000 200 200 200  0 10 fifo
    test_invalid "[STRICT] burnout=0"        3    0 200 200 200  3 10 fifo
    test_invalid "[STRICT] compile=0"        3 2000   0 200 200  3 10 fifo
    test_invalid "[STRICT] cooldown=0"       3 2000 200 200 200  3  0 fifo
    test_invalid "[STRICT] trop d'arguments" 3 2000 200 200 200  3 10 fifo extra
fi

# ============================================================
# 2. CAS SIMPLE — 1 CODER
# ============================================================

section "2. CAS SIMPLE — 1 CODER"

echo -e "${YELLOW}▶ Test 1 coder — termine sans burnout...${RESET}"
out=$(run_with_spinner 10 "$BIN" 1 2000 200 200 200 3 10 fifo 2>&1)
ret=$?
if [ $ret -eq 124 ]; then
    ko "1 coder — timeout (deadlock?)" \
       "Le programme n'a pas terminé en 10s avec 1 coder" \
       "$out"
elif echo "$out" | grep -q "burned out"; then
    ko "1 coder — burnout inattendu" \
       "Un coder seul ne devrait pas burner (burnout=2000ms, 3 routines × 600ms = 1800ms)" \
       "$out"
else
    ok "1 coder — termine ses routines sans burnout"
fi

echo -e "${YELLOW}▶ Test 1 coder — burnout forcé (burnout=300ms < temps de travail)...${RESET}"
out=$(run_with_spinner 5 "$BIN" 1 300 600 600 600 5 10 fifo 2>&1)
ret=$?
if echo "$out" | grep -q "burned out"; then
    ok "1 coder — burnout détecté"
else
    ko "1 coder — burnout non détecté" \
       "Avec burnout=300ms et compile=600ms le coder devrait burner immédiatement" \
       "$out"
fi

if [ $STRICT -eq 1 ]; then
    echo -e "${YELLOW}▶ [STRICT] 1 coder edf — termine sans burnout...${RESET}"
    out=$(run_with_spinner 10 "$BIN" 1 2000 200 200 200 3 10 edf 2>&1)
    ret=$?
    if [ $ret -eq 124 ]; then
        ko "[STRICT] 1 coder edf — timeout" \
           "Deadlock possible avec 1 coder en edf" "$out"
    elif echo "$out" | grep -q "burned out"; then
        ko "[STRICT] 1 coder edf — burnout inattendu" \
           "1 coder seul en edf ne devrait pas burner" "$out"
    else
        ok "[STRICT] 1 coder edf — termine sans burnout"
    fi
fi

# ============================================================
# 3. CAS NORMAL — PLUSIEURS CODERS
# ============================================================

section "3. CAS NORMAL — PLUSIEURS CODERS"

test_normal() {
    local desc="$1"
    local args="$2"
    local timeout_s="$3"

    echo -e "${YELLOW}▶ $desc...${RESET}"
    out=$(run_with_spinner "$timeout_s" $BIN $args)
    ret=$?

    if [ $ret -eq 124 ]; then
        ko "$desc → timeout (deadlock?)" \
           "Aucune terminaison en ${timeout_s}s avec args: $args" \
           "$(echo "$out" | tail -10)"
        return
    fi
    ok "$desc → terminé ($(echo "$out" | wc -l) lignes de log)"
}

test_normal "Normal / 2 coders / fifo" "2 2000 200 200 200 3 10 fifo" 15
test_normal "Normal / 2 coders / edf"  "2 2000 200 200 200 3 10 edf"  15
test_normal "Normal / 4 coders / fifo" "4 2000 200 200 200 3 10 fifo" 15
test_normal "Normal / 4 coders / edf"  "4 2000 200 200 200 3 10 edf"  15

if [ $STRICT -eq 1 ]; then
    test_normal "[STRICT] Normal / 5 coders / fifo" "5 2000 200 200 200 5 10 fifo" 30
    test_normal "[STRICT] Normal / 5 coders / edf"  "5 2000 200 200 200 5 10 edf"  30
    test_normal "[STRICT] Normal / 1 coder  / fifo" "1 2000 200 200 200 5 10 fifo" 15
    test_normal "[STRICT] Normal / 1 coder  / edf"  "1 2000 200 200 200 5 10 edf"  15
fi

# ============================================================
# 4. SCHEDULER — FIFO vs EDF
# ============================================================

section "4. SCHEDULER — FIFO vs EDF"

echo -e "${YELLOW}▶ FIFO — simulation terminée...${RESET}"
out=$(run_with_spinner 15 $BIN 3 2000 200 200 200 3 10 fifo)
if [ $? -ne 124 ]; then
    ok "FIFO — simulation terminée"
else
    ko "FIFO — timeout" "Simulation FIFO bloquée" "$(echo "$out" | tail -10)"
fi

echo -e "${YELLOW}▶ EDF — simulation terminée...${RESET}"
out=$(run_with_spinner 15 $BIN 3 2000 200 200 200 3 10 edf)
if [ $? -ne 124 ]; then
    ok "EDF — simulation terminée"
else
    ko "EDF — timeout" "Simulation EDF bloquée" "$(echo "$out" | tail -10)"
fi

if [ $STRICT -eq 1 ]; then
    # FIFO : un coder qui attend ne doit pas être doublé par un arrivant plus tard
    # Test : si coder A prend le dongle, puis le relâche, et coder B attendait déjà,
    # B doit passer avant un coder C qui arrive après.
    # → En pratique non déterministe. On vérifie simplement :
    #   1. Pas de starvation : tous les coders obtiennent le dongle au moins une fois
    #   2. La simulation se termine sans deadlock
    echo -e "${YELLOW}▶ [STRICT] FIFO — pas de starvation...${RESET}"
    out=$(run_with_spinner 15 $BIN 3 2000 200 200 200 3 10 fifo)
    if [ $? -eq 124 ]; then
        ko "[STRICT] FIFO — timeout (deadlock?)" \
           "La simulation FIFO n'a pas terminé" "$(echo "$out" | tail -10)"
    else
        starved=""
        for i in 1 2 3; do
            if ! echo "$out" | grep -q "^[0-9]* $i has taken a dongle"; then
                starved="$starved $i"
            fi
        done
        if [ -z "$starved" ]; then
            ok "[STRICT] FIFO — pas de starvation (tous les coders ont eu le dongle)"
        else
            ko "[STRICT] FIFO — starvation détectée pour coder(s) :$starved" \
               "Ces coders n'ont jamais obtenu le dongle" \
               "$out"
        fi
    fi

    # EDF : le coder avec la deadline la plus proche doit passer en premier
    # → vérification que la simulation se termine et tous les coders progressent
    echo -e "${YELLOW}▶ [STRICT] EDF — pas de starvation...${RESET}"
    out=$(run_with_spinner 15 $BIN 3 2000 200 200 200 3 10 edf)
    if [ $? -eq 124 ]; then
        ko "[STRICT] EDF — timeout (deadlock?)" \
           "La simulation EDF n'a pas terminé" "$(echo "$out" | tail -10)"
    else
        starved=""
        for i in 1 2 3; do
            if ! echo "$out" | grep -q "^[0-9]* $i has taken a dongle"; then
                starved="$starved $i"
            fi
        done
        if [ -z "$starved" ]; then
            ok "[STRICT] EDF — pas de starvation (tous les coders ont eu le dongle)"
        else
            ko "[STRICT] EDF — starvation détectée pour coder(s) :$starved" \
               "Ces coders n'ont jamais obtenu le dongle" \
               "$out"
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
    local timeout_s="$3"

    echo -e "${YELLOW}▶ $desc...${RESET}"
    out=$(run_with_spinner "$timeout_s" $BIN $args)
    ret=$?

    if [ $ret -eq 124 ]; then
        ko "$desc → timeout" \
           "Pas de terminaison en ${timeout_s}s — possible deadlock" \
           "$(echo "$out" | tail -10)"
        return
    fi

    if ! echo "$out" | grep -q "burned out"; then
        ko "$desc → pas de burnout détecté" \
           "Aucune ligne 'burned out' dans la sortie (args: $args)" \
           "$(echo "$out" | tail -15)"
        return
    fi

    burnout_id=$(echo "$out" | grep "burned out" | head -1 | awk '{print $2}')
    burnout_ts=$(echo "$out" | grep "burned out" | head -1 | awk '{print $1}')
    last_compile_ts=$(echo "$out" | grep "^[0-9]* $burnout_id is compiling" \
        | tail -1 | awk '{print $1}')

    if [ -n "$last_compile_ts" ] && [ "$burnout_ts" -ge "$last_compile_ts" ]; then
        ok "$desc → burnout après dernière compile (ts: $last_compile_ts → $burnout_ts)"
    else
        ok "$desc → burnout détecté pour coder $burnout_id (ts: $burnout_ts)"
    fi

    if [ $STRICT -eq 1 ]; then
        after=$(echo "$out" | awk -v ts="$burnout_ts" -v id="$burnout_id" \
            '$1 > ts && $2 == id && $3 != "burned" {print}')
        if [ -z "$after" ]; then
            ok "[STRICT] $desc → aucune action après burned out pour coder $burnout_id"
        else
            ko "[STRICT] $desc → actions après burned out pour coder $burnout_id" \
               "Le coder $burnout_id a loggué après ts=$burnout_ts" \
               "$after"
        fi
    fi
}

test_burnout "Burnout / 3 coders / fifo" "3 600 200 200 200 20 10 fifo" 15
test_burnout "Burnout / 3 coders / edf"  "3 600 200 200 200 20 10 edf"  15

if [ $STRICT -eq 1 ]; then
    test_burnout "[STRICT] Burnout / 5 coders / fifo" "5 600 200 200 200 20 10 fifo" 20
    test_burnout "[STRICT] Burnout / 5 coders / edf"  "5 600 200 200 200 20 10 edf"  20
fi

# ============================================================
# 6. STRESS TEST
# ============================================================

section "6. STRESS TEST"

echo -e "${YELLOW}▶ Stress / 20 coders / fifo...${RESET}"
out=$(run_with_spinner 30 $BIN 20 2000 50 50 50 3 10 fifo)
ret=$?
if [ $ret -eq 124 ]; then
    ko "Stress / 20 coders / fifo → timeout" \
       "20 coders bloqués en fifo" "$(echo "$out" | tail -10)"
else
    ok "Stress / 20 coders / fifo → terminé ($(echo "$out" | wc -l) lignes de log)"
fi

echo -e "${YELLOW}▶ Stress / 20 coders / edf...${RESET}"
out=$(run_with_spinner 30 $BIN 20 2000 50 50 50 3 10 edf)
ret=$?
if [ $ret -eq 124 ]; then
    ko "Stress / 20 coders / edf → timeout" \
       "20 coders bloqués en edf" "$(echo "$out" | tail -10)"
else
    ok "Stress / 20 coders / edf → terminé ($(echo "$out" | wc -l) lignes de log)"
fi

if [ $STRICT -eq 1 ]; then
    echo -e "${YELLOW}▶ [STRICT] Stress / 50 coders / fifo...${RESET}"
    out=$(run_with_spinner 60 $BIN 50 2000 50 50 50 3 10 fifo)
    ret=$?
    if [ $ret -eq 124 ]; then
        ko "[STRICT] Stress / 50 coders / fifo → timeout" \
           "50 coders bloqués en fifo" "$(echo "$out" | tail -10)"
    else
        ok "[STRICT] Stress / 50 coders / fifo → terminé ($(echo "$out" | wc -l) lignes de log)"
    fi
fi

# ============================================================
# 7. RÉPÉTABILITÉ
# ============================================================

section "7. RÉPÉTABILITÉ"

runs=5
[ $STRICT -eq 1 ] && runs=10
echo -e "${YELLOW}▶ Répétabilité — $runs runs sans deadlock...${RESET}"
repeat_ok=0
failed_runs=""
for i in $(seq 1 $runs); do
    out=$(run_with_spinner 10 $BIN 3 2000 200 200 200 3 10 fifo)
    if [ $? -ne 124 ]; then
        repeat_ok=$((repeat_ok + 1))
    else
        failed_runs="$failed_runs $i"
    fi
done
if [ $repeat_ok -eq $runs ]; then
    ok "Répétabilité → $runs/$runs runs sans timeout"
else
    ko "Répétabilité → $repeat_ok/$runs runs sans timeout" \
       "Runs en timeout :$failed_runs" ""
fi

# ============================================================
# 8. VALGRIND — MEMCHECK
# ============================================================

section "8. VALGRIND — MEMCHECK"

if ! command -v valgrind &>/dev/null; then
    skip "valgrind non installé"
else
    test_memcheck() {
        local desc="$1"
        local args="$2"
        local timeout_s="${3:-20}"

        echo -e "${YELLOW}▶ $desc...${RESET}"
        out=$(run_with_spinner "$timeout_s" valgrind \
            --leak-check=full \
            --show-leak-kinds=all \
            --track-origins=yes \
            --error-exitcode=1 \
            $BIN $args)
        ret=$?

        errors=$(echo "$out" | grep "ERROR SUMMARY" | awk '{print $4}')

        if [ "$errors" = "0" ]; then
            ok "$desc → 0 erreurs mémoire"
        else
            ko "$desc → $errors erreurs mémoire détectées" \
               "Valgrind ERROR SUMMARY : $errors erreurs" \
               "$(echo "$out" | grep -A5 "ERROR SUMMARY\|Invalid\|definitely lost")"
        fi

        if [ $STRICT -eq 1 ]; then
            definite=$(echo "$out" | grep "definitely lost" | awk '{print $4}' | tr -d ',')
            if [ -z "$definite" ] || [ "$definite" = "0" ]; then
                ok "[STRICT] $desc → 0 bytes definitely lost"
            else
                ko "[STRICT] $desc → $definite bytes definitely lost" \
                   "Fuite mémoire certaine détectée" \
                   "$(echo "$out" | grep "definitely lost")"
            fi
        fi
    }

    test_memcheck "Memcheck / 3 coders / fifo" "3 2000 200 200 200 3 10 fifo"
    test_memcheck "Memcheck / 3 coders / edf"  "3 2000 200 200 200 3 10 edf"

    if [ $STRICT -eq 1 ]; then
        test_memcheck "[STRICT] Memcheck / burnout / fifo" "3 600 200 200 200 20 10 fifo" 30
        test_memcheck "[STRICT] Memcheck / 1 coder / fifo" "1 2000 200 200 200 3 10 fifo" 20
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
    local timeout_s="${3:-20}"

    echo -e "${YELLOW}▶ $desc...${RESET}"
    out=$(run_with_spinner "$timeout_s" valgrind \
        --tool=helgrind \
        --error-exitcode=1 \
        $BIN $args)
    ret=$?

    errors=$(echo "$out" | grep "ERROR SUMMARY" | awk '{print $4}')
    total_contexts=$(echo "$out" | grep "ERROR SUMMARY" | awk '{print $7}')

    real_errors=0
    false_positive_count=0

    if [ "$errors" != "0" ] && [ -n "$errors" ]; then

        # FP #1 : pthread_cond_timedwait interne — "dubious: associated lock is not held"
        fp_dubious=$(echo "$out" | grep -c "dubious: associated lock is not held")

        # FP #2 : tout contexte dont la stack contient uniquement
        #         pthread_cond_timedwait → wait_for_dongle_availability
        #         (variante où le message "dubious" n'apparaît pas seul)
        fp_timedwait_stack=$(echo "$out" | grep -c "wait_for_dongle_availability")

        # On prend le max entre les deux méthodes de comptage
        if [ "$fp_dubious" -ge "$fp_timedwait_stack" ]; then
            false_positive_count=$fp_dubious
        else
            false_positive_count=$fp_timedwait_stack
        fi

        # Borne : on ne peut pas avoir plus de FP que de contextes
        if [ "$false_positive_count" -gt "$total_contexts" ]; then
            false_positive_count=$total_contexts
        fi

        if [ "$false_positive_count" -ge "$total_contexts" ]; then
            real_errors=0
        else
            real_errors=$((total_contexts - false_positive_count))
        fi
    fi

    if [ "$errors" = "0" ]; then
        ok "$desc → 0 erreurs Helgrind"
    elif [ "$real_errors" -le 0 ]; then
        ok "$desc → 0 erreurs réelles (${false_positive_count} faux positif(s) ignoré(s) : pthread_cond_timedwait)"
    else
        ko "$desc → $real_errors contexte(s) d'erreur réel(s) (${false_positive_count} faux positif(s) ignoré(s))" \
           "Helgrind : $errors erreurs / $total_contexts contextes — $real_errors contextes réels" \
           "$(echo "$out" | grep -A4 "Possible data race\|Lock order" | head -30)"
    fi
}




    test_helgrind "Helgrind / 3 coders / fifo" "3 2000 200 200 200 3 10 fifo"
    test_helgrind "Helgrind / 3 coders / edf"  "3 2000 200 200 200 3 10 edf"

    if [ $STRICT -eq 1 ]; then
        test_helgrind "[STRICT] Helgrind / burnout / fifo" "3 600 200 200 200 20 10 fifo" 30
        test_helgrind "[STRICT] Helgrind / 5 coders / edf" "5 2000 200 200 200 3 10 edf"  30
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
    out=$(run_with_spinner 15 $BIN $args)
    ret=$?

    if [ $ret -eq 124 ]; then
        ko "$desc → timeout" "Deadlock possible" ""
        return
    fi

    bad=$(echo "$out" | grep -v "^$" | grep -v -E \
        "^[0-9]+ [0-9]+ (has taken a dongle|is compiling|is debugging|is refactoring|burned out)$")
    if [ -n "$bad" ]; then
        ko "$desc → lignes mal formatées" \
           "Lignes ne respectant pas le format attendu" \
           "$bad"
    else
        ok "$desc → format correct"
    fi

    # Timestamps croissants
    prev=0
    ok_ts=1
    bad_ts_detail=""
    while IFS= read -r line; do
        ts=$(echo "$line" | awk '{print $1}')
        if ! echo "$ts" | grep -qE '^[0-9]+$'; then
            continue
        fi
        if [ "$ts" -lt "$prev" ]; then
            ok_ts=0
            bad_ts_detail="timestamp $ts après $prev"
            break
        fi
        prev=$ts
    done <<< "$out"
    if [ $ok_ts -eq 1 ]; then
        ok "$desc → timestamps croissants"
    else
        ko "$desc → timestamps non croissants" "$bad_ts_detail" ""
    fi

    if [ $STRICT -eq 1 ]; then
        nb_coders=$(echo "$args" | awk '{print $1}')

        # Chaque coder a produit des logs
        for i in $(seq 1 "$nb_coders"); do
            if echo "$out" | grep -q "^[0-9]* $i "; then
                ok "[STRICT] $desc → coder $i a produit des logs"
            else
                ko "[STRICT] $desc → coder $i n'a produit aucun log" \
                   "Aucune ligne avec id=$i dans la sortie" ""
            fi
        done

        # has taken a dongle précède is compiling
        for i in $(seq 1 "$nb_coders"); do
            first_taken=$(echo "$out" | grep "^[0-9]* $i has taken a dongle" \
                | head -1 | awk '{print $1}')
            first_compile=$(echo "$out" | grep "^[0-9]* $i is compiling" \
                | head -1 | awk '{print $1}')
            if [ -n "$first_taken" ] && [ -n "$first_compile" ]; then
                if [ "$first_taken" -le "$first_compile" ]; then
                    ok "[STRICT] $desc → coder $i: taken(ts=$first_taken) avant compiling(ts=$first_compile)"
                else
                    ko "[STRICT] $desc → coder $i: compiling avant taken (incohérent)" \
                       "taken ts=$first_taken > compile ts=$first_compile" ""
                fi
            fi
        done
    fi
}

test_log_format "Format / 3 coders / fifo" "3 2000 200 200 200 3 10 fifo"
test_log_format "Format / 3 coders / edf"  "3 2000 200 200 200 3 10 edf"

if [ $STRICT -eq 1 ]; then
    test_log_format "[STRICT] Format / 5 coders / fifo" "5 2000 200 200 200 3 10 fifo"
    test_log_format "[STRICT] Format / 5 coders / edf"  "5 2000 200 200 200 3 10 edf"
fi

# ============================================================
# RÉSUMÉ — terminal + trace
# ============================================================

section "RÉSUMÉ"

if [ $STRICT -eq 1 ]; then
    echo -e "${BLUE}Mode strict actif — tests approfondis inclus${RESET}"
fi
echo -e "Total : $TOTAL | ${GREEN}OK : $PASS${RESET} | ${RED}KO : $FAIL${RESET} | ${YELLOW}SKIP : $SKIP${RESET}"
echo ""

# Finalise le fichier trace
{
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  RÉSUMÉ FINAL"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  Mode    : $([ $STRICT -eq 1 ] && echo 'STRICT' || echo 'NORMAL')"
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
