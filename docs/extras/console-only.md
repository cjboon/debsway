# Console-only (`extras/console-only.sh`)

You log in on a text console straight into tmux, with a bar and keys like the sway desktop's, instead of starting sway.

## The problem it solves

A computer with no screen to spare, a slow machine, or a taste for text. The same bar (workspace numbers, debsway menu, wifi, volume, brightness, battery, timer, date) and the same habits (workspaces on number keys) work without a desktop.

## The ideas behind it

**tmux** is a program that gives one terminal several windows. Here each tmux window is a "workspace", and the bar on top shows their numbers with the current one highlighted. The tmux config is always installed with the base (`parts/console-tmux.sh`), so this extra only changes what a login starts. The `debsway autostart` block in `~/.profile` reads `~/.config/debsway/login` (`sway` or `console`) and starts sway on tty1 or tmux on any text console. It is a loop: when the program ends and that file has changed, it starts the other one, so the switch needs no logout. Installing the extra from inside sway ends sway and drops you into tmux after 3 seconds; removing it from inside tmux detaches and starts sway on tty1. (A session started by an older autostart block, which had no loop, ends at the login prompt instead; log in again.) A tmux opened in a foot window under sway stays plain: the bar and Alt keys load only when there is no sway session.

## Keys

Alt takes the place of Super: Alt+1 … Alt+0 go to workspaces, Alt+Shift+1 … send the pane there (US keyboard), Alt+Enter / Alt+v split, Alt+h j k l or arrows move, Alt+f fullscreen, Alt+Shift+q close, Alt+m the debsway menu (it has a Font size entry for the text size), Alt+t timers, Alt+? the key sheet. Alt+w Wi-Fi, Alt+- / Alt+= volume (Alt+Backspace mutes), Alt+, / Alt+. brightness, Alt+b battery time. A real text console sends no mouse, so these keys are how you reach the bar's items; when tmux is used from a terminal program (over ssh, say) the items also click and scroll as in sway.

## What it changes on your computer

- `~/.profile`: the autostart block (it also sets the console font to Terminus 28x14 (`terminus-28`); to change it, type `console-font`: it lists the sizes, you type a number or a name such as `dejavu-43` or `terminus-bold-24`, and the text changes at once and is remembered in `~/.config/debsway/console-font`; `console-font list` only shows the list), and `~/.config/debsway/login` holds the mode. `sway` still starts the desktop by hand.
