# vim, with colors (`extras/vim.sh`)

## SYNOPSIS

```
bash ~/debsway/extras/vim.sh            install it
bash ~/debsway/extras/vim.sh --remove   remove it (vim-tiny stays; a ~/.vimrc of your own too)
bash ~/debsway/extras/vim.sh --manual   print the manual steps below

vim FILE                                open FILE (vi does the same)
  i  type text   Esc  stop typing   :w  save   :q  quit   :wq  both   u  undo
```

Debian comes with vim-tiny, which shows every file in one color; this
installs Debian's full vim, which colors the code of every language it knows
(shell, Python, C, JavaScript, HTML, Markdown and hundreds more), and writes
`~/.vimrc` (`data/vimrc`) unless you have one of your own: colors and
indenting by file type, a light or dark background as debsway's theme is
(`theme light`, `theme dark`), search highlighting, line numbers, and
modelines off, so settings hidden inside a file you open are ignored (crafted
files have used them to run commands). debsway rewrites that file while its
first line says debsway wrote it; change the line and it is yours.

## LIMITS

- The colors come from your terminal's palette (foot's, which the theme sets), so they look like the rest of the terminal.
- With a `~/.vimrc` of your own, debsway doesn't touch it: add `syntax on` and `filetype plugin indent on` for the colors.
- Plugins you add yourself run as you, with everything you can reach.

## MANUAL INSTALL

```
# Debian's full vim (vim-tiny stays; vi and vim start the full one now)
sudo apt install --no-install-recommends vim
# debsway's settings, if you have no ~/.vimrc of your own
[ -e ~/.vimrc ] || install -m 0644 @DEBSWAY_DIR@/data/vimrc ~/.vimrc
```

To undo:

```
rm ~/.vimrc      # only if it is debsway's (its first line says so)
sudo apt purge vim
sudo apt autoremove --purge
```
