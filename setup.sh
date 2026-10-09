#!/usr/bin/env bash
# setup.sh - Apply the Acer Nitro 5 (AN515-58) tweaks on top of lyne-dots
#
# Asks which parts to set up (cpu, fans, mouse, mangohud), then applies them.
# Safe to run again: every step checks what is already in place and only
# changes what differs.
#
#   ./setup.sh [--only=cpu,fans,...] [--dry-run] [--skip-packages] [--skip-state]
#
# Env: LYNE_DIR (default ~/.lyne-dots) and LYNE_STATE_FILE (default
# ~/.config/quickshell/state.json), mostly for testing against copies

set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN_DIR="$HOME/.local/bin"
LYNE_DIR="${LYNE_DIR:-$HOME/.lyne-dots}"
STATE_FILE="${LYNE_STATE_FILE:-$HOME/.config/quickshell/state.json}"

NBFC_CONFIG="nitro-fan-curve"
NBFC_DIR="/usr/share/nbfc/configs"
NBFC_OLD_CONFIG="Acer Nitro AN515-58-custom"
# No dot in the name: sudo skips files in sudoers.d that have one
SUDOERS_FILE="/etc/sudoers.d/nitro-cpupower"
QUIRKS_FILE="/etc/libinput/local-overrides.quirks"
MANGOHUD_FILE="$HOME/.config/MangoHud/MangoHud.conf"

COMPONENTS=(cpu fans mouse mangohud)
declare -A DESCRIPTION=(
    [cpu]="CPU frequency profiles: nitro-cpu, cpupower without password, keybinds"
    [fans]="Fan control: NBFC fan curve, nitro-fans, keybinds"
    [mouse]="Mouse drag click: libinput quirks (no debounce)"
    [mangohud]="MangoHud overlay config"
)
# Packages per component; jq is always needed
declare -A REPO_PKGS=([cpu]="cpupower libnotify" [fans]="libnotify" [mouse]="" [mangohud]="mangohud")
declare -A AUR_PKGS=([cpu]="" [fans]="nbfc-linux" [mouse]="" [mangohud]="")
declare -A SELECTED=()

DRY_RUN=false
DO_PACKAGES=true
DO_STATE=true
ONLY=""
NOTES=()

usage() {
    echo "Usage: ./setup.sh [options]"
    echo
    echo "Without --only, shows a menu to pick the parts (all of them when"
    echo "not run from a terminal)."
    echo
    echo "Parts:"
    for c in "${COMPONENTS[@]}"; do
        printf '  %-10s %s\n' "$c" "${DESCRIPTION[$c]}"
    done
    echo
    echo "Options:"
    echo "  --only=LIST       Comma separated parts to set up, no menu"
    echo "  --dry-run         Show what would change, change nothing"
    echo "  --skip-packages   Don't install packages"
    echo "  --skip-state      Don't touch the lyne-dots state.json"
    echo "  -h, --help        Show this help"
}

for arg in "$@"; do
    case "$arg" in
    --only=*) ONLY="${arg#--only=}" ;;
    --dry-run) DRY_RUN=true ;;
    --skip-packages) DO_PACKAGES=false ;;
    --skip-state) DO_STATE=false ;;
    -h | --help)
        usage
        exit 0
        ;;
    *)
        usage >&2
        exit 1
        ;;
    esac
done

step() { printf '\n==> %s\n' "$*"; }
info() { printf '    %s\n' "$*"; }
warn() { printf '    ! %s\n' "$*" >&2; }
note() { NOTES+=("$*"); }
selected() { [[ "${SELECTED[$1]}" == 1 ]]; }

# Runs a command, or only prints it with --dry-run
run() {
    if $DRY_RUN; then
        printf '    [dry-run]'
        printf ' %q' "$@"
        printf '\n'
    else
        "$@"
    fi
}

# True when $2 exists with the same content as $1. Uses sudo for files the
# user can't read (sudoers.d); without cached sudo, a dry run assumes it differs
same_file() {
    local src="$1" dest="$2"
    if [[ -r "$dest" ]]; then
        cmp -s "$src" "$dest"
    elif [[ -x "$(dirname "$dest")" && ! -e "$dest" ]]; then
        return 1
    elif $DRY_RUN && ! sudo -n true 2>/dev/null; then
        info "can't read $dest without sudo, assuming it differs"
        return 1
    else
        sudo cmp -s "$src" "$dest"
    fi
}

