# smplOS Fish Configuration
# Fish has built-in: autosuggestions, syntax highlighting, tab completions

# ── PATH ─────────────────────────────────────────────────────
fish_add_path -m ~/.local/bin

# ── Environment ──────────────────────────────────────────────
set -gx EDITOR micro
set -gx VISUAL micro
set -gx SUDO_EDITOR micro
set -gx BAT_THEME ansi

# ── Key Bindings ─────────────────────────────────────────────
# Use default (emacs) key bindings — prevents Tide vi mode indicator (D/I/R/V)
fish_default_key_bindings

# ── Aliases ──────────────────────────────────────────────────
if command -q eza
    alias ls 'eza --icons --group-directories-first'
    alias ll 'eza -la --icons --group-directories-first'
    alias la 'eza -a --icons --group-directories-first'
    alias lt 'eza --tree --level=2 --long --icons --git'
end

if command -q bat
    alias cat 'bat --style=plain --paging=never'
end

alias grep 'grep --color=auto'
alias .. 'cd ..'
alias ... 'cd ../..'
alias .... 'cd ../../..'

# Tools
alias d docker
alias r rails
alias g git
alias gcm 'git commit -m'
alias gcam 'git commit -a -m'
alias gcad 'git commit -a --amend'

# ── Integrations ─────────────────────────────────────────────
# Tide prompt (auto-configured in conf.d/_tide_init.fish)

# Zoxide (smart cd)
if command -q zoxide
    zoxide init fish | source
end

# fzf key bindings (Ctrl-R history, Ctrl-T files)
if command -q fzf
    fzf --fish 2>/dev/null | source
end

# mise (version manager)
if command -q mise
    mise activate fish | source
end

# ── Theme colors ─────────────────────────────────────────────
# Loaded from smplOS theme system (updated by theme-set)
if test -f ~/.config/fish/theme.fish
    source ~/.config/fish/theme.fish
end

# ── Greeting ─────────────────────────────────────────────────
set -g fish_greeting
