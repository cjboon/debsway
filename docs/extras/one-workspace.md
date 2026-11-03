# One workspace (`extras/one-workspace.sh`)

## SYNOPSIS

```
debsway install one-workspace                     switch to one workspace
debsway remove one-workspace                      workspaces back
debsway manual one-workspace                      print the manual steps below
```

A simpler sway: Super+1 … 0 and Super+Shift+1 … 0 do nothing and the bar
shows no workspace buttons, so no window can end up on a workspace you don't
see. Windows still tile, side by side or stacked, as before. An external screen still gets a workspace of its own. It only changes sway's
keys and bar, so it adds no programs. `prep/make-install-iso.sh --simplesway`
ticks it in the install list of the first login.

## LIMITS

- sway's own commands still make workspaces: `swaymsg workspace 2` works, and the bar shows nothing to get you back; Super+1 doesn't either. `swaymsg workspace 1` does.
- Windows already on other workspaces stay there until you move them back (Super+Shift+1 before switching it on).

## MANUAL INSTALL

```
# The keys unbound and the bar's buttons hidden, in a file sway's config includes
mkdir -p ~/.config/sway/config.d
{
    echo "# One workspace"
    for k in 1 2 3 4 5 6 7 8 9 0; do
        echo "unbindsym \$mod+$k"
        echo "unbindsym \$mod+Shift+$k"
    done
    echo "bar bar-0 workspace_buttons no"
} >~/.config/sway/config.d/one-workspace.conf
swaymsg reload
```

To undo:

```
rm ~/.config/sway/config.d/one-workspace.conf
swaymsg reload
```