# Installs $1 as $2 with mode $3 when it differs, and sets CHANGED. With
# --root it is owned by root (through sudo); with --backup a different file
# already there is kept as $2.bak
install_file() {
    local sudo=() backup=false
    while [[ "$1" == --* ]]; do
        case "$1" in
        --root) sudo=(sudo) ;;
        --backup) backup=true ;;
        esac
        shift
    done
    local src="$1" dest="$2" mode="$3"
    CHANGED=false
    if same_file "$src" "$dest"; then
        info "unchanged: $dest"
        return 0
    fi
    CHANGED=true
    if $backup && [[ -e "$dest" ]]; then
        run "${sudo[@]}" cp "$dest" "$dest.bak"
        info "backup of the current file: $dest.bak"
    fi
    if ((${#sudo[@]})); then
        run sudo install -D -m "$mode" -o root -g root "$src" "$dest"
    else
        run install -D -m "$mode" "$src" "$dest"
    fi
    info "installed: $dest"
}

# ------------------------------------------------------------------- menu

choose_components() {
    local input n c mark
    while true; do
        echo
        echo "Select what to set up (numbers toggle, Enter runs, q quits):"
        for n in "${!COMPONENTS[@]}"; do
            c="${COMPONENTS[n]}"
            mark=" "
            selected "$c" && mark="x"
            printf '  %d) [%s] %-9s %s\n' $((n + 1)) "$mark" "$c" "${DESCRIPTION[$c]}"
        done
        read -rp "> " input || exit 1
        case "$input" in
        "") return 0 ;;
        q | Q) exit 0 ;;
        esac
        for n in ${input//,/ }; do
            if [[ "$n" =~ ^[0-9]+$ ]] && ((n >= 1 && n <= ${#COMPONENTS[@]})); then
                c="${COMPONENTS[n - 1]}"
                if selected "$c"; then SELECTED[$c]=0; else SELECTED[$c]=1; fi
            else
                warn "no option '$n'"
            fi
        done
    done
}

for c in "${COMPONENTS[@]}"; do SELECTED[$c]=1; done
if [[ -n "$ONLY" ]]; then
    for c in "${COMPONENTS[@]}"; do SELECTED[$c]=0; done
    for c in ${ONLY//,/ }; do
        if [[ -z "${DESCRIPTION[$c]+set}" ]]; then
            echo "Unknown part '$c' (parts: ${COMPONENTS[*]})" >&2
            exit 1
        fi
        SELECTED[$c]=1
    done
elif [[ -t 0 ]]; then
    choose_components
fi

chosen=()
for c in "${COMPONENTS[@]}"; do selected "$c" && chosen+=("$c"); done
if ((${#chosen[@]} == 0)); then
    echo "Nothing selected."
    exit 0
fi

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

echo
$DRY_RUN && echo "Dry run: nothing will be changed"
echo "Setting up: ${chosen[*]}"

# ---------------------------------------------------------------- packages

# Installs the packages in $2.. that are missing, with $1 (pacman or AUR)
install_missing() {
    local source="$1" pkg missing=()
    shift
    for pkg in "$@"; do
        pacman -Qq "$pkg" &>/dev/null || missing+=("$pkg")
    done
    if ((${#missing[@]} == 0)); then
        (($#)) && info "installed: $*"
        return 0
    fi
    if [[ "$source" == pacman ]]; then
        run sudo pacman -S --needed "${missing[@]}"
    else
        local aur_helper
        aur_helper="$(command -v yay || command -v paru || true)"
        if [[ -z "$aur_helper" ]]; then
            warn "no AUR helper (yay or paru) to install: ${missing[*]}"
            exit 1
        fi
        run "$aur_helper" -S --needed "${missing[@]}"
    fi
}

if $DO_PACKAGES; then
    step "Packages"
    declare -A repo_pkgs=([jq]=1) aur_pkgs=()
    for c in "${chosen[@]}"; do
        for p in ${REPO_PKGS[$c]}; do repo_pkgs[$p]=1; done
        for p in ${AUR_PKGS[$c]}; do aur_pkgs[$p]=1; done
    done
    install_missing pacman "${!repo_pkgs[@]}"
    install_missing aur "${!aur_pkgs[@]}"
fi

# --------------------------------------------------------------------- cpu

if selected cpu; then
    step "cpu: nitro-cpu and sudoers rule for cpupower"
    install_file "$REPO/cpu/nitro-cpu" "$BIN_DIR/nitro-cpu" 755

    sudoers_tmp="$TMP_DIR/nitro-cpupower"
    printf '# nitro-cpu caps the CPU frequency without a password\n%s ALL=(root) NOPASSWD: /usr/bin/cpupower\n' \
        "$USER" >"$sudoers_tmp"
    if ! visudo -cqf "$sudoers_tmp"; then
        warn "the generated sudoers rule doesn't validate, skipping it"
    else
        install_file --root "$sudoers_tmp" "$SUDOERS_FILE" 440
    fi
fi

# -------------------------------------------------------------------- fans

if selected fans; then
    step "fans: nitro-fans and NBFC fan curve"
    install_file "$REPO/fans/nitro-fans" "$BIN_DIR/nitro-fans" 755

    install_file --root "$REPO/fans/$NBFC_CONFIG.json" "$NBFC_DIR/$NBFC_CONFIG.json" 644
    restart_nbfc=$CHANGED

    selected_config="$(jq -r '.SelectedConfigId // empty' /etc/nbfc/nbfc.json 2>/dev/null || true)"
    if [[ "$selected_config" == "$NBFC_CONFIG" ]]; then
        info "selected: $NBFC_CONFIG"
    else
        run sudo nbfc config -s "$NBFC_CONFIG"
        info "selected: $NBFC_CONFIG (was: ${selected_config:-none})"
        restart_nbfc=true
    fi

    if systemctl is-enabled --quiet nbfc_service 2>/dev/null; then
        info "nbfc_service enabled"
    else
        run sudo systemctl enable nbfc_service
    fi
    if $restart_nbfc || ! systemctl is-active --quiet nbfc_service; then
        run sudo systemctl restart nbfc_service
        info "nbfc_service restarted"
    else
        info "nbfc_service running"
    fi

    if [[ -e "$NBFC_DIR/$NBFC_OLD_CONFIG.json" ]]; then
        note "The old NBFC config is no longer used, remove it with:" \
            "sudo rm '$NBFC_DIR/$NBFC_OLD_CONFIG.json'"
    fi
fi

# ------------------------------------------------------------------- mouse

if selected mouse; then
    step "mouse: libinput quirks (drag click)"
    install_file --root --backup "$REPO/mouse/local-overrides.quirks" "$QUIRKS_FILE" 644
    $CHANGED && note "Log out and back in for the libinput quirks to apply."
fi

# ---------------------------------------------------------------- mangohud

if selected mangohud; then
    step "mangohud: overlay config"
    install_file --backup "$REPO/mangohud/MangoHud.conf" "$MANGOHUD_FILE" 644
    $CHANGED && note "The MangoHud config applies to games started from now on."
fi

# ------------------------------------------------------- lyne-dots state

# Keybinds and autostart of the chosen parts that have them
lyne_files=()
for c in "${chosen[@]}"; do
    [[ -f "$REPO/$c/lyne.json" ]] && lyne_files+=("$REPO/$c/lyne.json")
done

if $DO_STATE && ((${#lyne_files[@]})); then
    step "lyne-dots keybinds and autostart ($STATE_FILE)"
    state_lib="$LYNE_DIR/.data/lyne-cli/lib/state.sh"
    if [[ ! -f "$state_lib" ]]; then
        warn "lyne-dots not found ($state_lib), skipping"
    elif [[ ! -f "$STATE_FILE" ]]; then
        warn "no state.json yet (log in to lyne-dots once), skipping"
    elif ! command -v jq &>/dev/null; then
        warn "jq is missing, skipping"
    else
        filter="$(<"$REPO/lyne/state.jq")"
        entries="$(jq -s '{keybinds: map(.keybinds[]), autostart: map(.autostart[])}' "${lyne_files[@]}")"

        # Our keys taken by something else
        jq -r --argjson e "$entries" '
            def combo: ascii_upcase | gsub("\\s"; "");
            ($e.keybinds | map(.description)) as $ours
            | [(.keybinds.custom // [])[] | select(.description as $d | $ours | index($d) | not)
                  | {who: (.description // .command), keys}]
              + [(.keybinds.overrides // [])[] | {who: .id, keys}]
            | .[] as $other
            | $e.keybinds[]
            | select(($other.keys // "") != "" and (.keys | combo) == ($other.keys | combo))
            | "\(.keys) (\(.description)) is also used by \"\($other.who)\""
        ' "$STATE_FILE" | while read -r line; do warn "$line"; done

        if [[ "$(jq -c . "$STATE_FILE")" == "$(jq -c --argjson e "$entries" "$filter" "$STATE_FILE")" ]]; then
            info "unchanged"
        elif $DRY_RUN; then
            diff -u --label "$STATE_FILE" --label "after setup" \
                <(jq . "$STATE_FILE") <(jq --argjson e "$entries" "$filter" "$STATE_FILE") |
                sed 's/^/    /' || true
        else
            # shellcheck source=/dev/null
            source "$state_lib"
            LYNE_STATE_FILE="$STATE_FILE" lyne_state_set "$filter" --argjson e "$entries"
            info "updated (the shell applies the keybinds right away)"
            note "The autostart entries run from the next login on."
        fi
    fi
fi

# ------------------------------------------------------------------- done

step "Done"
if ((${#NOTES[@]})); then
    for n in "${NOTES[@]}"; do info "- $n"; done
else
    info "Nothing else to do."
fi
