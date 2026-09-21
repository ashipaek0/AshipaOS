#!/usr/bin/env bash
# Layer 4: Apply the distro-provided systemd service policy to an x86_64 rootfs.
# Verification Class: BUILD, VM
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LAYER_DIR="$(dirname "$SCRIPT_DIR")"
CONFIG_FILE="$LAYER_DIR/config/services-config.yaml"
EVIDENCE_DIR="$LAYER_DIR/evidence"
REPO_ROOT="$(cd "$LAYER_DIR/../.." && pwd)"
TARGET=""
ROOTFS_TARBALL=""
TEMP_DIR=""
ROOTFS=""

usage() {
    cat <<EOF
Usage: $(basename "$0") <rootfs-tar.gz> [target]

Apply the Layer 4 systemd policy to an x86_64 rootfs tarball in place.
The target must be x86_64; no packages or service units are created.

Options:
    -h, --help      Show this help message
    --validate      Validate Layer 4 configuration only
    --list          List configured enabled and disabled units
EOF
}

log() { printf '[L4-SERVICES] %s\n' "$*"; }
error() { printf '[L4-SERVICES ERROR] %s\n' "$*" >&2; exit 1; }

config_list() {
    local section="$1"
    awk -v section="$section" '
        $0 == "  " section ":" { in_section=1; next }
        in_section && $0 ~ /^  [[:alnum:]_-]+:/ { exit }
        in_section && $1 == "-" { print $2 }
    ' "$CONFIG_FILE"
}

is_safe_unit_identifier() {
    local unit="$1"
    # Unit names are data, not paths. Keep the accepted grammar deliberately
    # narrow so configured values cannot introduce paths or dot-dot traversal.
    [[ "$unit" =~ ^[A-Za-z0-9_@%:+.-]+\.service$ ]] || return 1
    [[ "$unit" != /* && "$unit" != */* && "$unit" != *..* ]]
}

validate_unit_identifier() {
    local unit="$1" provenance="$2"
    is_safe_unit_identifier "$unit" \
        || error "unsafe $provenance service unit identifier: $unit"
}

config_scalar() {
    local key="$1"
    awk -v key="$key" '$1 == key ":" { print $2; exit }' "$CONFIG_FILE"
}

config_section_scalar() {
    local section="$1" key="$2"
    awk -v section="$section" -v key="$key" '
        $0 == section ":" { in_section=1; next }
        in_section && $0 ~ /^[[:alnum:]_-]+:/ { exit }
        in_section && $1 == key ":" { print $2; exit }
    ' "$CONFIG_FILE"
}

