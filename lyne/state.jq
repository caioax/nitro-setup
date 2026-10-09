# Adds this repo's keybinds and autostart apps to the lyne-dots state.json
#
# $e is lyne/entries.json. Keybinds are matched by description and autostart
# apps by name: an entry already there only gets its command updated (keys,
# delay, enabled... stay as set in Settings), a missing one is appended.
# Everything else is kept, in its order.

def upsert($key; $new):
  reduce $new[] as $n (.;
    if any(.[]; .[$key] == $n[$key])
    then map(if .[$key] == $n[$key] then .command = $n.command else . end)
    else . + [$n]
    end);

.keybinds.custom = ((.keybinds.custom // []) | upsert("description"; $e.keybinds))
| .autostart.apps = ((.autostart.apps // []) | upsert("name"; $e.autostart))
