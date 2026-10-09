# nitro-setup

Tweaks for my Acer Nitro 5 (AN517-54), applied on top of
lyne-dots (`~/.lyne-dots`).

| What                                                                                | Where it goes                     |
| ----------------------------------------------------------------------------------- | --------------------------------- |
| `bin/nitro-cpu`: cap the CPU max frequency (Low/Base/High/Ultra/Max)                | `~/.local/bin`                    |
| `bin/nitro-fans`: fans on Auto (NBFC curve) or Max                                  | `~/.local/bin`                    |
| `system/nbfc/nitro-fan-curve.json`: NBFC fan curve, selected as the active config   | `/usr/share/nbfc/configs`         |
| `cpupower` without password, for `nitro-cpu`                                        | `/etc/sudoers.d/nitro-cpupower`   |
| `system/libinput/local-overrides.quirks`: no mouse debounce (drag click, Minecraft) | `/etc/libinput`                   |
| Keybinds and autostart (`lyne/entries.json`)                                        | `~/.config/quickshell/state.json` |

Keybinds: `CTRL + ALT + 1..5` CPU Low/Base/High/Ultra/Max, `CTRL + ALT + A/M`
fans Auto/Max. At login: `nitro-cpu Base` and `nitro-fans Auto`.

## Fresh install

1. Install lyne-dots and log in to it once, so `state.json` exists.
2. Clone and run:

    ```sh
    git clone git@github.com:caioax/nitro-setup.git ~/Dev/nitro-setup
    cd ~/Dev/nitro-setup
    ./setup.sh --dry-run   # see what will change
    ./setup.sh
    ```

3. Log out and back in (libinput quirks and autostart). The setup lists what
   needs it at the end.

`setup.sh` can be run again at any time: it only changes what differs. Keybinds
are matched by description and autostart apps by name, and only their command
is updated, so keys or options changed in Settings are kept.

Options: `--dry-run`, `--skip-packages`, `--skip-system`, `--skip-state`.
