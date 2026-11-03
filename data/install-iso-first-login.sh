
# >>> Wren Linux first login >>>
# shellcheck shell=sh
# Put here by Wren Linux's install stick (prep/make-install-iso.sh): at the first
# login on the console it asks once whether to set Wren Linux up, then takes
# itself out of this file. Later: bash ~/wren/start.sh
case "${WREN_TTY:-$(tty 2>/dev/null)}" in
    /dev/tty[0-9]*)
        sed -i '/^# >>> Wren Linux first login >>>$/,/^# <<< Wren Linux first login <<<$/d' "$HOME/.profile"
        if [ -f "$HOME/wren/start.sh" ]; then
            printf '\nWren Linux is on this computer, but not set up yet.\n'
            printf 'It explains what it will do and asks before changing anything.\n'
            printf 'Set it up now? [Y/n] '
            read -r wren_answer
            case $wren_answer in
                [Nn]*) printf 'Later: bash ~/wren/start.sh\n' ;;
                *) bash "$HOME/wren/start.sh" ;;
            esac
            unset wren_answer
        fi
        ;;
esac
# <<< Wren Linux first login <<<
