# Console-only (`extras/console-only.sh`)

You log in on a text console straight into tmux, with a bar and keys like the sway desktop's, instead of starting sway.

## The problem it solves

A computer with no screen to spare, a slow machine, or a taste for text. The same bar (workspace numbers, debsway menu, wifi, volume, brightness, battery, timer, date) and the same habits (workspaces on number keys) work without a desktop.

## The ideas behind it

**tmux** is a program that gives one terminal several windows. Here each tmux window is a "workspace", and the bar on top shows their numbers with the current one highlighted. The tmux config is always installed with the base (`parts/console-tmux.sh`), so this extra only changes what happens at login: the `debsway autostart` block in `~/.profile` (which starts sway on tty1) is swapped for a `debsway console` block (which starts tmux on any text console). Removing the extra swaps it back. A tmux opened in a foot window under sway stays plain: the bar and Alt keys load only when there is no sway session.

## Keys

Alt takes the place of Super: Alt+1 … Alt+0 go to workspaces, Alt+Shift+1 … send the pane there (US keyboard), Alt+Enter / Alt+v split, Alt+h j k l or arrows move, Alt+f fullscreen, Alt+Shift+q close, Alt+m the debsway menu, Alt+t timers, Alt+? the key sheet. Click or scroll the bar items as in sway.

## What it changes on your computer

- `~/.profile`: the autostart block (sway or tmux). `sway` still starts the desktop by hand.
