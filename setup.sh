#!/usr/bin/env bash
# setup.sh - Apply the Acer Nitro 5 (AN515-58) tweaks on top of lyne-dots
#
# Safe to run again: every step checks what is already in place and only
# changes what differs.
#
#   ./setup.sh [--dry-run] [--skip-packages] [--skip-system] [--skip-state]
#
# Env: LYNE_DIR (default ~/.lyne-dots) and LYNE_STATE_FILE (default
# ~/.config/quickshell/state.json), mostly for testing against copies

set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN_DIR="$HOME/.local/bin"
LYNE_DIR="${LYNE_DIR:-$HOME/.lyne-dots}"
STATE_FILE="${LYNE_STATE_FILE:-$HOME/.config/quickshell/state.json}"

REPO_PKGS=(cpupower libnotify jq)
AUR_PKGS=(nbfc-linux)

NBFC_CONFIG="nitro-fan-curve"
NBFC_DIR="/usr/share/nbfc/configs"
NBFC_OLD_CONFIG="Acer Nitro AN515-58-custom"
# No dot in the name: sudo skips files in sudoers.d that have one
SUDOERS_FILE="/etc/sudoers.d/nitro-cpupower"
QUIRKS_FILE="/etc/libinput/local-overrides.quirks"

DRY_RUN=false
DO_PACKAGES=true
DO_SYSTEM=true
DO_STATE=true
NOTES=()

usage() {
    echo "Usage: ./setup.sh [options]"
    echo
    echo "Options:"
    echo "  --dry-run         Show what would change, change nothing"
    echo "  --skip-packages   Don't install packages"
    echo "  --skip-system     Don't touch /etc, /usr or services (sudo)"
    echo "  --skip-state      Don't touch the lyne-dots state.json"
    echo "  -h, --help        Show this help"
}

for arg in "$@"; do
    case "$arg" in
    --dry-run) DRY_RUN=true ;;
    --skip-packages) DO_PACKAGES=false ;;
    --skip-system) DO_SYSTEM=false ;;
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

# Installs $1 as $2 (mode $3, owned by root) when it differs. Sets CHANGED
install_root() {
    local src="$1" dest="$2" mode="$3"
    CHANGED=false
    if same_file "$src" "$dest"; then
        info "unchanged: $dest"
        return 0
    fi
    CHANGED=true
    run sudo install -D -m "$mode" -o root -g root "$src" "$dest"
    info "installed: $dest"
}

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

$DRY_RUN && echo "Dry run: nothing will be changed"

# ---------------------------------------------------------------- packages

if $DO_PACKAGES; then
    step "Packages"
    missing=()
    for pkg in "${REPO_PKGS[@]}"; do
        pacman -Qq "$pkg" &>/dev/null || missing+=("$pkg")
    done
    if ((${#missing[@]})); then
        run sudo pacman -S --needed "${missing[@]}"
    else
        info "installed: ${REPO_PKGS[*]}"
    fi

    missing=()
    for pkg in "${AUR_PKGS[@]}"; do
        pacman -Qq "$pkg" &>/dev/null || missing+=("$pkg")
    done
    if ((${#missing[@]})); then
        aur_helper="$(command -v yay || command -v paru || true)"
        if [[ -z "$aur_helper" ]]; then
            warn "no AUR helper (yay or paru) to install: ${missing[*]}"
            exit 1
        fi
        run "$aur_helper" -S --needed "${missing[@]}"
    else
        info "installed: ${AUR_PKGS[*]}"
    fi
fi

# ----------------------------------------------------------------- scripts

step "Scripts in $BIN_DIR"
for src in "$REPO"/bin/*; do
    dest="$BIN_DIR/$(basename "$src")"
    if cmp -s "$src" "$dest"; then
        info "unchanged: $dest"
    else
        run install -D -m 755 "$src" "$dest"
        info "installed: $dest"
    fi
done

# ------------------------------------------------------------------ system

if $DO_SYSTEM; then
    step "NBFC fan curve"
    install_root "$REPO/system/nbfc/$NBFC_CONFIG.json" "$NBFC_DIR/$NBFC_CONFIG.json" 644
    restart_nbfc=$CHANGED

    selected="$(jq -r '.SelectedConfigId // empty' /etc/nbfc/nbfc.json 2>/dev/null || true)"
    if [[ "$selected" == "$NBFC_CONFIG" ]]; then
        info "selected: $NBFC_CONFIG"
    else
        run sudo nbfc config -s "$NBFC_CONFIG"
        info "selected: $NBFC_CONFIG (was: ${selected:-none})"
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

    step "sudoers rule for cpupower"
    sudoers_tmp="$TMP_DIR/nitro-cpupower"
    printf '# nitro-cpu caps the CPU frequency without a password\n%s ALL=(root) NOPASSWD: /usr/bin/cpupower\n' \
        "$USER" >"$sudoers_tmp"
    if ! visudo -cqf "$sudoers_tmp"; then
        warn "the generated sudoers rule doesn't validate, skipping it"
    else
        install_root "$sudoers_tmp" "$SUDOERS_FILE" 440
    fi

    step "libinput quirks (mouse drag click)"
    if [[ -e "$QUIRKS_FILE" ]] && ! cmp -s "$REPO/system/libinput/local-overrides.quirks" "$QUIRKS_FILE"; then
        run sudo cp "$QUIRKS_FILE" "$QUIRKS_FILE.bak"
        info "backup of the current file: $QUIRKS_FILE.bak"
    fi
    install_root "$REPO/system/libinput/local-overrides.quirks" "$QUIRKS_FILE" 644
    $CHANGED && note "Log out and back in for the libinput quirks to apply."
fi

# ------------------------------------------------------- lyne-dots state

if $DO_STATE; then
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
        entries="$(<"$REPO/lyne/entries.json")"

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
