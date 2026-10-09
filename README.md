# nitro-setup

Tweaks for my Acer Nitro 5 (AN517-54), applied on top of
lyne-dots (`~/.lyne-dots`). Each folder is a part that `setup.sh` can set up
on its own:

| Part       | What                                                                  | Where it goes                   |
| ---------- | --------------------------------------------------------------------- | ------------------------------- |
| `cpu`      | `nitro-cpu`: cap the CPU max frequency (Low/Base/High/Ultra/Max)      | `~/.local/bin`                  |
|            | `cpupower` without password, for `nitro-cpu`                          | `/etc/sudoers.d/nitro-cpupower` |
| `fans`     | `nitro-fans`: fans on Auto (NBFC curve) or Max                        | `~/.local/bin`                  |
|            | `nitro-fan-curve.json`: NBFC fan curve, selected as the active config | `/usr/share/nbfc/configs`       |
| `mouse`    | `local-overrides.quirks`: no mouse debounce (drag click, Minecraft)   | `/etc/libinput`                 |
| `mangohud` | `MangoHud.conf`: overlay config (toggle with `Home`), 32-bit too      | `~/.config/MangoHud`            |

`cpu` and `fans` also add their keybinds and autostart (`lyne.json`) to
`~/.config/quickshell/state.json`: `CTRL + ALT + 1..5` CPU
Low/Base/High/Ultra/Max, `CTRL + ALT + A/M` fans Auto/Max, and at login
`nitro-cpu Base` and `nitro-fans Auto`.

## Fresh install

1. Install lyne-dots and log in to it once, so `state.json` exists.
2. Clone and run:

    ```sh
    git clone https://github.com/caioax/nitro-setup.git ~/Dev/nitro-setup
    cd ~/Dev/nitro-setup
    ./setup.sh --dry-run   # see what will change
    ./setup.sh
    ```

    A menu lists the parts, all selected: move with ↑/↓, toggle with Space,
    Enter to run. `--only=cpu,fans` skips the menu.

3. Log out and back in (libinput quirks and autostart). The setup lists what
   needs it at the end.

`setup.sh` can be run again at any time: it only changes what differs. Keybinds
are matched by description and autostart apps by name, and only their command
is updated, so keys or options changed in Settings are kept. A different
`local-overrides.quirks` or `MangoHud.conf` already there is kept as `.bak`.

Options: `--only=LIST`, `--dry-run`, `--skip-packages`, `--skip-state`.
