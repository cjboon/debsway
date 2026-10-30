
# >>> debsway first login >>>
# shellcheck shell=sh
# Put here by debsway's install stick (prep/make-install-iso.sh): at the first
# login on the console it asks once whether to set debsway up, then takes
# itself out of this file. Later: bash ~/debsway/start.sh
case "${DEBSWAY_TTY:-$(tty 2>/dev/null)}" in
    /dev/tty[0-9]*)
        sed -i '/^# >>> debsway first login >>>$/,/^# <<< debsway first login <<<$/d' "$HOME/.profile"
        if [ -f "$HOME/debsway/start.sh" ]; then
            printf '\ndebsway is on this computer, but not set up yet.\n'
            printf 'It explains what it will do and asks before changing anything.\n'
            printf 'Set it up now? [Y/n] '
            read -r debsway_answer
            case $debsway_answer in
                [Nn]*) printf 'Later: bash ~/debsway/start.sh\n' ;;
                *) bash "$HOME/debsway/start.sh" ;;
            esac
            unset debsway_answer
        fi
        ;;
esac
# <<< debsway first login <<<
