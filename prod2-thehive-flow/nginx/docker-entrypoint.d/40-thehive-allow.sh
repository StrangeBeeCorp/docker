#!/usr/bin/env bash

thehive_addresses_entries() {
    local line entry
    local -a entries
    while IFS= read -r line || [[ -n "${line}" ]]; do
        IFS=',' read -r -a entries <<<"${line}"
        for entry in "${entries[@]}"; do
            if [[ -n "${entry}" ]]; then
                printf '%s\n' "${entry}"
            fi
        done
    done <<<"$1"
}

thehive_address_valid() {
    local octet
    if [[ "$1" == */* ]]; then
        [[ "${1#*/}" =~ ^(3[0-2]|[12]?[0-9])$ ]] || return 1
    fi
    [[ "${1%/*}" =~ ^([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})$ ]] || return 1
    for octet in "${BASH_REMATCH[@]:1}"; do
        ((10#${octet} <= 255)) || return 1
    done
}

thehive_address_int() {
    local -a octets
    IFS=. read -r -a octets <<<"$1"
    printf '%d\n' $(( (10#${octets[0]} << 24) | (10#${octets[1]} << 16) | (10#${octets[2]} << 8) | 10#${octets[3]} ))
}

thehive_address_covers() {
    local prefix=32 mask network address
    if [[ "$1" == */* ]]; then
        prefix="${1#*/}"
    fi
    mask=$(( 10#${prefix} == 0 ? 0 : (0xFFFFFFFF << (32 - 10#${prefix})) & 0xFFFFFFFF ))
    network="$(thehive_address_int "${1%/*}")"
    address="$(thehive_address_int "$2")"
    (( (network & mask) == (address & mask) ))
}

thehive_addresses_covering() {
    local entry gateway="$2"
    while IFS= read -r entry; do
        if thehive_address_valid "${entry}" && thehive_address_covers "${entry}" "${gateway}"; then
            printf '%s\n' "${entry}"
        fi
    done < <(thehive_addresses_entries "$1")
}

thehive_gateway() {
    local destination gateway
    while read -r _ destination gateway _; do
        if [[ "${destination}" == 00000000 && "${gateway}" =~ ^[0-9A-Fa-f]{8}$ && "${gateway}" != 00000000 ]]; then
            printf '%d.%d.%d.%d\n' "0x${gateway:6:2}" "0x${gateway:4:2}" "0x${gateway:2:2}" "0x${gateway:0:2}"
            return 0
        fi
    done </proc/net/route
    return 1
}

thehive_check_include() {
    local dir="$1" me="${0##*/}"
    if ! grep -rlE --include='*.conf' -- '^[[:space:]]*include[[:space:]]+[^;]*thehive-allow' "${dir}" >/dev/null 2>&1; then
        echo "${me}: warn: no nginx configuration includes /etc/nginx/thehive-allow*.conf, so this list does not filter /api/"
    fi
}

thehive_make_executable() {
    local path="$1"
    if [[ ! -x "${path}" ]]; then
        chmod 755 "${path}"
        echo "restored the executable bit on ${path}"
    fi
    return 0
}

thehive_allow_main() {
    set -euo pipefail
    local me="${0##*/}" conf=/etc/nginx/thehive-allow.conf gateway="" entry allowed=0
    if ! gateway="$(thehive_gateway)"; then
        echo "${me}: warn: no default route in /proc/net/route, entries are not checked against the Docker gateway"
        gateway=""
    fi
    : >"${conf}"
    while IFS= read -r entry; do
        if ! thehive_address_valid "${entry}"; then
            echo "${me}: warn: skipping '${entry}': not an IPv4 address or IPv4 CIDR range"
        elif [[ -n "${gateway}" ]] && thehive_address_covers "${entry}" "${gateway}"; then
            echo "${me}: warn: skipping '${entry}': it covers the Docker gateway ${gateway}, the address of every caller whose source Docker masks"
        else
            printf 'allow %s;\n' "${entry}" >>"${conf}"
            echo "${me}: info: allowing /api/ from ${entry}"
            allowed=$((allowed + 1))
        fi
    done < <(thehive_addresses_entries "${NGINX_THEHIVE_ADDRESSES:-}")
    thehive_check_include /etc/nginx/conf.d
    if ((allowed == 0)); then
        echo "${me}: warn: no TheHive address allowed, nginx refuses /api/ to every caller"
    fi
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    thehive_allow_main
fi
