#!/usr/bin/env bash
# Runs one reconnect test case repeatedly, each run in its own network namespace so that parallel runs
# do not share fixture addresses, and reports how many runs ended with exit status zero.
#
# Usage: exit_loop.bash CASE COUNT JOBS IOC DBD TEMPLATE OUTDIR
# Exit status: 0 when every run passed, 1 when any run failed, 2 on a usage error.

set -u

RUNNER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUN_TIMEOUT=120s

usage() {
    printf 'Usage: %s CASE COUNT JOBS IOC DBD TEMPLATE OUTDIR\n' "${0##*/}" >&2
    exit 2
}

run_one() {
    local index="$1" case_name="$2" ioc="$3" dbd="$4" template="$5" outdir="$6"
    local prefix="${outdir}/run-${index}"
    # The single-quoted script is expanded by the inner shell, which receives its arguments positionally.
    # shellcheck disable=SC2016
    unshare -Urn bash -c '
        ip link set lo up &&
        ip link add sim0 type dummy &&
        ip addr add 192.0.2.1/24 dev sim0 &&
        ip link set sim0 up &&
        ip addr add 192.0.2.2/32 dev lo &&
        ip addr add 192.0.2.3/32 dev lo &&
        exec timeout "$1" perl "$2" --case "$3" "$4" "$5" "$6" "$7"
    ' bash "${RUN_TIMEOUT}" "${RUNNER_DIR}/test_reconnect.pl" "${case_name}" "${ioc}" "${dbd}" "${template}" \
        "${prefix}.log" > "${prefix}.out" 2> "${prefix}.err"
    printf '%s\n' "$?" > "${prefix}.status"
}

main() {
    [[ $# -eq 7 ]] || usage
    local case_name="$1" count="$2" jobs="$3" ioc="$4" dbd="$5" template="$6" outdir="$7"
    [[ "${count}" =~ ^[1-9][0-9]*$ && "${jobs}" =~ ^[1-9][0-9]*$ ]] || usage
    mkdir -p "${outdir}" || exit 2

    export -f run_one
    export RUN_TIMEOUT RUNNER_DIR
    seq 1 "${count}" | xargs -P "${jobs}" -I '{}' bash -c 'run_one "$@"' bash '{}' \
        "${case_name}" "${ioc}" "${dbd}" "${template}" "${outdir}"

    local passed=0 failed=0 status
    for ((i = 1; i <= count; i++)); do
        status="$(cat "${outdir}/run-${i}.status" 2> /dev/null || printf 'missing')"
        if [[ "${status}" == 0 ]]; then
            passed=$((passed + 1))
        else
            failed=$((failed + 1))
            printf 'run %d: runner status %s\n' "${i}" "${status}" >&2
        fi
    done
    printf 'case %s: %d runs, %d passed, %d failed\n' "${case_name}" "${count}" "${passed}" "${failed}"
    [[ "${failed}" -eq 0 ]]
}

main "$@"