validate_config() {
    [[ -f "$CONFIG_FILE" ]] || error "Configuration file not found: $CONFIG_FILE"
    grep -q '^target: x86_64$' "$CONFIG_FILE" || error "configuration target must be x86_64"
    grep -q '^services:$' "$CONFIG_FILE" || error "missing services section"
    grep -q '^  enabled:$' "$CONFIG_FILE" || error "missing enabled list"
    grep -q '^  disabled:$' "$CONFIG_FILE" || error "missing disabled list"
    local enabled disabled unit
    mapfile -t enabled < <(config_list enabled)
    mapfile -t disabled < <(config_list disabled)
    ((${#enabled[@]} > 0)) || error "enabled list is empty"
    ((${#disabled[@]} > 0)) || error "disabled list is empty"
    local required
    mapfile -t required < <(config_list required_services)
    ((${#required[@]} > 0)) || error "required services list is empty"
    for unit in "${enabled[@]}" "${disabled[@]}" "${required[@]}"; do
        validate_unit_identifier "$unit" "configured"
        [[ "$unit" == *.service ]] || error "service policy must use explicit .service units: $unit"
    done
    for unit in "${enabled[@]}"; do
        for disabled_unit in "${disabled[@]}"; do
            [[ "$unit" != "$disabled_unit" ]] || error "unit appears in both policy lists: $unit"
        done
    done
    [[ "$(config_scalar default_target)" == graphical.target ]] || error "default target must be graphical.target"
    [[ "$(config_section_scalar policy disable_unlisted)" == true ]] \
        || error "policy.disable_unlisted must be true"
    [[ -n "$(config_section_scalar policy preset_file)" ]] \
        || error "policy.preset_file is required"
    log "Configuration validation passed"
}

list_services() {
    validate_config >/dev/null
    printf 'Enabled services:\n'
    config_list enabled | sed 's/^/  /'
    printf 'Disabled services:\n'
    config_list disabled | sed 's/^/  /'
}

cleanup() {
    if [[ -n "${TEMP_DIR:-}" && -d "$TEMP_DIR" ]]; then
        rm -rf -- "$TEMP_DIR"
    fi
    return 0
}
trap cleanup EXIT

extract_rootfs() {
    [[ -s "$ROOTFS_TARBALL" ]] || error "rootfs tarball not found or empty: $ROOTFS_TARBALL"
    tar -tzf "$ROOTFS_TARBALL" >/dev/null || error "rootfs is not a readable gzip tar archive: $ROOTFS_TARBALL"
    while IFS= read -r member; do
        case "$member" in
            /*|..|../*|*/../*|*/..)
                error "unsafe rootfs tar member: $member"
                ;;
        esac
    done < <(tar -tzf "$ROOTFS_TARBALL")
    TEMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/ashipaos-layer4.XXXXXX")
    ROOTFS="$TEMP_DIR/rootfs"
    mkdir -p "$ROOTFS"
    tar --extract --gzip --file "$ROOTFS_TARBALL" --directory "$ROOTFS" \
        --exclude='./dev/*' --exclude='dev/*' --exclude='./proc/*' --exclude='proc/*' --exclude='./sys/*' --exclude='sys/*' --exclude='./run/*' --exclude='run/*'
    [[ -d "$ROOTFS/etc/systemd" ]] || error "rootfs has no systemd configuration directory"
}

unit_path() {
    local unit="$1" candidate base
    for candidate in "$unit" "${unit%%@*}@.service"; do
        [[ "$candidate" == "$unit" || "$unit" == *@*.service ]] || continue
        for base in "$ROOTFS/usr/lib/systemd/system" "$ROOTFS/lib/systemd/system"; do
            [[ -e "$base/$candidate" || -L "$base/$candidate" ]] && {
                printf '%s\n' "$base/$candidate"
                return 0
            }
        done
    done
    return 1
}

dependency_path() {
    local unit="$1" base
    for base in "$ROOTFS/etc/systemd/system" "$ROOTFS/usr/lib/systemd/system" "$ROOTFS/lib/systemd/system"; do
        [[ -e "$base/$unit" ]] && {
            printf '%s\n' "$base/$unit"
            return 0
        }
    done
    return 1
}

optional_missing_dependency() {
    local source="$1" dependency="$2" directive value token optional=0 required=0
    while IFS= read -r line; do
        [[ "$line" == *=* ]] || continue
        directive="${line%%=*}"
        value="${line#*=}"
        case "$directive" in
            Wants|After)
                for token in $value; do
                    [[ "$token" == "$dependency" ]] && optional=1
                done
                ;;
            Requires|Requisite|BindsTo|Upholds|RequiresMountsFor|WantsMountsFor)
                for token in $value; do
                    [[ "$token" == "$dependency" ]] && required=1
                done
                ;;
        esac
    done < "$source"
    ((optional == 1 && required == 0))
}

optional_missing_dependencies() {
    local unit source line directive value dependency
    local -a units=("${required[@]}")
    for unit in "${units[@]}"; do
        source=$(unit_path "$unit") || continue
        while IFS= read -r line; do
            [[ "$line" == Wants=* || "$line" == After=* ]] || continue
            directive="${line%%=*}"
            value="${line#*=}"
            for dependency in $value; do
                dependency_path "$dependency" >/dev/null 2>&1 && continue
                optional_missing_dependency "$source" "$dependency" \
                    && printf '%s\n' "$dependency"
            done
        done < "$source"
    done | sort -u
}

verify_units() {
    local verify_output="$TEMP_DIR/systemd-analyze-verify.out" line dependency allowed saw_diagnostic=0
    local -a optional_missing=()
    mapfile -t optional_missing < <(optional_missing_dependencies)
    # Layer 1 intentionally omits /usr/share/man; suppress only systemd-analyze's
    # optional man-page lookup while retaining all unit/dependency diagnostics.
    if systemd-analyze --man=no verify --root="$ROOTFS" "${required[@]}" >"$verify_output" 2>&1; then
        return 0
    fi
    while IFS= read -r line; do
        [[ -n "$line" ]] || continue
        saw_diagnostic=1
        allowed=0
        for dependency in "${optional_missing[@]}"; do
            if [[ "$line" == *"Unit $dependency not found."* ]]; then
                allowed=1
                break
            fi
        done
        if [[ "$allowed" -eq 0 ]]; then
            cat "$verify_output" >&2
            return 1
        fi
    done < "$verify_output"
    ((saw_diagnostic == 1 && ${#optional_missing[@]} > 0)) || return 1
    log "systemd-analyze accepted configured units with optional missing dependencies: ${optional_missing[*]}"
}

validate_units() {
    local unit path
    mapfile -t required < <(config_list enabled)
    for unit in "${required[@]}"; do
        validate_unit_identifier "$unit" "enabled"
        path=$(unit_path "$unit") || error "required distro unit missing from rootfs: $unit"
        [[ -f "$path" && ! -L "$path" ]] || error "required unit is not a real unit file: $unit"
        grep -q '^\[Unit\]$' "$path" || error "required unit is missing [Unit]: $unit"
    done
    mapfile -t disabled < <(config_list disabled)
    for unit in "${disabled[@]}"; do
        validate_unit_identifier "$unit" "disabled"
        if path=$(unit_path "$unit"); then
            [[ -f "$path" && ! -L "$path" ]] || error "disabled unit is not a real unit file: $unit"
            grep -q '^\[Unit\]$' "$path" || error "disabled unit is missing [Unit]: $unit"
        fi
    done
    command -v systemd-analyze >/dev/null 2>&1 || error "systemd-analyze is required for unit validation"
    mapfile -t required < <(config_list required_services)
    for unit in "${required[@]}"; do
        validate_unit_identifier "$unit" "required"
    done
    verify_units || error "systemd-analyze rejected the configured units"
}

enable_unit() {
    local unit="$1" path
    path=$(unit_path "$unit")
    if grep -q '^\[Install\]' "$path"; then
        systemctl --root="$ROOTFS" --no-reload enable "$unit"
    else
        log "Validated static distro unit: $unit"
    fi
}

apply_policy() {
    local preset="$ROOTFS$(config_section_scalar policy preset_file)"
    local unit
    mkdir -p "$(dirname "$preset")"
    {
        printf '# Generated by Layer 4; all entries are distro-provided units.\n'
        printf 'disable *\n'
        while IFS= read -r unit; do printf 'enable %s\n' "$unit"; done < <(config_list enabled)
        while IFS= read -r unit; do printf 'disable %s\n' "$unit"; done < <(config_list disabled)
    } > "$preset"
    command -v systemctl >/dev/null 2>&1 || error "systemctl is required for policy application"
    while IFS= read -r unit; do enable_unit "$unit"; done < <(config_list enabled)
    while IFS= read -r unit; do
        if path=$(unit_path "$unit"); then
            systemctl --root="$ROOTFS" --no-reload disable "$unit" >/dev/null 2>&1 \
                || error "failed to disable present distro unit: $unit"
        else
            log "Disabled unit absent from rootfs: $unit"
        fi
    done < <(config_list disabled)
    systemctl --root="$ROOTFS" --no-reload set-default "$(config_scalar default_target)"
}

generate_evidence() {
    mkdir -p "$EVIDENCE_DIR"
    local enabled_count
    enabled_count=$(config_list enabled | wc -l)
    cat > "$EVIDENCE_DIR/build-evidence.json" <<EOF
{
  "layer": 4,
  "task": "x86_64-systemd-service-policy",
  "verification_class": ["BUILD", "VM"],
  "target": "$TARGET",
  "rootfs_tarball": "$ROOTFS_TARBALL",
  "enabled_services_count": $enabled_count,
  "policy_applied": true,
  "real_units_validated": true,
  "packages_changed": false
}
EOF
}

main() {
    case "${1:-}" in
        -h|--help) usage; return 0 ;;
        --validate) validate_config; return 0 ;;
        --list) list_services; return 0 ;;
    esac
    [[ $# -ge 1 && $# -le 2 ]] || { usage >&2; return 2; }
    ROOTFS_TARBALL="$1"
    TARGET="${2:-x86_64}"
    [[ "$TARGET" == x86_64 ]] || error "Layer 4 is x86_64-only; refusing target '$TARGET'"
    validate_config
    extract_rootfs
    validate_units
    apply_policy
    local output="${ROOTFS_TARBALL}.layer4.tmp"
    tar --create --gzip --file "$output" --directory "$ROOTFS" \
        --exclude='./dev/*' --exclude='dev/*' --exclude='./proc/*' --exclude='proc/*' --exclude='./sys/*' --exclude='sys/*' --exclude='./run/*' --exclude='run/*' .
    [[ -s "$output" ]] || error "Layer 4 output tarball is empty"
    mv -f -- "$output" "$ROOTFS_TARBALL"
    generate_evidence
    log "Applied systemd policy to $ROOTFS_TARBALL"
}

main "$@"
